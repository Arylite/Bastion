# SSH Dynamic Bastion - Installation & Usage Guide

## Quick Start

### 1. Install Dependencies

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configuration

Copy and edit the configuration file:

```bash
cp .env.example .env
# Edit .env with your settings
```

### 3. Generate Host Key

```bash
python scripts/generate_hostkey.py --key-file bastion_host_key
```

### 4. Add SSH Keys

Add SSH keys that are allowed to connect:

```bash
# Interactive mode
python setup.py add-key

# Direct mode
python -m bastion.main add-key "SHA256:AAAA..." username 192.168.1.100 ubuntu
```

### 5. Test Configuration

```bash
python -m bastion.main test
```

### 6. Start Server

```bash
# Development
python -m bastion.main start

# Production (systemd)
sudo cp systemd/bastion.service /etc/systemd/system/
sudo systemctl enable bastion
sudo systemctl start bastion
```

## Detailed Setup

### Database Setup

The bastion uses SQLite by default. For production, configure PostgreSQL in [.env](.env):

```bash
DB_URL=postgresql://username:password@localhost/bastion
```

### Adding SSH Keys

1. Get the public key fingerprint:
   ```bash
   ssh-keygen -l -f ~/.ssh/id_rsa.pub
   ```

2. Add to bastion database:
   ```bash
   python -m bastion.main add-key "SHA256:..." username target_host target_user
   ```

### Client Usage

Clients connect normally:
```bash
ssh username@bastion_server
```

The bastion will:
1. Authenticate using the client's SSH key
2. Look up the target VM for that key
3. Establish a transparent proxy to the target
4. No shell access on bastion itself

## Security Notes

- Only SSH key authentication is allowed
- No password authentication
- No shell access on bastion
- No command execution on bastion
- All connections are logged

## Troubleshooting

1. **Connection refused**: Check if bastion server is running
2. **Authentication failed**: Verify SSH key is in database
3. **Target unreachable**: Check target VM connectivity
4. **Permission denied**: Check SSH key permissions and target user

## Development

### Project Structure

```
bastion/
├── __init__.py
├── main.py           # Entry point
├── server.py         # SSH server
├── auth.py           # Authentication
├── router.py         # Routing logic
├── proxy.py          # Traffic relay
├── models.py         # Data models
├── db.py            # Database operations
├── config.py        # Configuration
└── logging.py       # Logging
```

### Running Tests

```bash
# TODO: Add tests
python -m pytest tests/
```

### Code Quality

```bash
# Format code
black bastion/

# Lint code
flake8 bastion/
```