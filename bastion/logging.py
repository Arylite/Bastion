"""Logging configuration for the SSH bastion."""

import logging
import logging.handlers
import sys
from typing import Optional

from .config import Config


class BastionLogger:
    """Custom logger for the SSH bastion."""
    
    def __init__(self, name: str = "bastion", log_file: Optional[str] = None):
        """Initialize the bastion logger."""
        self.logger = logging.getLogger(name)
        self.log_file = log_file or Config.LOG_FILE
        self.log_level = getattr(logging, Config.LOG_LEVEL.upper(), logging.INFO)
        
        self._setup_logger()
    
    def _setup_logger(self):
        """Setup logger with console and file handlers."""
        # Clear existing handlers
        self.logger.handlers.clear()
        
        # Set log level
        self.logger.setLevel(self.log_level)
        
        # Create formatter
        formatter = logging.Formatter(
            fmt='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(self.log_level)
        console_handler.setFormatter(formatter)
        self.logger.addHandler(console_handler)
        
        # File handler with rotation
        try:
            file_handler = logging.handlers.RotatingFileHandler(
                self.log_file,
                maxBytes=10 * 1024 * 1024,  # 10MB
                backupCount=5
            )
            file_handler.setLevel(self.log_level)
            file_handler.setFormatter(formatter)
            self.logger.addHandler(file_handler)
        except Exception as e:
            self.logger.warning(f"Could not setup file logging: {e}")
    
    def get_logger(self) -> logging.Logger:
        """Get the configured logger."""
        return self.logger


def setup_logging() -> logging.Logger:
    """Setup logging for the bastion application."""
    bastion_logger = BastionLogger()
    return bastion_logger.get_logger()


def log_connection_attempt(logger: logging.Logger, source_ip: str, 
                         fingerprint: str, username: str):
    """Log a connection attempt."""
    logger.info(
        f"Connection attempt - IP: {source_ip}, "
        f"Fingerprint: {fingerprint[:16]}..., User: {username}"
    )


def log_connection_success(logger: logging.Logger, source_ip: str, 
                         fingerprint: str, username: str, target_host: str):
    """Log a successful connection."""
    logger.info(
        f"Connection SUCCESS - IP: {source_ip}, "
        f"Fingerprint: {fingerprint[:16]}..., User: {username}, "
        f"Target: {target_host}"
    )


def log_connection_denied(logger: logging.Logger, source_ip: str, 
                        fingerprint: str, username: str, reason: str):
    """Log a denied connection."""
    logger.warning(
        f"Connection DENIED - IP: {source_ip}, "
        f"Fingerprint: {fingerprint[:16]}..., User: {username}, "
        f"Reason: {reason}"
    )


def log_connection_error(logger: logging.Logger, source_ip: str, 
                       fingerprint: str, username: str, error: str):
    """Log a connection error."""
    logger.error(
        f"Connection ERROR - IP: {source_ip}, "
        f"Fingerprint: {fingerprint[:16]}..., User: {username}, "
        f"Error: {error}"
    )


def log_connection_closed(logger: logging.Logger, source_ip: str, 
                        fingerprint: str, target_host: str):
    """Log a connection closure."""
    logger.info(
        f"Connection CLOSED - IP: {source_ip}, "
        f"Fingerprint: {fingerprint[:16]}..., Target: {target_host}"
    )