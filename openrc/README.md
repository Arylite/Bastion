# SSH Dynamic Bastion Server - OpenRC Support

This directory contains OpenRC init scripts and configuration files for running the SSH Dynamic Bastion Server on OpenRC-based systems (such as Gentoo, Alpine Linux, etc.).

## Files

- `bastion` - OpenRC init script
- `bastion.conf` - Configuration file with default values
- `install-openrc.sh` - Installation script for OpenRC systems
- `README.md` - This file

## Installation

### Automatic Installation

Run the installation script as root:

```bash
sudo ./install-openrc.sh
```

This script will:
- Check for OpenRC availability
- Create the `bastion` user if it doesn't exist
- Copy the init script to `/etc/init.d/bastion`
- Copy the configuration file to `/etc/conf.d/bastion`
- Set appropriate permissions
- Optionally enable the service for automatic startup

### Manual Installation

1. **Create the bastion user:**
   ```bash
   sudo useradd -r -s /bin/false -d /opt/bastion-ssh -c "SSH Bastion Server" bastion
   ```

2. **Copy the init script:**
   ```bash
   sudo cp bastion /etc/init.d/
   sudo chmod 755 /etc/init.d/bastion
   ```

3. **Copy the configuration file:**
   ```bash
   sudo cp bastion.conf /etc/conf.d/bastion
   sudo chmod 644 /etc/conf.d/bastion
   ```

4. **Enable the service (optional):**
   ```bash
   sudo rc-update add bastion default
   ```

## Configuration

Edit the configuration file to customize the service:

```bash
sudo vim /etc/conf.d/bastion
```

Available configuration options:

- `BASTION_USER` - User to run the service as (default: bastion)
- `BASTION_GROUP` - Group to run the service as (default: bastion)
- `BASTION_HOME` - Installation directory (default: /opt/bastion-ssh)
- `BASTION_VENV` - Python virtual environment path (default: /opt/bastion-ssh/venv)
- `BASTION_PIDFILE` - PID file location (default: /var/run/bastion.pid)
- `BASTION_LOGFILE` - Log file location (default: /var/log/bastion.log)

## Service Management

### Start the service
```bash
sudo rc-service bastion start
```

### Stop the service
```bash
sudo rc-service bastion stop
```

### Restart the service
```bash
sudo rc-service bastion restart
```

### Reload configuration
```bash
sudo rc-service bastion reload
```

### Check service status
```bash
sudo rc-service bastion status
```

### Enable automatic startup
```bash
sudo rc-update add bastion default
```

### Disable automatic startup
```bash
sudo rc-update del bastion default
```

## Logs

Service logs are written to `/var/log/bastion.log` by default. You can change this location in the configuration file.

To view logs:
```bash
sudo tail -f /var/log/bastion.log
```

## Troubleshooting

### Service fails to start

1. Check if the virtual environment exists:
   ```bash
   ls -la /opt/bastion-ssh/venv/bin/python
   ```

2. Check if the bastion module is importable:
   ```bash
   sudo -u bastion /opt/bastion-ssh/venv/bin/python -c "import bastion.main"
   ```

3. Check the logs:
   ```bash
   sudo tail -n 50 /var/log/bastion.log
   ```

4. Run the service in the foreground for debugging:
   ```bash
   sudo -u bastion /opt/bastion-ssh/venv/bin/python -m bastion.main start
   ```

### Permission issues

Ensure the bastion user has proper permissions:
```bash
sudo chown -R bastion:bastion /opt/bastion-ssh
sudo chmod 755 /opt/bastion-ssh
```

### Port binding issues

If the service needs to bind to privileged ports (< 1024), you may need to:

1. Run as root (modify BASTION_USER in configuration)
2. Use capabilities (requires additional setup)
3. Use a port redirect (iptables/netfilter)

## Differences from systemd

The OpenRC implementation provides similar functionality to the systemd service but with some differences:

- Configuration is done via `/etc/conf.d/bastion` instead of systemd environment files
- Logs are written to a file instead of journald
- Service dependencies are declared in the `depend()` function
- Additional commands like `reload` and enhanced `status` are available

## Requirements

- OpenRC init system
- Python 3.6+ with the bastion application installed
- Sufficient permissions to create users and install system services

## Support

This OpenRC configuration has been tested on:
- Gentoo Linux
- Alpine Linux

Other OpenRC-based distributions should work but may require minor adjustments.