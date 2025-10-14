# SilverSupport Repository Structure

This document describes the organization of the SilverSupport installer repository.

## Repository Layout

```
SilverSupportInstaller/
│
├── README.md                          # Main project documentation
├── LICENSE                            # MIT License
├── VERSION                            # Current version (1.0.0)
├── .gitignore                         # Git exclusions
├── DIRECTORY_STRUCTURE.md            # This file
│
├── installer/                         # Installation scripts
│   ├── silver-installer.sh           # Main versioned installer
│   ├── latest                        # Copy of current installer
│   └── README.md                     # Installer documentation
│
├── scripts/                          # Utility scripts
│   ├── build-release.sh             # Build release tarball
│   ├── deploy-release.sh            # Deploy to S3
│   ├── update-version.sh            # Version management
│   └── test-installer.sh            # Test installation locally
│
├── docs/                            # Documentation
│   ├── installation/
│   │   ├── requirements.md          # System requirements
│   │   ├── quickstart.md           # Quick start guide
│   │   └── troubleshooting.md      # Common issues
│   ├── development/
│   │   ├── building.md             # Building from source
│   │   └── contributing.md         # How to contribute
│   └── deployment/
│       ├── s3-setup.md             # S3 infrastructure
│       └── cloudfront.md           # CloudFront setup
│
├── config/                          # Configuration templates
│   ├── nginx.conf.template         # Nginx configuration
│   ├── pm2.config.js.template      # PM2 configuration
│   └── env.template                # Environment variables
│
├── src/                             # Application source (future)
│   ├── server/                      # Backend Node.js
│   ├── admin-dashboard/            # Admin panel
│   └── setup-wizard/               # Port 9443 interface
│
└── .github/                        # GitHub configuration
    ├── workflows/
    │   ├── ci.yml                  # CI pipeline
    │   └── release.yml             # Release automation
    └── ISSUE_TEMPLATE/
        └── bug_report.md           # Bug report template
```

## Directory Purposes

### `/installer/`
Contains the installation scripts that users download and run.

- **silver-installer.sh** - The main installer script with full system setup
- **latest** - Symlink or copy of the current stable installer
- Deployed to: `https://install.silverzupport.us/`

### `/scripts/`
Build, deployment, and maintenance utilities for developers.

- **build-release.sh** - Creates tarball from source code
- **deploy-release.sh** - Uploads releases to S3
- **update-version.sh** - Manages version numbers across files
- **test-installer.sh** - Local testing without server

### `/docs/`
Comprehensive documentation for users and developers.

#### `/docs/installation/`
End-user installation documentation.

#### `/docs/development/`
Developer guides and contribution information.

#### `/docs/deployment/`
Infrastructure setup and deployment guides.

### `/config/`
Template configuration files used during installation.

- **nginx.conf.template** - Web server configuration
- **pm2.config.js.template** - Process manager config
- **env.template** - Environment variables template

### `/src/`
Application source code (to be added).

- **server/** - Node.js backend application
- **admin-dashboard/** - React-based admin interface
- **setup-wizard/** - Post-installation setup interface (port 9443)

### `/.github/`
GitHub-specific configurations.

- **workflows/** - GitHub Actions for CI/CD
- **ISSUE_TEMPLATE/** - Issue and PR templates

## Installation Flow

1. User runs: `curl -o silver-latest -L https://install.silverzupport.us/latest && sh silver-latest`
2. Script downloads from S3 bucket `silversupport-install`
3. Installer fetches release tarball from `silversupport-releases`
4. Files extracted and installed to `/usr/local/silver/`
5. Services configured and started
6. Setup wizard available at `https://SERVER-IP:9443`

## Release Flow

1. Developer updates code in `/src/`
2. Run `./scripts/build-release.sh 1.0.0`
3. Creates `releases/silversupport-1.0.0.tar.gz`
4. Run `./scripts/deploy-release.sh 1.0.0`
5. Uploads to S3 and updates VERSION files
6. CloudFront cache invalidated
7. New version available at `https://releases.silverzupport.us/`

## File Locations After Installation

When installed on a server, SilverSupport uses this structure:

```
/usr/local/silver/              # Main installation
├── version                     # Installed version
├── .build-info                 # Build metadata
├── bin/                        # Executables
├── base/                       # Core application
├── whostmgr/                   # Admin panel
└── scripts/                    # Maintenance scripts

/var/silver/                    # Runtime data
├── logs/                       # Application logs
├── backups/                    # System backups
└── databases/                  # Database dumps

/etc/silver/                    # Configuration
├── silver.conf                 # Main config
├── database.conf               # DB config
└── api.conf                    # API config
```

## Version Control

- **VERSION** file in repository root contains current version
- Git tags mark release versions: `v1.0.0`, `v1.1.0`, etc.
- S3 buckets have `VERSION`, `ALPHA_VERSION`, `STAGING_VERSION` files
- Each release has manifest: `manifests/1.0.0.json`

## Getting Started

### For Users
See [Quick Start Guide](docs/installation/quickstart.md)

### For Developers
See [Building Guide](docs/development/building.md) and [Contributing Guide](docs/development/contributing.md)