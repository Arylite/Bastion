"""Authentication module for SSH key-based authentication."""

import hashlib
import base64
import logging
from typing import Optional, Tuple

import paramiko

from .db import Database
from .models import SSHKey
from .logging import log_connection_attempt, log_connection_denied


class SSHKeyAuth:
    """SSH key-based authentication handler."""
    
    def __init__(self, database: Database):
        """Initialize authentication with database."""
        self.database = database
        self.logger = logging.getLogger(__name__)
    
    def get_key_fingerprint(self, public_key: paramiko.PKey) -> str:
        """Calculate SHA256 fingerprint of a public key."""
        try:
            # Get the key bytes
            key_bytes = public_key.asbytes()
            
            # Calculate SHA256 hash
            sha256_hash = hashlib.sha256(key_bytes).digest()
            
            # Format as SSH fingerprint (SHA256:base64)
            fingerprint = "SHA256:" + base64.b64encode(sha256_hash).decode().rstrip('=')
            
            return fingerprint
            
        except Exception as e:
            self.logger.error(f"Error calculating key fingerprint: {e}")
            return ""
    
    def authenticate_key(self, username: str, public_key: paramiko.PKey, 
                        source_ip: str) -> Tuple[bool, Optional[SSHKey]]:
        """
        Authenticate an SSH public key.
        
        Args:
            username: The SSH username from the connection
            public_key: The public key used for authentication
            source_ip: Source IP address of the connection
        
        Returns:
            Tuple of (authentication_success, ssh_key_info)
        """
        try:
            # Calculate fingerprint
            fingerprint = self.get_key_fingerprint(public_key)
            if not fingerprint:
                log_connection_denied(
                    self.logger, source_ip, "INVALID", username, 
                    "Could not calculate key fingerprint"
                )
                return False, None
            
            # Log the connection attempt
            log_connection_attempt(self.logger, source_ip, fingerprint, username)
            
            # Look up the key in the database
            ssh_key = self.database.find_ssh_key(fingerprint)
            
            if not ssh_key:
                log_connection_denied(
                    self.logger, source_ip, fingerprint, username, 
                    "SSH key not found in database"
                )
                return False, None
            
            if not ssh_key.enabled:
                log_connection_denied(
                    self.logger, source_ip, fingerprint, username, 
                    "SSH key is disabled"
                )
                return False, None
            
            # Successful authentication
            self.logger.info(
                f"Authentication SUCCESS for {username} from {source_ip} "
                f"with fingerprint {fingerprint[:16]}..."
            )
            
            return True, ssh_key
            
        except Exception as e:
            self.logger.error(f"Authentication error: {e}")
            log_connection_denied(
                self.logger, source_ip, fingerprint or "UNKNOWN", username, 
                f"Authentication error: {e}"
            )
            return False, None
    
    def is_key_authorized(self, fingerprint: str) -> bool:
        """Check if a key fingerprint is authorized."""
        try:
            ssh_key = self.database.find_ssh_key(fingerprint)
            return ssh_key is not None and ssh_key.enabled
        except Exception as e:
            self.logger.error(f"Error checking key authorization: {e}")
            return False


class BastionSSHServerInterface(paramiko.ServerInterface):
    """Custom SSH server interface for the bastion."""
    
    def __init__(self, auth_handler: SSHKeyAuth, source_ip: str):
        """Initialize the SSH server interface."""
        super().__init__()
        self.auth_handler = auth_handler
        self.source_ip = source_ip
        self.authenticated_key = None
        self.username = None
        self.logger = logging.getLogger(__name__)
    
    def check_channel_request(self, kind: str, chanid: int) -> int:
        """Check if a channel request is allowed."""
        if kind == 'session':
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
    
    def check_auth_password(self, username: str, password: str) -> int:
        """Reject password authentication."""
        log_connection_denied(
            self.logger, self.source_ip, "N/A", username, 
            "Password authentication not allowed"
        )
        return paramiko.AUTH_FAILED
    
    def check_auth_publickey(self, username: str, key: paramiko.PKey) -> int:
        """Check public key authentication."""
        try:
            success, ssh_key = self.auth_handler.authenticate_key(
                username, key, self.source_ip
            )
            
            if success and ssh_key:
                self.authenticated_key = ssh_key
                self.username = username
                return paramiko.AUTH_SUCCESSFUL
            else:
                return paramiko.AUTH_FAILED
                
        except Exception as e:
            self.logger.error(f"Public key authentication error: {e}")
            return paramiko.AUTH_FAILED
    
    def check_channel_shell_request(self, channel: paramiko.Channel) -> bool:
        """Deny shell requests - bastion doesn't provide shells."""
        self.logger.warning(
            f"Shell request denied for {self.username} from {self.source_ip}"
        )
        return False
    
    def check_channel_exec_request(self, channel: paramiko.Channel, command: bytes) -> bool:
        """Deny command execution - bastion doesn't execute commands."""
        self.logger.warning(
            f"Exec request denied for {self.username} from {self.source_ip} "
            f"(command: {command.decode('utf-8', errors='ignore')})"
        )
        return False
    
    def check_channel_subsystem_request(self, channel: paramiko.Channel, name: str) -> bool:
        """Allow SFTP subsystem for SSH tunneling."""
        if name == 'sftp':
            return True
        self.logger.warning(
            f"Subsystem request denied: {name} for {self.username} from {self.source_ip}"
        )
        return False
    
    def check_port_forward_request(self, address: str, port: int) -> int:
        """Allow port forwarding for SSH tunneling."""
        return port
    
    def cancel_port_forward_request(self, address: str, port: int):
        """Handle port forward cancellation."""
        pass
    
    def get_allowed_auths(self, username: str) -> str:
        """Return allowed authentication methods."""
        return "publickey"