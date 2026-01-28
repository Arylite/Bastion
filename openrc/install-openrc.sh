#!/bin/bash
# Installation script for SSH Dynamic Bastion Server on OpenRC systems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
BASTION_USER="bastion"
BASTION_GROUP="bastion"
BASTION_HOME="/opt/bastion-ssh"
SERVICE_NAME="bastion"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_openrc() {
    if ! command -v openrc-run &> /dev/null; then
        log_error "OpenRC not found. This script is designed for OpenRC systems."
        exit 1
    fi
    log_info "OpenRC detected"
}

create_user() {
    if ! id "${BASTION_USER}" &>/dev/null; then
        log_info "Creating user ${BASTION_USER}"
        useradd -r -s /bin/false -d "${BASTION_HOME}" -c "SSH Bastion Server" "${BASTION_USER}"
    else
        log_info "User ${BASTION_USER} already exists"
    fi
}

install_service() {
    log_info "Installing OpenRC service files"
    
    # Copy init script
    cp "$(dirname "$0")/bastion" /etc/init.d/
    chmod 755 /etc/init.d/bastion
    log_info "Installed init script to /etc/init.d/bastion"
    
    # Copy configuration file
    cp "$(dirname "$0")/bastion.conf" /etc/conf.d/bastion
    chmod 644 /etc/conf.d/bastion
    log_info "Installed configuration file to /etc/conf.d/bastion"
    
    # Create necessary directories
    mkdir -p /var/run
    mkdir -p /var/log
    
    # Set ownership
    if [[ -d "${BASTION_HOME}" ]]; then
        chown -R "${BASTION_USER}:${BASTION_GROUP}" "${BASTION_HOME}"
        log_info "Set ownership of ${BASTION_HOME} to ${BASTION_USER}:${BASTION_GROUP}"
    else
        log_warn "Directory ${BASTION_HOME} does not exist. Please create it and install the bastion application."
    fi
}

enable_service() {
    log_info "Adding bastion to default runlevel"
    rc-update add bastion default
}

main() {
    echo "SSH Dynamic Bastion Server - OpenRC Installation Script"
    echo "======================================================="
    
    check_root
    check_openrc
    create_user
    install_service
    
    read -p "Do you want to enable the service to start at boot? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        enable_service
        log_info "Service enabled for automatic startup"
    else
        log_info "Service not enabled for automatic startup"
        log_info "You can enable it later with: rc-update add bastion default"
    fi
    
    echo
    log_info "Installation completed!"
    echo
    echo "Usage:"
    echo "  Start service:   rc-service bastion start"
    echo "  Stop service:    rc-service bastion stop"
    echo "  Restart service: rc-service bastion restart"
    echo "  Reload config:   rc-service bastion reload"
    echo "  Service status:  rc-service bastion status"
    echo
    echo "Configuration file: /etc/conf.d/bastion"
    echo "Log file: /var/log/bastion.log"
}

main "$@"