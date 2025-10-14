#!/bin/bash
# SilverSupport Installer v1.0.0
# Installation script for Ubuntu servers
# Usage: cd /home && curl -o silver-latest -L https://install.silverzupport.us/latest && sh silver-latest

set -e  # Exit on any error

# Installer Configuration
INSTALLER_VERSION="1.0.0"
SILVERSUPPORT_VERSION="${SILVER_VERSION:-latest}"
INSTALL_SOURCE="https://releases.silverzupport.us"
LOG_FILE="/var/log/silver-install.log"
LOCK_FILE="/var/lock/silver-install.lock"

# Directory Structure (cPanel-style)
SILVER_ROOT="/usr/local/silver"
SILVER_VAR="/var/silver"
SILVER_ETC="/etc/silver"
SILVER_CRON="/var/spool/silver/cron"

# Installation Port
SETUP_PORT="9443"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Initialize logging
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE")
exec 2>&1

#############################################
# BANNER
#############################################

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║              SilverSupport Installer v1.0.0                ║
║          Helping Seniors with Technology                   ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Installation Log: ${LOG_FILE}${NC}"
    echo -e "${BLUE}Started: $(date)${NC}\n"
}

#############################################
# PROGRESS TRACKING
#############################################

TOTAL_STEPS=15
CURRENT_STEP=0

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}[Step $CURRENT_STEP/$TOTAL_STEPS - ${percentage}%] $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

print_substep() {
    echo -e "${BLUE}  ▸ $1${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✗ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  ⚠ WARNING: $1${NC}"
}

#############################################
# PRE-FLIGHT CHECKS
#############################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This installer must be run as root"
        echo "Please run: sudo su -"
        echo "Then retry the installation"
        exit 1
    fi
}

check_already_installed() {
    if [ -f "$SILVER_ROOT/version" ]; then
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║          SilverSupport Already Installed                   ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        local installed_version=$(cat $SILVER_ROOT/version)
        echo -e "${YELLOW}Installed Version: ${installed_version}${NC}"
        echo -e "${YELLOW}Installation Date: $(stat -c %y $SILVER_ROOT/version | cut -d' ' -f1)${NC}"
        echo ""
        echo -e "${RED}SilverSupport cannot be uninstalled or reinstalled.${NC}"
        echo -e "${RED}To install on this server, you must:${NC}"
        echo ""
        echo "  1. Backup any important data"
        echo "  2. Reinstall the operating system"
        echo "  3. Run the SilverSupport installer on the fresh OS"
        echo ""
        echo -e "${YELLOW}This is by design to ensure system integrity.${NC}"
        exit 1
    fi
}

check_clean_system() {
    print_step "Checking System Cleanliness"
    
    local conflicts=()
    
    # Check for other control panels
    if [ -d "/usr/local/cpanel" ]; then
        conflicts+=("cPanel/WHM detected at /usr/local/cpanel")
    fi
    
    if [ -d "/usr/local/psa" ]; then
        conflicts+=("Plesk detected at /usr/local/psa")
    fi
    
    if [ -d "/usr/local/directadmin" ]; then
        conflicts+=("DirectAdmin detected at /usr/local/directadmin")
    fi
    
    if [ -d "/etc/webmin" ]; then
        conflicts+=("Webmin detected at /etc/webmin")
    fi
    
    if [ -d "/usr/local/lsws" ] || [ -d "/usr/local/CyberCP" ]; then
        conflicts+=("CyberPanel detected")
    fi
    
    # Check for existing web servers
    if systemctl is-active --quiet apache2 2>/dev/null; then
        conflicts+=("Apache is running")
    fi
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        conflicts+=("Nginx is running")
    fi
    
    # Check for existing databases
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        conflicts+=("MySQL/MariaDB is running")
    fi
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║          INSTALLATION BLOCKED                              ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${RED}SilverSupport requires a CLEAN Ubuntu installation.${NC}"
        echo ""
        echo -e "${YELLOW}Detected conflicts:${NC}"
        for conflict in "${conflicts[@]}"; do
            echo -e "  ${RED}✗${NC} $conflict"
        done
        echo ""
        echo -e "${CYAN}To install SilverSupport:${NC}"
        echo "  1. Deploy a fresh Ubuntu 20.04 or 22.04 LTS server"
        echo "  2. Run only system updates (apt update && apt upgrade)"
        echo "  3. Run this installer immediately"
        echo ""
        exit 1
    fi
    
    print_success "System is clean - ready for installation"
}

