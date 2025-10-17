#!/usr/bin/env bash
# SilverSupport Installer v1.1.1
# Installation script for Ubuntu servers with dynamic version loading
# Usage: curl -L https://install.silverzupport.us/latest | bash

set -e  # Exit on any error

#############################################
# INSTALLER CONFIGURATION
#############################################

INSTALLER_VERSION="1.1.3"
ENVIRONMENT="${SILVER_ENV:-production}"
RELEASE_URL="https://releases.silverzupport.us"
LOG_FILE="/var/log/silver-install.log"
LOCK_FILE="/var/lock/silver-install.lock"

# Directory Structure
SILVER_ROOT="/opt/silversupport"
SILVER_VAR="/var/silversupport"
SILVER_ETC="/etc/silversupport"

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

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

#############################################
# BANNER
#############################################

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║          SilverSupport Installation Wizard                ║
║          Patient Tech Support for Seniors                  ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Installer Version: ${INSTALLER_VERSION}${NC}"
    echo -e "${BLUE}Installation Log: ${LOG_FILE}${NC}\n"
}

#############################################
# HELPER FUNCTIONS
#############################################

print_step() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}▸ $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

#############################################
# PRE-FLIGHT CHECKS
#############################################

check_root() {
    print_step "Checking root privileges"
    if [[ $EUID -ne 0 ]]; then
        print_error "This installer must be run as root"
        echo "Please run: sudo bash $0"
        exit 1
    fi
    print_success "Running as root"
}

check_ubuntu() {
    print_step "Checking operating system"
    
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot detect OS version"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This installer requires Ubuntu"
        echo "Detected: $ID $VERSION"
        exit 1
    fi
    
    # Check Ubuntu version
    VERSION_NUM=$(echo $VERSION_ID | cut -d. -f1)
    if [ "$VERSION_NUM" -lt 20 ]; then
        print_error "Ubuntu 20.04 LTS or newer is required"
        echo "Detected: Ubuntu $VERSION_ID"
        exit 1
    fi
    
    print_success "Ubuntu $VERSION_ID detected"
}

check_requirements() {
    print_step "Checking system requirements"
    
    # Check memory
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 900 ]; then
        print_error "Insufficient memory (${total_mem}MB). Minimum: 900MB"
        exit 1
    elif [ "$total_mem" -lt 1900 ]; then
        print_warning "Low memory detected (${total_mem}MB). Recommended: 2GB+"
        print_warning "This may work for testing but consider upgrading for production"
    else
        print_success "Memory: ${total_mem}MB"
    fi
    
    # Check disk space
    local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_disk" -lt 10 ]; then
        print_error "Insufficient disk space (${available_disk}GB). Required: 10GB+"
        exit 1
    fi
    print_success "Disk space: ${available_disk}GB available"
}

check_already_installed() {
    if [ -f "$SILVER_ROOT/version" ]; then
        print_step "Checking existing installation"
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║          SilverSupport Already Installed                   ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        local installed_version=$(cat $SILVER_ROOT/version)
        echo -e "${YELLOW}Installed Version: ${installed_version}${NC}"
        echo -e "${YELLOW}Installation Date: $(stat -c %y $SILVER_ROOT/version | cut -d' ' -f1)${NC}"
        echo ""
        echo -e "${RED}SilverSupport cannot be uninstalled or reinstalled.${NC}"
        echo -e "${RED}To install on this server, you must reinstall the OS.${NC}"
        echo ""
        exit 1
    fi
}

select_environment() {
    print_step "Select Installation Environment"
    
    echo -e "${YELLOW}Choose environment:${NC}"
    echo "1) Production (Stable)"
    echo "2) Staging (Pre-production)"
    echo "3) Alpha (Development/Testing)"
    echo ""
    
    # Check if interactive terminal
    if [ ! -t 0 ]; then
        print_error "No interactive terminal detected"
        echo "This installer must be run interactively."
        echo ""
        echo "Please run:"
        echo "  wget https://install.silverzupport.us/latest -O install.sh"
        echo "  sudo bash install.sh"
        exit 1
    fi
    
    local attempts=0
    local max_attempts=3
    
    while true; do
        read -r -p "Enter choice [1-3]: " env_choice
        
        case $env_choice in
            1)
                ENVIRONMENT="production"
                VERSION_FILE="LATEST_VERSION"
                break
                ;;
            2)
                ENVIRONMENT="staging"
                VERSION_FILE="STAGING_VERSION"
                break
                ;;
            3)
                ENVIRONMENT="alpha"
                VERSION_FILE="ALPHA_VERSION"
                break
                ;;
            *)
                attempts=$((attempts + 1))
                if [ $attempts -ge $max_attempts ]; then
                    print_error "Too many invalid attempts"
                    exit 1
                fi
                echo -e "${RED}Invalid choice. Please enter 1, 2, or 3${NC}"
                ;;
        esac
    done
    
    echo ""
    print_success "Environment selected: $ENVIRONMENT"
}

