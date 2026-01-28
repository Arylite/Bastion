#!/bin/bash
# SSH Dynamic Bastion Server - Universal Installation Script
# Supports systemd, OpenRC, and other init systems
# Usage: sudo ./install.sh [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BASTION_USER="bastion"
BASTION_GROUP="bastion"
BASTION_HOME="/opt/bastion-ssh"
SERVICE_NAME="bastion"
PYTHON_VERSION="3.11"
VENV_PATH="${BASTION_HOME}/venv"
CONFIG_DIR="/etc/bastion"
LOG_DIR="/var/log/bastion"
DATA_DIR="/var/lib/bastion"
ENV_FILE="${BASTION_HOME}/.env"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Flags
SKIP_DEPS=false
SKIP_SERVICE=false
FORCE=false
DRY_RUN=false
VERBOSE=false

# Print functions
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  Bastion Server Installer                    ║"
    echo "║                     Universal Edition                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
SSH Dynamic Bastion Server - Universal Installation Script

USAGE:
    sudo $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -u, --user USER         Specify bastion user (default: bastion)
    -g, --group GROUP       Specify bastion group (default: bastion)
    -d, --directory DIR     Installation directory (default: /opt/bastion-ssh)
    --skip-deps             Skip dependency installation
    --skip-service          Skip service installation/configuration
    --force                 Force installation (overwrite existing)
    --dry-run               Show what would be done without executing
    -v, --verbose           Enable verbose output
    --python-version VER    Python version to use (default: 3.11)

EXAMPLES:
    # Basic installation
    sudo $0

    # Custom user and directory
    sudo $0 --user mybastion --directory /opt/my-bastion

    # Skip dependency installation (useful for Docker)
    sudo $0 --skip-deps

    # Dry run to see what would be done
    sudo $0 --dry-run

SUPPORTED SYSTEMS:
    - Ubuntu/Debian (systemd)
    - CentOS/RHEL/Fedora (systemd)
    - Alpine Linux (OpenRC)
    - Arch Linux (systemd)
    - openSUSE (systemd)
    - Gentoo (OpenRC)
    - And more...

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -u|--user)
                BASTION_USER="$2"
                shift 2
                ;;
            -g|--group)
                BASTION_GROUP="$2"
                shift 2
                ;;
            -d|--directory)
                BASTION_HOME="$2"
                VENV_PATH="${BASTION_HOME}/venv"
                shift 2
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --skip-service)
                SKIP_SERVICE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --python-version)
                PYTHON_VERSION="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Execute command with dry run support
execute() {
    local cmd="$*"
    log_debug "Command: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $cmd"
    else
        eval "$cmd"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$NAME"
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_NAME="Red Hat Enterprise Linux"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        OS_NAME="Debian"
    else
        OS="unknown"
        OS_NAME="Unknown"
    fi
    
    log_info "Detected OS: $OS_NAME"
    log_debug "OS ID: $OS, Version: ${OS_VERSION:-unknown}"
}

# Detect init system
detect_init_system() {
    if systemctl --version &>/dev/null && [[ -d /run/systemd/system ]]; then
        INIT_SYSTEM="systemd"
        log_info "Detected init system: systemd"
    elif command -v openrc-run &>/dev/null || [[ -d /etc/init.d && -f /sbin/openrc-run ]]; then
        INIT_SYSTEM="openrc"
        log_info "Detected init system: OpenRC"
    elif [[ -d /etc/init.d && -f /sbin/service ]]; then
        INIT_SYSTEM="sysv"
        log_info "Detected init system: SysV Init"
    elif command -v initctl &>/dev/null; then
        INIT_SYSTEM="upstart"
        log_info "Detected init system: Upstart"
    else
        INIT_SYSTEM="unknown"
        log_warn "Could not detect init system"
    fi
}

