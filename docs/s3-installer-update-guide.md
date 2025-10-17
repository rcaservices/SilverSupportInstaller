# SilverSupport Installer Update & S3 Upload Guide

This guide explains how to update the SilverSupport installer and upload it to the S3 buckets for distribution.

---

## Setup Checklist for Your Mac

Use this checklist to make sure your Mac is properly configured:

### One-Time Setup

- [ ] **Install AWS CLI**
  ```bash
  # Check if installed
  aws --version
  
  # Install if needed (macOS)
  brew install awscli
  ```

- [ ] **Configure AWS credentials**
  ```bash
  aws configure
  # Enter your AWS Access Key ID
  # Enter your AWS Secret Access Key
  # Default region: us-east-1
  # Default output: json
  ```

- [ ] **Find your CloudFront Distribution IDs**
  ```bash
  aws cloudfront list-distributions \
    --query 'DistributionList.Items[*].[Id,Origins.Items[0].DomainName,DomainName]' \
    --output table
  
  # Look for:
  # - install.silverzupport.us (install bucket)
  # - releases.silverzupport.us (releases bucket)
  ```

- [ ] **Add CloudFront IDs to ~/.zshrc**
  ```bash
  # Edit your shell config
  vi ~/.zshrc
  
  # Add these lines (replace with your actual IDs):
  export CLOUDFRONT_INSTALL_ID="E1234567890ABC"
  export CLOUDFRONT_RELEASES_ID="E0987654321XYZ"
  
  # Save and reload
  source ~/.zshrc
  ```

- [ ] **Verify environment variables are set**
  ```bash
  echo $CLOUDFRONT_INSTALL_ID
  echo $CLOUDFRONT_RELEASES_ID
  
  # Should both print IDs, not blank
  ```

- [ ] **Test AWS permissions**
  ```bash
  # Test S3 access
  aws s3 ls s3://silversupport-releases/
  aws s3 ls s3://silversupport-install/
  
  # Test CloudFront access
  aws cloudfront list-distributions > /dev/null && echo "✓ CloudFront access OK"
  ```

- [ ] **Create helper script**
  ```bash
  # Save the update-version.sh script from this guide
  # Place in: ~/bin/update-version.sh or project root
  chmod +x update-version.sh
  ```

### Before Each Deployment

- [ ] Code changes committed to git
- [ ] Version number decided (e.g., 1.5.24-alpha.6)
- [ ] Application tarball built
- [ ] Tarball tested locally (if possible)

### After Each Deployment

- [ ] Verify VERSION file updated in S3
- [ ] Verify CloudFront cache invalidated
- [ ] Wait 5-10 seconds for cache to clear
- [ ] Test that correct version downloads
- [ ] Test installation on clean server (for major changes)

---

## ⚠️ CRITICAL: CloudFront Caching Issues and Solutions

### The Problem

Your S3 buckets are served through CloudFront CDN, which **caches files** for faster global delivery. When you update a VERSION file in S3, CloudFront doesn't know immediately and continues serving the **old cached version** for hours or days.

**Symptoms:**
- You update `ALPHA_VERSION` to "1.5.24-alpha.6" in S3
- Installer still downloads version "1.5.23-alpha.5" (the old cached version)
- Wrong application version gets installed on servers
- Changes seem to "not take effect"

### The Solution: Three-Layer Protection

We use **three methods** together to ensure VERSION files are always current:

#### 1. Cache-Control Headers (Prevention)
When uploading VERSION files, tell CloudFront **never to cache them**:

```bash
--cache-control "no-cache, no-store, must-revalidate"
```

#### 2. CloudFront Invalidation (Immediate Fix)
After uploading, tell CloudFront to **immediately clear its cache**:

```bash
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/ALPHA_VERSION"
```

#### 3. Query String Cache Busting (Backup)
The installer adds a timestamp to bypass cache as a last resort:

```bash
# Instead of: ALPHA_VERSION
# Downloads: ALPHA_VERSION?t=1234567890
```

