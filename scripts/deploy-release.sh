#!/bin/bash
# scripts/deploy-release.sh
# Deploy a SilverSupport release to S3

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: ./deploy-release.sh VERSION"
  echo "Example: ./deploy-release.sh 1.0.0"
  exit 1
fi

TARBALL="silversupport-${VERSION}.tar.gz"
CHECKSUM="${TARBALL}.sha256"
BUCKET="silversupport-releases"

echo "SilverSupport Release Deployment"
echo "================================="
echo "Version: $VERSION"
echo ""

# Check if files exist
if [ ! -f "$TARBALL" ]; then
  echo "Error: $TARBALL not found"
  echo "Run ./build-release.sh $VERSION first"
  exit 1
fi

# Generate checksum if not exists
if [ ! -f "$CHECKSUM" ]; then
  echo "Generating checksum..."
  sha256sum "$TARBALL" > "$CHECKSUM"
fi

# Upload to S3 (requires AWS CLI configured)
echo "Uploading $TARBALL to S3..."
aws s3 cp "$TARBALL" "s3://${BUCKET}/${TARBALL}" --content-type "application/gzip" || {
  echo "Error: Failed to upload tarball"
  echo "Make sure AWS CLI is configured with proper credentials"
  exit 1
}

echo "Uploading checksum..."
aws s3 cp "$CHECKSUM" "s3://${BUCKET}/${CHECKSUM}" --content-type "text/plain"

# Update VERSION file
echo "Updating VERSION file..."
echo "$VERSION" > VERSION
aws s3 cp VERSION "s3://${BUCKET}/VERSION" \
  --content-type "text/plain" \
  --cache-control "no-cache, no-store, must-revalidate"

# Update installer script
echo "Updating installer script..."
if [ -f "installer/silver-installer.sh" ]; then
  aws s3 cp installer/silver-installer.sh "s3://silversupport-install/latest" \
    --content-type "text/x-shellscript" \
    --cache-control "no-cache, no-store, must-revalidate"
  
  # Also upload version-specific installer
  aws s3 cp installer/silver-installer.sh "s3://silversupport-install/silver-${VERSION}" \
    --content-type "text/x-shellscript"
fi

# Invalidate CloudFront cache (optional, requires distribution ID)
if [ ! -z "$CLOUDFRONT_INSTALL_ID" ]; then
  echo "Invalidating CloudFront cache for install..."
  aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_INSTALL_ID" \
    --paths "/*" > /dev/null
fi

if [ ! -z "$CLOUDFRONT_RELEASES_ID" ]; then
  echo "Invalidating CloudFront cache for releases..."
  aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_RELEASES_ID" \
    --paths "/*" > /dev/null
fi

echo ""
echo "✓ Release $VERSION deployed successfully!"
echo ""
echo "Download URLs:"
echo "  https://releases.silverzupport.us/${TARBALL}"
echo "  https://releases.silverzupport.us/${CHECKSUM}"
echo ""
echo "Installation URL:"
echo "  https://install.silverzupport.us/latest"
echo ""
echo "Test installation:"
echo "  cd /home && curl -o silver-latest -L https://install.silverzupport.us/latest && sh silver-latest"
echo ""