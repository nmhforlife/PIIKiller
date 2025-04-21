#!/bin/bash

# Build and package the PIIKiller Electron app for release
set -e

echo "==== PIIKiller Release Build Process ===="

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

# Parse command line arguments
SIGN_APP=false
NOTARIZE=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --sign)
      SIGN_APP=true
      shift
      ;;
    --notarize)
      NOTARIZE=true
      SIGN_APP=true # Notarization requires signing
      shift
      ;;
    *)
      # Unknown option
      echo "Unknown option: $1"
      echo "Usage: ./release.sh [--sign] [--notarize]"
      exit 1
      ;;
  esac
done

# Step 1: Set up the Python environment for Presidio if not already done
echo "Step 1: Checking Python environment and Presidio..."
if [ ! -d "presidio_env" ]; then
    echo "Creating new Python environment..."
    ./setup_presidio.sh
else
    echo "Python environment already exists, skipping setup."
fi

# Step 1.5: Make sure our custom Presidio files are preserved
echo "Step 1.5: Preserving custom Presidio enhancements..."
# Check if enhanced Presidio server exists
if [ -f "presidio_server.py" ]; then
    if grep -q "monkey-patch" "presidio_server.py" || grep -q "CustomNameRecognizer" "presidio_server.py"; then
        echo "Found enhanced presidio_server.py - preserving enhancements"
        cp presidio_server.py presidio_env/lib/
    else
        echo "Using standard presidio_server.py" 
    fi
fi

# Ensure custom recognizer is included
if [ -f "presidio_custom_recognizer.py" ]; then
    echo "Found custom recognizer - preserving for packaging"
    cp presidio_custom_recognizer.py presidio_env/lib/
fi

# Step 2: Fix the Python environment for packaging
echo "Step 2: Fixing Python environment for packaging..."

# Fix for potential spaCy path issues in packaged app
# This ensures models work correctly when bundled
if [ -d "presidio_env" ]; then
    ENV_PYTHON="presidio_env/bin/python"
    if [ -f "$ENV_PYTHON" ]; then
        echo "Fixing spaCy paths for packaging..."
        $ENV_PYTHON -c "
import sys
import os
import spacy
from pathlib import Path

# Print spaCy info for debugging
print(f'spaCy version: {spacy.__version__}')
print(f'spaCy path: {spacy.__path__}')

# Get the en_core_web_lg model path
try:
    model = spacy.load('en_core_web_lg')
    model_path = model.path
    print(f'Model loaded successfully from: {model_path}')
except Exception as e:
    print(f'Error loading model: {e}')
"
    else
        echo "Python not found in the environment"
    fi
fi

# Step 3: Clean up any previous builds
echo "Step 3: Cleaning up previous builds..."
if [ -d "dist" ]; then
    rm -rf dist
fi

# Step 4: Remove .pyc files from the Python environment
# (this helps with code signing issues)
echo "Step 4: Cleaning up __pycache__ directories..."
find presidio_env -name "__pycache__" -type d -exec rm -rf {} +
find presidio_env -name "*.pyc" -delete
find presidio_env -name "*.pyo" -delete
find presidio_env -name "*.pyd" -delete

# Step 5: Install or update dependencies
echo "Step 5: Installing/updating dependencies..."
npm install

# Step 6: Build with or without signing
if [ "$SIGN_APP" = true ]; then
    echo "Step 6: Building for production with code signing..."
    
    # Check for Apple Developer ID certificate
    if ! security find-identity -v | grep -q "Developer ID Application"; then
        echo "Error: No Developer ID Application certificate found in your keychain."
        echo "Please make sure you have a valid Apple Developer certificate installed."
        exit 1
    fi
    
    # For notarization, we need Apple ID credentials
    if [ "$NOTARIZE" = true ]; then
        echo "Building with notarization enabled..."
        
        # Check if Apple ID and password are set
        if [ -z "$APPLE_ID" ] || [ -z "$APPLE_ID_PASSWORD" ]; then
            echo "Error: APPLE_ID and APPLE_ID_PASSWORD environment variables must be set for notarization."
            echo "Please set them and try again:"
            echo "  export APPLE_ID=your.email@example.com"
            echo "  export APPLE_ID_PASSWORD=your-app-specific-password"
            exit 1
        fi
        
        # Build with notarization
        npm run build-signed
    else
        # Build with signing but no notarization
        npm run build-signed
    fi
else
    echo "Step 6: Building for production (unsigned)..."
    npm run build-unsigned
    echo "This is an unsigned build. App will show 'app is damaged' warning on newer macOS versions."
    echo "For production use, run with --sign to enable code signing."
fi

echo "==== Release Build Complete ===="
echo "Your PIIKiller application has been built and packaged in the 'dist' directory."

# List the generated distribution files
echo "Generated distribution files:"
ls -la dist

# Provide instructions based on signing status
if [ "$SIGN_APP" = false ]; then
    echo ""
    echo "IMPORTANT: This build is unsigned and will trigger security warnings on macOS."
    echo "To build a properly signed version:"
    echo "1. Obtain an Apple Developer ID certificate (requires Apple Developer Program membership)"
    echo "2. Run: ./release.sh --sign"
    echo ""
    echo "For distribution to other users, notarization is also recommended:"
    echo "1. Set up environment variables: APPLE_ID and APPLE_ID_PASSWORD"
    echo "2. Run: ./release.sh --notarize"
fi 