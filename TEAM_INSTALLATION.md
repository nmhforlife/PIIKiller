# PIIKiller - Team Installation Guide

This guide provides instructions for installing and running PIIKiller within our team environment. Since the application isn't signed with an Apple Developer certificate, there are a few extra steps required during installation.

## Pre-built Application Installation

If you received a pre-built DMG file:

1. **Download** the PIIKiller DMG file provided by your team lead.

2. **Mount** the DMG by double-clicking it.

3. **Drag** the PIIKiller application to your Applications folder.

4. **First Launch** (important):
   - **DO NOT** double-click the application the first time
   - Instead, right-click (or Control+click) on the app in your Applications folder
   - Select "Open" from the context menu
   - Click "Open" on the security warning dialog
   - The app should now launch successfully

5. **Future Launches**: After the first successful launch, you can open the app normally by double-clicking.

## Troubleshooting Installation Issues

### "App is damaged and can't be opened" Error

If you see a message stating the app is damaged and can't be opened:

1. Open System Preferences (or System Settings on newer macOS)
2. Go to Security & Privacy > General
3. Look for a message about PIIKiller being blocked
4. Click "Open Anyway"
5. Try launching the app again with right-click > Open

### Gatekeeper Bypass (if needed)

In some cases, more restrictive security settings might prevent the app from opening. You can temporarily disable Gatekeeper to install the app:

```bash
# In Terminal, run:
sudo spctl --master-disable

# Install and run the app once

# Re-enable Gatekeeper when finished:
sudo spctl --master-enable
```

**Note**: This requires administrator privileges and temporarily lowers your security settings. Only use this method if necessary and re-enable Gatekeeper immediately after.

## Building From Source (for developers)

If you need to build the application from source:

1. **Clone the repository**:
   ```
   git clone https://github.com/nmhforlife/PIIKiller.git
   cd PIIKiller
   ```

2. **Install dependencies**:
   ```
   npm install
   ```

3. **Set up the Python environment**:
   ```
   chmod +x setup_presidio.sh
   ./setup_presidio.sh
   ```

4. **Build the application**:
   ```
   ./release.sh
   ```

5. **Self-sign the application** (optional):
   ```
   chmod +x self-sign.sh
   ./self-sign.sh
   ```

6. **Distribute the resulting DMG** from the `dist` folder.

## Using PIIKiller

Once installed, PIIKiller will:

1. Start a local server to process PII detection
2. Provide a desktop interface for text analysis
3. Allow for configuration of which types of PII to detect and how to anonymize them

## Security Notes

- PIIKiller runs completely locally on your machine
- No data is sent to external servers
- PII detection and anonymization is performed using Microsoft's Presidio library
- The application requires Python 3.8+ and several dependencies to function

## Getting Help

If you encounter any issues with installation or usage, please contact the team administrator. 