# Detect package manager
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
        PYTHON_PKG="python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache"
        PKG_INSTALL="yum install -y"
        PYTHON_PKG="python${PYTHON_VERSION} python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-pip"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
        PYTHON_PKG="python${PYTHON_VERSION} python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-pip"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
        PYTHON_PKG="python3 python3-dev py3-pip py3-virtualenv"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
        PYTHON_PKG="python python-pip python-virtualenv"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
        PKG_UPDATE="zypper refresh"
        PKG_INSTALL="zypper install -y"
        PYTHON_PKG="python${PYTHON_VERSION} python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-pip"
    elif command -v emerge &>/dev/null; then
        PKG_MANAGER="portage"
        PKG_UPDATE="emerge --sync"
        PKG_INSTALL="emerge"
        PYTHON_PKG="dev-lang/python dev-python/pip dev-python/virtualenv"
    else
        PKG_MANAGER="unknown"
        log_warn "Could not detect package manager"
    fi
    
    if [[ "$PKG_MANAGER" != "unknown" ]]; then
        log_info "Detected package manager: $PKG_MANAGER"
    fi
}

# Install dependencies
install_dependencies() {
    if [[ "$SKIP_DEPS" == "true" ]]; then
        log_info "Skipping dependency installation"
        return
    fi
    
    log_step "Installing system dependencies"
    
    # Update package cache
    if [[ "$PKG_MANAGER" != "unknown" ]]; then
        log_info "Updating package cache..."
        execute "$PKG_UPDATE"
        
        # Install Python and essential packages
        log_info "Installing Python and essential packages..."
        case "$PKG_MANAGER" in
            apt)
                execute "$PKG_INSTALL build-essential libssl-dev libffi-dev $PYTHON_PKG postgresql-client"
                ;;
            yum|dnf)
                execute "$PKG_INSTALL gcc openssl-devel libffi-devel $PYTHON_PKG postgresql"
                ;;
            apk)
                execute "$PKG_INSTALL build-base openssl-dev libffi-dev $PYTHON_PKG postgresql-client"
                ;;
            pacman)
                execute "$PKG_INSTALL base-devel openssl libffi $PYTHON_PKG postgresql"
                ;;
            zypper)
                execute "$PKG_INSTALL gcc openssl-devel libffi-devel $PYTHON_PKG postgresql"
                ;;
            portage)
                execute "$PKG_INSTALL dev-libs/openssl dev-libs/libffi $PYTHON_PKG dev-db/postgresql"
                ;;
        esac
    else
        log_warn "Unknown package manager. Please install Python $PYTHON_VERSION and development tools manually"
    fi
}

# Create user and group
create_user() {
    log_step "Setting up user and group"
    
    # Create group if it doesn't exist
    if ! getent group "$BASTION_GROUP" &>/dev/null; then
        log_info "Creating group: $BASTION_GROUP"
        execute "groupadd -r $BASTION_GROUP"
    else
        log_debug "Group $BASTION_GROUP already exists"
    fi
    
    # Create user if it doesn't exist
    if ! id "$BASTION_USER" &>/dev/null; then
        log_info "Creating user: $BASTION_USER"
        execute "useradd -r -s /bin/false -d $BASTION_HOME -g $BASTION_GROUP -c 'SSH Bastion Server' $BASTION_USER"
    else
        log_debug "User $BASTION_USER already exists"
    fi
}

# Create directories
create_directories() {
    log_step "Creating directories"
    
    local dirs=(
        "$BASTION_HOME"
        "$CONFIG_DIR"
        "$LOG_DIR"
        "$DATA_DIR"
        "$(dirname "$BASTION_HOME")"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]] || [[ "$FORCE" == "true" ]]; then
            log_info "Creating directory: $dir"
            execute "mkdir -p $dir"
            execute "chown $BASTION_USER:$BASTION_GROUP $dir"
            execute "chmod 755 $dir"
        else
            log_debug "Directory $dir already exists"
        fi
    done
    
    # Special permissions for log directory
    execute "chmod 750 $LOG_DIR"
    execute "chmod 750 $DATA_DIR"
}

