# Contributing to PIIKiller

Thank you for your interest in contributing to PIIKiller! This document provides guidelines and instructions for contributing to this project.

## Code of Conduct

Please be respectful and considerate of others when contributing to this project. We expect all contributors to adhere to professional standards of communication and collaboration.

## How to Contribute

There are many ways to contribute to PIIKiller:

1. **Reporting Bugs**: If you find a bug, please create an issue with a clear description of the problem, steps to reproduce, and your environment details.

2. **Suggesting Enhancements**: Have an idea for a new feature or improvement? Open an issue describing your suggestion and why it would be valuable.

3. **Code Contributions**: If you'd like to contribute code, please follow the process below.

## Development Process

1. **Fork the Repository**: Create your own fork of the repository on GitHub.

2. **Create a Branch**: Create a feature branch for your contribution:
   ```
   git checkout -b feature/your-feature-name
   ```

3. **Make Your Changes**: Write your code and tests. Please follow the coding style and patterns already in the project.

4. **Test Your Changes**: Ensure your changes do not break existing functionality.

5. **Commit Your Changes**: Use clear, descriptive commit messages:
   ```
   git commit -m "Add feature: your feature description"
   ```

6. **Push to Your Fork**: Push your changes to your fork on GitHub:
   ```
   git push origin feature/your-feature-name
   ```

7. **Submit a Pull Request**: Create a pull request from your fork to the main repository.

## Development Environment Setup

1. Clone your fork:
   ```
   git clone https://github.com/nmhforlife/PIIKiller.git
   cd PIIKiller
   ```

2. Install dependencies:
   ```
   npm install
   ```

3. Set up the Python environment:
   ```
   chmod +x setup_presidio.sh
   ./setup_presidio.sh
   ```

4. Run in development mode:
   ```
   npm run dev
   ```

## Project Structure

- `main.js`: Electron main process
- `index.html`: Application UI
- `preload.js`: Preload script for Electron renderer
- `presidio_server.py`: Flask server for PII processing
- `presidio_custom_recognizer.py`: Custom name recognizer
- `setup_presidio.sh`: Python environment setup script

## Key Areas for Contribution

We particularly welcome contributions in the following areas:

1. **Improved PII Detection**: Enhancements to the custom recognizer for better accuracy
2. **Performance Optimization**: Making the application faster and more efficient
3. **UI Improvements**: Making the interface more user-friendly
4. **Documentation**: Improving the documentation for users and developers
5. **Testing**: Adding tests and improving test coverage

## Pull Request Guidelines

- Follow the coding style of the project
- Include tests for new features or bug fixes
- Update documentation as needed
- Keep pull requests focused on a single change
- Link to any relevant issues

## Code Review Process

All submissions will be reviewed by project maintainers. We may suggest changes, improvements, or alternative approaches during the review process.

## License

By contributing to PIIKiller, you agree that your contributions will be licensed under the project's ISC license.

Thank you for contributing to PIIKiller! 