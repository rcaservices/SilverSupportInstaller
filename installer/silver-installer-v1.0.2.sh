#!/usr/bin/env bash
# SilverSupport Installer v1.0.2
# Installation script for Ubuntu servers
# Usage: curl -L https://install.silverzupport.us/latest | bash

set -e  # Exit on any error

# Installer Configuration
INSTALLER_VERSION="1.0.2"
SILVERSUPPORT_VERSION="${SILVER_VERSION:-latest}"
INSTALL_SOURCE="https://releases.silverzupport.us"
LOG_FILE="/var/log/silver-install.log"
LOCK_FILE="/var/lock/silver-install.lock"

# Directory Structure
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

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║          SilverSupport Installation Wizard                ║"
    echo "║                                                            ║"
    echo "║       Patient Tech Support for Seniors                    ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${BLUE}Version:${NC} $INSTALLER_VERSION"
    echo -e "${BLUE}Target:${NC} Ubuntu Server"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        echo "Please run: sudo bash $0"
        exit 1
    fi
}

# Check Ubuntu version
check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}Error: Cannot detect OS version${NC}"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        echo -e "${RED}Error: This installer requires Ubuntu${NC}"
        echo "Detected: $ID $VERSION"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Ubuntu $VERSION_ID detected${NC}"
}

# Check system requirements
check_requirements() {
    echo -e "${YELLOW}Checking system requirements...${NC}"
    
    # Check memory
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 900 ]; then
        echo -e "${RED}Error: Insufficient memory (${total_mem}MB). Minimum: 900MB${NC}"
        exit 1
    elif [ "$total_mem" -lt 1900 ]; then
        echo -e "${YELLOW}⚠ Low memory detected (${total_mem}MB). Recommended: 2GB+${NC}"
        echo -e "${YELLOW}  This may work for testing but consider upgrading for production.${NC}"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        echo -e "${GREEN}✓ Memory: ${total_mem}MB (minimal)${NC}"
    else
        echo -e "${GREEN}✓ Memory: ${total_mem}MB${NC}"
    fi
    
    # Check disk space
    available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_disk" -lt 10 ]; then
        echo -e "${RED}Error: Insufficient disk space (${available_disk}GB). Required: 10GB+${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Disk space: ${available_disk}GB available${NC}"
    fi
}

# Prompt for environment
select_environment() {
    echo -e "${YELLOW}Select Installation Environment:${NC}"
    echo "1) Alpha (Development/Testing)"
    echo "2) Staging (Pre-production)"
    echo "3) Production"
    echo ""

    # Check if we have an interactive terminal
    if [ ! -t 0 ]; then
        echo -e "${RED}Error: No interactive terminal detected${NC}"
        echo "This installer must be run interactively, not piped from curl."
        echo ""
        echo "Please run:"
        echo "  wget https://install.silverzupport.us/latest -O install.sh"
        echo "  sudo bash install.sh"
        exit 1
    fi

    local attempts=0
    local max_attempts=5
    
    while true; do
        read -r -p "Enter choice [1-3]: " env_choice
        
        # Check if read was successful
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to read input${NC}"
            exit 1
        fi
        
        case $env_choice in
            1)
                ENVIRONMENT="alpha"
                DOMAIN="alpha.silverzupport.us"
                break
                ;;
            2)
                ENVIRONMENT="staging"
                DOMAIN="staging.silverzupport.us"
                break
                ;;
            3)
                ENVIRONMENT="production"
                DOMAIN="silverzupport.us"
                break
                ;;
            *)
                attempts=$((attempts + 1))
                if [ $attempts -ge $max_attempts ]; then
                    echo -e "${RED}Error: Too many invalid attempts${NC}"
                    exit 1
                fi
                echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done

    echo -e "${GREEN}✓ Environment: $ENVIRONMENT${NC}"
    echo -e "${GREEN}✓ Domain: $DOMAIN${NC}"
}





# Install system dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing system dependencies...${NC}"
    
    log "Updating package list"
    apt-get update -qq
    
    log "Installing prerequisites"
    apt-get install -y -qq \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release
    
    echo -e "${GREEN}✓ System dependencies installed${NC}"
}

