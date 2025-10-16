#!/usr/bin/env bash
# SilverSupport Installer for Alpha Environment
# Version: 1.0.0
# Usage: sudo bash silver-installer-alpha-v1.0.0.sh

set -e  # Exit on any error

#############################################
# CONFIGURATION
#############################################

INSTALLER_VERSION="1.0.0"
ENVIRONMENT="alpha"
## S3_BUCKET="ai-support-installer-793bc413"
RELEASE_URL="https://releases.silverzupport.us"
TARBALL_NAME="silversupport-alpha-latest.tar.gz"
LOG_FILE="/var/log/silver-install.log"
SETUP_PORT="9443"

# Directory Structure
SILVER_ROOT="/opt/silversupport"
SILVER_USER="silversupport"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#############################################
# LOGGING
#############################################

mkdir -p /var/log
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

#############################################
# DISPLAY FUNCTIONS
#############################################

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║        SilverSupport Alpha Installation Wizard            ║
║                                                            ║
║          Patient Tech Support for Seniors                 ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Version: ${INSTALLER_VERSION}${NC}"
    echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
    echo -e "${BLUE}Log File: ${LOG_FILE}${NC}"
    echo ""
}

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
    
    print_success "Ubuntu $VERSION_ID detected"
}

check_memory() {
    print_step "Checking system requirements"
    
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    
    if [ "$total_mem" -lt 1800 ]; then
        print_error "Insufficient memory: ${total_mem}MB"
        echo "Minimum required: 2GB (2048MB)"
        echo "Current memory: ${total_mem}MB"
        exit 1
    fi
    
    print_success "Memory check passed: ${total_mem}MB"
}

check_disk_space() {
    local available=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available" -lt 10 ]; then
        print_error "Insufficient disk space: ${available}GB"
        echo "Minimum required: 10GB"
        exit 1
    fi
    
    print_success "Disk space check passed: ${available}GB available"
}

check_existing_install() {
    if [ -d "$SILVER_ROOT" ] && [ -f "$SILVER_ROOT/package.json" ]; then
        print_error "SilverSupport is already installed at $SILVER_ROOT"
        echo ""
        echo "To reinstall:"
        echo "  1. Backup your data"
        echo "  2. Remove existing installation: sudo rm -rf $SILVER_ROOT"
        echo "  3. Run this installer again"
        exit 1
    fi
}

#############################################
# SYSTEM PACKAGES
#############################################

install_prerequisites() {
    print_step "Installing system prerequisites"
    
    export DEBIAN_FRONTEND=noninteractive
    
    echo "Updating package lists..."
    apt-get update -qq
    
    echo "Installing base packages..."
    apt-get install -y -qq \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        unzip \
        > /dev/null 2>&1
    
    print_success "Base packages installed"
}

install_awscli() {
    print_step "Installing AWS CLI"
    
    if command -v aws &> /dev/null; then
        print_success "AWS CLI already installed"
        aws --version
        return
    fi
    
    echo "Downloading AWS CLI..."
    cd /tmp
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    
    echo "Installing AWS CLI..."
    unzip -q awscliv2.zip
    ./aws/install > /dev/null 2>&1
    rm -rf aws awscliv2.zip
    
    print_success "AWS CLI installed: $(aws --version)"
}

install_nodejs() {
    print_step "Installing Node.js 18.x"
    
    if command -v node &> /dev/null; then
        local node_version=$(node --version)
        print_success "Node.js already installed: $node_version"
        return
    fi
    
    echo "Adding NodeSource repository..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
    
    echo "Installing Node.js..."
    apt-get install -y -qq nodejs > /dev/null 2>&1
    
    print_success "Node.js installed: $(node --version)"
    print_success "npm installed: $(npm --version)"
}

install_postgresql() {
    print_step "Installing PostgreSQL"
    
    if command -v psql &> /dev/null; then
        print_success "PostgreSQL already installed"
        return
    fi
    
    echo "Installing PostgreSQL..."
    apt-get install -y -qq postgresql postgresql-contrib > /dev/null 2>&1
    
    systemctl start postgresql
    systemctl enable postgresql > /dev/null 2>&1
    
    print_success "PostgreSQL installed and running"
}