check_system_requirements() {
    print_step "Verifying System Requirements"
    
    local errors=0
    
    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            print_error "Ubuntu required (detected: $ID)"
            errors=$((errors + 1))
        else
            local version_num="${VERSION_ID%%.*}"
            if [ "$version_num" -lt 20 ]; then
                print_error "Ubuntu 20.04 or higher required (detected: $VERSION_ID)"
                errors=$((errors + 1))
            else
                print_success "Operating System: Ubuntu $VERSION_ID"
            fi
        fi
    else
        print_error "Cannot determine OS version"
        errors=$((errors + 1))
    fi
    
    # Check memory
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_total" -lt 2048 ]; then
        print_error "Minimum 2GB RAM required (detected: ${mem_total}MB)"
        errors=$((errors + 1))
    else
        print_success "Memory: ${mem_total}MB"
    fi
    
    # Check disk space
    local disk_avail=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_avail" -lt 20 ]; then
        print_error "Minimum 20GB free disk space required (available: ${disk_avail}GB)"
        errors=$((errors + 1))
    else
        print_success "Disk Space: ${disk_avail}GB available"
    fi
    
    # Check internet
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "Internet connection required"
        errors=$((errors + 1))
    else
        print_success "Internet connectivity verified"
    fi
    
    # Check DNS
    if ! nslookup google.com &> /dev/null; then
        print_warning "DNS resolution may have issues"
    else
        print_success "DNS resolution working"
    fi
    
    if [ $errors -gt 0 ]; then
        echo ""
        print_error "System requirements not met. Installation cannot continue."
        exit 1
    fi
    
    echo ""
}

create_install_lock() {
    if [ -f "$LOCK_FILE" ]; then
        print_error "Installation already in progress (lock file exists)"
        echo "If this is an error, remove: $LOCK_FILE"
        exit 1
    fi
    
    echo $$ > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT
}

#############################################
# MAIN INSTALLATION
#############################################

install_packages() {
    print_step "Installing System Packages"
    
    print_substep "Updating package lists..."
    apt-get update -qq
    
    print_substep "Installing Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - &> /dev/null
    apt-get install -y -qq nodejs
    
    print_substep "Installing PostgreSQL 14..."
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - &> /dev/null
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    apt-get update -qq
    apt-get install -y -qq postgresql-14 postgresql-contrib-14
    
    print_substep "Installing Redis..."
    apt-get install -y -qq redis-server
    
    print_substep "Installing Nginx..."
    apt-get install -y -qq nginx
    
    print_substep "Installing PM2..."
    npm install -g pm2 --silent
    
    print_substep "Installing Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx
    
    print_success "All packages installed"
}

create_directories() {
    print_step "Creating Directory Structure"
    
    mkdir -p "$SILVER_ROOT"/{bin,base,whostmgr,scripts,logs,3rdparty,docs}
    mkdir -p "$SILVER_VAR"/{logs,backups,sessions,temp,databases}
    mkdir -p "$SILVER_ETC"
    mkdir -p "$SILVER_CRON"
    
    chmod 755 /home/$USER 2>/dev/null || true
    
    print_success "Directory structure created"
}