# Install Python application
install_application() {
    log_step "Installing SSH Bastion application"
    
    # Copy application files
    log_info "Copying application files..."
    if [[ -d "$SCRIPT_DIR/bastion" ]]; then
        execute "cp -r $SCRIPT_DIR/bastion $BASTION_HOME/"
    else
        log_error "Bastion application directory not found at $SCRIPT_DIR/bastion"
        exit 1
    fi
    
    # Copy additional files
    for file in "requirements.txt" "pyproject.toml"; do
        if [[ -f "$SCRIPT_DIR/$file" ]]; then
            execute "cp $SCRIPT_DIR/$file $BASTION_HOME/"
        fi
    done
    
    # Setup Python virtual environment
    log_info "Setting up Python virtual environment..."
    
    # Find Python executable
    PYTHON_CMD=""
    for py_cmd in "python${PYTHON_VERSION}" "python3" "python"; do
        if command -v "$py_cmd" &>/dev/null; then
            PYTHON_CMD="$py_cmd"
            break
        fi
    done
    
    if [[ -z "$PYTHON_CMD" ]]; then
        log_error "Python not found. Please install Python $PYTHON_VERSION"
        exit 1
    fi
    
    log_info "Using Python: $PYTHON_CMD"
    
    # Create virtual environment
    execute "$PYTHON_CMD -m venv $VENV_PATH"
    
    # Upgrade pip and install dependencies
    execute "$VENV_PATH/bin/pip install --upgrade pip setuptools wheel"
    
    if [[ -f "$BASTION_HOME/requirements.txt" ]]; then
        log_info "Installing Python dependencies..."
        execute "$VENV_PATH/bin/pip install -r $BASTION_HOME/requirements.txt"
    fi
    
    # Install the application
    execute "$VENV_PATH/bin/pip install -e $BASTION_HOME"
    
    # Set permissions
    execute "chown -R $BASTION_USER:$BASTION_GROUP $BASTION_HOME"
    execute "chmod -R 755 $BASTION_HOME"
    execute "chmod +x $VENV_PATH/bin/*"
}

# Generate host keys
generate_host_keys() {
    log_step "Generating SSH host keys"
    
    local key_dir="$BASTION_HOME/keys"
    execute "mkdir -p $key_dir"
    
    # Generate different key types
    local key_types=("rsa" "ecdsa" "ed25519")
    
    for key_type in "${key_types[@]}"; do
        local key_file="$key_dir/ssh_host_${key_type}_key"
        if [[ ! -f "$key_file" ]] || [[ "$FORCE" == "true" ]]; then
            log_info "Generating $key_type host key..."
            case "$key_type" in
                rsa)
                    execute "ssh-keygen -t rsa -b 4096 -f $key_file -N '' -C 'SSH Bastion Host Key'"
                    ;;
                ecdsa)
                    execute "ssh-keygen -t ecdsa -b 521 -f $key_file -N '' -C 'SSH Bastion Host Key'"
                    ;;
                ed25519)
                    execute "ssh-keygen -t ed25519 -f $key_file -N '' -C 'SSH Bastion Host Key'"
                    ;;
            esac
        else
            log_debug "Host key $key_file already exists"
        fi
    done
    
    execute "chown -R $BASTION_USER:$BASTION_GROUP $key_dir"
    execute "chmod 600 $key_dir/ssh_host_*_key"
    execute "chmod 644 $key_dir/ssh_host_*_key.pub"
}

# Install systemd service
install_systemd_service() {
    log_info "Installing systemd service..."
    
    local service_file="/etc/systemd/system/$SERVICE_NAME.service"
    
    # Copy and customize service file
    if [[ -f "$SCRIPT_DIR/systemd/bastion.service" ]]; then
        execute "cp $SCRIPT_DIR/systemd/bastion.service $service_file"
        
        # Update paths in service file
        execute "sed -i 's|WorkingDirectory=.*|WorkingDirectory=$BASTION_HOME|g' $service_file"
        execute "sed -i 's|ExecStart=.*|ExecStart=$VENV_PATH/bin/python -m bastion.main start|g' $service_file"
        execute "sed -i 's|ReadWritePaths=.*|ReadWritePaths=$BASTION_HOME $LOG_DIR $DATA_DIR|g' $service_file"
        
        # Set user if not root
        if [[ "$BASTION_USER" != "root" ]]; then
            execute "sed -i 's|^User=.*|User=$BASTION_USER|g' $service_file"
            execute "sed -i 's|^#.*User=bastion|User=$BASTION_USER|g' $service_file"
            execute "sed -i 's|^Group=.*|Group=$BASTION_GROUP|g' $service_file"
            execute "sed -i 's|^#.*Group=bastion|Group=$BASTION_GROUP|g' $service_file"
        fi
        
        execute "systemctl daemon-reload"
        execute "systemctl enable $SERVICE_NAME"
        
        log_info "Systemd service installed successfully"
    else
        log_error "Systemd service file not found at $SCRIPT_DIR/systemd/bastion.service"
        exit 1
    fi
}

