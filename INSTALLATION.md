# SilverSupport Installation Guide

## Quick Start - Install in 3 Minutes

SilverSupport installs on a fresh Ubuntu server similar to how you'd install cPanel. The installer handles everything automatically.

---

## Requirements

- **OS:** Fresh Ubuntu 20.04 LTS or 22.04 LTS (clean installation required)
- **RAM:** 2GB minimum (recommended for production)
- **Disk:** 20GB minimum free space
- **Network:** Static IPv4 address
- **Access:** Root SSH access

⚠️ **Important:** Server must be clean - no existing control panels (cPanel, Plesk, etc.) or web servers.

---

## Installation Steps

### 1. SSH into Your Server
```bash
ssh root@your-server-ip
```

### 2. Run the Installer
```bash
cd /home
curl -L https://install.silverzupport.us/latest -o silver-installer.sh
bash silver-installer.sh
```

### 3. Select Your Environment

When prompted, choose:
- **Option 1:** Production (stable releases)
- **Option 2:** Staging (pre-production testing)
- **Option 3:** Alpha (development/latest features)

### 4. Wait for Installation

Installation takes 3-5 minutes. The installer will:
- Install Node.js, PostgreSQL, Nginx, PM2
- Download the SilverSupport application
- Configure the database
- Set up the web server
- Start all services

### 5. Access Your Application

After installation completes, open your browser:
```
http://YOUR-SERVER-IP/health
```

You should see a JSON response showing status "ok".

---

## Post-Installation

### Verify Installation
```bash
# Check version
silver-version

# Check system status
silver-status

# View application logs
pm2 logs silversupport
```

### System Information

- **Application Directory:** `/opt/silversupport`
- **Configuration:** `/etc/silversupport/`
- **Logs:** `/var/silversupport/logs/`
- **Database:** PostgreSQL (credentials in `/etc/silversupport/database.conf`)
- **Web Server:** Nginx (port 80)
- **Process Manager:** PM2

---

## Important Notes

### Cannot Be Uninstalled
Once installed, SilverSupport becomes part of your system. **The only way to remove it is to reinstall the operating system.** This is by design for system integrity (similar to cPanel).

### Dedicated Server Required
After installation, this server is dedicated to SilverSupport. Do not install other control panels or hosting software.

### Fresh Installation Only
SilverSupport **cannot** be installed on servers with:
- Existing control panels
- Existing web servers or databases  
- Previously configured hosting software

You must start with a clean Ubuntu installation.

---

## Troubleshooting

### Installation Fails
```bash
# Check the installation log
tail -100 /var/log/silver-install.log
```

### Service Not Starting
```bash
# Check PM2 status
pm2 status

# Restart services
pm2 restart silversupport
```

### Database Connection Issues
```bash
# Check database credentials
cat /etc/silversupport/database.conf

# Test database connection
sudo -u postgres psql -d silversupport_production -c "SELECT NOW();"
```

---

## Support

- **Installation Logs:** `/var/log/silver-install.log`
- **Application Logs:** `/var/silversupport/logs/`
- **Health Check:** `http://YOUR-SERVER-IP/health`

---

## Example: Complete Installation Session
```bash
# SSH to server
ssh root@164.90.130.112

# Download and run installer
cd /home
curl -L https://install.silverzupport.us/latest -o silver-installer.sh
bash silver-installer.sh

# Select environment when prompted
# Press 1 for Production

# Wait 3-5 minutes for installation

# Verify installation
silver-version
# Output: 1.0.0-alpha.1

# Check health
curl http://localhost:3000/health
# Output: {"status":"ok",...}
```

---

**Installation Complete!** Your SilverSupport system is now ready to use.
