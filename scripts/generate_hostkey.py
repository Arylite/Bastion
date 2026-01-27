#!/usr/bin/env python3
"""Script to generate SSH host key for the bastion server."""

import os
import sys
import argparse
from pathlib import Path

import paramiko


def generate_host_key(key_file: str, key_type: str = 'rsa', key_size: int = 2048):
    """Generate SSH host key."""
    try:
        print(f"Generating {key_type.upper()} host key ({key_size} bits)...")
        
        if key_type.lower() == 'rsa':
            host_key = paramiko.RSAKey.generate(key_size)
        elif key_type.lower() == 'dss':
            host_key = paramiko.DSSKey.generate(key_size)
        elif key_type.lower() == 'ecdsa':
            host_key = paramiko.ECDSAKey.generate()
        elif key_type.lower() == 'ed25519':
            host_key = paramiko.Ed25519Key.generate()
        else:
            raise ValueError(f"Unsupported key type: {key_type}")
        
        # Save private key
        host_key.write_private_key_file(key_file)
        
        # Save public key
        public_key_file = f"{key_file}.pub"
        with open(public_key_file, 'w') as f:
            f.write(f"{host_key.get_name()} {host_key.get_base64()}")
        
        # Set proper permissions
        os.chmod(key_file, 0o600)
        os.chmod(public_key_file, 0o644)
        
        print(f"Host key saved to: {key_file}")
        print(f"Public key saved to: {public_key_file}")
        print(f"Key fingerprint: {host_key.get_fingerprint().hex()}")
        
        return True
        
    except Exception as e:
        print(f"Error generating host key: {e}", file=sys.stderr)
        return False


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="Generate SSH host key for bastion server")
    parser.add_argument(
        '--key-file', 
        default='bastion_host_key',
        help='Output file for private key (default: bastion_host_key)'
    )
    parser.add_argument(
        '--key-type',
        choices=['rsa', 'dss', 'ecdsa', 'ed25519'],
        default='rsa',
        help='Key type (default: rsa)'
    )
    parser.add_argument(
        '--key-size',
        type=int,
        default=2048,
        help='Key size in bits (default: 2048, only for RSA/DSS)'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Overwrite existing key file'
    )
    
    args = parser.parse_args()
    
    # Check if file already exists
    if Path(args.key_file).exists() and not args.force:
        print(f"Key file {args.key_file} already exists. Use --force to overwrite.")
        sys.exit(1)
    
    # Generate host key
    success = generate_host_key(args.key_file, args.key_type, args.key_size)
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()