# Install OpenRC service
install_openrc_service() {
    log_info "Installing OpenRC service..."
    
    local init_script="/etc/init.d/$SERVICE_NAME"
    local conf_file="/etc/conf.d/$SERVICE_NAME"
    
    # Create OpenRC init script
    log_info "Creating OpenRC init script..."
    cat > "$init_script" << 'EOF'
#!/sbin/openrc-run
# SSH Dynamic Bastion Server OpenRC init script

name="SSH Dynamic Bastion Server"
description="SSH Dynamic Bastion Server for secure remote access"

# Load configuration from /etc/conf.d/bastion
: ${BASTION_USER:=bastion}
: ${BASTION_GROUP:=bastion}
: ${BASTION_HOME:=/opt/bastion-ssh}
: ${BASTION_VENV:=/opt/bastion-ssh/venv}
: ${BASTION_PIDFILE:=/var/run/bastion.pid}
: ${BASTION_LOGFILE:=/var/log/bastion/bastion.log}
: ${BASTION_ENV_FILE:=/opt/bastion-ssh/.env}

# OpenRC configuration
command="${BASTION_VENV}/bin/python"
command_args="-m bastion.main start"
command_background="yes"
command_user="${BASTION_USER}:${BASTION_GROUP}"
pidfile="${BASTION_PIDFILE}"
directory="${BASTION_HOME}"

# Output redirection
output_log="${BASTION_LOGFILE}"
error_log="${BASTION_LOGFILE}"

# Dependencies
depend() {
    need net
    use logger dns
    after firewall
}

# Pre-start checks
start_pre() {
    # Check if virtual environment exists
    if [ ! -f "${BASTION_VENV}/bin/python" ]; then
        eerror "Python virtual environment not found at ${BASTION_VENV}"
        return 1
    fi

    # Check if bastion module exists
    if ! "${BASTION_VENV}/bin/python" -c "import bastion.main" 2>/dev/null; then
        eerror "Bastion module not found or not importable"
        return 1
    fi

    # Create PID file directory if it doesn't exist
    checkpath --directory --owner "${BASTION_USER}:${BASTION_GROUP}" --mode 0755 "$(dirname "${BASTION_PIDFILE}")"
    
    # Create log file directory if it doesn't exist
    checkpath --directory --owner "${BASTION_USER}:${BASTION_GROUP}" --mode 0755 "$(dirname "${BASTION_LOGFILE}")"
    
    # Create log file if it doesn't exist
    checkpath --file --owner "${BASTION_USER}:${BASTION_GROUP}" --mode 0644 "${BASTION_LOGFILE}"
    
    # Check if env file exists
    if [ ! -f "${BASTION_ENV_FILE}" ]; then
        ewarn "Environment file not found at ${BASTION_ENV_FILE}"
    fi

    einfo "Starting ${description}..."
}

# Post-start checks
start_post() {
    # Wait a moment for the service to start
    sleep 2
    
    # Check if the service actually started
    if [ -f "${BASTION_PIDFILE}" ]; then
        local pid=$(cat "${BASTION_PIDFILE}")
        if kill -0 "$pid" 2>/dev/null; then
            einfo "${description} started successfully with PID $pid"
        else
            eerror "${description} failed to start"
            return 1
        fi
    else
        eerror "PID file not created"
        return 1
    fi
}

# Pre-stop function
stop_pre() {
    einfo "Stopping ${description}..."
}

# Post-stop cleanup
stop_post() {
    # Clean up PID file if it still exists
    if [ -f "${BASTION_PIDFILE}" ]; then
        rm -f "${BASTION_PIDFILE}"
    fi
    einfo "${description} stopped"
}

# Reload function
reload() {
    einfo "Reloading ${description}..."
    if [ -f "${BASTION_PIDFILE}" ]; then
        local pid=$(cat "${BASTION_PIDFILE}")
        if kill -0 "$pid" 2>/dev/null; then
            kill -HUP "$pid"
            einfo "Reload signal sent to ${description}"
        else
            eerror "${description} is not running"
            return 1
        fi
    else
        eerror "PID file not found"
        return 1
    fi
}

# Status function
status() {
    if [ -f "${BASTION_PIDFILE}" ]; then
        local pid=$(cat "${BASTION_PIDFILE}")
        if kill -0 "$pid" 2>/dev/null; then
            einfo "${description} is running with PID $pid"
        else
            eerror "${description} is not running (PID file exists but process is dead)"
            return 1
        fi
    else
        einfo "${description} is not running"
        return 1
    fi
}
EOF

    # Make init script executable
    execute "chmod +x $init_script"
    
    # Create configuration file
    log_info "Creating OpenRC configuration file..."
    cat > "$conf_file" << EOF
# Configuration file for SSH Dynamic Bastion Server (OpenRC)

# User and group to run the service as
BASTION_USER="$BASTION_USER"
BASTION_GROUP="$BASTION_GROUP"

# Installation directory
BASTION_HOME="$BASTION_HOME"

# Python virtual environment path
BASTION_VENV="$VENV_PATH"

# PID file location
BASTION_PIDFILE="/var/run/bastion.pid"

# Log file location
BASTION_LOGFILE="$LOG_DIR/bastion.log"

# Environment file location
BASTION_ENV_FILE="$ENV_FILE"

# Additional environment variables can be set here
# export BASTION_DEBUG="false"
# export BASTION_PORT="2222"
EOF

    # Add service to default runlevel
    execute "rc-update add $SERVICE_NAME default"
    log_info "OpenRC service installed and enabled successfully"
}