**All three methods are built into the scripts below to make this bulletproof.**

---

## Overview

The SilverSupport installer system uses two AWS S3 buckets:
- **silversupport-install** - Contains installer scripts (accessed via https://install.silverzupport.us/)
- **silversupport-releases** - Contains application tarballs (accessed via https://releases.silverzupport.us/)

Both buckets are served through AWS CloudFront CDN for fast global distribution.

### Understanding Two Version Numbers

**IMPORTANT:** There are TWO separate version numbers to track:

1. **Installer Version** (e.g., `1.0.2`) - Changes rarely, only when Ubuntu OS compatibility requires updates
2. **Application Version** (e.g., `1.5.23-alpha.6`) - Changes frequently with new features and bug fixes

The installer reads VERSION pointer files in S3 to determine which application version to download. This decoupling allows you to:
- Deploy new application versions without changing the installer
- Update the installer independently when OS changes require it
- Maintain different versions for alpha, staging, and production environments

### Version Pointer System

In the `silversupport-releases` bucket, we maintain pointer files that tell installers which version to download:

```
s3://silversupport-releases/
├── ALPHA_VERSION                         ← Text file containing "1.5.23-alpha.6"
├── STAGING_VERSION                       ← Text file containing "1.5.20"
├── LATEST_VERSION                        ← Text file containing "1.5.23"
├── silversupport-1.5.23.tar.gz          ← Actual application tarball
├── silversupport-1.5.23-alpha.6.tar.gz  ← Actual application tarball
└── silversupport-1.5.20.tar.gz          ← Actual application tarball
```

**Key Points:**
- VERSION files are small **text files** (not directories) containing just the version number
- Tarballs are named with their full version number and never change once uploaded
- The installer reads the appropriate VERSION file, then downloads that specific tarball
- All files are at the root level of the bucket

---

## Prerequisites

Before updating and uploading the installer, ensure you have:

1. **AWS CLI installed and configured**
   ```bash
   aws --version
   aws configure
   ```

2. **CRITICAL: Set up environment variables in your Mac's ~/.zshrc file**
   
   Add these lines to your `~/.zshrc` (or `~/.bash_profile` if using bash):
   ```bash
   # SilverSupport AWS Configuration
   export CLOUDFRONT_INSTALL_ID="your-install-distribution-id"
   export CLOUDFRONT_RELEASES_ID="your-releases-distribution-id"
   ```
   
   **To find your CloudFront Distribution IDs:**
   ```bash
   aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,Origins.Items[0].DomainName,DomainName]' --output table
   ```
   
   **After adding to ~/.zshrc, reload it:**
   ```bash
   source ~/.zshrc
   ```
   
   **Why this is critical:** Without these environment variables, CloudFront will cache old versions of your VERSION files, causing installers to download the wrong application version. This is the #1 source of "wrong version being installed" problems.

3. **Git repository access** to the SilverSupport project

4. **Proper AWS credentials** with permissions for:
   - S3 bucket read/write access
   - CloudFront cache invalidation (required, not optional!)

---

## Step-by-Step Process

### Step 1: Prepare Your Code

1. **Make your changes** to the application code in the `/src/` directory

2. **Test your changes** locally:
   ```bash
   npm ci
   npm run lint
   npm test
   ```

3. **Commit your changes** to git:
   ```bash
   git add .
   git commit -m "Description of your changes"
   ```

---

### Step 2: Build the Release

The build script creates a tarball of your application code.

```bash
# Run the build script with your version number
./scripts/build-release.sh 1.0.0
```

**What this does:**
- Creates a tarball named `silversupport-1.0.0.tar.gz`
- Packages all application code from `/src/`
- Includes configuration templates
- Excludes development files (.git, node_modules, etc.)
- Saves the tarball in the current directory

**Example output:**
```
Building SilverSupport release 1.0.0...
✓ Creating release tarball
✓ Release tarball created: silversupport-1.0.0.tar.gz (15MB)
```

---

### Step 3: Deploy to S3

The deployment script uploads both the application tarball and the installer script to S3.

```bash
# Run the deployment script with the same version number
./scripts/deploy-release.sh 1.0.0
```

**What this does:**

1. **Generates checksum** for the tarball:
   ```
   silversupport-1.0.0.tar.gz.sha256
   ```

2. **Uploads application tarball** to releases bucket:
   ```
   s3://silversupport-releases/silversupport-1.0.0.tar.gz
   ```

3. **Uploads checksum file**:
   ```
   s3://silversupport-releases/silversupport-1.0.0.tar.gz.sha256
   ```

4. **Updates VERSION file** in releases bucket:
   ```
   s3://silversupport-releases/VERSION
   ```

5. **Uploads installer script** to install bucket:
   ```
   s3://silversupport-install/latest                    (main installer)
   s3://silversupport-install/silver-1.0.0             (version-specific)
   ```

6. **Invalidates CloudFront cache** (if environment variables are set)

**Example output:**
```
SilverSupport Release Deployment
=================================
Version: 1.0.0

Generating checksum...
Uploading silversupport-1.0.0.tar.gz to S3...
Uploading checksum...
Updating VERSION file...
Updating installer script...
Invalidating CloudFront cache...

✓ Release 1.0.0 deployed successfully!

Download URLs:
  https://releases.silverzupport.us/silversupport-1.0.0.tar.gz
  https://releases.silverzupport.us/silversupport-1.0.0.tar.gz.sha256

Installation URL:
  https://install.silverzupport.us/latest

Test installation:
  cd /home && curl -o silver-latest -L https://install.silverzupport.us/latest && sh silver-latest
```

---

## File Locations After Upload

### In silversupport-releases bucket:
```
silversupport-releases/
├── ALPHA_VERSION                            # Text file: "1.5.23-alpha.6"
├── STAGING_VERSION                          # Text file: "1.5.20"
├── LATEST_VERSION                           # Text file: "1.5.23"
├── silversupport-1.0.0.tar.gz              # Application tarball
├── silversupport-1.5.20.tar.gz             # Application tarball
├── silversupport-1.5.23.tar.gz             # Application tarball
├── silversupport-1.5.23-alpha.6.tar.gz     # Application tarball
└── [version].tar.gz.sha256                  # Checksum files
```

### In silversupport-install bucket:
```
silversupport-install/
├── latest                                   # Current stable installer script
├── silver-1.0.0                            # Version-specific installer
├── silver-1.0.2                            # Version-specific installer
├── alpha                                    # Alpha channel installer (optional)
└── staging                                  # Staging channel installer (optional)
```

---

## Updating the Installer Script Only

If you only need to update the installer script without creating a new application release:

1. **Edit the installer script**:
   ```bash
   vi installer/silver-installer.sh
   ```

2. **Upload directly to S3 with proper cache headers**:
   ```bash
   aws s3 cp installer/silver-installer.sh s3://silversupport-install/latest \
     --content-type "text/x-shellscript" \
     --cache-control "no-cache, no-store, must-revalidate"
   ```

3. **Invalidate CloudFront cache**:
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id $CLOUDFRONT_INSTALL_ID \
     --paths "/latest"
   ```

4. **Verify the update**:
   ```bash
   # Wait a few seconds, then test download
   sleep 5
   curl -I https://install.silverzupport.us/latest
   # Check the Last-Modified date
   ```

---

## Managing Application Versions from Your Mac

You can manage application versions entirely from your Mac using AWS CLI, without modifying the installer at all.

### Quick Version Update (Most Common)

When you have a new application tarball and want to deploy it:

```bash
# 1. Upload the new tarball
aws s3 cp silversupport-1.5.24-alpha.6.tar.gz \
  s3://silversupport-releases/silversupport-1.5.24-alpha.6.tar.gz \
  --content-type "application/gzip"

# 2. Upload checksum
sha256sum silversupport-1.5.24-alpha.6.tar.gz > silversupport-1.5.24-alpha.6.tar.gz.sha256
aws s3 cp silversupport-1.5.24-alpha.6.tar.gz.sha256 \
  s3://silversupport-releases/silversupport-1.5.24-alpha.6.tar.gz.sha256 \
  --content-type "text/plain"

# 3. Update VERSION pointer (with cache-busting)
echo "1.5.24-alpha.6" | aws s3 cp - s3://silversupport-releases/ALPHA_VERSION \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate"

# 4. Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/ALPHA_VERSION"

# 5. Verify
sleep 5
curl "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)"
# Should show: 1.5.24-alpha.6
```

### Helper Script: update-version.sh

Save this script on your Mac to make version updates easier:

```bash
#!/bin/bash
# update-version.sh - Update SilverSupport version pointers with cache invalidation
# Usage: ./update-version.sh <alpha|staging|production> <version>

ENVIRONMENT=$1
VERSION=$2

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

if [ -z "$ENVIRONMENT" ] || [ -z "$VERSION" ]; then
    echo -e "${RED}Usage: $0 <alpha|staging|production> <version>${NC}"
    echo "Example: $0 alpha 1.5.24-alpha.6"
    exit 1
fi

# Determine which VERSION file to update
case $ENVIRONMENT in
    alpha)
        FILE="ALPHA_VERSION"
        ;;
    staging)
        FILE="STAGING_VERSION"
        ;;
    production)
        FILE="LATEST_VERSION"
        ;;
    *)
        echo -e "${RED}Invalid environment. Use: alpha, staging, or production${NC}"
        exit 1
        ;;
