#!/bin/bash
# SSH Bastion - Debug and Test Script for OpenRC
# This script helps debug OpenRC service issues

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${CYAN}SSH Bastion OpenRC Debug Tool${NC}"
echo "=================================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Service and path configuration
SERVICE_NAME="bastion"
BASTION_HOME="/opt/bastion-ssh"
VENV_PATH="$BASTION_HOME/venv"
INIT_SCRIPT="/etc/init.d/$SERVICE_NAME"
CONF_FILE="/etc/conf.d/$SERVICE_NAME"
LOG_FILE="/var/log/bastion/bastion.log"
PID_FILE="/var/run/bastion.pid"

echo "1. Checking OpenRC environment..."
if ! command -v openrc-run &>/dev/null; then
    log_error "OpenRC not found!"
    exit 1
fi
log_info "OpenRC is available"

echo
echo "2. Checking service files..."

if [[ -f "$INIT_SCRIPT" ]]; then
    log_info "Init script exists: $INIT_SCRIPT"
    log_info "Init script permissions: $(ls -la $INIT_SCRIPT | awk '{print $1, $3, $4}')"
else
    log_error "Init script not found: $INIT_SCRIPT"
fi

if [[ -f "$CONF_FILE" ]]; then
    log_info "Config file exists: $CONF_FILE"
else
    log_warn "Config file not found: $CONF_FILE"
fi

echo
echo "3. Checking application files..."

if [[ -d "$BASTION_HOME" ]]; then
    log_info "Bastion home exists: $BASTION_HOME"
    log_info "Home permissions: $(ls -lad $BASTION_HOME | awk '{print $1, $3, $4}')"
else
    log_error "Bastion home not found: $BASTION_HOME"
fi

if [[ -f "$VENV_PATH/bin/python" ]]; then
    log_info "Python venv exists: $VENV_PATH"
    
    # Test Python import
    if "$VENV_PATH/bin/python" -c "import bastion.main" 2>/dev/null; then
        log_info "Bastion module can be imported"
    else
        log_error "Cannot import bastion module"
        echo "Trying to show Python path and errors:"
        "$VENV_PATH/bin/python" -c "
import sys
print('Python path:', sys.path)
try:
    import bastion.main
    print('Import successful')
except Exception as e:
    print('Import error:', e)
"
    fi
else
    log_error "Python venv not found: $VENV_PATH"
fi

echo
echo "4. Checking service configuration..."

if [[ -f "$CONF_FILE" ]]; then
    echo "Configuration file contents:"
    cat "$CONF_FILE"
    echo
fi

echo
echo "5. Testing init script syntax..."

if bash -n "$INIT_SCRIPT" 2>/dev/null; then
    log_info "Init script syntax is valid"
else
    log_error "Init script has syntax errors"
    bash -n "$INIT_SCRIPT"
fi

echo
echo "6. Checking OpenRC service status..."

if rc-service "$SERVICE_NAME" status &>/dev/null; then
    log_info "Service status check successful"
    rc-service "$SERVICE_NAME" status
else
    log_warn "Service status check failed"
    rc-service "$SERVICE_NAME" status || true
fi

echo
echo "7. Checking if service is in runlevels..."
if rc-update show | grep -q "$SERVICE_NAME"; then
    log_info "Service is added to runlevel:"
    rc-update show | grep "$SERVICE_NAME"
else
    log_warn "Service is not added to any runlevel"
fi

echo
echo "8. Checking log and PID directories..."

LOG_DIR="$(dirname "$LOG_FILE")"
if [[ -d "$LOG_DIR" ]]; then
    log_info "Log directory exists: $LOG_DIR"
    log_info "Log dir permissions: $(ls -lad $LOG_DIR | awk '{print $1, $3, $4}')"
else
    log_warn "Log directory missing: $LOG_DIR"
fi

PID_DIR="$(dirname "$PID_FILE")"
if [[ -d "$PID_DIR" ]]; then
    log_info "PID directory exists: $PID_DIR"
else
    log_warn "PID directory missing: $PID_DIR"
fi

echo
echo "9. Manual test of command..."

if [[ -f "$VENV_PATH/bin/python" ]]; then
    echo "Attempting to run bastion command manually..."
    echo "Command: $VENV_PATH/bin/python -m bastion.main --help"
    
    if "$VENV_PATH/bin/python" -m bastion.main --help 2>&1; then
        log_info "Manual command test successful"
    else
        log_error "Manual command test failed"
    fi
fi

echo
echo "10. Recommendations..."

if [[ ! -f "$INIT_SCRIPT" ]]; then
    echo "❌ Run the install script to create the init script"
fi

if [[ ! -f "$VENV_PATH/bin/python" ]]; then
    echo "❌ Install Python virtual environment and bastion application"
fi

if ! "$VENV_PATH/bin/python" -c "import bastion.main" 2>/dev/null; then
    echo "❌ Install bastion Python package in virtual environment"
fi

if ! rc-update show | grep -q "$SERVICE_NAME"; then
    echo "⚠️  Add service to runlevel: rc-update add $SERVICE_NAME default"
fi

if [[ ! -d "$(dirname "$LOG_FILE")" ]]; then
    echo "⚠️  Create log directory: mkdir -p $(dirname "$LOG_FILE")"
    echo "   Set permissions: chown bastion:bastion $(dirname "$LOG_FILE")"
fi

echo
echo "Debug completed!"
echo
echo "To try starting the service manually:"
echo "  rc-service $SERVICE_NAME start"
echo
echo "To view detailed errors:"
echo "  rc-service $SERVICE_NAME start --verbose"
echo
echo "To view logs:"
echo "  tail -f $LOG_FILE"