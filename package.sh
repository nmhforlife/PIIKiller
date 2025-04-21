#!/bin/bash

# Package the Presidio Electron app

# Make sure the script exits on error
set -e

echo "=== PIIKiller Packaging Script ==="
echo "This script will package the Presidio Electron app"

# Check if presidio_env exists
if [ ! -d "presidio_env" ]; then
  echo "Error: presidio_env directory not found!"
  echo "Please run setup_presidio.sh first to create the Python environment."
  exit 1
fi

# Check if presidio_server.py exists
if [ ! -f "presidio_server.py" ]; then
  echo "Error: presidio_server.py not found!"
  exit 1
fi

# Create the assets directory if it doesn't exist
if [ ! -d "assets" ]; then
  echo "Creating assets directory..."
  mkdir -p assets
fi

# Install npm dependencies
echo "Installing npm dependencies..."
npm install

# Package for current platform (unsigned to avoid code signing issues)
echo "Building Electron app (unsigned)..."
npm run build-unsigned

echo "=== Packaging Complete ==="
echo "Your application has been packaged in the 'dist' directory." 