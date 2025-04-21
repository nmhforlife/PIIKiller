#!/bin/bash

# Build and package the PIIKiller Electron app
set -e

echo "==== PIIKiller Build Process ===="

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

# Step 1: Set up the Python environment for Presidio
echo "Step 1: Setting up Python environment and Presidio..."
if [ ! -d "presidio_env" ]; then
    echo "Creating new Python environment..."
    ./setup_presidio.sh
else
    echo "Python environment already exists, skipping setup."
fi

# Step 2: Package the Electron app
echo "Step 2: Packaging the Electron application..."
./package.sh

echo "==== Build Complete ===="
echo "Your PIIKiller application has been built and packaged in the 'dist' directory."
echo "You can run the application by opening the executable file in the dist folder." 