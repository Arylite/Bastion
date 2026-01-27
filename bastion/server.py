"""SSH server implementation using Paramiko."""

import socket
import threading
import logging
import os
from typing import Optional

import paramiko

from .auth import SSHKeyAuth, BastionSSHServerInterface
from .db import Database  
from .router import SSHRouter
from .proxy import ProxySession
from .config import Config
from .logging import setup_logging, log_connection_error


class BastionSSHServer:
    """Main SSH server for the bastion."""
    
    def __init__(self):
        """Initialize the bastion SSH server."""
        self.logger = setup_logging()
        self.config = Config()
        self.database = Database()
        self.auth_handler = SSHKeyAuth(self.database)
        self.router = SSHRouter(self.database)
        self.host_key = None
        self.server_socket = None
        self.running = False
        self.connection_count = 0
        self.connection_lock = threading.Lock()
        
        # Load or generate host key
        self._load_host_key()
    
    def _load_host_key(self):
        """Load or generate SSH host key."""
        try:
            host_key_file = self.config.HOST_KEY_FILE
            
            if os.path.exists(host_key_file):
                # Load existing host key
                try:
                    self.host_key = paramiko.RSAKey.from_private_key_file(host_key_file)
                    self.logger.info(f"Loaded host key from {host_key_file}")
                except Exception as e:
                    self.logger.warning(f"Failed to load host key from {host_key_file}: {e}")
                    self.host_key = None
            
            if not self.host_key:
                # Generate new host key
                self.logger.info("Generating new RSA host key...")
                self.host_key = paramiko.RSAKey.generate(2048)
                
                # Save the key
                try:
                    self.host_key.write_private_key_file(host_key_file)
                    self.logger.info(f"Saved new host key to {host_key_file}")
                except Exception as e:
                    self.logger.warning(f"Failed to save host key: {e}")
            
        except Exception as e:
            self.logger.error(f"Error with host key: {e}")
            raise
    
    def start(self):
        """Start the SSH server."""
        try:
            # Validate configuration
            self.config.validate()
            
            # Create server socket
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            
            # Bind to address
            self.server_socket.bind((self.config.BASTION_BIND, self.config.BASTION_PORT))
            self.server_socket.listen(100)
            
            self.running = True
            
            self.logger.info(
                f"Bastion SSH server started on {self.config.BASTION_BIND}:{self.config.BASTION_PORT}"
            )
            
            # Accept connections
            while self.running:
                try:
                    client_socket, client_address = self.server_socket.accept()
                    
                    # Handle connection in separate thread
                    connection_thread = threading.Thread(
                        target=self._handle_connection,
                        args=(client_socket, client_address),
                        daemon=True
                    )
                    connection_thread.start()
                    
                except Exception as e:
                    if self.running:
                        self.logger.error(f"Error accepting connection: {e}")
            
        except Exception as e:
            self.logger.error(f"Error starting server: {e}")
            raise
        
        finally:
            self.stop()
    
    def stop(self):
        """Stop the SSH server."""
        try:
            self.running = False
            
            if self.server_socket:
                self.server_socket.close()
            
            self.logger.info("Bastion SSH server stopped")
            
        except Exception as e:
            self.logger.error(f"Error stopping server: {e}")
    
    def _handle_connection(self, client_socket: socket.socket, client_address: tuple):
        """Handle individual SSH connection."""
        source_ip = client_address[0]
        
        try:
            with self.connection_lock:
                self.connection_count += 1
            
            self.logger.info(f"New connection from {source_ip}")
            
            # Check connection limits
            if not self._check_connection_limits(source_ip):
                client_socket.close()
                return
            
            # Create SSH transport
            transport = paramiko.Transport(client_socket)
            
            try:
                # Add host key
                transport.add_server_key(self.host_key)
                
                # Create server interface
                server_interface = BastionSSHServerInterface(self.auth_handler, source_ip)
                
                # Start SSH server
                transport.start_server(server=server_interface)
                
                # Wait for authentication
                channel = transport.accept(timeout=30)
                
                if channel is None:
                    self.logger.warning(f"No channel established for {source_ip}")
                    return
                
                # Check if authentication was successful
                if not server_interface.authenticated_key:
                    self.logger.warning(f"Authentication failed for {source_ip}")
                    return
                
                # Get target from router
                target = self.router.get_target(
                    server_interface.authenticated_key, 
                    server_interface.username, 
                    source_ip
                )
                
                if not target:
                    self.logger.warning(f"No target found for {source_ip}")
                    return
                
                # Start proxy session
                fingerprint = server_interface.authenticated_key.fingerprint
                proxy_session = ProxySession(channel, target, source_ip, fingerprint)
                
                if not proxy_session.start():
                    self.logger.error(f"Failed to start proxy session for {source_ip}")
                    log_connection_error(
                        self.logger, source_ip, fingerprint, 
                        server_interface.username, "Failed to start proxy session"
                    )
                    return
                
                # Keep connection alive until channel closes
                try:
                    while not channel.closed:
                        if transport.is_active():
                            threading.Event().wait(1.0)
                        else:
                            break
                except:
                    pass
                
            except Exception as e:
                self.logger.error(f"SSH transport error for {source_ip}: {e}")
            
            finally:
                try:
                    transport.close()
                except:
                    pass
            
        except Exception as e:
            self.logger.error(f"Connection handling error for {source_ip}: {e}")
        
        finally:
            with self.connection_lock:
                self.connection_count -= 1
            
            try:
                client_socket.close()
            except:
                pass
            
            self.logger.info(f"Connection from {source_ip} closed")
    
    def _check_connection_limits(self, source_ip: str) -> bool:
        """Check connection limits per IP."""
        try:
            # TODO: Implement per-IP connection tracking
            # For now, just check total connection count
            
            if self.connection_count >= self.config.MAX_CONNECTIONS_PER_IP * 10:
                self.logger.warning(f"Connection limit exceeded, rejecting {source_ip}")
                return False
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error checking connection limits: {e}")
            return False
    
    def get_server_stats(self) -> dict:
        """Get server statistics."""
        return {
            'running': self.running,
            'active_connections': self.connection_count,
            'bind_address': self.config.BASTION_BIND,
            'bind_port': self.config.BASTION_PORT
        }


def create_server() -> BastionSSHServer:
    """Create and return a bastion SSH server instance."""
    return BastionSSHServer()