get_application_version() {
    print_step "Determining application version"
    
    # Add cache-busting timestamp to avoid CloudFront caching issues
    local TIMESTAMP=$(date +%s)
    
    # Fetch version from S3 with cache-busting
    log "Fetching version from ${RELEASE_URL}/${VERSION_FILE}?t=${TIMESTAMP}"
    APP_VERSION=$(curl -sf "${RELEASE_URL}/${VERSION_FILE}?t=${TIMESTAMP}" 2>/dev/null)
    
    if [ -z "$APP_VERSION" ]; then
        print_error "Could not determine application version"
        echo "Unable to fetch version from: ${RELEASE_URL}/${VERSION_FILE}"
        echo ""
        echo "Possible causes:"
        echo "  1. Network connectivity issues"
        echo "  2. VERSION file not found in S3"
        echo "  3. CloudFront distribution issues"
        exit 1
    fi
    
    # Validate version format (basic check)
    if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_error "Invalid version format: $APP_VERSION"
        exit 1
    fi
    
    print_success "Application version: $APP_VERSION"
    log "Installing SilverSupport version: $APP_VERSION"
}

#############################################
# PACKAGE INSTALLATION
#############################################

update_system() {
    print_step "Updating system packages"
    
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    
    print_success "System packages updated"
}

install_dependencies() {
    print_step "Installing system dependencies"
    
    apt-get install -y -qq \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        ufw \
        certbot \
        python3-certbot-nginx
    
    print_success "Dependencies installed"
}

install_nodejs() {
    print_step "Installing Node.js"
    
    if command -v node &> /dev/null; then
        local node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$node_version" -ge 18 ]; then
            print_success "Node.js $(node --version) already installed"
            return
        fi
    fi
    
    log "Installing Node.js 18 LTS"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    print_success "Node.js $(node --version) installed"
}

install_postgresql() {
    print_step "Installing PostgreSQL"
    
    if command -v psql &> /dev/null; then
        print_success "PostgreSQL already installed"
        return
    fi
    
    log "Installing PostgreSQL 14"
    apt-get install -y postgresql postgresql-contrib
    
    systemctl enable postgresql
    systemctl start postgresql
    
    print_success "PostgreSQL installed"
}

install_pm2() {
    print_step "Installing PM2 process manager"
    
    if command -v pm2 &> /dev/null; then
        print_success "PM2 already installed"
        return
    fi
    
    log "Installing PM2 globally"
    npm install -g pm2
    pm2 startup systemd -u root --hp /root > /dev/null 2>&1
    
    print_success "PM2 installed"
}

install_nginx() {
    print_step "Installing Nginx web server"
    
    if command -v nginx &> /dev/null; then
        print_success "Nginx already installed"
        return
    fi
    
    log "Installing Nginx"
    apt-get install -y nginx
    
    systemctl enable nginx
    systemctl start nginx
    
    print_success "Nginx installed"
}

#############################################
# DIRECTORY AND FILE SETUP
#############################################

create_directories() {
    print_step "Creating directory structure"
    
    mkdir -p "$SILVER_ROOT"/{logs,admin-dashboard/dist}
    mkdir -p "$SILVER_VAR"/{logs,uploads,backups}
    mkdir -p "$SILVER_ETC"
    
    chmod 755 "$SILVER_ROOT"
    chmod 755 "$SILVER_VAR"
    chmod 750 "$SILVER_ETC"
    
    print_success "Directory structure created"
}

download_application() {
    print_step "Downloading SilverSupport application"
    
    local TARBALL="silversupport-${APP_VERSION}.tar.gz"
    local DOWNLOAD_URL="${RELEASE_URL}/${TARBALL}"
    
    log "Downloading: $DOWNLOAD_URL"
    
    cd /tmp
    if ! wget -q "$DOWNLOAD_URL" -O "$TARBALL"; then
        print_error "Failed to download application tarball"
        echo ""
        echo "URL: $DOWNLOAD_URL"
        echo "Version: $APP_VERSION"
        echo ""
        echo "Please verify:"
        echo "  1. The tarball exists in S3 releases bucket"
        echo "  2. Version file points to correct version"
        echo "  3. Network connectivity is working"
        exit 1
    fi
    
    local size=$(du -h "$TARBALL" | cut -f1)
    print_success "Downloaded ${TARBALL} (${size})"
    
    log "Extracting application to $SILVER_ROOT"
    tar -xzf "$TARBALL" -C "$SILVER_ROOT/" --strip-components=1
    rm "$TARBALL"
    
    print_success "Application extracted"
}

