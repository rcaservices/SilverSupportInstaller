# SilverSupport Installer Update & S3 Upload Guide

This guide explains how to update the SilverSupport installer and upload it to the S3 buckets for distribution.

---

## Overview

The SilverSupport installer system uses two AWS S3 buckets:
- **silversupport-install** - Contains installer scripts (accessed via https://install.silverzupport.us/)
- **silversupport-releases** - Contains application tarballs (accessed via https://releases.silverzupport.us/)

Both buckets are served through AWS CloudFront CDN for fast global distribution.

---

## Prerequisites

Before updating and uploading the installer, ensure you have:

1. **AWS CLI installed and configured**
   ```bash
   aws --version
   aws configure
   ```

2. **Required environment variables** (optional, for CloudFront cache invalidation):
   ```bash
   export CLOUDFRONT_INSTALL_ID="your-install-distribution-id"
   export CLOUDFRONT_RELEASES_ID="your-releases-distribution-id"
   ```

3. **Git repository access** to the SilverSupport project

4. **Proper AWS credentials** with permissions for:
   - S3 bucket read/write access
   - CloudFront cache invalidation (if using CDN)

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
├── silversupport-1.0.0.tar.gz              # Application tarball
├── silversupport-1.0.0.tar.gz.sha256       # Checksum file
└── VERSION                                  # Current version pointer
```

### In silversupport-install bucket:
```
silversupport-install/
├── latest                                   # Current stable installer
├── silver-1.0.0                            # Version-specific installer
├── alpha                                    # Alpha channel (optional)
└── staging                                  # Staging channel (optional)
```

---

## Updating the Installer Script Only

If you only need to update the installer script without creating a new release:

1. **Edit the installer script**:
   ```bash
   vi installer/silver-installer.sh
   ```

2. **Upload directly to S3**:
   ```bash
   aws s3 cp installer/silver-installer.sh s3://silversupport-install/latest \
     --content-type "text/x-shellscript" \
     --cache-control "no-cache, no-store, must-revalidate"
   ```

3. **Invalidate CloudFront cache** (if using CDN):
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id $CLOUDFRONT_INSTALL_ID \
     --paths "/*"
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
aws sts get-caller-identity
aws s3 ls s3://silversupport-releases/
```

### Problem: "Tarball not found"
**Solution**: Run build script before deploy script
```bash
./scripts/build-release.sh 1.0.0
ls -lh silversupport-1.0.0.tar.gz
```

### Problem: CloudFront cache not invalidating
**Solution**: Set environment variables
```bash
export CLOUDFRONT_INSTALL_ID="E1234567890ABC"
export CLOUDFRONT_RELEASES_ID="E0987654321DEF"
```

### Problem: Installer downloads old version
**Solution**: 
1. Wait 5-10 minutes for CloudFront cache to clear
2. Or force invalidation manually:
   ```bash
   aws cloudfront create-invalidation \
     --distribution-id $CLOUDFRONT_INSTALL_ID \
     --paths "/*"
   ```

---

## Quick Reference Commands

### Complete Release Process
```bash
# 1. Build the release
./scripts/build-release.sh 1.0.0

# 2. Deploy to S3
./scripts/deploy-release.sh 1.0.0

# 3. Test download
curl -I https://install.silverzupport.us/latest

# 4. Test installation
cd /home && curl -o silver-latest -L https://install.silverzupport.us/latest && sh silver-latest
```

### Update Installer Only
```bash
# Upload installer script
aws s3 cp installer/silver-installer.sh s3://silversupport-install/latest \
  --content-type "text/x-shellscript" \
  --cache-control "no-cache, no-store, must-revalidate"

# Invalidate cache
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_INSTALL_ID \
  --paths "/*"
```

### Check Current Version
```bash
# Check VERSION file in S3
aws s3 cp s3://silversupport-releases/VERSION - | cat

# Or via URL
curl https://releases.silverzupport.us/VERSION
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