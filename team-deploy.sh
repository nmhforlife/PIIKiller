#!/bin/bash
# Team deployment script for PIIKiller
# This script builds and packages PIIKiller for distribution to your team
set -e

echo "==== PIIKiller Team Deployment Tool ===="

# Check for prerequisites
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required but not installed."
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

# Get version number
TIMESTAMP=$(date +%Y%m%d%H%M)
VERSION=$(node -e "console.log(require('./package.json').version)")
TEAM_BUILD="${VERSION}-team-${TIMESTAMP}"

# Update package version for this build
echo "Creating team build version: $TEAM_BUILD"
node -e "const fs=require('fs'); const pkg=require('./package.json'); pkg.version='${TEAM_BUILD}'; fs.writeFileSync('./package.json', JSON.stringify(pkg, null, 2));"

# Install or update dependencies
echo "Installing dependencies..."
npm install

# Set up Python environment
echo "Setting up Python environment..."
if [ ! -d "presidio_env" ]; then
    chmod +x setup_presidio.sh
    ./setup_presidio.sh
else
    echo "Using existing Python environment"
fi

# Build the application
echo "Building application for macOS..."
./release.sh --unsigned

# Create additional deployment materials
echo "Creating team deployment package..."

# Create a team-specific directory
DEPLOY_DIR="team-deploy-${TIMESTAMP}"
mkdir -p "$DEPLOY_DIR"

# Copy the DMG file
if [ -f "dist/PIIKiller-${TEAM_BUILD}.dmg" ]; then
    cp "dist/PIIKiller-${TEAM_BUILD}.dmg" "$DEPLOY_DIR/"
else
    # Find any DMG file if the specific one isn't found
    find dist -name "*.dmg" -exec cp {} "$DEPLOY_DIR/" \;
fi

# Copy documentation
cp README.md "$DEPLOY_DIR/README.md"
cp TEAM_INSTALLATION.md "$DEPLOY_DIR/INSTALLATION.md"

# Create version info file
cat > "$DEPLOY_DIR/VERSION.txt" << EOF
PIIKiller Team Build
--------------------
Version: ${TEAM_BUILD}
Build Date: $(date)
Build Host: $(hostname)

This build is intended for internal team use only.
EOF

# Create a ZIP archive of everything
echo "Creating deployment archive..."
zip -r "PIIKiller-TeamDeploy-${TIMESTAMP}.zip" "$DEPLOY_DIR"

# Restore original version
echo "Restoring original package version..."
node -e "const fs=require('fs'); const pkg=require('./package.json'); pkg.version='${VERSION}'; fs.writeFileSync('./package.json', JSON.stringify(pkg, null, 2));"

echo "==== Team Deployment Package Complete ===="
echo "Deployment package created: PIIKiller-TeamDeploy-${TIMESTAMP}.zip"
echo ""
echo "Distribution Instructions:"
echo "1. Send the ZIP file to team members"
echo "2. Instruct them to follow the INSTALLATION.md instructions"
echo "3. For any issues, refer to the troubleshooting section in the instructions" 