# Install SysV service
install_sysv_service() {
    log_warn "SysV Init detected. Creating basic init script..."
    
    local init_script="/etc/init.d/$SERVICE_NAME"
    
    cat > "$init_script" << EOF
#!/bin/bash
# SSH Bastion Server SysV init script
# chkconfig: 35 99 99
# description: SSH Dynamic Bastion Server

. /etc/rc.d/init.d/functions

USER="$BASTION_USER"
DAEMON="$SERVICE_NAME"
ROOT_DIR="$BASTION_HOME"
DAEMON_PATH="\$ROOT_DIR/venv/bin/python"
DAEMON_OPTS="-m bastion.main start"
PIDFILE="/var/run/\$DAEMON.pid"
LOCKFILE="/var/lock/subsys/\$DAEMON"

start() {
    if [ -f \$PIDFILE ] && kill -0 \$(cat \$PIDFILE); then
        echo '\$DAEMON already running' >&2
        return 1
    fi
    echo -n "Starting \$DAEMON: "
    runuser -l "\$USER" -c "\$DAEMON_PATH \$DAEMON_OPTS" && echo_success || echo_failure
    RETVAL=\$?
    echo
    [ \$RETVAL -eq 0 ] && touch \$LOCKFILE
    return \$RETVAL
}

stop() {
    if [ ! -f "\$PIDFILE" ] || ! kill -0 \$(cat "\$PIDFILE"); then
        echo '\$DAEMON not running' >&2
        return 1
    fi
    echo -n "Shutting down \$DAEMON: "
    pid=\$(cat \$PIDFILE)
    kill -15 \$pid && echo_success || echo_failure
    RETVAL=\$?
    echo
    [ \$RETVAL -eq 0 ] && rm -f \$LOCKFILE
    return \$RETVAL
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status \$DAEMON
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Usage: {\$0 {start|stop|status|restart}"
        exit 1
        ;;
esac

exit \$?
EOF

    execute "chmod +x $init_script"
    
    # Add to startup (distribution-specific)
    if command -v chkconfig &>/dev/null; then
        execute "chkconfig --add $SERVICE_NAME"
        execute "chkconfig $SERVICE_NAME on"
    elif command -v update-rc.d &>/dev/null; then
        execute "update-rc.d $SERVICE_NAME defaults"
    fi
    
    log_info "SysV init script installed successfully"
}

# Install service based on init system
install_service() {
    if [[ "$SKIP_SERVICE" == "true" ]]; then
        log_info "Skipping service installation"
        return
    fi
    
    log_step "Installing service for $INIT_SYSTEM"
    
    case "$INIT_SYSTEM" in
        systemd)
            install_systemd_service
            ;;
        openrc)
            install_openrc_service
            ;;
        sysv)
            install_sysv_service
            ;;
        upstart)
            log_warn "Upstart support is limited. Please configure manually."
            ;;
        *)
            log_warn "Unknown init system. Service not installed."
            ;;
    esac
}

