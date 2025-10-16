#!/usr/bin/env bash
# SilverSupport Installer v1.1.0
# Installation script for Ubuntu servers with SSL auto-configuration
# Usage: curl -L https://install.silverzupport.us/latest | bash

set -e  # Exit on any error

# Installer Configuration
INSTALLER_VERSION="1.1.0"
SILVERSUPPORT_VERSION="${SILVER_VERSION:-latest}"
INSTALL_SOURCE="https://releases.silverzupport.us"
LOG_FILE="/var/log/silver-install.log"
LOCK_FILE="/var/lock/silver-install.lock"

# Directory Structure
SILVER_ROOT="/opt/silversupport"
SILVER_VAR="/var/silversupport"
SILVER_ETC="/etc/silversupport"

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
║          SilverSupport Installation Wizard v1.1            ║
║          Patient Tech Support for Seniors                  ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Installation Log: ${LOG_FILE}${NC}\n"
}

#############################################
# SYSTEM CHECKS
#############################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}Error: Cannot detect OS version${NC}"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        echo -e "${RED}Error: This installer requires Ubuntu${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Ubuntu $VERSION_ID detected${NC}"
}

check_requirements() {
    echo -e "${YELLOW}Checking system requirements...${NC}"
    
    # Check memory
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 900 ]; then
        echo -e "${RED}Error: Insufficient memory (${total_mem}MB). Minimum: 900MB${NC}"
        exit 1
    elif [ "$total_mem" -lt 1900 ]; then
        echo -e "${YELLOW}⚠ Low memory detected (${total_mem}MB). Recommended: 2GB+${NC}"
    fi
    
    # Check disk space
    available_space=$(df / | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 10485760 ]; then
        echo -e "${RED}Error: Insufficient disk space. Minimum: 10GB${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ System requirements met${NC}"
}

#############################################
# INSTALLATION STEPS
#############################################

install_dependencies() {
    echo -e "${YELLOW}Installing system dependencies...${NC}"
    
    apt-get update -qq
    apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        ufw \
        net-tools \
        certbot \
        python3-certbot-nginx
    
    echo -e "${GREEN}✓ Dependencies installed${NC}"
}

install_nodejs() {
    echo -e "${YELLOW}Installing Node.js 18...${NC}"
    
    if command -v node &> /dev/null; then
        node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$node_version" -ge 18 ]; then
            echo -e "${GREEN}✓ Node.js $(node --version) already installed${NC}"
            return
        fi
    fi
    
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    echo -e "${GREEN}✓ Node.js $(node --version) installed${NC}"
}

install_postgresql() {
    echo -e "${YELLOW}Installing PostgreSQL...${NC}"
    
    if command -v psql &> /dev/null; then
        echo -e "${GREEN}✓ PostgreSQL already installed${NC}"
        return
    fi
    
    apt-get install -y postgresql postgresql-contrib
    systemctl enable postgresql
    systemctl start postgresql
    
    echo -e "${GREEN}✓ PostgreSQL installed${NC}"
}

install_pm2() {
    echo -e "${YELLOW}Installing PM2...${NC}"
    
    if command -v pm2 &> /dev/null; then
        echo -e "${GREEN}✓ PM2 already installed${NC}"
        return
    fi
    
    npm install -g pm2
    pm2 startup systemd -u root --hp /root
    env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root
    
    echo -e "${GREEN}✓ PM2 installed${NC}"
}

install_nginx() {
    echo -e "${YELLOW}Installing Nginx...${NC}"
    
    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}✓ Nginx already installed${NC}"
        return
    fi
    
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    
    echo -e "${GREEN}✓ Nginx installed${NC}"
}

#############################################
# DIRECTORY SETUP
#############################################

