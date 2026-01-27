"""Configuration module for the SSH bastion."""

import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Config:
    """Configuration class for the SSH bastion."""
    
    # Server configuration
    BASTION_BIND = os.getenv("BASTION_BIND", "0.0.0.0")
    BASTION_PORT = int(os.getenv("BASTION_PORT", "2222"))
    
    # Database configuration
    DB_URL = os.getenv("DB_URL", "sqlite:///bastion.db")
    
    # Logging configuration
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
    LOG_FILE = os.getenv("LOG_FILE", "bastion.log")
    
    # Security configuration
    MAX_CONNECTIONS_PER_IP = int(os.getenv("MAX_CONNECTIONS_PER_IP", "5"))
    CONNECTION_TIMEOUT = int(os.getenv("CONNECTION_TIMEOUT", "300"))
    
    # SSH configuration
    HOST_KEY_FILE = os.getenv("HOST_KEY_FILE", "bastion_host_key")
    
    RESTRICTED_NETWORKS = os.getenv("RESTRICTED_NETWORKS", "10.10.254.0/24").split(",")
    
    @classmethod
    def validate(cls):
        """Validate the configuration."""
        if cls.BASTION_PORT < 1 or cls.BASTION_PORT > 65535:
            raise ValueError("Invalid port number")
        
        if cls.CONNECTION_TIMEOUT < 1:
            raise ValueError("Invalid connection timeout")
        
        if cls.MAX_CONNECTIONS_PER_IP < 1:
            raise ValueError("Invalid max connections per IP")