# Create sample configuration
create_config() {
    log_step "Creating configuration files"
    
    local config_file="$CONFIG_DIR/config.yml"
    local env_file="$ENV_FILE"
    
    # Create YAML config file
    if [[ ! -f "$config_file" ]] || [[ "$FORCE" == "true" ]]; then
        log_info "Creating sample YAML configuration..."
        
        cat > "$config_file" << EOF
# SSH Dynamic Bastion Server Configuration

# Server settings
server:
  host: "0.0.0.0"
  port: 2222
  host_key_paths:
    - "$BASTION_HOME/keys/ssh_host_rsa_key"
    - "$BASTION_HOME/keys/ssh_host_ecdsa_key"
    - "$BASTION_HOME/keys/ssh_host_ed25519_key"

# Database settings (SQLite for simplicity, change to PostgreSQL in production)
database:
  url: "sqlite:////$DATA_DIR/bastion.db"
  # For PostgreSQL, use:
  # url: "postgresql://bastion_user:bastion_password@localhost:5432/bastion"
  
# Logging settings
logging:
  level: "INFO"
  file: "$LOG_DIR/bastion.log"
  max_size: "10MB"
  backup_count: 5

# Security settings
security:
  max_connections: 100
  max_connections_per_ip: 5
  connection_timeout: 300
  idle_timeout: 600
  max_auth_attempts: 3

# Proxy settings
proxy:
  buffer_size: 65536
  connect_timeout: 10
EOF

        execute "chown $BASTION_USER:$BASTION_GROUP $config_file"
        execute "chmod 640 $config_file"
    else
        log_debug "YAML configuration file already exists"
    fi
    
    # Create .env file
    if [[ ! -f "$env_file" ]] || [[ "$FORCE" == "true" ]]; then
        log_info "Creating environment configuration..."
        
        # Copy from example if it exists
        if [[ -f "$SCRIPT_DIR/.env.example" ]]; then
            execute "cp $SCRIPT_DIR/.env.example $env_file"
        else
            # Create from template
            cat > "$env_file" << EOF
# Bastion SSH Configuration
BASTION_BIND=0.0.0.0
BASTION_PORT=2222

# Database Configuration  
DB_URL=sqlite:///$DATA_DIR/bastion.db

# Logging Configuration
LOG_LEVEL=INFO
LOG_FILE=$LOG_DIR/bastion.log

# Security Configuration
MAX_CONNECTIONS_PER_IP=5
CONNECTION_TIMEOUT=300

# SSH Configuration
HOST_KEY_FILE=$BASTION_HOME/keys/ssh_host_rsa_key
HOST_KEY_DIR=$BASTION_HOME/keys

# Application Configuration
BASTION_HOME=$BASTION_HOME
BASTION_CONFIG=$CONFIG_DIR/config.yml
BASTION_DATA_DIR=$DATA_DIR
EOF
        fi
        
        execute "chown $BASTION_USER:$BASTION_GROUP $env_file"
        execute "chmod 640 $env_file"
    else
        log_debug "Environment file already exists"
    fi
    
    # Create database directory for SQLite
    execute "mkdir -p $DATA_DIR"
    execute "chown $BASTION_USER:$BASTION_GROUP $DATA_DIR"
    execute "chmod 750 $DATA_DIR"
}

# Setup firewall rules
setup_firewall() {
    log_step "Setting up firewall (optional)"
    
    local port="2222"
    
    if command -v ufw &>/dev/null; then
        log_info "Configuring UFW firewall..."
        execute "ufw allow $port/tcp comment 'SSH Bastion Server'"
    elif command -v firewall-cmd &>/dev/null; then
        log_info "Configuring firewalld..."
        execute "firewall-cmd --permanent --add-port=$port/tcp"
        execute "firewall-cmd --reload"
    elif command -v iptables &>/dev/null; then
        log_warn "Please manually configure iptables to allow port $port/tcp"
    else
        log_warn "No firewall management tool detected. Please configure firewall manually."
    fi
}

