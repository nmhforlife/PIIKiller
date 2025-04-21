#!/bin/bash

# Fix script for Python environment issues
set -e  # Exit immediately if a command fails

echo "=== PIIKiller Environment Diagnostic and Repair ==="

# Check for Python 3
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

# Force rebuild the environment
echo "Removing existing Python environment..."
rm -rf presidio_env

echo "Creating fresh Python environment..."
python3 -m venv presidio_env

# Activate the environment with specific path to ensure we're using the right Python
VENV_PYTHON="$(pwd)/presidio_env/bin/python"
VENV_PIP="$(pwd)/presidio_env/bin/pip"

echo "Using Python at: $VENV_PYTHON"
echo "Using pip at: $VENV_PIP"

# Upgrade pip first to avoid any installation issues
echo "Upgrading pip..."
$VENV_PYTHON -m pip install --upgrade pip setuptools wheel

# Install packages with explicit versions
echo "Installing required packages..."
$VENV_PIP install wheel
$VENV_PIP install flask==2.3.3
$VENV_PIP install flask-cors==4.0.0
$VENV_PIP install presidio-analyzer==2.2.33
$VENV_PIP install presidio-anonymizer==2.2.33

# Install spaCy with extra safeguards
echo "Installing spaCy..."
$VENV_PIP install --no-build-isolation spacy==3.6.1

# Download the spaCy model with explicit confirmation
echo "Downloading spaCy model..."
$VENV_PYTHON -m spacy download en_core_web_lg

# Verify the installation
echo "Verifying installation..."
$VENV_PYTHON -c "import spacy; print(f'spaCy version: {spacy.__version__}')"
$VENV_PYTHON -c "import presidio_analyzer; print(f'Presidio Analyzer version: {presidio_analyzer.__version__}')"
$VENV_PYTHON -c "import presidio_anonymizer; print(f'Presidio Anonymizer version: {presidio_anonymizer.__version__}')"
$VENV_PYTHON -c "import flask; print(f'Flask version: {flask.__version__}')"

# Ensure custom Presidio files are copied
echo "Copying custom Presidio files..."
if [ -f "presidio_server.py" ]; then
    cp presidio_server.py presidio_env/lib/
    echo "Copied presidio_server.py"
fi

if [ -f "presidio_custom_recognizer.py" ]; then
    cp presidio_custom_recognizer.py presidio_env/lib/
    echo "Copied presidio_custom_recognizer.py"
fi

echo "=== Environment setup complete ==="
echo "Run './release.sh' to build the application" 