#!/bin/bash

# Build and package the PIIKiller Electron app for release
set -e

echo "==== PIIKiller Release Build Process ===="

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

# Check Python version
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "Detected Python version: $PYTHON_VERSION"

# Check if we need compatibility mode
if [[ $PYTHON_VERSION == 3.1[23]* ]]; then
    echo "Using compatibility mode for Python 3.12/3.13"
    COMPATIBILITY_MODE=true
    SPACY_MODEL="en_core_web_sm"
else
    COMPATIBILITY_MODE=false
    SPACY_MODEL="en_core_web_lg"
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

# Step 1: Set up or verify the Python environment
echo "Step 1: Checking Python environment and Presidio..."

# Define environment paths
VENV_DIR="$(pwd)/presidio_env"
VENV_PYTHON="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"

# Function to activate the virtual environment
activate_venv() {
    echo "Activating virtual environment..."
    # Check if the script is being sourced
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        # If sourced, we can directly activate
        source "$VENV_DIR/bin/activate"
        echo "Environment activated via source"
    else
        # If not sourced, we need to use the absolute paths
        echo "Note: Using absolute paths for Python since the script is not sourced."
        echo "For interactive use, run: source $VENV_DIR/bin/activate"
    fi
}

# Function to run Python with the virtual environment
run_python() {
    if [ -n "$VIRTUAL_ENV" ]; then
        python "$@"
    else
        "$VENV_PYTHON" "$@"
    fi
}

# Check if Python environment exists and has all required packages
if [ -d "$VENV_DIR" ]; then
    echo "Python environment exists, verifying required packages..."
    
    # Activate the virtual environment
    activate_venv
    
    # Verify that all required packages are installed
    if ! run_python -c "import flask, flask_cors, presidio_analyzer, presidio_anonymizer, spacy" 2>/dev/null; then
        echo "Environment exists but missing required packages."
        echo "Creating a fresh environment..."
        ./fix_env.sh
    else
        echo "All required packages verified."
        
        # Double-check spaCy and model installation specifically
        if ! run_python -c "import spacy; spacy.load('$SPACY_MODEL')" 2>/dev/null; then
            echo "spaCy model not properly installed. Reinstalling..."
            run_python -m spacy download $SPACY_MODEL
        else
            echo "spaCy model verified: $SPACY_MODEL"
        fi
    fi
else
    echo "Creating new Python environment..."
    ./fix_env.sh
    # Activate the newly created environment
    activate_venv
fi

# Step 1.5: Make sure our custom Presidio files are preserved
echo "Step 1.5: Preserving custom Presidio enhancements..."
mkdir -p "$VENV_DIR/lib"

# Check if enhanced Presidio server exists
if [ -f "presidio_server.py" ]; then
    if grep -q "monkey-patch\|CustomNameRecognizer" "presidio_server.py"; then
        echo "Found enhanced presidio_server.py - preserving enhancements"
        cp presidio_server.py "$VENV_DIR/lib/"
    else
        echo "Using standard presidio_server.py" 
    fi
fi

# Ensure custom recognizer is included
if [ -f "presidio_custom_recognizer.py" ]; then
    echo "Found custom recognizer - preserving for packaging"
    cp presidio_custom_recognizer.py "$VENV_DIR/lib/"
fi

# Step 2: Fix the Python environment for packaging
echo "Step 2: Fixing Python environment for packaging..."

# Fix for potential spaCy path issues in packaged app
# This ensures models work correctly when bundled
if [ -d "$VENV_DIR" ]; then
    echo "Verifying spaCy and dependencies..."
    
    # Use a more robust check with error handling
    SPACY_VERIFICATION=$(run_python -c "
try:
    import spacy
    import os
    import sys
    
    # Print spaCy info for debugging
    print(f'spaCy version: {spacy.__version__}')
    print(f'spaCy path: {spacy.__path__}')
    
    # Verify model is loadable
    try:
        model = spacy.load('$SPACY_MODEL')
        model_path = model.path
        print(f'Model $SPACY_MODEL loaded successfully from: {model_path}')
    except Exception as e:
        print(f'Error loading model: {str(e)}')
        # Try fallback model if needed
        if '$SPACY_MODEL' != 'en_core_web_sm':
            print('Trying fallback model: en_core_web_sm')
            model = spacy.load('en_core_web_sm')
            print(f'Fallback model loaded from: {model.path}')
    
    exit(0)
except Exception as e:
    print(f'Error: {str(e)}')
    exit(1)
" 2>&1)
    
    SPACY_CHECK_RESULT=$?
    echo "$SPACY_VERIFICATION"
    
    if [ $SPACY_CHECK_RESULT -ne 0 ]; then
        echo "WARNING: spaCy verification failed. Attempting to fix..."
        run_python -m spacy download $SPACY_MODEL
        
        # Check again
        if ! run_python -c "import spacy; spacy.load('$SPACY_MODEL')" 2>/dev/null; then
            echo "ERROR: Could not fix spaCy installation. Falling back to en_core_web_sm."
            SPACY_MODEL="en_core_web_sm"
            run_python -m spacy download en_core_web_sm
        fi
    fi
else
    echo "ERROR: Python environment not found. Please run './fix_env.sh' first."
    exit 1
fi

# Step 3: Clean up any previous builds
echo "Step 3: Cleaning up previous builds..."
if [ -d "dist" ]; then
    rm -rf dist
fi

# Step 4: Remove .pyc files from the Python environment
# (this helps with code signing issues)
echo "Step 4: Cleaning up __pycache__ directories..."
find "$VENV_DIR" -name "__pycache__" -type d -exec rm -rf {} +
find "$VENV_DIR" -name "*.pyc" -delete
find "$VENV_DIR" -name "*.pyo" -delete
find "$VENV_DIR" -name "*.pyd" -delete

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