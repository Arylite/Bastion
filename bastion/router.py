"""Routing module to determine target VMs from SSH keys."""

import ipaddress
import logging
from typing import Optional
from xml.etree.ElementInclude import include

from bastion.config import Config

from .db import Database
from .models import Target, SSHKey, ConnectionEvent
from .logging import log_connection_success, log_connection_denied


class SSHRouter:
    """Router to determine target VM based on SSH key identity."""
    
    def __init__(self, database: Database):
        """Initialize router with database."""
        self.database = database
        self.logger = logging.getLogger(__name__)
    
    def get_target(self, ssh_key: SSHKey, username: str, source_ip: str) -> Optional[Target]:
        """
        Determine target VM for an authenticated SSH key.
        
        Args:
            ssh_key: The authenticated SSH key information
            username: SSH username from the connection
            source_ip: Source IP address
            
        Returns:
            Target information or None if routing fails
        """
        try:
            # Basic validation
            if not ssh_key or not ssh_key.enabled:
                log_connection_denied(
                    self.logger, source_ip, ssh_key.fingerprint if ssh_key else "UNKNOWN", 
                    username, "SSH key not valid or disabled"
                )
                return None
            
            # Create target from SSH key information
            target = Target(
                host=ssh_key.target_host,
                port=ssh_key.target_port,
                user=ssh_key.target_user
            )
            
            # Validate target
            if not self._validate_target(target):
                log_connection_denied(
                    self.logger, source_ip, ssh_key.fingerprint, username, 
                    "Invalid target configuration"
                )
                return None
            
            # Log successful routing
            log_connection_success(
                self.logger, source_ip, ssh_key.fingerprint, 
                username, target.host
            )
            
            # Log connection event to database
            self._log_connection_event(
                ssh_key, username, source_ip, target, "success"
            )
            
            self.logger.info(
                f"Routing SUCCESS: {username}@{source_ip} -> "
                f"{target.user}@{target.host}:{target.port}"
            )
            
            return target
            
        except Exception as e:
            self.logger.error(f"Routing error: {e}")
            
            # Log failed connection event
            self._log_connection_event(
                ssh_key, username, source_ip, None, "error", str(e)
            )
            
            return None
    
    def _validate_target(self, target: Target) -> bool:
        """Validate target configuration."""
        try:
            if not target.host or not target.user:
                return False
            
            if target.port < 1 or target.port > 65535:
                return False
            
            # Additional validation could be added here:
            # - Check if target host is reachable
            # - Validate hostname format
            # - Check against allowed target networks
            
            # Host example : 10.10.254.0/24
            for host in Config.RESTRICTED_NETWORKS:
                if ipaddress.ip_address(target.host) in ipaddress.ip_network(host, strict=False):
                    self.logger.error(f"Target host {target.host} is in restricted network {host}!")
                    return False
            
            return True
            
        except Exception as e:
            self.logger.error(f"Target validation error: {e}")
            return False
    
    def _log_connection_event(self, ssh_key: SSHKey, username: str, source_ip: str, 
                            target: Optional[Target], status: str, error_message: str = None):
        """Log connection event to database."""
        try:
            event = ConnectionEvent(
                fingerprint=ssh_key.fingerprint,
                source_ip=source_ip,
                target_host=target.host if target else "",
                target_user=target.user if target else "",
                username=username,
                status=status,
                error_message=error_message
            )
            
            self.database.log_connection_event(event)
            
        except Exception as e:
            self.logger.error(f"Error logging connection event: {e}")
    
    def is_target_reachable(self, target: Target) -> bool:
        """
        Check if target is reachable (basic connectivity test).
        This could be enhanced with actual network connectivity checks.
        """
        try:
            # Basic validation - could be enhanced with actual reachability test
            return self._validate_target(target)
            
        except Exception as e:
            self.logger.error(f"Target reachability check error: {e}")
            return False
    
    def get_target_by_fingerprint(self, fingerprint: str) -> Optional[Target]:
        """Get target directly by SSH key fingerprint."""
        try:
            return self.database.get_target_for_key(fingerprint)
            
        except Exception as e:
            self.logger.error(f"Error getting target for fingerprint: {e}")
            return None