esac

echo -e "${CYAN}Updating $ENVIRONMENT to version $VERSION${NC}"
echo ""

# Check if CloudFront ID is set
if [ -z "$CLOUDFRONT_RELEASES_ID" ]; then
    echo -e "${YELLOW}⚠ WARNING: CLOUDFRONT_RELEASES_ID not set!${NC}"
    echo -e "${YELLOW}Cache invalidation will be skipped.${NC}"
    echo -e "${YELLOW}Add to ~/.zshrc: export CLOUDFRONT_RELEASES_ID='your-id'${NC}"
    echo ""
    read -p "Continue without cache invalidation? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Step 1: Upload VERSION file with no-cache headers
echo -e "${CYAN}Step 1: Uploading $FILE to S3...${NC}"
echo "$VERSION" | aws s3 cp - s3://silversupport-releases/$FILE \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --metadata-directive REPLACE

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to upload version file${NC}"
    exit 1
fi
echo -e "${GREEN}✓ File uploaded to S3${NC}"
echo ""

# Step 2: Invalidate CloudFront cache
if [ ! -z "$CLOUDFRONT_RELEASES_ID" ]; then
    echo -e "${CYAN}Step 2: Invalidating CloudFront cache...${NC}"
    INVALIDATION_OUTPUT=$(aws cloudfront create-invalidation \
      --distribution-id "$CLOUDFRONT_RELEASES_ID" \
      --paths "/$FILE" 2>&1)
    
    if [ $? -eq 0 ]; then
        INVALIDATION_ID=$(echo "$INVALIDATION_OUTPUT" | grep -o '"Id": "[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}✓ CloudFront cache invalidated${NC}"
        echo -e "${CYAN}  Invalidation ID: $INVALIDATION_ID${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: CloudFront invalidation failed${NC}"
        echo -e "${YELLOW}  File is updated in S3, but cache may take 5-15 minutes to clear${NC}"
    fi
else
    echo -e "${YELLOW}Step 2: Skipped (no CLOUDFRONT_RELEASES_ID set)${NC}"
fi
echo ""

# Step 3: Verify the update
echo -e "${CYAN}Step 3: Verifying update...${NC}"
echo "Waiting 5 seconds for cache to clear..."
sleep 5

# Try with cache-busting query string
CURRENT=$(curl -s "https://releases.silverzupport.us/$FILE?t=$(date +%s)")

echo -e "${CYAN}Expected version: $VERSION${NC}"
echo -e "${CYAN}Current version:  $CURRENT${NC}"
echo ""

if [ "$CURRENT" = "$VERSION" ]; then
    echo -e "${GREEN}✓✓✓ Verification successful! ✓✓✓${NC}"
    echo -e "${GREEN}Installers will now download version: $VERSION${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Version mismatch detected${NC}"
    echo -e "${YELLOW}This may resolve in a few minutes as the cache clears globally.${NC}"
    echo -e "${YELLOW}Try verifying again in 2-3 minutes.${NC}"
fi
echo ""

# Show test command
echo -e "${CYAN}To test installation with this version:${NC}"
echo "  cd /home && curl -o silver-test -L https://install.silverzupport.us/latest && sudo sh silver-test"
```

**Make it executable:**
```bash
chmod +x update-version.sh
```

**Usage examples:**
```bash
# Update alpha environment
./update-version.sh alpha 1.5.24-alpha.6

# Update staging environment  
./update-version.sh staging 1.5.20

# Update production environment
./update-version.sh production 1.5.23
```

### Check Current Versions

```bash
# See what version each environment is using
echo "Alpha:      $(curl -s https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s))"
echo "Staging:    $(curl -s https://releases.silverzupport.us/STAGING_VERSION?t=$(date +%s))"
echo "Production: $(curl -s https://releases.silverzupport.us/LATEST_VERSION?t=$(date +%s))"
```

Or using AWS CLI:
```bash
# Check all environments at once
for env in ALPHA_VERSION STAGING_VERSION LATEST_VERSION; do
  echo -n "$env: "
  aws s3 cp s3://silversupport-releases/$env - | cat
done
```

### List All Available Versions

```bash
# See all tarballs available in S3
aws s3 ls s3://silversupport-releases/ | grep "\.tar\.gz$" | grep -v "\.sha256"
```

### Promote a Version Between Environments

```bash
# Alpha tested successfully? Promote to staging
ALPHA_VERSION=$(curl -s "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)")
echo "Promoting $ALPHA_VERSION from alpha to staging"

echo "$ALPHA_VERSION" | aws s3 cp - s3://silversupport-releases/STAGING_VERSION \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate"

aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/STAGING_VERSION"
```

### Rollback to Previous Version

```bash
# Emergency rollback - alpha has a critical bug
echo "1.5.23-alpha.5" | aws s3 cp - s3://silversupport-releases/ALPHA_VERSION \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate"

aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/ALPHA_VERSION"
```

---

## Version Management

### Version File Format
The `VERSION` file contains just the version number:
```
1.0.0
```

### Version Naming Convention
- **Format**: `MAJOR.MINOR.PATCH`
- **Example**: `1.0.0`
- **Alpha releases**: `1.0.0-alpha.1`
- **Beta releases**: `1.0.0-beta.1`

---

## Testing Your Deployment

### 1. Test Download URLs
```bash
# Test tarball download
curl -I https://releases.silverzupport.us/silversupport-1.0.0.tar.gz

# Test installer download
curl -I https://install.silverzupport.us/latest

# Test checksum download
curl https://releases.silverzupport.us/silversupport-1.0.0.tar.gz.sha256
```

### 2. Test Installation
```bash
# Run installation on a test server
cd /home
curl -o silver-latest -L https://install.silverzupport.us/latest
sh silver-latest
```

### 3. Verify Version
After installation completes:
```bash
cat /usr/local/silver/version
```

---

## Troubleshooting

### Problem: "Failed to upload tarball"
**Solution**: Check AWS credentials and permissions
```bash
# Verify AWS credentials are working
aws sts get-caller-identity

# Check if you can access the bucket
aws s3 ls s3://silversupport-releases/

# Check your permissions
aws s3api get-bucket-acl --bucket silversupport-releases
```

### Problem: "Tarball not found"
**Solution**: Run build script before deploy script
```bash
./scripts/build-release.sh 1.0.0
ls -lh silversupport-1.0.0.tar.gz
```

### Problem: CloudFront cache not invalidating
**Solution 1**: Check environment variables are set
```bash
echo $CLOUDFRONT_INSTALL_ID
echo $CLOUDFRONT_RELEASES_ID

# If empty, add to ~/.zshrc and reload
source ~/.zshrc
```

**Solution 2**: Verify you have CloudFront permissions
```bash
# Test if you can create invalidations
aws cloudfront list-distributions

# If this fails, you need CloudFront permissions added to your IAM user
```

### Problem: Installer downloads wrong/old version
This is the **most common problem** - caused by CloudFront caching.

**Solution 1**: Check if VERSION file was updated
```bash
# Check S3 directly (bypasses CloudFront)
aws s3 cp s3://silversupport-releases/ALPHA_VERSION - | cat

# Check via CloudFront (may be cached)
curl https://releases.silverzupport.us/ALPHA_VERSION

# If different, caching is the issue
```

**Solution 2**: Use cache-busting query string
```bash
# This bypasses cache
curl "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)"
```

**Solution 3**: Wait for cache to expire (5-15 minutes)**
```bash
# Or force invalidation
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/ALPHA_VERSION" "/STAGING_VERSION" "/LATEST_VERSION"
```

**Solution 4**: Check if cache-control headers were set correctly
```bash
# View metadata of the VERSION file
aws s3api head-object \
  --bucket silversupport-releases \
  --key ALPHA_VERSION

# Look for: "CacheControl": "no-cache, no-store, must-revalidate"
# If missing, re-upload with correct headers
```

**Complete diagnostic script:**
```bash
#!/bin/bash
# diagnose-version.sh - Check why wrong version is being installed

ENV=${1:-ALPHA_VERSION}

echo "=== Diagnosing $ENV ==="
echo ""

echo "1. Version in S3 (source of truth):"
aws s3 cp s3://silversupport-releases/$ENV - | cat
echo ""

echo "2. Version via CloudFront (may be cached):"
curl -s https://releases.silverzupport.us/$ENV
echo ""

echo "3. Version via CloudFront with cache-bust:"
curl -s "https://releases.silverzupport.us/$ENV?t=$(date +%s)"
echo ""

echo "4. Cache-Control header on S3 object:"
aws s3api head-object --bucket silversupport-releases --key $ENV \
  --query 'CacheControl' --output text
echo ""

echo "5. Last modified date:"
aws s3api head-object --bucket silversupport-releases --key $ENV \
  --query 'LastModified' --output text
echo ""

echo "=== Recommendation ==="
echo "If versions differ, run:"
echo "  aws cloudfront create-invalidation \\"
echo "    --distribution-id \$CLOUDFRONT_RELEASES_ID \\"
echo "    --paths '/$ENV'"
```

### Problem: "Access Denied" when uploading
**Solution**: Check bucket policy and IAM permissions
```bash
# Your IAM user needs these permissions:
# - s3:PutObject
# - s3:PutObjectAcl  
# - cloudfront:CreateInvalidation
# - cloudfront:GetInvalidation

# Check current user
aws sts get-caller-identity

# Test upload permission
echo "test" | aws s3 cp - s3://silversupport-releases/test.txt
aws s3 rm s3://silversupport-releases/test.txt
```

### Problem: Downloads work but installation fails
**Solution**: Check checksum file exists
```bash
# Verify both tarball and checksum exist
aws s3 ls s3://silversupport-releases/ | grep "1.5.24-alpha.6"

# Should show both:
# silversupport-1.5.24-alpha.6.tar.gz
# silversupport-1.5.24-alpha.6.tar.gz.sha256

# If checksum missing, create and upload it
sha256sum silversupport-1.5.24-alpha.6.tar.gz > silversupport-1.5.24-alpha.6.tar.gz.sha256
aws s3 cp silversupport-1.5.24-alpha.6.tar.gz.sha256 \
  s3://silversupport-releases/silversupport-1.5.24-alpha.6.tar.gz.sha256
```

---

## Quick Reference Commands

### Complete Release Process
```bash
# 1. Build the release
./scripts/build-release.sh 1.5.24-alpha.6

# 2. Upload tarball
aws s3 cp silversupport-1.5.24-alpha.6.tar.gz \
  s3://silversupport-releases/silversupport-1.5.24-alpha.6.tar.gz \
  --content-type "application/gzip"

# 3. Upload checksum
sha256sum silversupport-1.5.24-alpha.6.tar.gz > silversupport-1.5.24-alpha.6.tar.gz.sha256
aws s3 cp silversupport-1.5.24-alpha.6.tar.gz.sha256 \
  s3://silversupport-releases/silversupport-1.5.24-alpha.6.tar.gz.sha256

# 4. Update VERSION pointer
echo "1.5.24-alpha.6" | aws s3 cp - s3://silversupport-releases/ALPHA_VERSION \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate"

# 5. Invalidate cache (CRITICAL!)
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/ALPHA_VERSION"

# 6. Verify (wait 5 seconds first)
sleep 5
curl "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)"
```

### Update Application Version Only (Most Common)
```bash
# Using the helper script (recommended)
./update-version.sh alpha 1.5.24-alpha.6

# Or manually
echo "1.5.24-alpha.6" | aws s3 cp - s3://silversupport-releases/ALPHA_VERSION \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate"

aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/ALPHA_VERSION"
```

### Update Installer Only
```bash
# Upload new installer script
aws s3 cp installer/silver-installer.sh s3://silversupport-install/latest \
  --content-type "text/x-shellscript" \
  --cache-control "no-cache, no-store, must-revalidate"

# Invalidate cache
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_INSTALL_ID \
  --paths "/latest"
```

### Check Current Versions
```bash
# Check all environment versions (with cache-busting)
echo "Alpha:      $(curl -s "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)")"
echo "Staging:    $(curl -s "https://releases.silverzupport.us/STAGING_VERSION?t=$(date +%s)")"
echo "Production: $(curl -s "https://releases.silverzupport.us/LATEST_VERSION?t=$(date +%s)")"