# Run post-installation tests
run_tests() {
    log_step "Running post-installation tests"
    
    # Test Python environment
    log_info "Testing Python environment..."
    if execute "$VENV_PATH/bin/python -c 'import bastion.main; print(\"Bastion module imported successfully\")'"; then
        log_info "✓ Python environment test passed"
    else
        log_error "✗ Python environment test failed"
        return 1
    fi
    
    # Test service configuration
    case "$INIT_SYSTEM" in
        systemd)
            if execute "systemctl is-enabled $SERVICE_NAME"; then
                log_info "✓ Service is enabled"
            else
                log_warn "✗ Service is not enabled"
            fi
            ;;
        openrc)
            if execute "rc-service $SERVICE_NAME status"; then
                log_info "✓ Service configuration test passed"
            else
                log_warn "✗ Service configuration test failed"
            fi
            ;;
    esac
    
    # Test permissions
    log_info "Testing permissions..."
    if [[ -r "$BASTION_HOME" && -x "$BASTION_HOME" ]]; then
        log_info "✓ Directory permissions test passed"
    else
        log_warn "✗ Directory permissions test failed"
    fi
}

# Print post-installation instructions
print_instructions() {
    echo
    log_step "Installation completed successfully!"
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    POST-INSTALLATION INSTRUCTIONS                 ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}1. Configuration files:${NC}"
    echo -e "   YAML Config: ${CYAN}$CONFIG_DIR/config.yml${NC}"
    echo -e "   Environment: ${CYAN}$ENV_FILE${NC}"
    echo -e "   Edit these files to customize the bastion server"
    echo
    echo -e "${YELLOW}2. Database setup:${NC}"
    echo -e "   ${GREEN}SQLite (default):${NC} Already configured in $DATA_DIR/bastion.db"
    echo -e "   ${GREEN}PostgreSQL (optional):${NC}"
    echo -e "   ${CYAN}sudo -u postgres createdb bastion${NC}"
    echo -e "   ${CYAN}sudo -u postgres createuser bastion_user${NC}"
    echo -e "   ${CYAN}sudo -u postgres psql -c \"ALTER USER bastion_user WITH PASSWORD 'bastion_password';\"${NC}"
    echo -e "   ${CYAN}sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE bastion TO bastion_user;\"${NC}"
    echo -e "   Then update DB_URL in ${CYAN}$ENV_FILE${NC}"
    echo
    echo -e "${YELLOW}3. Start the service:${NC}"
    case "$INIT_SYSTEM" in
        systemd)
            echo -e "\t${CYAN}sudo systemctl start $SERVICE_NAME${NC}"
            echo -e "\t${CYAN}sudo systemctl status $SERVICE_NAME${NC}"
            echo -e "\t${CYAN}sudo journalctl -u $SERVICE_NAME -f${NC}  # View logs"
            ;;
        openrc)
            echo -e "\t${CYAN}sudo rc-service $SERVICE_NAME start${NC}"
            echo -e "\t${CYAN}sudo rc-service $SERVICE_NAME status${NC}"
            echo -e "\t${CYAN}tail -f $LOG_DIR/bastion.log${NC}  # View logs"
            ;;
        sysv)
            echo -e "\t${CYAN}sudo service $SERVICE_NAME start${NC}"
            echo -e "\t${CYAN}sudo service $SERVICE_NAME status${NC}"
            echo -e "\t${CYAN}tail -f $LOG_DIR/bastion.log${NC}  # View logs"
            ;;
        *)
            echo -e "\t${CYAN}sudo -u $BASTION_USER $VENV_PATH/bin/python -m bastion.main start${NC}"
            ;;
    esac
    echo
    echo -e "${YELLOW}4. Add SSH keys to the database:${NC}"
    echo -e "\t${CYAN}sudo -u $BASTION_USER $VENV_PATH/bin/python $BASTION_HOME/setup.py${NC}"
    echo
    echo -e "${YELLOW}5. Test the connection:${NC}"
    echo -e "\t${CYAN}ssh -p 2222 username@$(hostname -I | awk '{print $1}' 2>/dev/null || echo 'localhost')${NC}"
    echo
    echo -e "${YELLOW}6. Service management commands:${NC}"
    case "$INIT_SYSTEM" in
        systemd)
            echo -e "   Start:   ${CYAN}sudo systemctl start $SERVICE_NAME${NC}"
            echo -e "   Stop:    ${CYAN}sudo systemctl stop $SERVICE_NAME${NC}"
            echo -e "   Restart: ${CYAN}sudo systemctl restart $SERVICE_NAME${NC}"
            echo -e "   Status:  ${CYAN}sudo systemctl status $SERVICE_NAME${NC}"
            ;;
        openrc)
            echo -e "   Start:   ${CYAN}sudo rc-service $SERVICE_NAME start${NC}"
            echo -e "   Stop:    ${CYAN}sudo rc-service $SERVICE_NAME stop${NC}"
            echo -e "   Restart: ${CYAN}sudo rc-service $SERVICE_NAME restart${NC}"
            echo -e "   Status:  ${CYAN}sudo rc-service $SERVICE_NAME status${NC}"
            echo -e "   Reload:  ${CYAN}sudo rc-service $SERVICE_NAME reload${NC}"
            ;;
        sysv)
            echo -e "   Start:   ${CYAN}sudo service $SERVICE_NAME start${NC}"
            echo -e "   Stop:    ${CYAN}sudo service $SERVICE_NAME stop${NC}"
            echo -e "   Restart: ${CYAN}sudo service $SERVICE_NAME restart${NC}"
            echo -e "   Status:  ${CYAN}sudo service $SERVICE_NAME status${NC}"
            ;;
    esac
    echo
    echo -e "${GREEN}Installation details:${NC}"
    echo -e "${GREEN}├─ Application directory: ${CYAN}$BASTION_HOME${NC}"
    echo -e "${GREEN}├─ Configuration directory: ${CYAN}$CONFIG_DIR${NC}"
    echo -e "${GREEN}├─ Environment file: ${CYAN}$ENV_FILE${NC}"
    echo -e "${GREEN}├─ Log directory: ${CYAN}$LOG_DIR${NC}"
    echo -e "${GREEN}├─ Data directory: ${CYAN}$DATA_DIR${NC}"
    echo -e "${GREEN}├─ Service user: ${CYAN}$BASTION_USER${NC}"
    echo -e "${GREEN}└─ Init system: ${CYAN}$INIT_SYSTEM${NC}"
    echo
    echo -e "${GREEN}Documentation and support:${NC}"
    echo -e "${CYAN}https://github.com/Arylite/Bastion${NC}"
    echo
}

