#!/bin/bash

# Cleanup script for preparing PIIKiller for open source distribution
echo "=== Cleaning up PIIKiller project for open source distribution ==="

# Remove build artifacts
echo "Removing build artifacts..."
rm -rf dist
rm -rf node_modules/.cache
rm -rf .electron-builder

# Remove Python environments and cache files
echo "Removing Python environments and cache files..."
rm -rf presidio_env
rm -rf __pycache__
find . -name "*.pyc" -delete
find . -name "*.pyo" -delete
find . -name "*.pyd" -delete
find . -name "__pycache__" -type d -exec rm -rf {} +

# Remove macOS-specific files
echo "Removing macOS-specific files..."
find . -name ".DS_Store" -delete
find . -name "._*" -delete

# Remove backup files
echo "Removing backup files..."
find . -name "*.bak" -delete
rm -rf backup

# Remove test result files
echo "Removing test result files..."
rm -f custom_recognizer_results.json
rm -f name_detection_results.json

# Remove temporary files
echo "Removing temporary files..."
rm -rf .tmp
rm -rf .temp
rm -rf .cache

# Keep essential files only
echo "Essential files for the project:"
echo "- main.js (Electron main process)"
echo "- preload.js (Preload script for Electron)"
echo "- index.html (Application UI)"
echo "- package.json & package-lock.json (Node.js dependencies)"
echo "- presidio_server.py (Flask server)"
echo "- presidio_custom_recognizer.py (Custom name recognition)"
echo "- setup_presidio.sh (Python environment setup)"
echo "- release.sh (Build script)"
echo "- build-resources/ (Application resources)"
echo "- .gitignore (Git ignore rules)"
echo "- README.md (Documentation)"
echo "- LICENSE (License file)"

# Add GitHub files if they don't exist
if [ ! -f "LICENSE" ]; then
    echo "Creating ISC license file..."
    cat > LICENSE << 'EOL'
ISC License

Copyright (c) 2023

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
EOL
fi

# Create a minimal environment for development
if [ ! -f ".github/workflows/build.yml" ]; then
    mkdir -p .github/workflows
    echo "Creating GitHub workflow for continuous integration..."
    cat > .github/workflows/build.yml << 'EOL'
name: Build PIIKiller

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [macos-latest, ubuntu-latest, windows-latest]
        
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup Node.js
      uses: actions/setup-node@v2
      with:
        node-version: '16.x'
    
    - name: Setup Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.9'
    
    - name: Install dependencies
      run: |
        npm install
        
    - name: Setup Python environment (non-Windows)
      if: runner.os != 'Windows'
      run: |
        chmod +x setup_presidio.sh
        ./setup_presidio.sh
        
    - name: Setup Python environment (Windows)
      if: runner.os == 'Windows'
      run: |
        python -m venv presidio_env
        presidio_env\Scripts\activate
        pip install presidio_analyzer presidio_anonymizer flask flask-cors
        python -m spacy download en_core_web_lg
        
    - name: Build application
      run: npm run build-unsigned
      
    - name: Upload artifacts
      uses: actions/upload-artifact@v2
      with:
        name: piikiller-${{ runner.os }}
        path: |
          dist/*.dmg
          dist/*.exe
          dist/*.AppImage
          dist/*.deb
          dist/*.zip
EOL
fi

echo "=== Cleanup complete ==="
echo "Project is now ready for GitHub. A few manual steps to consider:"
echo "1. Update the repository URL in README.md"
echo "2. Review the LICENSE file"
echo "3. Create a .github/CONTRIBUTING.md file if needed"
echo "4. Create a basic CHANGELOG.md file"
echo "5. Run 'git init' if this is a new repository" 