install_nginx() {
    print_step "Installing nginx web server"
    
    if command -v nginx &> /dev/null; then
        print_success "nginx already installed"
        return
    fi
    
    echo "Installing nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    
    systemctl stop nginx
    
    print_success "nginx installed"
}

install_pm2() {
    print_step "Installing PM2 process manager"
    
    if command -v pm2 &> /dev/null; then
        print_success "PM2 already installed"
        return
    fi
    
    echo "Installing PM2 globally..."
    npm install -g pm2 > /dev/null 2>&1
    
    print_success "PM2 installed: $(pm2 --version)"
}

#############################################
# AWS CONFIGURATION
#############################################

configure_aws_credentials() {
    print_step "Configuring AWS credentials"
    
    # Check if AWS credentials already exist
    if aws sts get-caller-identity &> /dev/null; then
        print_success "AWS credentials already configured"
        return
    fi
    
    echo ""
    echo -e "${YELLOW}AWS credentials are required to download the SilverSupport application.${NC}"
    echo ""
    echo "Please enter your AWS credentials:"
    echo ""
    
    read -p "AWS Access Key ID: " aws_access_key
    read -p "AWS Secret Access Key: " aws_secret_key
    
    # Configure AWS CLI
    mkdir -p /root/.aws
    
    cat > /root/.aws/credentials << EOF
[default]
aws_access_key_id = $aws_access_key
aws_secret_access_key = $aws_secret_key
EOF
    
    cat > /root/.aws/config << EOF
[default]
region = us-east-1
output = json
EOF
    
    chmod 600 /root/.aws/credentials
    chmod 600 /root/.aws/config
    
    # Test credentials
    if aws sts get-caller-identity &> /dev/null; then
        print_success "AWS credentials configured successfully"
    else
        print_error "AWS credentials test failed"
        echo "Please verify your credentials and try again"
        exit 1
    fi
}

#############################################
# USER AND DIRECTORIES
#############################################

create_system_user() {
    print_step "Creating system user: $SILVER_USER"
    
    if id "$SILVER_USER" &>/dev/null; then
        print_success "User $SILVER_USER already exists"
        return
    fi
    
    useradd -r -m -d /home/$SILVER_USER -s /bin/bash $SILVER_USER
    
    print_success "User $SILVER_USER created"
}

create_directories() {
    print_step "Creating directory structure"
    
    mkdir -p $SILVER_ROOT
    mkdir -p /var/log/silversupport
    mkdir -p /var/lib/silversupport
    
    print_success "Directories created"
}

#############################################
# APPLICATION DOWNLOAD
#############################################

download_application() {
    print_step "Downloading SilverSupport application from S3"
    
    ## echo "Downloading: s3://${S3_BUCKET}/releases/${TARBALL_NAME}"
    echo "Downloading: ${RELEASE_URL}/${TARBALL_NAME}"

    # Download tarball from S3
    if ! wget -q "${RELEASE_URL}/${TARBALL_NAME}" -O "/tmp/${TARBALL_NAME}"; then
    ## if ! aws s3 cp "s3://${S3_BUCKET}/releases/${TARBALL_NAME}" "/tmp/${TARBALL_NAME}"; then
        print_error "Failed to download application from S3"
        echo ""
        echo "Bucket: $S3_BUCKET"
        echo "File: $TARBALL_NAME"
        echo ""
        echo "Please verify:"
        echo "  1. The S3 bucket exists and contains the tarball"
        echo "  2. Your AWS credentials have s3:GetObject permission"
        exit 1
    fi
    
    local size=$(du -h "/tmp/${TARBALL_NAME}" | cut -f1)
    print_success "Downloaded ${TARBALL_NAME} (${size})"
    
    echo "Extracting application..."
    tar -xzf "/tmp/${TARBALL_NAME}" -C "$SILVER_ROOT/"
    rm "/tmp/${TARBALL_NAME}"
    
    print_success "Application extracted to $SILVER_ROOT"
}

