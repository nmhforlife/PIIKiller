#!/bin/bash
# Script to self-sign the PIIKiller app without an Apple Developer account
set -e

echo "==== PIIKiller Self-Signing Tool ===="

# Check if the app exists
if [ ! -d "dist/mac/PIIKiller.app" ]; then
    echo "Error: Application not found at dist/mac/PIIKiller.app"
    echo "Please run './release.sh' first to build the app."
    exit 1
fi

# Create a self-signed certificate if it doesn't exist
if ! security find-certificate -c "PIIKiller Self-Signed" > /dev/null 2>&1; then
    echo "Creating self-signed certificate for PIIKiller..."
    
    # Create the certificate
    security create-keychain -p "piikiller" PIIKiller.keychain
    security unlock-keychain -p "piikiller" PIIKiller.keychain
    
    # Add the keychain to the search list
    security list-keychains -d user -s PIIKiller.keychain $(security list-keychains -d user | tr -d \")
    
    # Set keychain settings
    security set-keychain-settings PIIKiller.keychain
    
    # Create certificate request
    openssl req -new -x509 -days 365 -nodes \
        -subj "/CN=PIIKiller Self-Signed/O=Your Organization/C=US" \
        -keyout PIIKiller.key -out PIIKiller.crt
    
    # Create p12 file
    openssl pkcs12 -export -in PIIKiller.crt -inkey PIIKiller.key \
        -out PIIKiller.p12 -name "PIIKiller Self-Signed" -passout pass:piikiller
    
    # Import the certificate
    security import PIIKiller.p12 -k PIIKiller.keychain -P "piikiller" -T "/usr/bin/codesign"
    
    # Set certificate trust
    security add-trusted-cert -d -r trustRoot -k PIIKiller.keychain PIIKiller.crt
    
    # Clean up
    rm PIIKiller.key PIIKiller.crt PIIKiller.p12
    
    echo "Certificate created successfully."
else
    echo "Self-signed certificate already exists."
fi

# Unlock keychain
security unlock-keychain -p "piikiller" PIIKiller.keychain

# Sign the application
echo "Signing application with self-signed certificate..."
codesign --force --deep --options runtime --sign "PIIKiller Self-Signed" "dist/mac/PIIKiller.app"

echo "Creating DMG installer..."
# Create DMG file
node_modules/.bin/electron-builder --mac dmg --config.dmg.sign=false

echo "==== Self-Signing Complete ===="
echo ""
echo "Important Notes for Team Distribution:"
echo "1. This app is signed with a self-signed certificate, not an Apple Developer certificate."
echo "2. Users will still need to bypass Gatekeeper on first launch:"
echo "   - Right-click the app and select 'Open'"
echo "   - Click 'Open' again when prompted"
echo "3. For smoother deployment, provide these instructions to your team."
echo ""
echo "The signed application is available at: dist/PIIKiller-*.dmg" 