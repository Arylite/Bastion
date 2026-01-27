"""Main entry point for the SSH bastion server."""

import sys
import signal
import argparse
import logging
from pathlib import Path

from .server import create_server
from .db import Database
from .models import SSHKey
from .config import Config
from .logging import setup_logging


class BastionMain:
    """Main application class for the bastion."""
    
    def __init__(self):
        """Initialize the bastion application."""
        self.logger = setup_logging()
        self.server = None
        self.running = False
    
    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown."""
        def signal_handler(signum, frame):
            self.logger.info(f"Received signal {signum}, shutting down...")
            self.shutdown()
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    def start_server(self):
        """Start the bastion server."""
        try:
            self.logger.info("Starting SSH bastion server...")
            
            # Create and start server
            self.server = create_server()
            self.running = True
            
            # Setup signal handlers
            self.setup_signal_handlers()
            
            # Start the server (this will block)
            self.server.start()
            
        except KeyboardInterrupt:
            self.logger.info("Received keyboard interrupt")
            self.shutdown()
        except Exception as e:
            self.logger.error(f"Error starting server: {e}")
            sys.exit(1)
    
    def shutdown(self):
        """Shutdown the bastion server."""
        try:
            if self.running and self.server:
                self.logger.info("Shutting down server...")
                self.server.stop()
                self.running = False
        except Exception as e:
            self.logger.error(f"Error during shutdown: {e}")
    
    def add_ssh_key(self, fingerprint: str, username: str, target_host: str, 
                   target_user: str, target_port: int = 22):
        """Add an SSH key to the database."""
        try:
            database = Database()
            
            ssh_key = SSHKey(
                fingerprint=fingerprint,
                username=username,
                target_host=target_host,
                target_port=target_port,
                target_user=target_user,
                enabled=True
            )
            
            if database.add_ssh_key(ssh_key):
                self.logger.info(f"Successfully added SSH key: {fingerprint[:16]}...")
                return True
            else:
                self.logger.error("Failed to add SSH key")
                return False
                
        except Exception as e:
            self.logger.error(f"Error adding SSH key: {e}")
            return False
    
    def list_ssh_keys(self):
        """List all SSH keys (placeholder for future implementation)."""
        self.logger.info("List SSH keys functionality not yet implemented")
    
    def test_config(self):
        """Test configuration and database connectivity."""
        try:
            # Test configuration
            config = Config()
            config.validate()
            self.logger.info("Configuration validation passed")
            
            # Test database connection
            database = Database()
            test_key = database.find_ssh_key("test-fingerprint")
            self.logger.info("Database connectivity test passed")
            
            # Test host key
            host_key_file = config.HOST_KEY_FILE
            if Path(host_key_file).exists():
                self.logger.info(f"Host key file exists: {host_key_file}")
            else:
                self.logger.info(f"Host key file will be generated: {host_key_file}")
            
            self.logger.info("Configuration test completed successfully")
            
        except Exception as e:
            self.logger.error(f"Configuration test failed: {e}")
            sys.exit(1)


def main():
    """Main function with command line argument parsing."""
    parser = argparse.ArgumentParser(description="SSH Dynamic Bastion Server")
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Start server command
    start_parser = subparsers.add_parser('start', help='Start the bastion server')
    
    # Add SSH key command
    add_key_parser = subparsers.add_parser('add-key', help='Add SSH key to database')
    add_key_parser.add_argument('fingerprint', help='SSH key fingerprint (SHA256:...)')
    add_key_parser.add_argument('username', help='SSH username')
    add_key_parser.add_argument('target_host', help='Target host IP/hostname')
    add_key_parser.add_argument('target_user', help='Target SSH username')
    add_key_parser.add_argument('--target-port', type=int, default=22, help='Target SSH port (default: 22)')
    
    # List SSH keys command
    list_parser = subparsers.add_parser('list-keys', help='List SSH keys')
    
    # Test configuration command
    test_parser = subparsers.add_parser('test', help='Test configuration and connectivity')
    
    # Parse arguments
    args = parser.parse_args()
    
    # Create main application
    app = BastionMain()
    
    if args.command == 'start' or args.command is None:
        # Start server (default action)
        app.start_server()
        
    elif args.command == 'add-key':
        # Add SSH key
        success = app.add_ssh_key(
            args.fingerprint,
            args.username,
            args.target_host,
            args.target_user,
            args.target_port
        )
        sys.exit(0 if success else 1)
        
    elif args.command == 'list-keys':
        # List SSH keys
        app.list_ssh_keys()
        
    elif args.command == 'test':
        # Test configuration
        app.test_config()
        
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()