#############################################
# DATABASE SETUP
#############################################

setup_database() {
    print_step "Setting up PostgreSQL database"
    
    local DB_NAME="silversupport_alpha"
    local DB_USER="silversupport_user"
    local DB_PASS="alpha_secure_password_$(date +%s)"
    
    echo "Creating database and user..."
    
    # Create database user
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
    
    # Create database
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true
    
    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>/dev/null || true
    
    # Store database credentials for later
    echo "DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}" > /tmp/db_creds
    
    print_success "Database created: $DB_NAME"
    print_success "Database user: $DB_USER"
}

#############################################
# APPLICATION SETUP
#############################################

install_dependencies() {
    print_step "Installing application dependencies"
    
    cd "$SILVER_ROOT"
    
    echo "Installing Node.js packages (this may take a few minutes)..."
    npm ci --production --quiet
    
    print_success "Dependencies installed"
}

create_env_file() {
    print_step "Creating environment configuration"
    
    local DB_URL=$(cat /tmp/db_creds)
    rm /tmp/db_creds
    
    cat > "$SILVER_ROOT/.env" << EOF
# SilverSupport Alpha Environment Configuration
NODE_ENV=alpha
PORT=3000
HOST=0.0.0.0

# Database
$DB_URL

# Security (will be configured via setup wizard)
JWT_SECRET=
ENCRYPTION_KEY=
SESSION_SECRET=

# Twilio (will be configured via setup wizard)
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=
TWILIO_WEBHOOK_URL=

# AI Services (will be configured via setup wizard)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=

# Application
ENABLE_VOICE_AUTH=true
ENABLE_ANALYTICS=true
ENABLE_CALL_RECORDING=true

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
EOF
    
    chmod 600 "$SILVER_ROOT/.env"
    
    print_success "Environment file created"
}

#############################################
# SETUP WIZARD
#############################################