write_version_files() {
    print_step "Writing Version Information"
    
    echo "$SILVERSUPPORT_VERSION" > "$SILVER_ROOT/version"
    
    cat > "$SILVER_ROOT/.build-info" << EOF
VERSION=$SILVERSUPPORT_VERSION
INSTALLER_VERSION=$INSTALLER_VERSION
INSTALLED_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
INSTALL_LOG=$LOG_FILE
EOF
    
    cat > "$SILVER_ROOT/.installed" << EOF
Installation completed: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Version: $SILVERSUPPORT_VERSION
Installer: $INSTALLER_VERSION

WARNING: SilverSupport cannot be uninstalled.
To remove, the operating system must be reinstalled.
EOF
    
    chmod 444 "$SILVER_ROOT/.installed"
    
    print_success "Version files created"
}

create_system_commands() {
    print_step "Creating System Commands"
    
    # silver-version command
    cat > "$SILVER_ROOT/bin/silver-version" << 'EOF'
#!/bin/bash
if [ -f /usr/local/silver/version ]; then
    echo "SilverSupport $(cat /usr/local/silver/version)"
    if [ -f /usr/local/silver/.build-info ]; then
        echo ""
        cat /usr/local/silver/.build-info
    fi
else
    echo "SilverSupport not installed"
    exit 1
fi
EOF
    
    chmod +x "$SILVER_ROOT/bin/silver-version"
    ln -sf "$SILVER_ROOT/bin/silver-version" /usr/local/bin/silver-version
    
    # silver-status command
    cat > "$SILVER_ROOT/bin/silver-status" << 'EOF'
#!/bin/bash
echo "SilverSupport System Status"
echo "============================"
echo ""
/usr/local/silver/bin/silver-version
echo ""
echo "Services:"
pm2 list | grep silver || echo "  No services running"
echo ""
echo "Database:"
sudo -u postgres psql -c '\l' | grep silver || echo "  No databases found"
EOF
    
    chmod +x "$SILVER_ROOT/bin/silver-status"
    ln -sf "$SILVER_ROOT/bin/silver-status" /usr/local/bin/silver-status
    
    print_success "System commands created"
}

configure_firewall() {
    print_step "Configuring Firewall"
    
    ufw --force reset &> /dev/null
    ufw default deny incoming &> /dev/null
    ufw default allow outgoing &> /dev/null
    ufw allow 22/tcp &> /dev/null
    ufw allow 80/tcp &> /dev/null
    ufw allow 443/tcp &> /dev/null
    ufw allow $SETUP_PORT/tcp &> /dev/null
    ufw --force enable &> /dev/null
    
    print_success "Firewall configured"
}

print_completion() {
    local install_time=$((SECONDS / 60))
    
    echo ""
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     SilverSupport Installation Complete!                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Installation Summary:${NC}"
    echo -e "  Version: ${GREEN}${SILVERSUPPORT_VERSION}${NC}"
    echo -e "  Installation Time: ${GREEN}${install_time} minutes${NC}"
    echo -e "  Installation Log: ${BLUE}${LOG_FILE}${NC}"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  ${BLUE}silver-version${NC}  - Show version information"
    echo -e "  ${BLUE}silver-status${NC}   - Check system status"
    echo ""
    
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Next Step: Complete Setup Wizard${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Open your browser and navigate to:"
    echo ""
    echo -e "  ${GREEN}https://${SERVER_IP}:${SETUP_PORT}${NC}"
    echo ""
    echo -e "  Login with root credentials to complete configuration"
    echo ""
    echo -e "${RED}IMPORTANT: SilverSupport cannot be uninstalled.${NC}"
    echo -e "${RED}The only way to remove it is to reinstall the OS.${NC}"
    echo ""
}

#############################################
# MAIN EXECUTION
#############################################

main() {
    SECONDS=0
    
    print_banner
    check_root
    check_already_installed
    check_clean_system
    check_system_requirements
    create_install_lock
    
    install_packages
    create_directories
    write_version_files
    create_system_commands
    configure_firewall
    
    print_completion
}

# Run installer
main "$@"