# Cleanup function for failed installations
cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    log_warn "Cleaning up failed installation..."
    
    # Stop service if it was started
    case "$INIT_SYSTEM" in
        systemd)
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            rm -f "/etc/systemd/system/$SERVICE_NAME.service"
            systemctl daemon-reload 2>/dev/null || true
            ;;
        openrc)
            rc-service "$SERVICE_NAME" stop 2>/dev/null || true
            rc-update del "$SERVICE_NAME" default 2>/dev/null || true
            rm -f "/etc/init.d/$SERVICE_NAME"
            rm -f "/etc/conf.d/$SERVICE_NAME"
            ;;
        sysv)
            service "$SERVICE_NAME" stop 2>/dev/null || true
            chkconfig --del "$SERVICE_NAME" 2>/dev/null || true
            rm -f "/etc/init.d/$SERVICE_NAME"
            ;;
    esac
    
    # Remove directories if they were created by this script
    if [[ "$FORCE" == "true" ]]; then
        rm -rf "$BASTION_HOME" "$CONFIG_DIR" 2>/dev/null || true
    fi
    
    log_info "Cleanup completed"
}

# Main installation function
main() {
    # Set up signal handlers
    trap cleanup EXIT ERR
    
    print_banner
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        echo
    fi
    
    # Pre-flight checks
    check_root
    detect_os
    detect_init_system
    detect_package_manager
    
    log_info "Installation configuration:"
    log_info "\tUser: $BASTION_USER"
    log_info "\tGroup: $BASTION_GROUP"
    log_info "\tDirectory: $BASTION_HOME"
    log_info "\tInit system: $INIT_SYSTEM"
    log_info "\tPackage manager: $PKG_MANAGER"
    echo
    
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Continue with installation? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    # Installation steps
    install_dependencies
    create_user
    create_directories
    install_application
    generate_host_keys
    install_service
    create_config
    setup_firewall
    
    # Disable cleanup on successful installation
    trap - EXIT ERR
    
    if [[ "$DRY_RUN" != "true" ]]; then
        run_tests
        print_instructions
    else
        log_info "Dry run completed. No changes were made."
    fi
}

# Run main function
main "$@"