# Install Node.js
install_nodejs() {
    echo -e "${YELLOW}Installing Node.js...${NC}"
    
    if command -v node &> /dev/null; then
        node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$node_version" -ge 18 ]; then
            echo -e "${GREEN}✓ Node.js $(node --version) already installed${NC}"
            return
        fi
    fi
    
    log "Installing Node.js 18"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    echo -e "${GREEN}✓ Node.js $(node --version) installed${NC}"
}

# Install PostgreSQL
install_postgresql() {
    echo -e "${YELLOW}Installing PostgreSQL...${NC}"
    
    if command -v psql &> /dev/null; then
        echo -e "${GREEN}✓ PostgreSQL already installed${NC}"
        return
    fi
    
    log "Installing PostgreSQL 14"
    apt-get install -y postgresql postgresql-contrib
    
    systemctl enable postgresql
    systemctl start postgresql
    
    echo -e "${GREEN}✓ PostgreSQL installed${NC}"
}

# Install PM2
install_pm2() {
    echo -e "${YELLOW}Installing PM2...${NC}"
    
    if command -v pm2 &> /dev/null; then
        echo -e "${GREEN}✓ PM2 already installed${NC}"
        return
    fi
    
    log "Installing PM2"
    npm install -g pm2
    pm2 startup systemd -u root --hp /root
    
    echo -e "${GREEN}✓ PM2 installed${NC}"
}

# Install Nginx
install_nginx() {
    echo -e "${YELLOW}Installing Nginx...${NC}"
    
    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}✓ Nginx already installed${NC}"
        return
    fi
    
    log "Installing Nginx"
    apt-get install -y nginx
    
    systemctl enable nginx
    systemctl start nginx
    
    echo -e "${GREEN}✓ Nginx installed${NC}"
}

# Create directory structure
create_directories() {
    echo -e "${YELLOW}Creating directory structure...${NC}"
    
    mkdir -p "$SILVER_ROOT"
    mkdir -p "$SILVER_VAR"/{logs,uploads,backups,temp}
    mkdir -p "$SILVER_ETC"
    mkdir -p "$SILVER_CRON"
    
    chmod 755 "$SILVER_ROOT"
    chmod 750 "$SILVER_VAR"
    chmod 750 "$SILVER_ETC"
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Download SilverSupport code
download_code() {
    echo -e "${YELLOW}Downloading SilverSupport code...${NC}"
    
    cd "$SILVER_ROOT"
    
    # Try to download from releases bucket
    local tarball="silversupport-${SILVERSUPPORT_VERSION}.tar.gz"
    local download_url="${INSTALL_SOURCE}/${tarball}"
    
    log "Downloading from $download_url"
    
    if wget -q "$download_url" -O "$tarball"; then
        log "Extracting tarball"
        tar -xzf "$tarball"
        rm "$tarball"
        echo -e "${GREEN}✓ Code downloaded and extracted${NC}"
    else
        echo -e "${YELLOW}Warning: Could not download from releases bucket${NC}"
        echo -e "${YELLOW}You'll need to manually deploy the code to $SILVER_ROOT${NC}"
    fi
}

# Configure database
configure_database() {
    echo -e "${YELLOW}Configuring database...${NC}"
    
    local db_name="silversupport_${ENVIRONMENT}"
    local db_user="silversupport"
    local db_pass=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    log "Creating database and user"
    
    sudo -u postgres psql << EOF
CREATE DATABASE ${db_name};
CREATE USER ${db_user} WITH ENCRYPTED PASSWORD '${db_pass}';
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
\q
EOF
    
    # Save credentials
    cat > "$SILVER_ETC/database.conf" << EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASS=${db_pass}
EOF
    
    chmod 600 "$SILVER_ETC/database.conf"
    
    echo -e "${GREEN}✓ Database configured${NC}"
    echo -e "${BLUE}Database credentials saved to: $SILVER_ETC/database.conf${NC}"
}

# Create environment file
create_env_file() {
    echo -e "${YELLOW}Creating environment configuration...${NC}"
    
    # Source database config
    . "$SILVER_ETC/database.conf"
    
    cat > "$SILVER_ROOT/.env" << EOF
# SilverSupport Environment Configuration
# Environment: ${ENVIRONMENT}
# Generated: $(date)

NODE_ENV=${ENVIRONMENT}
PORT=3000
HOST=0.0.0.0

# Database
DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}

# Security (CHANGE THESE IN PRODUCTION!)
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -hex 16)
SESSION_SECRET=$(openssl rand -base64 32)

