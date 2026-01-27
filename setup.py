#!/usr/bin/env python3
"""Setup script for adding SSH keys to the bastion database."""

import sys
import subprocess
from pathlib import Path

def get_ssh_key_fingerprint(public_key_file: str) -> str:
    """Get SSH key fingerprint using ssh-keygen."""
    try:
        result = subprocess.run(
            ['ssh-keygen', '-l', '-f', public_key_file],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Parse output: "2048 SHA256:... user@host (RSA)"
        parts = result.stdout.strip().split()
        if len(parts) >= 2:
            return parts[1]  # SHA256:...
        
        return ""
        
    except Exception as e:
        print(f"Error getting fingerprint: {e}", file=sys.stderr)
        return ""


def add_key_interactive():
    """Interactive mode to add SSH key."""
    print("=== SSH Bastion - Add SSH Key ===")
    print()
    
    # Get public key file
    pub_key_file = input("Public key file path (e.g., ~/.ssh/id_rsa.pub): ").strip()
    if not Path(pub_key_file).exists():
        print(f"Error: File {pub_key_file} does not exist")
        return False
    
    # Get fingerprint
    fingerprint = get_ssh_key_fingerprint(pub_key_file)
    if not fingerprint:
        print("Error: Could not get key fingerprint")
        return False
    
    print(f"Key fingerprint: {fingerprint}")
    
    # Get other information
    username = input("SSH username: ").strip()
    target_host = input("Target host (IP or hostname): ").strip()
    target_user = input("Target SSH username: ").strip()
    target_port = input("Target SSH port (default 22): ").strip() or "22"
    
    try:
        target_port = int(target_port)
    except ValueError:
        print("Error: Invalid port number")
        return False
    
    # Confirm
    print()
    print("=== Confirm SSH Key Addition ===")
    print(f"Fingerprint: {fingerprint}")
    print(f"Username: {username}")
    print(f"Target: {target_user}@{target_host}:{target_port}")
    print()
    
    confirm = input("Add this key? (y/N): ").strip().lower()
    if confirm != 'y':
        print("Cancelled")
        return False
    
    # Add the key using bastion command
    try:
        result = subprocess.run([
            sys.executable, '-m', 'bastion.main', 'add-key',
            fingerprint, username, target_host, target_user,
            '--target-port', str(target_port)
        ], check=True)
        
        print("SSH key added successfully!")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"Error adding SSH key: {e}")
        return False


def main():
    """Main function."""
    print("SSH Bastion Setup Utility")
    print()
    
    if len(sys.argv) > 1 and sys.argv[1] == 'add-key':
        success = add_key_interactive()
        sys.exit(0 if success else 1)
    else:
        print("Available commands:")
        print("  python setup.py add-key    - Add SSH key interactively")
        print()
        print("For direct key addition, use:")
        print("  python -m bastion.main add-key <fingerprint> <username> <target_host> <target_user> [--target-port <port>]")


if __name__ == '__main__':
    main()