# Or via AWS CLI (direct from S3, no cache)
aws s3 cp s3://silversupport-releases/ALPHA_VERSION - | cat
aws s3 cp s3://silversupport-releases/STAGING_VERSION - | cat
aws s3 cp s3://silversupport-releases/LATEST_VERSION - | cat
```

### List Available Versions
```bash
# See all application tarballs
aws s3 ls s3://silversupport-releases/ | grep "\.tar\.gz$" | grep -v "\.sha256"

# See just alpha versions
aws s3 ls s3://silversupport-releases/ | grep "alpha.*\.tar\.gz$"
```

### Emergency Rollback
```bash
# Rollback alpha to previous version
echo "1.5.23-alpha.5" | aws s3 cp - s3://silversupport-releases/ALPHA_VERSION \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate"

aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_RELEASES_ID \
  --paths "/ALPHA_VERSION"

# Verify rollback
sleep 5
curl "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)"
```

### Test Installation
```bash
# Test on a clean server
cd /home
curl -o silver-test -L https://install.silverzupport.us/latest
sudo sh silver-test

# After installation, verify version
cat /usr/local/silver/version
```

### Cache Diagnostics
```bash
# Check if cache is causing issues
# Compare S3 vs CloudFront
echo "S3 version:"
aws s3 cp s3://silversupport-releases/ALPHA_VERSION - | cat