# Application
DOMAIN=${DOMAIN}
ENABLE_VOICE_AUTH=true
ENABLE_ANALYTICS=true

# Logging
LOG_LEVEL=info
LOG_FILE=${SILVER_VAR}/logs/application.log

# Add your API keys here:
# TWILIO_ACCOUNT_SID=
# TWILIO_AUTH_TOKEN=
# TWILIO_PHONE_NUMBER=
# OPENAI_API_KEY=
# ANTHROPIC_API_KEY=
EOF
    
    chmod 600 "$SILVER_ROOT/.env"
    
    echo -e "${GREEN}✓ Environment file created${NC}"
    echo -e "${YELLOW}Important: Edit $SILVER_ROOT/.env and add your API keys${NC}"
}

# Install application dependencies
install_app_dependencies() {
    echo -e "${YELLOW}Installing application dependencies...${NC}"
    
    if [ -f "$SILVER_ROOT/package.json" ]; then
        cd "$SILVER_ROOT"
        npm install --production
        echo -e "${GREEN}✓ Application dependencies installed${NC}"
    else
        echo -e "${YELLOW}Warning: package.json not found. Skipping npm install.${NC}"
    fi
}

# Create setup wizard
create_setup_wizard() {
    echo -e "${YELLOW}Creating setup wizard...${NC}"
    
    # Create the setup wizard JavaScript file
    cat > "$SILVER_ROOT/setup-wizard.js" << 'WIZARDEOF'
const express = require('express');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const app = express();
const PORT = 9443;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const SILVER_ROOT = '/usr/local/silver';
const SILVER_ETC = '/etc/silver';
const ENV_FILE = path.join(SILVER_ROOT, '.env');
const SETUP_LOCK = path.join(SILVER_ETC, 'setup.lock');

const isSetupComplete = () => fs.existsSync(SETUP_LOCK);

app.get('/', (req, res) => {
  if (isSetupComplete()) {
    return res.send('<h1>Setup Already Complete</h1><p>This server has been configured.</p>');
  }
  
  const html = '<!DOCTYPE html>' +
'<html><head><title>SilverSupport Setup</title>' +
'<style>' +
'* { margin: 0; padding: 0; box-sizing: border-box; }' +
'body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }' +
'.container { max-width: 800px; margin: 0 auto; background: white; border-radius: 12px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }' +
'.header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; border-radius: 12px 12px 0 0; }' +
'.content { padding: 40px; }' +
'.form-group { margin-bottom: 20px; }' +
'label { display: block; font-weight: 600; margin-bottom: 8px; }' +
'input, select { width: 100%; padding: 12px; border: 2px solid #e0e0e0; border-radius: 6px; font-size: 14px; }' +
'.section-title { font-size: 18px; font-weight: 600; margin: 30px 0 20px; color: #667eea; }' +
'button { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; padding: 15px; font-size: 16px; font-weight: 600; border-radius: 6px; cursor: pointer; width: 100%; margin-top: 20px; }' +
'.help-text { font-size: 12px; color: #666; margin-top: 5px; }' +
'</style></head><body>' +
'<div class="container">' +
'  <div class="header"><h1>🎉 SilverSupport Setup</h1><p>Configure your installation</p></div>' +
'  <div class="content">' +
'    <form id="form">' +
'      <div class="section-title">📞 Twilio Configuration</div>' +
'      <div class="form-group"><label>Account SID</label><input name="TWILIO_ACCOUNT_SID" required placeholder="ACxxxxx"><div class="help-text">From Twilio Console</div></div>' +
'      <div class="form-group"><label>Auth Token</label><input type="password" name="TWILIO_AUTH_TOKEN" required><div class="help-text">Keep secret</div></div>' +
'      <div class="form-group"><label>Phone Number</label><input name="TWILIO_PHONE_NUMBER" required placeholder="+1234567890"></div>' +
'      <div class="section-title">🤖 AI Services</div>' +
'      <div class="form-group"><label>OpenAI API Key</label><input type="password" name="OPENAI_API_KEY" required placeholder="sk-..."></div>' +
'      <div class="form-group"><label>Anthropic API Key</label><input type="password" name="ANTHROPIC_API_KEY" required placeholder="sk-ant-..."></div>' +
'      <div class="section-title">🌐 Domain</div>' +
'      <div class="form-group"><label>Domain Name</label><input name="DOMAIN" required value="' + process.env.DOMAIN + '"></div>' +
'      <button type="submit">Complete Setup</button>' +
'    </form>' +
'    <div id="msg" style="margin-top:20px;padding:15px;border-radius:6px;display:none;"></div>' +
'  </div>' +
'</div>' +
'<script>' +
'document.getElementById("form").onsubmit = async (e) => {' +
'  e.preventDefault();' +
'  const data = {};' +
'  new FormData(e.target).forEach((v,k) => data[k]=v);' +
'  try {' +
'    const r = await fetch("/setup", { method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(data) });' +
'    const j = await r.json();' +
'    const msg = document.getElementById("msg");' +
'    if(r.ok) {' +
'      msg.style.background="#d4edda"; msg.style.color="#155724";' +
'      msg.innerHTML = "✅ Setup complete! Server restarting...";' +
'      msg.style.display="block";' +
'      setTimeout(() => location.reload(), 3000);' +
'    } else {' +
'      throw new Error(j.error);' +
'    }' +
'  } catch(err) {' +
'    const msg = document.getElementById("msg");' +
'    msg.style.background="#f8d7da"; msg.style.color="#721c24";' +
'    msg.innerHTML = "❌ Error: "+err.message;' +
'    msg.style.display="block";' +
'  }' +
'};' +
'</script></body></html>';
  
  res.send(html);
});

app.post('/setup', async (req, res) => {
  if (isSetupComplete()) {
    return res.status(403).json({ error: 'Setup already complete' });
  }
  try {
    let env = fs.readFileSync(ENV_FILE, 'utf8');
    for (const [k, v] of Object.entries(req.body)) {
      const re = new RegExp('^' + k + '=.*
<html><head><title>SilverSupport Setup</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }
.container { max-width: 800px; margin: 0 auto; background: white; border-radius: 12px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
.header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; border-radius: 12px 12px 0 0; }
.content { padding: 40px; }
.form-group { margin-bottom: 20px; }
label { display: block; font-weight: 600; margin-bottom: 8px; }
input, select { width: 100%; padding: 12px; border: 2px solid #e0e0e0; border-radius: 6px; font-size: 14px; }
.section-title { font-size: 18px; font-weight: 600; margin: 30px 0 20px; color: #667eea; }
button { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; padding: 15px; font-size: 16px; font-weight: 600; border-radius: 6px; cursor: pointer; width: 100%; margin-top: 20px; }
.help-text { font-size: 12px; color: #666; margin-top: 5px; }
</style></head><body>
<div class="container">
  <div class="header"><h1>🎉 SilverSupport Setup</h1><p>Configure your installation</p></div>
  <div class="content">
    <form id="form">
      <div class="section-title">📞 Twilio Configuration</div>
      <div class="form-group"><label>Account SID</label><input name="TWILIO_ACCOUNT_SID" required placeholder="ACxxxxx"><div class="help-text">From Twilio Console</div></div>
      <div class="form-group"><label>Auth Token</label><input type="password" name="TWILIO_AUTH_TOKEN" required><div class="help-text">Keep secret</div></div>
      <div class="form-group"><label>Phone Number</label><input name="TWILIO_PHONE_NUMBER" required placeholder="+1234567890"></div>
      
      <div class="section-title">🤖 AI Services</div>
      <div class="form-group"><label>OpenAI API Key</label><input type="password" name="OPENAI_API_KEY" required placeholder="sk-..."></div>
      <div class="form-group"><label>Anthropic API Key</label><input type="password" name="ANTHROPIC_API_KEY" required placeholder="sk-ant-..."></div>
      
      <div class="section-title">🌐 Domain</div>
      <div class="form-group"><label>Domain Name</label><input name="DOMAIN" required value="${DOMAIN}"></div>
      
      <button type="submit">Complete Setup</button>
    </form>
    <div id="msg" style="margin-top:20px;padding:15px;border-radius:6px;display:none;"></div>
  </div>
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
      msg.innerHTML = '✅ Setup complete! Server restarting...';
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
</script></body></html>\`);
});

app.post('/setup', async (req, res) => {
  if (isSetupComplete()) {
    return res.status(403).json({ error: 'Setup already complete' });
  }
  try {
    let env = fs.readFileSync(ENV_FILE, 'utf8');
    for (const [k, v] of Object.entries(req.body)) {
      const re = new RegExp(\`^\${k}=.*$\`, 'm');
      env = re.test(env) ? env.replace(re, \`\${k}=\${v}\`) : env + \`\\n\${k}=\${v}\`;
    }
    fs.writeFileSync(ENV_FILE, env);
    fs.writeFileSync(SETUP_LOCK, new Date().toISOString());
    exec('pm2 restart all', (err) => {
      if (err) console.error(err);
    });
    res.json({ success: true });
    setTimeout(() => process.exit(0), 5000);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(\`Setup wizard: http://YOUR_IP:\${PORT}\`);
});
WIZARDEOF
    
    echo -e "${GREEN}✓ Setup wizard created${NC}"
}

# Start admin dashboard
start_setup_wizard() {
    echo -e "${YELLOW}Starting admin dashboard...${NC}"
    
    cd "$SILVER_ROOT"
    
    # Install express if needed
    if [ ! -d "node_modules/express" ]; then
        npm install express --save
    fi
    
    # Start dashboard with PM2
    pm2 start setup-wizard.js --name silversupport-admin
    pm2 save
    
    echo -e "${GREEN}✓ Admin dashboard started on port $SETUP_PORT${NC}"
}

# Configure PM2
configure_pm2() {
    echo -e "${YELLOW}Configuring PM2...${NC}"
    
    if [ -f "$SILVER_ROOT/ecosystem.config.js" ]; then
        cd "$SILVER_ROOT"
        pm2 start ecosystem.config.js
        pm2 save
        echo -e "${GREEN}✓ PM2 configured and started${NC}"
    else
        echo -e "${YELLOW}Warning: ecosystem.config.js not found. Skipping PM2 setup.${NC}"
    fi
}

# Configure Nginx
configure_nginx() {
    echo -e "${YELLOW}Configuring Nginx...${NC}"
    
    cat > /etc/nginx/sites-available/silversupport << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    
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
    
    ln -sf /etc/nginx/sites-available/silversupport /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t
    systemctl reload nginx
    
    echo -e "${GREEN}✓ Nginx configured${NC}"
}

# Display summary
display_summary() {
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}║         SilverSupport Installation Complete!              ║${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
    echo -e "${GREEN}Installation Path:${NC} $SILVER_ROOT"
    echo -e "${GREEN}Configuration:${NC} $SILVER_ETC"
    echo -e "${GREEN}Data Directory:${NC} $SILVER_VAR"
    echo ""
    echo -e "${YELLOW}IMPORTANT - Complete Setup:${NC}"
    echo ""
    echo -e "  ${GREEN}Open your browser:${NC}"
    echo -e "  ${BLUE}http://${SERVER_IP}:${SETUP_PORT}${NC}"
    echo ""
    echo -e "  Complete the web-based setup wizard to configure:"
    echo -e "  - Administrator username and password"
    echo -e "  - Twilio credentials"
    echo -e "  - OpenAI and Anthropic API keys"
    echo -e "  - Domain settings"
    echo ""
    echo -e "${YELLOW}After Setup:${NC}"
    echo -e "  - Login with your credentials"
    echo -e "  - Manage settings via admin dashboard"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo -e "  Check status: ${BLUE}pm2 status${NC}"
    echo -e "  View logs: ${BLUE}pm2 logs silversupport-admin${NC}"
    echo -e "  Restart: ${BLUE}pm2 restart silversupport-admin${NC}"
    echo ""
    
    # Show upgrade info if low memory
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 1900 ]; then
        echo -e "${YELLOW}📊 Server Scaling:${NC}"
        echo -e "   Current: ${total_mem}MB RAM (minimal configuration)"
        echo -e "   To upgrade: Resize your droplet to 2GB+ for better performance"
        echo -e "   All data and configuration will be preserved during resize"
        echo ""
    fi
    
    echo -e "${BLUE}Documentation: https://docs.silverzupport.us${NC}"
    echo -e "${BLUE}Support: support@silverzupport.us${NC}"
    echo ""
}

# Main installation flow
main() {
    print_banner
    check_root
    check_ubuntu
    check_requirements
    select_environment
    
    echo ""
    echo -e "${YELLOW}Starting installation...${NC}"
    echo ""
    
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
    create_setup_wizard
    start_setup_wizard
    configure_pm2
    configure_nginx
    
    display_summary
    
    log "Installation completed successfully"
}

# Run main installation
main "$@"
, 'm');
      env = re.test(env) ? env.replace(re, k + '=' + v) : env + '\n' + k + '=' + v;
    }
    fs.writeFileSync(ENV_FILE, env);
    fs.writeFileSync(SETUP_LOCK, new Date().toISOString());
    exec('pm2 restart all', (err) => {
      if (err) console.error(err);
    });
    res.json({ success: true });
    setTimeout(() => process.exit(0), 5000);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('Setup wizard: http://YOUR_IP:' + PORT);
});
WIZARDEOF
    
    echo -e "${GREEN}✓ Setup wizard created${NC}"
}
<html><head><title>SilverSupport Setup</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }
.container { max-width: 800px; margin: 0 auto; background: white; border-radius: 12px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
.header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; border-radius: 12px 12px 0 0; }
.content { padding: 40px; }
.form-group { margin-bottom: 20px; }
label { display: block; font-weight: 600; margin-bottom: 8px; }
input, select { width: 100%; padding: 12px; border: 2px solid #e0e0e0; border-radius: 6px; font-size: 14px; }
.section-title { font-size: 18px; font-weight: 600; margin: 30px 0 20px; color: #667eea; }
button { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; padding: 15px; font-size: 16px; font-weight: 600; border-radius: 6px; cursor: pointer; width: 100%; margin-top: 20px; }
.help-text { font-size: 12px; color: #666; margin-top: 5px; }
</style></head><body>
<div class="container">
  <div class="header"><h1>🎉 SilverSupport Setup</h1><p>Configure your installation</p></div>
  <div class="content">
    <form id="form">
      <div class="section-title">📞 Twilio Configuration</div>
      <div class="form-group"><label>Account SID</label><input name="TWILIO_ACCOUNT_SID" required placeholder="ACxxxxx"><div class="help-text">From Twilio Console</div></div>
      <div class="form-group"><label>Auth Token</label><input type="password" name="TWILIO_AUTH_TOKEN" required><div class="help-text">Keep secret</div></div>
      <div class="form-group"><label>Phone Number</label><input name="TWILIO_PHONE_NUMBER" required placeholder="+1234567890"></div>
      
      <div class="section-title">🤖 AI Services</div>
      <div class="form-group"><label>OpenAI API Key</label><input type="password" name="OPENAI_API_KEY" required placeholder="sk-..."></div>
      <div class="form-group"><label>Anthropic API Key</label><input type="password" name="ANTHROPIC_API_KEY" required placeholder="sk-ant-..."></div>
      
      <div class="section-title">🌐 Domain</div>
      <div class="form-group"><label>Domain Name</label><input name="DOMAIN" required value="${DOMAIN}"></div>
      
      <button type="submit">Complete Setup</button>
    </form>
    <div id="msg" style="margin-top:20px;padding:15px;border-radius:6px;display:none;"></div>
  </div>
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
      msg.innerHTML = '✅ Setup complete! Server restarting...';
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
</script></body></html>\`);
});

app.post('/setup', async (req, res) => {
  if (isSetupComplete()) {
    return res.status(403).json({ error: 'Setup already complete' });
  }
  try {
    let env = fs.readFileSync(ENV_FILE, 'utf8');
    for (const [k, v] of Object.entries(req.body)) {
      const re = new RegExp(\`^\${k}=.*$\`, 'm');
      env = re.test(env) ? env.replace(re, \`\${k}=\${v}\`) : env + \`\\n\${k}=\${v}\`;
    }
    fs.writeFileSync(ENV_FILE, env);
    fs.writeFileSync(SETUP_LOCK, new Date().toISOString());
    exec('pm2 restart all', (err) => {
      if (err) console.error(err);
    });
    res.json({ success: true });
    setTimeout(() => process.exit(0), 5000);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(\`Setup wizard: http://YOUR_IP:\${PORT}\`);
});
WIZARDEOF
    
    echo -e "${GREEN}✓ Setup wizard created${NC}"
}

# Start setup wizard
start_setup_wizard() {
    echo -e "${YELLOW}Starting setup wizard...${NC}"
    
    cd "$SILVER_ROOT"
    
    # Install express if needed
    if [ ! -d "node_modules/express" ]; then
        npm install express --save
    fi
    
    # Start wizard with PM2
    pm2 start setup-wizard.js --name silversupport-setup
    pm2 save
    
    echo -e "${GREEN}✓ Setup wizard started on port $SETUP_PORT${NC}"
}

# Configure PM2
configure_pm2() {
    echo -e "${YELLOW}Configuring PM2...${NC}"
    
    if [ -f "$SILVER_ROOT/ecosystem.config.js" ]; then
        cd "$SILVER_ROOT"
        pm2 start ecosystem.config.js
        pm2 save
        echo -e "${GREEN}✓ PM2 configured and started${NC}"
    else
        echo -e "${YELLOW}Warning: ecosystem.config.js not found. Skipping PM2 setup.${NC}"
    fi
}

# Configure Nginx
configure_nginx() {
    echo -e "${YELLOW}Configuring Nginx...${NC}"
    
    cat > /etc/nginx/sites-available/silversupport << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    
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
    
    ln -sf /etc/nginx/sites-available/silversupport /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t
    systemctl reload nginx
    
    echo -e "${GREEN}✓ Nginx configured${NC}"
}

# Display summary
display_summary() {
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}║         SilverSupport Installation Complete!              ║${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
    echo -e "${GREEN}Installation Path:${NC} $SILVER_ROOT"
    echo -e "${GREEN}Configuration:${NC} $SILVER_ETC"
    echo -e "${GREEN}Data Directory:${NC} $SILVER_VAR"
    echo ""
    echo -e "${YELLOW}⚡ IMPORTANT - Complete Setup:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e ""
    echo -e "  ${GREEN}Open your browser and visit:${NC}"
    echo -e "  ${BLUE}http://${SERVER_IP}:${SETUP_PORT}${NC}"
    echo -e ""
    echo -e "  Complete the web-based setup wizard to configure:"
    echo -e "  • Twilio credentials"
    echo -e "  • OpenAI & Anthropic API keys"
    echo -e "  • Domain settings"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Alternative - Manual Configuration:${NC}"
    echo -e "  Edit: ${BLUE}${SILVER_ROOT}/.env${NC}"
    echo -e "  Then: ${BLUE}pm2 restart all${NC}"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo -e "  Check status: ${BLUE}pm2 status${NC}"
    echo -e "  View logs: ${BLUE}pm2 logs${NC}"
    echo -e "  Restart: ${BLUE}pm2 restart all${NC}"
    echo -e "  Stop setup wizard: ${BLUE}pm2 stop silversupport-setup${NC}"
    echo ""
    
    # Show upgrade info if low memory
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 1900 ]; then
        echo -e "${YELLOW}📊 Server Scaling:${NC}"
        echo -e "   Current: ${total_mem}MB RAM (minimal configuration)"
        echo -e "   To upgrade: Resize your droplet to 2GB+ for better performance"
        echo -e "   All data and configuration will be preserved during resize"
        echo ""
    fi
    
    echo -e "${BLUE}Documentation: https://docs.silverzupport.us${NC}"
    echo -e "${BLUE}Support: support@silverzupport.us${NC}"
    echo ""
}

# Main installation flow
main() {
    print_banner
    check_root
    check_ubuntu
    check_requirements
    select_environment
    
    echo ""
    echo -e "${YELLOW}Starting installation...${NC}"
    echo ""
    
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
    create_setup_wizard
    start_setup_wizard
    configure_pm2
    configure_nginx
    
    display_summary
    
    log "Installation completed successfully"
}

# Run main installation
main "$@"