create_setup_wizard() {
    print_step "Creating setup wizard"
    
    cat > "$SILVER_ROOT/setup-wizard.js" << 'WIZARDEOF'
const express = require('express');
const fs = require('fs');
const { exec } = require('child_process');
const app = express();
const PORT = process.env.SETUP_PORT || 9443;
const ENV_FILE = '/opt/silversupport/.env';
const SETUP_LOCK = '/opt/silversupport/.setup-complete';

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

function isSetupComplete() {
  return fs.existsSync(SETUP_LOCK);
}

app.get('/', (req, res) => {
  if (isSetupComplete()) {
    return res.send(`
      <html><head><title>Setup Complete</title>
      <style>body{font-family:Arial;max-width:600px;margin:100px auto;text-align:center;}
      .success{color:#28a745;font-size:24px;margin:20px 0;}</style></head>
      <body><h1>✓ Setup Complete</h1>
      <p class="success">SilverSupport is configured and running!</p>
      <p>You can close this window.</p></body></html>
    `);
  }
  
  const SERVER_IP = require('os').networkInterfaces()['eth0']?.[0]?.address || 'YOUR_SERVER_IP';
  
  res.send(`
    <html><head><title>SilverSupport Setup Wizard</title>
    <style>
      * { margin:0; padding:0; box-sizing:border-box; }
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }
      .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); padding: 40px; }
      h1 { color: #333; margin-bottom: 10px; font-size: 28px; }
      .subtitle { color: #666; margin-bottom: 30px; }
      .section-title { color: #667eea; font-weight: 600; margin: 25px 0 15px 0; font-size: 16px; border-bottom: 2px solid #667eea; padding-bottom: 8px; }
      .form-group { margin-bottom: 20px; }
      label { display: block; font-weight: 500; margin-bottom: 8px; color: #333; font-size: 14px; }
      input { width: 100%; padding: 12px; border: 2px solid #e0e0e0; border-radius: 6px; font-size: 14px; transition: border-color 0.3s; }
      input:focus { outline: none; border-color: #667eea; }
      button { width: 100%; padding: 14px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; border-radius: 6px; font-size: 16px; font-weight: 600; cursor: pointer; transition: transform 0.2s, box-shadow 0.2s; }
      button:hover { transform: translateY(-2px); box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4); }
      button:active { transform: translateY(0); }
    </style></head>
    <body>
    <div class="container">
      <h1>🎉 SilverSupport Setup</h1>
      <p class="subtitle">Configure your tech support service</p>
      
      <form id="form">
        <div class="section-title">📞 Twilio Configuration</div>
        <div class="form-group"><label>Twilio Account SID</label><input name="TWILIO_ACCOUNT_SID" required placeholder="AC..."></div>
        <div class="form-group"><label>Twilio Auth Token</label><input type="password" name="TWILIO_AUTH_TOKEN" required placeholder="Your auth token"></div>
        <div class="form-group"><label>Twilio Phone Number</label><input name="TWILIO_PHONE_NUMBER" required placeholder="+1234567890"></div>
        <div class="form-group"><label>Webhook URL</label><input name="TWILIO_WEBHOOK_URL" required value="https://${SERVER_IP}/webhooks/twilio"></div>
        
        <div class="section-title">🤖 AI Services</div>
        <div class="form-group"><label>OpenAI API Key</label><input type="password" name="OPENAI_API_KEY" required placeholder="sk-..."></div>
        <div class="form-group"><label>Anthropic API Key</label><input type="password" name="ANTHROPIC_API_KEY" required placeholder="sk-ant-..."></div>
        
        <button type="submit">Complete Setup & Start Services</button>
      </form>
      <div id="msg" style="margin-top:20px;padding:15px;border-radius:6px;display:none;"></div>
    </div>
    <script>
    document.getElementById('form').onsubmit = async (e) => {
      e.preventDefault();
      const data = {};
      new FormData(e.target).forEach((v,k) => data[k]=v);
      try {
        const r = await fetch('/setup', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data) });
        const j = await r.json();
        const msg = document.getElementById('msg');
        if(r.ok) {
          msg.style.background='#d4edda'; msg.style.color='#155724';
          msg.innerHTML = '✅ Setup complete! Starting services...';
          msg.style.display='block';
          setTimeout(() => location.reload(), 3000);
        } else {
          throw new Error(j.error);
        }
      } catch(err) {
        const msg = document.getElementById('msg');
        msg.style.background='#f8d7da'; msg.style.color='#721c24';
        msg.innerHTML = '❌ Error: '+err.message;
        msg.style.display='block';
      }
    };
    </script></body></html>
  `);
});

app.post('/setup', async (req, res) => {
  if (isSetupComplete()) {
    return res.status(403).json({ error: 'Setup already complete' });
  }
  try {
    let env = fs.readFileSync(ENV_FILE, 'utf8');
    for (const [k, v] of Object.entries(req.body)) {
      const re = new RegExp(`^${k}=.*$`, 'm');
      env = re.test(env) ? env.replace(re, `${k}=${v}`) : env + `\n${k}=${v}`;
    }
    
    // Generate security keys
    const crypto = require('crypto');
    env = env.replace(/^JWT_SECRET=.*$/m, `JWT_SECRET=${crypto.randomBytes(32).toString('hex')}`);
    env = env.replace(/^ENCRYPTION_KEY=.*$/m, `ENCRYPTION_KEY=${crypto.randomBytes(16).toString('hex')}`);
    env = env.replace(/^SESSION_SECRET=.*$/m, `SESSION_SECRET=${crypto.randomBytes(32).toString('hex')}`);
    
    fs.writeFileSync(ENV_FILE, env);
    fs.writeFileSync(SETUP_LOCK, new Date().toISOString());
    
    res.json({ success: true });
    
    // Start the main application
    setTimeout(() => {
      exec('cd /opt/silversupport && pm2 stop setup-wizard && pm2 start server.js --name silversupport', (err) => {
        if (err) console.error(err);
      });
    }, 2000);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Setup wizard running on http://YOUR_IP:${PORT}`);
});
WIZARDEOF
    
    chmod +x "$SILVER_ROOT/setup-wizard.js"
    
    print_success "Setup wizard created"
}

start_setup_wizard() {
    print_step "Starting setup wizard"
    
    cd "$SILVER_ROOT"
    pm2 start setup-wizard.js --name setup-wizard
    pm2 save > /dev/null 2>&1
    
    print_success "Setup wizard started on port $SETUP_PORT"
}

#############################################
# PERMISSIONS
#############################################

set_permissions() {
    print_step "Setting file permissions"
    
    chown -R $SILVER_USER:$SILVER_USER $SILVER_ROOT
    chown -R $SILVER_USER:$SILVER_USER /var/log/silversupport
    chown -R $SILVER_USER:$SILVER_USER /var/lib/silversupport
    
    chmod 600 "$SILVER_ROOT/.env"
    
    print_success "Permissions configured"
}

#############################################
# NGINX CONFIGURATION
#############################################

configure_nginx() {
    print_step "Configuring nginx"
    
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    cat > /etc/nginx/sites-available/silversupport << NGINXEOF
server {
    listen 80;
    server_name $SERVER_IP _;

    # Admin Dashboard
    location /admin/ {
        alias /opt/silversupport/admin-dashboard/dist/;
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
    }

    # Health check
    location /health {
        proxy_pass http://localhost:3000;
    }
}
NGINXEOF
    
    ln -sf /etc/nginx/sites-available/silversupport /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t > /dev/null 2>&1
    systemctl restart nginx
    systemctl enable nginx > /dev/null 2>&1
    
    print_success "nginx configured and started"
}

#############################################
# FIREWALL
#############################################

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
        print_warning "UFW not installed, skipping firewall configuration"
    fi
}

