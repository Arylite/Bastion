"""SSH proxy module for bidirectional traffic relay."""

import threading
import socket
import select
import logging
from typing import Optional, Tuple

import paramiko

from .models import Target
from .config import Config
from .logging import log_connection_closed, log_connection_error


class SSHProxy:
    """SSH proxy to relay traffic between client and target VM."""
    
    def __init__(self):
        """Initialize SSH proxy."""
        self.logger = logging.getLogger(__name__)
        self.active_connections = {}
        self.connection_lock = threading.Lock()
    
    def create_outbound_connection(self, target: Target) -> Optional[paramiko.SSHClient]:
        """
        Create SSH connection to target VM.
        
        Args:
            target: Target VM information
            
        Returns:
            SSH client connection or None if failed
        """
        try:
            # Create SSH client
            ssh_client = paramiko.SSHClient()
            ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # Load bastion private key from config
            pkey = paramiko.RSAKey.from_private_key_file(Config.HOST_KEY_FILE)
            
            # Connect with timeout using private key
            ssh_client.connect(
                hostname=target.host,
                port=target.port,
                username=target.user,
                pkey=pkey,
                timeout=Config.CONNECTION_TIMEOUT,
                allow_agent=False,
                look_for_keys=False,
                auth_timeout=30
            )
            
            self.logger.info(f"Outbound connection established to {target.host}:{target.port}")
            return ssh_client
            
        except Exception as e:
            self.logger.error(f"Failed to connect to target {target.host}:{target.port}: {e}")
            return None
    
    def setup_proxy_session(self, client_channel: paramiko.Channel, target: Target, 
                          source_ip: str, fingerprint: str) -> bool:
        """
        Setup bidirectional proxy session between client and target.
        
        Args:
            client_channel: Client SSH channel
            target: Target VM information  
            source_ip: Client source IP
            fingerprint: Client SSH key fingerprint
            
        Returns:
            True if proxy session was successfully established
        """
        try:
            # Create connection to target
            target_ssh = self.create_outbound_connection(target)
            if not target_ssh:
                return False
            
            # Open channel to target
            target_transport = target_ssh.get_transport()
            if not target_transport:
                self.logger.error("Failed to get target transport")
                target_ssh.close()
                return False
            
            target_channel = target_transport.open_channel('session')
            if not target_channel:
                self.logger.error("Failed to open target channel")
                target_ssh.close()
                return False
            
            # Store connection info for cleanup
            connection_id = f"{source_ip}:{fingerprint[:8]}"
            with self.connection_lock:
                self.active_connections[connection_id] = {
                    'client_channel': client_channel,
                    'target_ssh': target_ssh,
                    'target_channel': target_channel,
                    'target': target,
                    'source_ip': source_ip,
                    'fingerprint': fingerprint
                }
            
            # Start bidirectional relay
            self._start_relay(client_channel, target_channel, connection_id)
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error setting up proxy session: {e}")
            log_connection_error(
                self.logger, source_ip, fingerprint, target.user, str(e)
            )
            return False
    
    def _start_relay(self, client_channel: paramiko.Channel, target_channel: paramiko.Channel, 
                    connection_id: str):
        """Start bidirectional relay between channels."""
        try:
            # Start relay threads
            client_to_target_thread = threading.Thread(
                target=self._relay_data,
                args=(client_channel, target_channel, f"{connection_id}-c2t"),
                daemon=True
            )
            
            target_to_client_thread = threading.Thread(
                target=self._relay_data,
                args=(target_channel, client_channel, f"{connection_id}-t2c"),
                daemon=True
            )
            
            client_to_target_thread.start()
            target_to_client_thread.start()
            
            self.logger.info(f"Proxy relay started for connection {connection_id}")
            
            # Monitor connection and cleanup when done
            cleanup_thread = threading.Thread(
                target=self._monitor_connection,
                args=(connection_id, client_to_target_thread, target_to_client_thread),
                daemon=True
            )
            cleanup_thread.start()
            
        except Exception as e:
            self.logger.error(f"Error starting relay: {e}")
            self._cleanup_connection(connection_id)
    
    def _relay_data(self, source_channel: paramiko.Channel, dest_channel: paramiko.Channel, 
                   relay_id: str):
        """Relay data between two channels."""
        try:
            buffer_size = 4096
            
            while True:
                # Check if channels are still active
                if source_channel.closed or dest_channel.closed:
                    break
                
                # Use select to check for data
                ready, _, _ = select.select([source_channel], [], [], 1.0)
                
                if ready:
                    try:
                        data = source_channel.recv(buffer_size)
                        if not data:
                            break
                        
                        dest_channel.send(data)
                        
                    except Exception as e:
                        self.logger.debug(f"Relay {relay_id} data transfer error: {e}")
                        break
                
        except Exception as e:
            self.logger.error(f"Relay {relay_id} error: {e}")
        
        finally:
            self.logger.debug(f"Relay {relay_id} terminated")
    
    def _monitor_connection(self, connection_id: str, thread1: threading.Thread, 
                          thread2: threading.Thread):
        """Monitor connection and cleanup when threads finish."""
        try:
            # Wait for either thread to finish
            while thread1.is_alive() and thread2.is_alive():
                threading.Event().wait(1.0)
            
        except Exception as e:
            self.logger.error(f"Error monitoring connection {connection_id}: {e}")
        
        finally:
            # Cleanup connection
            self._cleanup_connection(connection_id)
    
    def _cleanup_connection(self, connection_id: str):
        """Cleanup connection resources."""
        try:
            with self.connection_lock:
                if connection_id in self.active_connections:
                    conn_info = self.active_connections[connection_id]
                    
                    # Close channels and connections
                    try:
                        if 'client_channel' in conn_info:
                            conn_info['client_channel'].close()
                    except:
                        pass
                    
                    try:
                        if 'target_channel' in conn_info:
                            conn_info['target_channel'].close()
                    except:
                        pass
                    
                    try:
                        if 'target_ssh' in conn_info:
                            conn_info['target_ssh'].close()
                    except:
                        pass
                    
                    # Log connection closure
                    log_connection_closed(
                        self.logger,
                        conn_info.get('source_ip', 'unknown'),
                        conn_info.get('fingerprint', 'unknown'),
                        conn_info.get('target', {}).get('host', 'unknown')
                    )
                    
                    # Remove from active connections
                    del self.active_connections[connection_id]
                    
                    self.logger.info(f"Connection {connection_id} cleaned up")
            
        except Exception as e:
            self.logger.error(f"Error cleaning up connection {connection_id}: {e}")
    
    def get_active_connections_count(self) -> int:
        """Get number of active connections."""
        with self.connection_lock:
            return len(self.active_connections)
    
    def cleanup_all_connections(self):
        """Cleanup all active connections."""
        try:
            with self.connection_lock:
                connection_ids = list(self.active_connections.keys())
            
            for connection_id in connection_ids:
                self._cleanup_connection(connection_id)
                
            self.logger.info("All connections cleaned up")
            
        except Exception as e:
            self.logger.error(f"Error cleaning up all connections: {e}")


class ProxySession:
    """Individual proxy session handler."""
    
    def __init__(self, client_channel: paramiko.Channel, target: Target, 
                 source_ip: str, fingerprint: str):
        """Initialize proxy session."""
        self.client_channel = client_channel
        self.target = target
        self.source_ip = source_ip
        self.fingerprint = fingerprint
        self.logger = logging.getLogger(__name__)
        self.proxy = SSHProxy()
    
    def start(self) -> bool:
        """Start the proxy session."""
        try:
            return self.proxy.setup_proxy_session(
                self.client_channel, self.target, self.source_ip, self.fingerprint
            )
        except Exception as e:
            self.logger.error(f"Error starting proxy session: {e}")
            return False