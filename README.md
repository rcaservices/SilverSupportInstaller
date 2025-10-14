# SilverSupport

**Helping Seniors with Technology**

SilverSupport is a comprehensive technical support platform designed specifically for seniors. It provides voice-based assistance, an intuitive admin panel, and automated support workflows to help seniors navigate technology challenges.

---

## 🚀 Quick Installation

Install SilverSupport on a fresh Ubuntu 20.04/22.04 LTS server:

```bash
cd /home && curl -o silver-latest -L https://install.silverzupport.us/latest && sh silver-latest
```

**Installation time:** 15-30 minutes

**Requirements:** Fresh Ubuntu server with 2GB RAM, 20GB disk, root access

---

## 📋 Features

- **Voice Call Support** - Twilio-powered voice assistance for seniors
- **Admin Dashboard** - Web-based control panel on port 9443
- **FAQ Management** - Organized knowledge base for common issues
- **Analytics Dashboard** - Track usage and support metrics
- **Auto-Configuration** - Setup wizard handles all configuration
- **Security Focused** - Built-in firewall, SSL, fail2ban protection

---

## 📚 Documentation

### Installation
- [System Requirements](docs/installation/requirements.md)
- [Quick Start Guide](docs/installation/quickstart.md)
- [Troubleshooting](docs/installation/troubleshooting.md)

### Development
- [Building from Source](docs/development/building.md)
- [Contributing Guidelines](docs/development/contributing.md)

### Deployment
- [S3 Infrastructure Setup](docs/deployment/s3-setup.md)
- [CloudFront Configuration](docs/deployment/cloudfront.md)

---

## 🏗️ Architecture

SilverSupport uses a cPanel-inspired directory structure:

```
/usr/local/silver/          # Main installation
├── version                 # Current version
├── bin/                    # Executable scripts
├── base/                   # Core application
├── whostmgr/              # Admin panel (like WHM)
└── scripts/               # Maintenance scripts

/var/silver/               # Runtime data
├── logs/                  # Application logs
├── backups/              # System backups
└── databases/            # Database dumps

/etc/silver/              # Configuration files
```

---

## 🔧 System Requirements

### Hardware
- **CPU:** 2+ cores
- **RAM:** 2GB minimum, 4GB recommended
- **Disk:** 20GB minimum, 40GB+ recommended
- **Architecture:** 64-bit

### Software
- **OS:** Ubuntu 22.04 LTS (recommended) or 20.04 LTS
- **Status:** Fresh installation only
- **Access:** Root SSH access required

### Network
- Static IPv4 address (required)
- Fully-qualified domain name
- Ports: 22, 80, 443, 9443

---

## 📦 Installation Process

1. **Pre-flight Checks** - System validation
2. **Package Installation** - Node.js, PostgreSQL, Nginx, PM2
3. **Directory Structure** - Create `/usr/local/silver`
4. **Database Setup** - PostgreSQL configuration
5. **Web Server** - Nginx with SSL
6. **Security** - Firewall and fail2ban
7. **Setup Wizard** - Web interface on port 9443

**Post-installation:**
- Access admin panel: `https://YOUR-SERVER-IP:9443`
- Login with root credentials
- Complete 6-step setup wizard

---

## 🚨 Important Notes

### ⚠️ Cannot Be Uninstalled

Once installed, SilverSupport becomes part of your system. The **only way to remove it is to reinstall the operating system**. This is by design to ensure system integrity.

### ⚠️ Fresh Installation Required

SilverSupport **cannot** be installed on servers with:
- Existing control panels (cPanel, Plesk, DirectAdmin, etc.)
- Existing web servers or databases
- Previously configured hosting software

**You must start with a clean Ubuntu installation.**

### ⚠️ Server Dedication

After installation, this server is dedicated to SilverSupport. Do not install other control panels or hosting software manually.

---

## 🔐 Security

SilverSupport includes multiple security layers:

- **Firewall (UFW)** - Blocks all unnecessary ports
- **Fail2ban** - Intrusion prevention
- **SSL Certificates** - Automated via Certbot
- **PostgreSQL** - Secured with generated credentials
- **Admin Access** - Root-only via port 9443

---

## 📊 Version Management

Check installed version:
```bash
silver-version
```

Check system status:
```bash
silver-status
```

**Current Version:** 1.0.0

**Release History:** [View Changelog](https://releases.silverzupport.us/manifests/changelog.json)

---

## 🌐 Hosting Infrastructure

### Installation
- **URL:** https://install.silverzupport.us/
- **CDN:** CloudFront (AWS)
- **Storage:** S3 bucket `silversupport-install`

### Releases
- **URL:** https://releases.silverzupport.us/
- **CDN:** CloudFront (AWS)
- **Storage:** S3 bucket `silversupport-releases`

### Available Versions
```bash
# Latest stable
https://install.silverzupport.us/latest

# Version-specific
https://install.silverzupport.us/silver-1.0.0

# Development channels
https://install.silverzupport.us/alpha
https://install.silverzupport.us/staging
```

---

## 🛠️ For Developers

### Building a Release

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/silversupport.git
cd silversupport

# Build release tarball
./scripts/build-release.sh 1.0.0

# Deploy to S3
./scripts/deploy-release.sh 1.0.0
```

### Project Structure
```
silversupport/
├── installer/           # Installation scripts
├── src/                # Application source code
├── scripts/            # Build and deploy scripts
├── docs/               # Documentation
└── config/             # Configuration templates
```

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](docs/development/contributing.md).

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📞 Support

- **Documentation:** https://docs.silverzupport.us
- **Installation Issues:** Check `/var/log/silver-install.log`
- **GitHub Issues:** [Report a bug](https://github.com/YOUR_USERNAME/silversupport/issues)
- **Email:** support@silverzupport.us

---

## 📄 License

[Add your license here - MIT, GPL, etc.]

---

## 🙏 Acknowledgments

Built with inspiration from cPanel/WHM's proven installer architecture.

**Technologies:**
- Node.js 18
- PostgreSQL 14
- Nginx
- PM2
- Redis
- React (Admin Dashboard)

---

## 📈 Roadmap

### Version 1.1 (Q4 2025)
- [ ] Multi-language support
- [ ] Enhanced analytics
- [ ] Mobile app integration

### Version 2.0 (Q1 2026)
- [ ] Video call support
- [ ] AI-powered assistance
- [ ] Multi-tenancy

---

**SilverSupport** - Making technology accessible for everyone. 🛡️
