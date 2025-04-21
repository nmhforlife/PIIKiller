# PIIKiller

PIIKiller is an open source desktop application for PII (Personally Identifiable Information) detection and anonymization using Microsoft Presidio. The application helps identify and redact sensitive personal information in text.

## Features

- Detect PII entities like names, email addresses, phone numbers, SSNs, credit card numbers, etc.
- Anonymize detected PII with configurable replacement options
- Enhanced name detection with custom recognizers
- Support for tabular data formats

## Getting Started

### Prerequisites

- Node.js 16+ and npm
- Python 3.8+
- Git

### Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/PIIKiller.git
   cd PIIKiller
   ```

2. Install Node.js dependencies:
   ```
   npm install
   ```

3. Set up the Python environment (requires Python 3):
   ```
   chmod +x setup_presidio.sh
   ./setup_presidio.sh
   ```

4. Run in development mode:
   ```
   npm run dev
   ```

## Project Structure

- `main.js` - Main Electron process
- `index.html` - Application UI
- `preload.js` - Secure bridge between renderer and main processes
- `presidio_server.py` - Flask server for PII processing
- `presidio_custom_recognizer.py` - Custom name recognizer implementation
- `setup_presidio.sh` - Python environment setup script
- `release.sh` - Build and packaging script
- `build-resources/` - Icons and entitlements for the app

## Building for Distribution

The application can be built locally in several ways:

### Development Build

```
npm run dev
```

### Production Build (Unsigned)

```
./release.sh
```

This builds an unsigned application. On macOS, users will need to bypass security warnings.

### Opening Unsigned Apps on macOS

Instructions for users:
1. Control+click (right-click) on the app and select "Open"
2. When prompted with a warning, click "Open" again
3. On first launch, macOS may require going to System Preferences > Security & Privacy and clicking "Open Anyway"

## Contributing

Contributions are welcome! Here's how to contribute:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Commit: `git commit -m 'Add amazing feature'`
5. Push: `git push origin feature/amazing-feature`
6. Open a Pull Request

Please ensure your code follows existing patterns and passes all tests.

## PII Detection and Processing

The application uses Microsoft's Presidio framework for detecting and anonymizing PII:

- Basic PII detection is handled by the standard Presidio analyzer
- Enhanced name detection is implemented in `presidio_custom_recognizer.py`
- The Flask server in `presidio_server.py` provides RESTful API endpoints
- The UI communicates with the server via localhost on port 3001

The custom name recognizer improves detection for:
- Names in tabular data
- Names with various formatting patterns
- Names that might be missed by standard NLP techniques

## License

ISC

## Acknowledgements

- [Microsoft Presidio](https://github.com/microsoft/presidio) - Core PII detection and anonymization framework
- [Electron](https://www.electronjs.org/) - Desktop application framework
- [Flask](https://flask.palletsprojects.com/) - Python web framework
- [spaCy](https://spacy.io/) - NLP library

## Troubleshooting

### Environment Setup Issues

If you encounter problems with the Python environment or spaCy installation:

1. **Use the fix_env.sh script**:
   ```
   chmod +x fix_env.sh
   ./fix_env.sh
   ```
   This script will create a fresh Python environment with all required packages at specific versions.

2. **"No module named 'spacy'" or similar errors**:
   This typically happens when the Python environment is created but packages are not installed correctly.
   Run the fix script above, which uses absolute paths and verified package versions.

3. **spaCy model loading failures**:
   If you see errors related to loading the spaCy model, run:
   ```
   ./presidio_env/bin/python -m spacy download en_core_web_lg
   ```

4. **Corrupt Python environment**:
   If you continue to have issues, remove the environment completely and start fresh:
   ```
   rm -rf presidio_env
   ./setup_presidio.sh
   ```

5. **Build errors with spaCy**:
   If you encounter errors during the build process about spaCy, ensure your package versions are compatible:
   ```
   ./presidio_env/bin/pip install spacy==3.6.1 presidio-analyzer==2.2.33 presidio-anonymizer==2.2.33
   ```

### Opening Unsigned Apps on macOS

Instructions for users:
1. Control+click (right-click) on the app and select "Open"
2. When prompted with a warning, click "Open" again
3. On first launch, macOS may require going to System Preferences > Security & Privacy and clicking "Open Anyway" 