echo "CloudFront version:"
curl -s https://releases.silverzupport.us/ALPHA_VERSION

echo "CloudFront with cache-bust:"
curl -s "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)"

# If all three differ, you have a caching problem!
```

---

## Security Best Practices

1. **Use IAM roles** instead of access keys when possible
2. **Set minimal permissions** on S3 buckets:
   - Public read for releases
   - Private write, authenticated only
3. **Use HTTPS** for all downloads (enforced by CloudFront)
4. **Verify checksums** in installer script before extraction
5. **Keep AWS credentials secure** - never commit to git

---

## Related Documentation

- [Building Guide](docs/development/building.md)
- [S3 Infrastructure Setup](docs/deployment/s3-setup.md)
- [CloudFront Configuration](docs/deployment/cloudfront.md)
- [PROJECT_AGREEMENT.md](PROJECT_AGREEMENT.md) - Development guidelines

---

## Support

For questions or issues:
1. Check the troubleshooting section above
2. Review AWS CloudWatch logs
3. Check S3 bucket permissions
4. Verify CloudFront distribution settings

---

*Last Updated: October 2025*

---

## Appendix: Common Workflows

### Workflow 1: Deploy New Alpha Version

```bash
# 1. Build locally
cd ~/projects/silversupport
./scripts/build-release.sh 1.5.24-alpha.6

