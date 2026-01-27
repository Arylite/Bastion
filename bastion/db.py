"""Database connection and operations for the SSH bastion."""

import sqlite3
import logging
from typing import Optional, List
from contextlib import contextmanager

from .models import SSHKey, Target, ConnectionEvent
from .config import Config


class Database:
    """Database operations for SSH bastion."""
    
    def __init__(self, db_url: str = None): # type: ignore
        """Initialize database connection."""
        self.db_url = db_url or Config.DB_URL
        self.logger = logging.getLogger(__name__)
        self._init_database()
    
    def _init_database(self):
        """Initialize database schema."""
        if self.db_url.startswith("sqlite"):
            db_path = self.db_url.replace("sqlite:///", "")
            with sqlite3.connect(db_path) as conn:
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS ssh_keys (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        fingerprint TEXT UNIQUE NOT NULL,
                        username TEXT NOT NULL,
                        target_host TEXT NOT NULL,
                        target_port INTEGER NOT NULL DEFAULT 22,
                        target_user TEXT NOT NULL,
                        enabled BOOLEAN NOT NULL DEFAULT 1
                    )
                """)
                
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS connection_logs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        fingerprint TEXT NOT NULL,
                        source_ip TEXT NOT NULL,
                        target_host TEXT NOT NULL,
                        target_user TEXT NOT NULL,
                        username TEXT NOT NULL,
                        status TEXT NOT NULL,
                        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                        error_message TEXT
                    )
                """)
                
                conn.execute("""
                    CREATE INDEX IF NOT EXISTS idx_ssh_keys_fingerprint 
                    ON ssh_keys(fingerprint)
                """)
                
                conn.execute("""
                    CREATE INDEX IF NOT EXISTS idx_connection_logs_timestamp 
                    ON connection_logs(timestamp)
                """)
                
                conn.commit()
    
    @contextmanager
    def _get_connection(self):
        """Get database connection context manager."""
        if self.db_url.startswith("sqlite"):
            db_path = self.db_url.replace("sqlite:///", "")
            conn = sqlite3.connect(db_path)
            conn.row_factory = sqlite3.Row
            try:
                yield conn
            finally:
                conn.close()
        else:
            # TODO: Implement PostgreSQL support
            raise NotImplementedError("PostgreSQL support not yet implemented")
    
    def find_ssh_key(self, fingerprint: str) -> Optional[SSHKey]:
        """Find SSH key by fingerprint."""
        try:
            with self._get_connection() as conn:
                cursor = conn.execute(
                    """
                    SELECT id, fingerprint, username, target_host, target_port, 
                           target_user, enabled
                    FROM ssh_keys 
                    WHERE fingerprint = ? AND enabled = 1
                    """, 
                    (fingerprint,)
                )
                row = cursor.fetchone()
                
                if row:
                    return SSHKey(
                        id=row['id'],
                        fingerprint=row['fingerprint'],
                        username=row['username'],
                        target_host=row['target_host'],
                        target_port=row['target_port'],
                        target_user=row['target_user'],
                        enabled=bool(row['enabled'])
                    )
                return None
                
        except Exception as e:
            self.logger.error(f"Error finding SSH key: {e}")
            return None
    
    def add_ssh_key(self, ssh_key: SSHKey) -> bool:
        """Add a new SSH key to the database."""
        try:
            with self._get_connection() as conn:
                conn.execute(
                    """
                    INSERT INTO ssh_keys 
                    (fingerprint, username, target_host, target_port, target_user, enabled)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (
                        ssh_key.fingerprint,
                        ssh_key.username,
                        ssh_key.target_host,
                        ssh_key.target_port,
                        ssh_key.target_user,
                        ssh_key.enabled
                    )
                )
                conn.commit()
                return True
                
        except Exception as e:
            self.logger.error(f"Error adding SSH key: {e}")
            return False
    
    def log_connection_event(self, event: ConnectionEvent) -> bool:
        """Log a connection event."""
        try:
            with self._get_connection() as conn:
                conn.execute(
                    """
                    INSERT INTO connection_logs 
                    (fingerprint, source_ip, target_host, target_user, username, 
                     status, error_message)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        event.fingerprint,
                        event.source_ip,
                        event.target_host,
                        event.target_user,
                        event.username,
                        event.status,
                        event.error_message
                    )
                )
                conn.commit()
                return True
                
        except Exception as e:
            self.logger.error(f"Error logging connection event: {e}")
            return False
    
    def get_target_for_key(self, fingerprint: str) -> Optional[Target]:
        """Get target information for an SSH key."""
        ssh_key = self.find_ssh_key(fingerprint)
        if ssh_key and ssh_key.enabled:
            return Target(
                host=ssh_key.target_host,
                port=ssh_key.target_port,
                user=ssh_key.target_user
            )
        return None