create_version_file() {
    print_step "Creating version file"
    
    echo "$APP_VERSION" > "$SILVER_ROOT/version"
    echo "Environment: $ENVIRONMENT" >> "$SILVER_ROOT/version"
    echo "Installer: $INSTALLER_VERSION" >> "$SILVER_ROOT/version"
    echo "Installed: $(date +'%Y-%m-%d %H:%M:%S')" >> "$SILVER_ROOT/version"
    
    chmod 644 "$SILVER_ROOT/version"
    
    print_success "Version file created"
}

#############################################
# DATABASE CONFIGURATION
#############################################

configure_database() {
    print_step "Configuring PostgreSQL database"
    
    local DB_NAME="silversupport_${ENVIRONMENT}"
    local DB_USER="silversupport"
    local DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    log "Creating database: $DB_NAME"
    
    # Create database user
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
    
    # Create database
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true
    
    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>/dev/null || true
    
    # Save credentials
    cat > "$SILVER_ETC/database.conf" << EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}
EOF
    
    chmod 600 "$SILVER_ETC/database.conf"
    
    print_success "Database configured: $DB_NAME"
}


apply_database_schema() {
    print_step "Applying database schema"
    
    # Source database configuration
    source "$SILVER_ETC/database.conf"
    
    log "Applying base schema to $DB_NAME"
    
    # Check if schema file exists
    if [ ! -f "$SILVER_ROOT/src/database/schema.sql" ]; then
        print_warning "Schema file not found, skipping schema application"
        return
    fi
    
    # Apply base schema
    sudo -u postgres psql -d "$DB_NAME" -f "$SILVER_ROOT/src/database/schema.sql" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "Base schema applied"
    else
        print_error "Failed to apply base schema"
        log "Schema application failed, but continuing installation"
    fi
    
    # Apply migrations if directory exists
    if [ -d "$SILVER_ROOT/src/database/migrations" ]; then
        log "Applying database migrations"
        
        for migration in "$SILVER_ROOT/src/database/migrations"/*.sql; do
            if [ -f "$migration" ]; then
                local migration_name=$(basename "$migration")
                log "Applying migration: $migration_name"
                sudo -u postgres psql -d "$DB_NAME" -f "$migration" > /dev/null 2>&1
            fi
        done
        
        print_success "Migrations applied"
    fi
    
    # Grant permissions to application user
    log "Granting database permissions to $DB_USER"
    
    sudo -u postgres psql -d "$DB_NAME" << EOSQL > /dev/null 2>&1
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;
GRANT USAGE ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOSQL
    
    if [ $? -eq 0 ]; then
        print_success "Database permissions granted"
    else
        print_warning "Could not grant all permissions, application may need manual setup"
    fi
    
    # Verify tables were created
    local table_count=$(PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h localhost -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null | tr -d ' ')
    
    if [ ! -z "$table_count" ] && [ "$table_count" -gt 0 ]; then
        print_success "Database initialized with $table_count tables"
    else
        print_warning "Could not verify database tables"
    fi
}

create_env_file() {
    print_step "Creating environment configuration"
    
    # Source database config
    . "$SILVER_ETC/database.conf"
    
    # Generate security keys
    local JWT_SECRET=$(openssl rand -hex 32)
    local ENCRYPTION_KEY=$(openssl rand -hex 16)
    local SESSION_SECRET=$(openssl rand -hex 32)
    
    cat > "$SILVER_ROOT/.env" << EOF
# SilverSupport Environment Configuration
# Environment: $ENVIRONMENT
# Version: $APP_VERSION
# Generated: $(date)

NODE_ENV=$ENVIRONMENT
PORT=3000
HOST=0.0.0.0

# Database
DATABASE_URL=$DATABASE_URL

# Security
JWT_SECRET=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
SESSION_SECRET=$SESSION_SECRET

# Twilio (configure via setup wizard)
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=
TWILIO_WEBHOOK_URL=

# AI Services (configure via setup wizard)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=

# Application Settings
ENABLE_VOICE_AUTH=true
ENABLE_ANALYTICS=true
ENABLE_CALL_RECORDING=true

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
EOF
    
    chmod 600 "$SILVER_ROOT/.env"
    
    print_success "Environment configuration created"
}

#############################################
# APPLICATION SETUP
#############################################

install_app_dependencies() {
    print_step "Installing application dependencies"
    
    cd "$SILVER_ROOT"
    
    log "Running npm install (this may take a few minutes)"
    npm ci --production --quiet
    
    print_success "Application dependencies installed"
}

configure_pm2() {
    print_step "Configuring PM2 process manager"
    
    cat > "$SILVER_ROOT/ecosystem.config.js" << 'EOF'
module.exports = {
  apps: [{
    name: 'silversupport',
    script: './server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/silversupport/logs/error.log',
    out_file: '/var/silversupport/logs/output.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
EOF
    
    cd "$SILVER_ROOT"
    pm2 start ecosystem.config.js
    pm2 save
    
    print_success "PM2 configured"
}

configure_nginx() {
    print_step "Configuring Nginx"
    
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    cat > /etc/nginx/sites-available/silversupport << NGINXEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $SERVER_IP _;

    # Admin Dashboard
    location /admin/ {
        alias $SILVER_ROOT/admin-dashboard/dist/;
        try_files \$uri \$uri/ /admin/index.html;
        index index.html;
    }

    # API Proxy
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Health check
    location /health {
        proxy_pass http://localhost:3000/health;
    }

    # Root
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXEOF
    
    ln -sf /etc/nginx/sites-available/silversupport /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t
    systemctl reload nginx
    
    print_success "Nginx configured"
}

configure_firewall() {
    print_step "Configuring firewall"
    
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp > /dev/null 2>&1
        ufw allow 80/tcp > /dev/null 2>&1
        ufw allow 443/tcp > /dev/null 2>&1
        ufw allow $SETUP_PORT/tcp > /dev/null 2>&1
        echo "y" | ufw enable > /dev/null 2>&1
        
        print_success "Firewall configured"
    else
        print_warning "UFW not available, skipping firewall configuration"
    fi
}

#############################################
# SYSTEM COMMANDS
#############################################

create_system_commands() {
    print_step "Creating system commands"
    
    # silver-version command
    cat > /usr/local/bin/silver-version << 'EOF'
#!/bin/bash
if [ -f /opt/silversupport/version ]; then
    cat /opt/silversupport/version
else
    echo "SilverSupport version file not found"
    exit 1
fi
EOF
    
    # silver-status command
    cat > /usr/local/bin/silver-status << 'EOF'
#!/bin/bash
echo "SilverSupport System Status"
echo "==========================="
echo ""
pm2 status silversupport
echo ""
echo "Nginx Status:"
systemctl status nginx --no-pager -l | head -3
echo ""
echo "PostgreSQL Status:"
systemctl status postgresql --no-pager -l | head -3
EOF
    
    chmod +x /usr/local/bin/silver-version
    chmod +x /usr/local/bin/silver-status
    
    print_success "System commands created"
}

#############################################
# COMPLETION
#############################################

display_completion() {
    local install_time=$((SECONDS / 60))
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    clear
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║              ✓ Installation Complete!                     ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Installation Summary:${NC}"
    echo -e "  Installer Version: ${GREEN}${INSTALLER_VERSION}${NC}"
    echo -e "  Application Version: ${GREEN}${APP_VERSION}${NC}"
    echo -e "  Environment: ${GREEN}${ENVIRONMENT}${NC}"
    echo -e "  Installation Time: ${GREEN}${install_time} minutes${NC}"
    echo -e "  Installation Log: ${BLUE}${LOG_FILE}${NC}"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  ${BLUE}silver-version${NC}  - Show version information"
    echo -e "  ${BLUE}silver-status${NC}   - Check system status"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Next Step: Access Your Application${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Open your browser and navigate to:"
    echo ""
    echo -e "  ${GREEN}http://${SERVER_IP}${NC}"
    echo ""
    echo -e "  Complete the setup wizard to configure:"
    echo -e "  - Administrator credentials"
    echo -e "  - Twilio integration"
    echo -e "  - AI service API keys"
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
    check_ubuntu
    check_requirements
    check_already_installed
    
    select_environment
    get_application_version
    
    update_system
    install_dependencies
    install_nodejs
    install_postgresql
    install_pm2
    install_nginx
    
    create_directories
    download_application
    create_version_file
    
    configure_database
    apply_database_schema
    create_env_file
    install_app_dependencies
    
    configure_pm2
    configure_nginx
    configure_firewall
    create_system_commands
    
    display_completion
    
    log "Installation completed successfully"
}

# Run installer
main "$@"