#############################################
# COMPLETION
#############################################

display_summary() {
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    clear
    echo -e "${GREEN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║           ✓ Installation Complete!                        ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}Installation Summary:${NC}"
    echo -e "  Environment: ${GREEN}${ENVIRONMENT}${NC}"
    echo -e "  Version: ${GREEN}${INSTALLER_VERSION}${NC}"
    echo -e "  Installation Path: ${GREEN}${SILVER_ROOT}${NC}"
    echo -e "  Database: ${GREEN}silversupport_alpha${NC}"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  NEXT STEP: Complete Setup Wizard${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Open your browser and navigate to:"
    echo ""
    echo -e "  ${GREEN}http://${SERVER_IP}:${SETUP_PORT}${NC}"
    echo ""
    echo -e "  Complete the web form to configure:"
    echo -e "    • Twilio credentials"
    echo -e "    • OpenAI API key"
    echo -e "    • Anthropic API key"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  ${BLUE}pm2 status${NC}          - Check application status"
    echo -e "  ${BLUE}pm2 logs${NC}            - View application logs"
    echo -e "  ${BLUE}pm2 restart all${NC}     - Restart services"
    echo ""
    echo -e "${BLUE}Installation Log: ${LOG_FILE}${NC}"
    echo ""
}

#############################################
# MAIN INSTALLATION
#############################################

main() {
    local start_time=$SECONDS
    
    print_banner
    
    # Pre-flight checks
    check_root
    check_ubuntu
    check_memory
    check_disk_space
    check_existing_install
    
    # System packages
    install_prerequisites
    install_awscli
    configure_aws_credentials
    install_nodejs
    install_postgresql
    install_nginx
    install_pm2
    
    # Application setup
    create_system_user
    create_directories
    download_application
    setup_database
    install_dependencies
    create_env_file
    
    # Configuration
    create_setup_wizard
    set_permissions
    start_setup_wizard
    configure_nginx
    configure_firewall
    
    # Complete
    local elapsed=$((SECONDS - start_time))
    local minutes=$((elapsed / 60))
    
    log "Installation completed in ${minutes} minutes"
    
    display_summary
}

# Run installation
main "$@"