# 2. Upload to S3
aws s3 cp silversupport-1.5.24-alpha.6.tar.gz \
  s3://silversupport-releases/silversupport-1.5.24-alpha.6.tar.gz

# 3. Update version pointer
./update-version.sh alpha 1.5.24-alpha.6

# 4. Test on server
ssh user@alpha-server.com
cd /home && curl -o test -L https://install.silverzupport.us/latest && sudo sh test
```

### Workflow 2: Promote Alpha to Staging

```bash
# 1. Check current alpha version
ALPHA_VER=$(curl -s "https://releases.silverzupport.us/ALPHA_VERSION?t=$(date +%s)")
echo "Current alpha version: $ALPHA_VER"

# 2. Verify this version exists
aws s3 ls s3://silversupport-releases/ | grep "$ALPHA_VER"

# 3. Promote to staging
./update-version.sh staging $ALPHA_VER

# 4. Announce to team
echo "Staging updated to $ALPHA_VER"
```

### Workflow 3: Emergency Production Rollback

```bash
# 1. Check what production currently has
CURRENT=$(curl -s "https://releases.silverzupport.us/LATEST_VERSION?t=$(date +%s)")
echo "Current production: $CURRENT"

# 2. Decide rollback version (previous stable)
ROLLBACK="1.5.22"

