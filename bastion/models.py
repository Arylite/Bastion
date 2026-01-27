"""Data models for the SSH bastion."""

from dataclasses import dataclass
from typing import Optional


@dataclass
class SSHKey:
    """Represents an SSH key in the database."""
    
    id: Optional[int] = None
    fingerprint: str = ""
    username: str = ""
    target_host: str = ""
    target_port: int = 22
    target_user: str = ""
    enabled: bool = True
    
    def __post_init__(self):
        """Validate the SSH key data."""
        if not self.fingerprint:
            raise ValueError("Fingerprint is required")
        if not self.target_host:
            raise ValueError("Target host is required")
        if not self.target_user:
            raise ValueError("Target user is required")
        if self.target_port < 1 or self.target_port > 65535:
            raise ValueError("Invalid target port")


@dataclass
class Target:
    """Represents a target VM for SSH connection."""
    
    host: str
    port: int = 22
    user: str = ""
    
    def __post_init__(self):
        """Validate the target data."""
        if not self.host:
            raise ValueError("Target host is required")
        if not self.user:
            raise ValueError("Target user is required")
        if self.port < 1 or self.port > 65535:
            raise ValueError("Invalid port")


@dataclass
class ConnectionEvent:
    """Represents a connection event for logging."""
    
    fingerprint: str
    source_ip: str
    target_host: str
    target_user: str
    username: str
    status: str  # 'success', 'denied', 'error'
    timestamp: Optional[str] = None
    error_message: Optional[str] = None