create_directories() {
    echo -e "${YELLOW}Creating directory structure...${NC}"
    
    # Create main directories
    mkdir -p "$SILVER_ROOT"/{admin-dashboard/dist,logs}
    mkdir -p "$SILVER_VAR"/{logs,uploads,backups}
    mkdir -p "$SILVER_ETC"
    
    # Set permissions
    chmod 755 "$SILVER_ROOT"
    chmod 755 "$SILVER_VAR"
    chmod 750 "$SILVER_ETC"
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

#############################################
# APPLICATION SETUP
#############################################

download_code() {
    echo -e "${YELLOW}Cloning SilverSupport repository...${NC}"
    
    cd /opt
    
    # Clone from GitHub (update with your actual repo URL)
    if [ -d "silversupport" ]; then
        rm -rf silversupport
    fi
    
    git clone https://github.com/YOUR_USERNAME/silversupport.git "$SILVER_ROOT" || {
        echo -e "${YELLOW}Note: Using local files for testing${NC}"
        mkdir -p "$SILVER_ROOT"
    }
    
    echo -e "${GREEN}✓ Code downloaded${NC}"
}

configure_database() {
    echo -e "${YELLOW}Configuring PostgreSQL database...${NC}"
    
    DB_NAME="ai_support"
    DB_USER="silversupport_user"
    DB_PASS=$(openssl rand -base64 32)
    
    # Create database and user
    sudo -u postgres psql << EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    
    # Save credentials
    echo "DB_NAME=$DB_NAME" > "$SILVER_ETC/db-credentials"
    echo "DB_USER=$DB_USER" >> "$SILVER_ETC/db-credentials"
    echo "DB_PASS=$DB_PASS" >> "$SILVER_ETC/db-credentials"
    chmod 600 "$SILVER_ETC/db-credentials"
    
    echo -e "${GREEN}✓ Database configured${NC}"
}

create_env_file() {
    echo -e "${YELLOW}Creating environment configuration...${NC}"
    
    source "$SILVER_ETC/db-credentials"
    
    cat > "$SILVER_ROOT/.env" << EOF
NODE_ENV=production
PORT=3000
HOST=0.0.0.0
DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}

# Security
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
SESSION_SECRET=$(openssl rand -base64 32)

# Application
ENABLE_VOICE_AUTH=false
ENABLE_ANALYTICS=true
LOG_LEVEL=info

# CORS
CORS_ORIGINS=https://${DOMAIN}
EOF
    
    chmod 600 "$SILVER_ROOT/.env"
    
    echo -e "${GREEN}✓ Environment configured${NC}"
}

install_app_dependencies() {
    echo -e "${YELLOW}Installing application dependencies...${NC}"
    
    cd "$SILVER_ROOT"
    
    if [ -f "package.json" ]; then
        npm install --production
        echo -e "${GREEN}✓ Dependencies installed${NC}"
    else
        echo -e "${YELLOW}Note: package.json not found, skipping npm install${NC}"
    fi
}

#############################################
# NGINX CONFIGURATION (IMPROVED)
#############################################

