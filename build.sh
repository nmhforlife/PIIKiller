#!/bin/bash

# Ensure we exit on any error
set -e

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Presidio Desktop build process...${NC}"

# Check required tools
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Python 3 is required but not installed.${NC}"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo -e "${RED}npm is required but not installed.${NC}"
    exit 1
fi

# Install Python dependencies if not already installed
echo -e "${GREEN}Installing Python dependencies...${NC}"
python3 -m pip install presidio-analyzer presidio-anonymizer flask flask-cors

# Install spaCy model if not already installed
echo -e "${GREEN}Installing spaCy model...${NC}"
python3 -m pip install spacy
python3 -m spacy download en_core_web_lg

# Install NPM dependencies
echo -e "${GREEN}Installing NPM dependencies...${NC}"
npm install

# Build the app
echo -e "${GREEN}Building macOS app...${NC}"
npm run build:mac

echo -e "${GREEN}==== Build completed successfully! ====${NC}"
echo -e "${GREEN}Package can be found in the dist/ directory.${NC}" 