# 3. Verify rollback version exists
aws s3 ls s3://silversupport-releases/ | grep "$ROLLBACK"

# 4. Execute rollback
./update-version.sh production $ROLLBACK

# 5. Verify immediately
sleep 10
curl "https://releases.silverzupport.us/LATEST_VERSION?t=$(date +%s)"

# 6. Notify team
echo "PRODUCTION ROLLED BACK: $CURRENT → $ROLLBACK"
```

### Workflow 4: Fix Installer Bug (No App Changes)

```bash
# 1. Edit installer
vi installer/silver-installer.sh

# 2. Test locally if possible
./scripts/test-installer.sh

# 3. Upload new installer
aws s3 cp installer/silver-installer.sh \
  s3://silversupport-install/latest \
  --content-type "text/x-shellscript" \
  --cache-control "no-cache, no-store, must-revalidate"

# 4. Invalidate cache
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_INSTALL_ID \
  --paths "/latest"

# 5. Test download
sleep 5
curl -L https://install.silverzupport.us/latest > test-installer.sh
head -20 test-installer.sh  # Verify it's the new version
```

---

## Key Reminders

🔴 **ALWAYS set CloudFront environment variables in ~/.zshrc** - Without these, cache invalidation won't work and wrong versions will be installed.

🔴 **ALWAYS invalidate CloudFront cache** after updating VERSION files - Cache can persist for hours/days otherwise.

🔴 **ALWAYS use `--cache-control "no-cache"` headers** when uploading VERSION files - This prevents future cache issues.

🔴 **NEVER update installer script when you just need to change app version** - Use VERSION pointer files instead.

🔴 **ALWAYS wait 5-10 seconds after cache invalidation** before testing - CloudFront needs time to propagate changes globally.

🟡 **Test on a clean server** after major changes - Especially for installer script updates.

🟢 **Keep old tarballs in S3** - They're cheap to store and enable easy rollbacks.

🟢 **Use the helper script** (`update-version.sh`) - It handles all the cache-busting automatically.

---

*Last Updated: October 2025*