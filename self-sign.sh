#!/bin/bash
# Script to self-sign the PIIKiller app without an Apple Developer account
set -e

echo "==== PIIKiller Self-Signing Tool ===="

# Check if the app exists (checking both Intel and Apple Silicon paths)
APP_PATH=""
if [ -d "dist/mac-arm64/PIIKiller.app" ]; then
    APP_PATH="dist/mac-arm64/PIIKiller.app"
    echo "Found application at $APP_PATH (Apple Silicon build)"
elif [ -d "dist/mac/PIIKiller.app" ]; then
    APP_PATH="dist/mac/PIIKiller.app"
    echo "Found application at $APP_PATH (Intel build)"
else
    echo "Error: Application not found at dist/mac-arm64/PIIKiller.app or dist/mac/PIIKiller.app"
    echo "Please run './release.sh' first to build the app."
    exit 1
fi

# Simplest approach: use ad-hoc signing which doesn't require a certificate
echo "Signing application with ad-hoc signature..."
codesign --force --deep --sign - "$APP_PATH"

echo "Creating DMG installer..."
# Create DMG file
node_modules/.bin/electron-builder --mac dmg --config.dmg.sign=false

echo "==== Self-Signing Complete ===="
echo ""
echo "Important Notes for Team Distribution:"
echo "1. This app is signed with an ad-hoc signature (no certificate)."
echo "2. Users will still need to bypass Gatekeeper on first launch:"
echo "   - Right-click the app and select 'Open'"
echo "   - Click 'Open' again when prompted"
echo "3. For smoother deployment, provide these instructions to your team."
echo ""
echo "The app for distribution is available at: dist/PIIKiller-*.dmg" 