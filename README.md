# SSH Dynamic Bastion

A Python-based SSH server that acts as a dynamic proxy, routing connections to target VMs based on SSH key identity.

## Features

- **SSH Key-Based Authentication** - Only public key authentication, no passwords
- **Identity-Based Routing** - Automatically routes to target VM based on the SSH key used
- **Transparent Proxy** - No shell access on the bastion, pure SSH relay
- **Database-Driven** - SSH keys and target configurations stored in database
- **Comprehensive Logging** - Full audit trail of all connections
- **Production Ready** - Systemd integration and security hardening

## Quick Start

### Installation

See INSTALL.MD.

### Configuration

1. **Generate host key:**
   ```bash
   python scripts/generate_hostkey.py
   ```

2. **Edit `.env` file** with your settings:
   ```env
   BASTION_BIND=0.0.0.0
   BASTION_PORT=2222
   DB_URL=sqlite:///bastion.db
   ```

3. **Add SSH keys to database:**
   ```bash
   python -m bastion.main add-key \
     SHA256:xxxxx \
     username \
     10.0.0.10 \
     target_user
   ```

### Run the Server

```bash
# Development
python -m bastion.main start

# Or test configuration first
python -m bastion.main test
```

## Usage

### Connect through bastion:

```bash
ssh -p 2222 user@bastion-ip
```

The bastion will:
1. Accept your SSH connection
2. Verify your SSH key fingerprint against the database
3. Look up your target VM from the database
4. Relay your connection to the target VM
5. Log the connection event

## Project Structure

```
bastion-ssh/
├── bastion/
│   ├── main.py       # Entry point
│   ├── server.py     # SSH server
│   ├── auth.py       # Authentication
│   ├── router.py     # Routing logic
│   ├── proxy.py      # SSH relay
│   ├── db.py         # Database
│   ├── models.py     # Data models
│   ├── config.py     # Configuration
│   └── logging.py    # Logging
├── scripts/
│   └── generate_hostkey.py
├── systemd/
│   └── bastion.service
├── .env              # Environment config
├── requirements.txt  # Dependencies
└── README.md         # This file
```

## Database Schema

The bastion stores SSH key mappings:

| Field | Description |
|-------|-------------|
| fingerprint | SSH key fingerprint (SHA256) |
| username | SSH username |
| target_host | Target VM IP or hostname |
| target_port | Target SSH port (default: 22) |
| target_user | Username on target VM |
| enabled | Whether key is active |

## Production Deployment

### Using Systemd

```bash
# Copy service file
sudo cp systemd/bastion.service /etc/systemd/system/

# Enable and start
sudo systemctl enable bastion
sudo systemctl start bastion

# View logs
sudo journalctl -u bastion -f
```

### Security Notes

- Only public key authentication is allowed
- No shell access on the bastion
- All connections are logged
- Configure firewall to restrict bastion access
- Use strong SSH keys (RSA 2048+, Ed25519)

## Commands

```bash
# Start server
python -m bastion.main start

# Add SSH key
python -m bastion.main add-key <fingerprint> <username> <target> <target_user> [--target-port PORT]

# List SSH keys (not yet implemented)
python -m bastion.main list-keys

# Test configuration
python -m bastion.main test
```

## Getting SSH Key Fingerprint

```bash
# From public key file
ssh-keygen -l -f ~/.ssh/id_rsa.pub

# Output format: 2048 SHA256:xxxxx user@host (RSA)
# Use the SHA256:xxxxx part
```

## Requirements

- Python 3.11+
- Paramiko (SSH library)
- SQLite or PostgreSQL (database)
- Linux/Unix system

## License

MIT

## Support

For issues and questions, refer to the original specification in the project documentation.
