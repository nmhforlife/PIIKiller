# Changelog

All notable changes to the PIIKiller project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2023-04-21

### Added
- Initial open source release
- Electron-based desktop application
- Flask server for PII processing using Microsoft Presidio
- Custom name recognizer with enhanced detection capabilities
- Support for tabular data format detection
- Detailed README and contribution guidelines
- Build scripts for development and production builds

### Features
- Detection of personal names, email addresses, phone numbers, SSNs, etc.
- Anonymization of detected PII entities
- Enhanced name detection for difficult cases
- Cross-platform support (macOS, Windows, Linux)
- Self-contained application with embedded Python environment

## [0.9.0] - 2023-04-07

### Added
- Improved tabular data detection
- Enhanced name detection patterns
- Custom name recognizer implementation
- Logging system for debugging

### Fixed
- Issue with overlapping entity detection
- Performance improvements for large documents

## [0.8.0] - 2023-03-27

### Added
- Initial application structure
- Basic PII detection using Microsoft Presidio
- Simple user interface
- Package and build scripts 