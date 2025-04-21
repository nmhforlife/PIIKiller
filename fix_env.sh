#!/bin/bash

# Fix script for Python environment issues
set -e  # Exit immediately if a command fails

echo "=== PIIKiller Environment Diagnostic and Repair ==="

# Check for Python version
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "Detected Python version: $PYTHON_VERSION"

# Python 3.13 specific handling
if [[ $PYTHON_VERSION == 3.13* ]]; then
    echo "⚠️ Python 3.13 detected - using compatibility mode"
    PYTHON_COMPATIBILITY_MODE=true
else
    PYTHON_COMPATIBILITY_MODE=false
fi

# Force rebuild the environment
echo "Removing existing Python environment..."
rm -rf presidio_env

echo "Creating fresh Python environment..."
python3 -m venv presidio_env

# Set paths for direct execution (when needed)
VENV_PYTHON="$(pwd)/presidio_env/bin/python"
VENV_PIP="$(pwd)/presidio_env/bin/pip"

echo "Using Python at: $VENV_PYTHON"
echo "Using pip at: $VENV_PIP"

# Activate the virtual environment
echo "Activating virtual environment..."
source "$(pwd)/presidio_env/bin/activate"

# Verify activation
if [ -z "$VIRTUAL_ENV" ]; then
    echo "⚠️ Virtual environment activation failed, falling back to absolute paths."
    USE_ABSOLUTE_PATHS=true
else
    echo "✅ Virtual environment activated: $VIRTUAL_ENV"
    USE_ABSOLUTE_PATHS=false
    
    # Ensure Python and pip point to the virtual environment
    PYTHON_PATH=$(which python)
    PIP_PATH=$(which pip)
    echo "Using Python from: $PYTHON_PATH"
    echo "Using pip from: $PIP_PATH"
fi

# Function to run pip commands with either activated env or absolute path
run_pip() {
    if [ "$USE_ABSOLUTE_PATHS" = true ]; then
        $VENV_PIP "$@"
    else
        pip "$@"
    fi
}

# Function to run python commands with either activated env or absolute path
run_python() {
    if [ "$USE_ABSOLUTE_PATHS" = true ]; then
        $VENV_PYTHON "$@"
    else
        python "$@"
    fi
}

# Upgrade pip first to avoid any installation issues
echo "Upgrading pip..."
run_pip install --upgrade pip setuptools wheel

# Install packages with explicit versions
echo "Installing required packages..."
run_pip install wheel
run_pip install flask==2.3.3
run_pip install flask-cors==4.0.0

# Create an environment file for persisting environment variables
ENV_FILE="$(pwd)/presidio_env/env_vars.sh"
echo "# PIIKiller environment variables" > "$ENV_FILE"
echo "export VIRTUAL_ENV=\"$VIRTUAL_ENV\"" >> "$ENV_FILE"

# For Python 3.13, we need to use a different approach for spaCy
if [ "$PYTHON_COMPATIBILITY_MODE" = true ]; then
    echo "Using Python 3.13 compatibility mode for spaCy installation"
    
    # Install prerequisites
    echo "Installing NumPy (required for spaCy)..."
    run_pip install --only-binary :all: numpy

    # Try to install a smaller, more compatible model
    echo "Installing minimal spaCy with en_core_web_sm model..."
    run_pip install --only-binary :all: spacy
    run_python -m spacy download en_core_web_sm
    
    # Use a direct wheel download approach for Presidio
    echo "Installing Presidio packages..."
    run_pip install --only-binary :all: presidio-analyzer
    run_pip install --only-binary :all: presidio-anonymizer
    
    # Set environment variable to use the smaller model
    export SPACY_MODEL="en_core_web_sm"
    echo "export SPACY_MODEL=\"en_core_web_sm\"" >> "$ENV_FILE"
else
    # Install prerequisite packages for spaCy
    echo "Installing prerequisites for spaCy..."
    run_pip install numpy==1.24.3
    run_pip install cython==0.29.36

    # Try multiple approaches to install spaCy
    echo "Attempting to install spaCy (method 1)..."
    if ! run_pip install --only-binary :all: spacy==3.6.1; then
        echo "First method failed, trying method 2..."
        if ! run_pip install --no-build-isolation spacy==3.6.1; then
            echo "Second method failed, trying older version..."
            if ! run_pip install --only-binary :all: spacy==3.5.3; then
                echo "Third method failed, trying minimal installation..."
                run_pip install --only-binary :all: spacy==3.5.0
            fi
        fi
    fi

    # Install Presidio packages after spaCy to avoid dependency conflicts
    echo "Installing Presidio packages..."
    run_pip install presidio-analyzer==2.2.33
    run_pip install presidio-anonymizer==2.2.33

    # Download the spaCy model with explicit confirmation
    echo "Downloading spaCy model..."
    run_python -m spacy download en_core_web_lg
    
    # Set environment variable to use the larger model
    export SPACY_MODEL="en_core_web_lg"
    echo "export SPACY_MODEL=\"en_core_web_lg\"" >> "$ENV_FILE"
fi

# Modify main scripts to handle different spaCy models
if [ "$PYTHON_COMPATIBILITY_MODE" = true ] && [ -f "presidio_server.py" ]; then
    echo "Updating server to use smaller spaCy model..."
    # Make a backup
    cp presidio_server.py presidio_server.py.bak
    # Replace en_core_web_lg with en_core_web_sm if found
    sed -i.bak 's/en_core_web_lg/en_core_web_sm/g' presidio_server.py
fi

# Verify the installation
echo "Verifying installation..."
echo "Testing spaCy import..."
run_python -c "import spacy; print(f'spaCy version: {spacy.__version__}')"

echo "Testing required packages..."
run_python -c "import flask; print(f'Flask version: {flask.__version__}')"

echo "Testing Presidio packages..."
if run_python -c "import presidio_analyzer, presidio_anonymizer; print('Presidio packages loaded successfully')" 2>/dev/null; then
    echo "✅ All packages verified successfully"
else
    echo "⚠️ Presidio verification failed, but continuing..."
fi

# Ensure custom Presidio files are copied
echo "Copying custom Presidio files..."
mkdir -p presidio_env/lib

if [ -f "presidio_server.py" ]; then
    cp presidio_server.py presidio_env/lib/
    echo "Copied presidio_server.py"
fi

if [ -f "presidio_custom_recognizer.py" ]; then
    cp presidio_custom_recognizer.py presidio_env/lib/
    echo "Copied presidio_custom_recognizer.py"
fi

# Create an activation helper script
ACTIVATE_HELPER="$(pwd)/activate_presidio.sh"
cat > "$ACTIVATE_HELPER" << 'EOL'
#!/bin/bash
# Helper script to activate the Presidio environment
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/presidio_env/bin/activate"
if [ -f "$SCRIPT_DIR/presidio_env/env_vars.sh" ]; then
    source "$SCRIPT_DIR/presidio_env/env_vars.sh"
    echo "✅ Presidio environment variables loaded"
fi
echo "✅ Presidio environment activated"
EOL
chmod +x "$ACTIVATE_HELPER"

echo ""
echo "=== Environment setup complete ==="
echo "Python Version: $PYTHON_VERSION"
echo "spaCy Model: $SPACY_MODEL"
echo ""
echo "Important: To activate this environment in your current shell, run either:"
echo "  source presidio_env/bin/activate"
echo "  or"
echo "  source ./activate_presidio.sh  (recommended)"
echo ""
echo "Run './release.sh' to build the application" 