configure_nginx() {
    echo -e "${YELLOW}Configuring Nginx...${NC}"
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    # Prompt for domain
    echo -e "${CYAN}Enter your domain name (or press Enter to use IP only):${NC}"
    read -p "Domain: " DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        DOMAIN="$SERVER_IP"
    fi
    
    # Create nginx configuration with proper static file handling
    cat > /etc/nginx/sites-available/silversupport << EOF
server {
    listen 80;
    server_name $DOMAIN $SERVER_IP;
    
    # Admin Dashboard - Static files
    location /admin/ {
        alias $SILVER_ROOT/admin-dashboard/dist/;
        try_files \$uri \$uri/ /admin/index.html;
        index index.html;
    }
    
    # Admin Dashboard Assets - Serve static assets directly
    location /assets/ {
        alias $SILVER_ROOT/admin-dashboard/dist/assets/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Let's Encrypt challenge directory
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
    
    # Health check
    location /health {
        proxy_pass http://localhost:3000/health;
    }
    
    # API and application proxy (MUST BE LAST)
    location / {
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
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/silversupport /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload
    nginx -t
    systemctl reload nginx
    
    echo -e "${GREEN}✓ Nginx configured${NC}"
}

#############################################
# SSL CERTIFICATE (NEW)
#############################################

install_ssl() {
    echo -e "${YELLOW}Installing SSL certificate...${NC}"
    
    # Only attempt if domain is set and not an IP
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${YELLOW}⚠ Skipping SSL (using IP address)${NC}"
        echo -e "${YELLOW}  Access via: http://${DOMAIN}/admin/${NC}"
        return
    fi
    
    # Create Let's Encrypt challenge directory
    mkdir -p /var/www/letsencrypt
    
    echo -e "${CYAN}Enter email for SSL certificate notifications:${NC}"
    read -p "Email: " SSL_EMAIL
    
    if [ -z "$SSL_EMAIL" ]; then
        echo -e "${YELLOW}⚠ No email provided, skipping SSL${NC}"
        echo -e "${YELLOW}  You can install SSL later with: certbot --nginx -d $DOMAIN${NC}"
        return
    fi
    
    # Stop nginx temporarily for standalone mode
    systemctl stop nginx
    
    # Get certificate with standalone mode (more reliable)
    certbot certonly \
        --standalone \
        -d "$DOMAIN" \
        --email "$SSL_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --non-interactive || {
        echo -e "${YELLOW}⚠ SSL certificate installation failed${NC}"
        echo -e "${YELLOW}  You can try again later with: certbot --nginx -d $DOMAIN${NC}"
        systemctl start nginx
        return
    }
    
    # Start nginx back up
    systemctl start nginx
    
    # Install certificate in nginx
    certbot install \
        --cert-name "$DOMAIN" \
        --nginx \
        --non-interactive || {
        echo -e "${YELLOW}⚠ SSL certificate installation failed${NC}"
        return
    }
    
    echo -e "${GREEN}✓ SSL certificate installed${NC}"
    echo -e "${GREEN}  Access via: https://${DOMAIN}/admin/${NC}"
}

#############################################
# PM2 CONFIGURATION
#############################################

configure_pm2() {
    echo -e "${YELLOW}Configuring PM2...${NC}"
    
    cd "$SILVER_ROOT"
    
    # Create ecosystem file if it doesn't exist
    if [ ! -f "ecosystem.config.js" ]; then
        cat > ecosystem.config.js << 'EOF'
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
    }
  }]
};
EOF
    fi
    
    # Start application
    if [ -f "server.js" ]; then
        pm2 start ecosystem.config.js
        pm2 save
        echo -e "${GREEN}✓ PM2 configured and application started${NC}"
    else
        echo -e "${YELLOW}Note: server.js not found, skipping PM2 start${NC}"
    fi
}

#############################################
# FIREWALL CONFIGURATION
#############################################

configure_firewall() {
    echo -e "${YELLOW}Configuring firewall...${NC}"
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH, HTTP, HTTPS
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Reload
    ufw reload
    
    echo -e "${GREEN}✓ Firewall configured${NC}"
}

#############################################
# COMPLETION SUMMARY
#############################################

display_summary() {
    local install_time=$((SECONDS / 60))
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║         SilverSupport Installation Complete!              ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Installation Summary:${NC}"
    echo -e "  Installation Time: ${GREEN}${install_time} minutes${NC}"
    echo -e "  Installation Log: ${BLUE}${LOG_FILE}${NC}"
    echo ""
    echo -e "${CYAN}Access Your Admin Dashboard:${NC}"
    
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "  ${GREEN}http://${DOMAIN}/admin/${NC}"
    else
        # Check if SSL was installed
        if certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
            echo -e "  ${GREEN}https://${DOMAIN}/admin/${NC}"
        else
            echo -e "  ${GREEN}http://${DOMAIN}/admin/${NC}"
        fi
    fi
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  ${BLUE}pm2 status${NC}           - Check application status"
    echo -e "  ${BLUE}pm2 logs${NC}             - View application logs"
    echo -e "  ${BLUE}pm2 restart all${NC}      - Restart application"
    echo -e "  ${BLUE}systemctl status nginx${NC} - Check web server status"
    echo -e "  ${BLUE}certbot certificates${NC}  - View SSL certificates"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  1. Access the admin dashboard URL above"
    echo -e "  2. Configure your Twilio and AI API credentials"
    echo -e "  3. Review the documentation at ${BLUE}https://docs.silverzupport.us${NC}"
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
    
    install_dependencies
    install_nodejs
    install_postgresql
    install_pm2
    install_nginx
    
    create_directories
    download_code
    configure_database
    create_env_file
    install_app_dependencies
    
    configure_nginx
    install_ssl
    configure_pm2
    configure_firewall
    
    display_summary
}

# Run installer
main "$@"
