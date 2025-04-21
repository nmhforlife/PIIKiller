#!/bin/bash
# Script to create a distributable package for PIIKiller without an Apple Developer account
set -e

echo "==== PIIKiller Team Distribution Tool ===="

# Check if dist directory exists
if [ ! -d "dist" ]; then
    echo "Error: No 'dist' directory found."
    echo "Please run './release.sh' first to build the app."
    exit 1
fi

# Build the DMG directly without modifying the app bundle
echo "Creating DMG installer..."
node_modules/.bin/electron-builder --mac dmg --config.dmg.sign=false

# Find the generated DMG
DMG_PATH=$(find dist -name "*.dmg" -type f -depth 1 | head -n 1)

if [ -z "$DMG_PATH" ]; then
    echo "Error: Could not find generated DMG in dist folder."
    exit 1
fi

echo "DMG created at: $DMG_PATH"

echo "==== Team Distribution Package Complete ===="
echo ""
echo "Important Notes for Team Distribution:"
echo "1. This app will require manual approval on first launch."
echo "2. Users will need to bypass Gatekeeper on first launch:"
echo "   - Right-click the app and select 'Open'"
echo "   - Click 'Open' again when prompted"
echo "3. For smoother deployment, provide the TEAM_INSTALLATION.md guide."
echo ""
echo "The app for distribution is available at: $DMG_PATH" 