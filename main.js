const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');
const axios = require('axios');

let mainWindow;
let presidioProcess;
let serverRunning = false;
let healthCheckRetries = 0;
const MAX_HEALTH_CHECK_RETRIES = 10;
let logBuffer = [];
const MAX_LOG_BUFFER = 100; // Maximum number of log entries to keep

// Content of the Python server script
const PRESIDIO_SERVER_CONTENT = `
from flask import Flask, request, jsonify
from flask_cors import CORS
from presidio_analyzer import AnalyzerEngine
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import RecognizerResult, OperatorConfig

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes
analyzer = AnalyzerEngine()
anonymizer = AnonymizerEngine()

@app.route('/health', methods=['GET', 'OPTIONS'])
def health():
    if request.method == 'OPTIONS':
        return '', 204
    
    return jsonify({"status": "healthy", "service": "presidio"}), 200

@app.route('/analyze', methods=['POST', 'OPTIONS'])
def analyze():
    if request.method == 'OPTIONS':
        return '', 204
        
    data = request.get_json()
    text = data.get('text', '')
    language = data.get('language', 'en')
    entities = data.get('entities', [])

    results = analyzer.analyze(
        text=text,
        language=language,
        entities=entities
    )
    
    return jsonify([result.to_dict() for result in results])

@app.route('/anonymize', methods=['POST', 'OPTIONS'])
def anonymize():
    if request.method == 'OPTIONS':
        return '', 204
        
    data = request.get_json()
    text = data.get('text', '')
    analyzer_results = data.get('analyzerResults', [])
    operators = data.get('operators', {})
    comment_info = data.get('commentInfo', {})  # Get comment metadata

    # Convert analyzer results to RecognizerResult objects
    results = [
        RecognizerResult(
            entity_type=result['entity_type'],
            start=result['start'],
            end=result['end'],
            score=result['score']
        )
        for result in analyzer_results
    ]

    # Convert operators to OperatorConfig objects
    operator_configs = {}
    for entity_type, config in operators.items():
        # Create a copy of the config without unsupported parameters
        config_copy = config.copy()
        
        # Remove unsupported parameters
        if 'type' in config_copy:
            del config_copy['type']
        if 'newValue' in config_copy:
            del config_copy['newValue']
            
        # Set the operator name based on the entity type
        operator_name = 'replace'  # Default operator
        if entity_type == 'EMAIL_ADDRESS':
            operator_name = 'replace'
        elif entity_type == 'PHONE_NUMBER':
            operator_name = 'replace'
        elif entity_type == 'SSN':
            operator_name = 'replace'
        elif entity_type == 'CREDIT_CARD':
            operator_name = 'replace'
        elif entity_type == 'IP_ADDRESS':
            operator_name = 'replace'
        elif entity_type == 'PERSON':
            operator_name = 'replace'
        elif entity_type == 'DATE_TIME':
            operator_name = 'replace'
        elif entity_type == 'ADDRESS':
            operator_name = 'replace'
            
        # Create the operator config with the required parameters
        operator_configs[entity_type] = OperatorConfig(
            operator_name=operator_name,
            **config_copy
        )

    anonymized_result = anonymizer.anonymize(
        text=text,
        analyzer_results=results,
        operators=operator_configs
    )

    # Include comment metadata in the response
    response = {
        'text': anonymized_result.text,
        'metadata': {
            'author': comment_info.get('author', 'Unknown'),
            'authorType': comment_info.get('authorType', 'Unknown'),  # 'agent' or 'end_user'
            'timestamp': comment_info.get('timestamp', ''),
            'commentId': comment_info.get('commentId', '')
        }
    }

    return jsonify(response)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3001)
`;

// Get the correct path for resources in dev and production
function getResourcePath(relativePath) {
  // In packaged app, resources are in a different location
  if (app.isPackaged) {
    // Use process.resourcesPath for extraResources
    if (relativePath.startsWith('presidio_env')) {
      return path.join(process.resourcesPath, relativePath);
    } 
    // For the main script file, check in multiple locations
    else {
      // First check in app directory
      const appPath = path.join(app.getAppPath(), relativePath);
      if (fs.existsSync(appPath)) {
        return appPath;
      }
      
      // Then check in the root of the package
      const resourcePath = path.join(process.resourcesPath, relativePath);
      if (fs.existsSync(resourcePath)) {
        return resourcePath;
      }
      
      // Finally check in the app resources directory
      const extraFilesPath = path.join(app.getAppPath(), '..', relativePath);
      if (fs.existsSync(extraFilesPath)) {
        return extraFilesPath;
      }
      
      // Log all attempted paths for debugging
      console.log('Attempted paths:');
      console.log('- App path:', appPath);
      console.log('- Resource path:', resourcePath);
      console.log('- Extra files path:', extraFilesPath);
      
      // Default to app path
      return appPath;
    }
  } else {
    // In development, use the current directory
    return path.join(__dirname, relativePath);
  }
}

// Write the server script to disk
function writeServerScript() {
  const serverScriptPath = path.join(app.getPath('userData'), 'presidio_server.py');
  console.log('Writing server script to:', serverScriptPath);
  
  try {
    fs.writeFileSync(serverScriptPath, PRESIDIO_SERVER_CONTENT);
    
    // Make the file executable
    if (process.platform !== 'win32') {
      fs.chmodSync(serverScriptPath, '755');
    }
    
    console.log('Server script written successfully');
    return serverScriptPath;
  } catch (error) {
    console.error('Failed to write server script:', error);
    return null;
  }
}

// Function to add a log to the buffer
function addToLogBuffer(type, message) {
  // Add timestamp and create log entry
  const logEntry = {
    timestamp: new Date().toISOString(),
    type: type, // 'log', 'error', or 'status'
    message: message
  };
  
  // Add to buffer, keeping only the most recent logs
  logBuffer.push(logEntry);
  if (logBuffer.length > MAX_LOG_BUFFER) {
    logBuffer.shift(); // Remove oldest log
  }
  
  // If window exists, send immediately
  if (mainWindow && !mainWindow.isDestroyed()) {
    if (type === 'log') {
      mainWindow.webContents.send('server-log', message);
    } else if (type === 'error') {
      mainWindow.webContents.send('server-error', message);
    } else if (type === 'status') {
      mainWindow.webContents.send('server-status', message);
    }
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 700,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
    },
    icon: path.join(__dirname, 'build-resources', 'icon.png')
  });

  mainWindow.loadFile('index.html');
  
  // Open DevTools in development
  if (process.env.NODE_ENV === 'development') {
    mainWindow.webContents.openDevTools();
  }
  
  // Handle window close event
  mainWindow.on('closed', () => {
    // Dereference the window object
    mainWindow = null;
  });
  
  // Send current server status when window is ready
  mainWindow.webContents.on('did-finish-load', () => {
    // Send server status
    mainWindow.webContents.send('server-status', serverRunning ? 'running' : 'stopped');
    
    // Send buffered logs
    setTimeout(() => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('init-logs', logBuffer);
      }
    }, 500); // Small delay to ensure the renderer is ready
  });
}

function startPresidioServer() {
  try {
    // Get paths based on whether we're in development or production
    const pythonBinDir = process.platform === 'win32' ? 'Scripts' : 'bin';
    const pythonExe = process.platform === 'win32' ? 'python.exe' : 'python';
    
    // Path to Python executable in the virtual environment
    const pythonPath = getResourcePath(path.join('presidio_env', pythonBinDir, pythonExe));
    
    // For the server script, use the enhanced version if available
    let serverPath = '';
    
    if (app.isPackaged) {
      // Check for custom server in resources
      const customServerPath = path.join(
        process.resourcesPath, 
        'presidio_env',
        'lib',
        'presidio_server.py'
      );
      
      // Check for custom recognizer in resources
      const customRecognizerPath = path.join(
        process.resourcesPath, 
        'presidio_env',
        'lib',
        'presidio_custom_recognizer.py'
      );
      
      // First try to use the enhanced version if it exists
      if (fs.existsSync(customServerPath)) {
        console.log('Using enhanced Presidio server from resources');
        serverPath = customServerPath;
        
        // If enhanced server exists, make sure the custom recognizer is available too
        if (fs.existsSync(customRecognizerPath)) {
          // Copy to user data directory to ensure it's accessible
          const userDataRecognizerPath = path.join(app.getPath('userData'), 'presidio_custom_recognizer.py');
          fs.copyFileSync(customRecognizerPath, userDataRecognizerPath);
          console.log('Copied custom recognizer to:', userDataRecognizerPath);
        } else {
          console.warn('Enhanced server found but custom recognizer is missing');
        }
      } else {
        // Fall back to the basic server
        console.log('Enhanced server not found, falling back to basic server');
        serverPath = writeServerScript();
        if (!serverPath) {
          throw new Error('Failed to write server script');
        }
      }
    } else {
      // In development mode, use local files
      serverPath = path.join(__dirname, 'presidio_server.py');
      
      // Make sure custom recognizer is accessible if needed
      if (fs.existsSync(serverPath)) {
        // Check if server imports custom recognizer
        const serverContent = fs.readFileSync(serverPath, 'utf8');
        if (serverContent.includes('CustomNameRecognizer') && 
            fs.existsSync(path.join(__dirname, 'presidio_custom_recognizer.py'))) {
          console.log('Using enhanced Presidio server with custom recognizer');
        }
      }
    }
    
    console.log('Python path:', pythonPath);
    console.log('Server path:', serverPath);
    
    // Check if paths exist
    if (!fs.existsSync(pythonPath)) {
      console.error('Python not found at:', pythonPath);
      addToLogBuffer('error', 'Python not found in the expected location');
      return false;
    }
    
    if (!serverPath || !fs.existsSync(serverPath)) {
      console.error('Server script not found at:', serverPath);
      addToLogBuffer('error', 'Server script not found');
      return false;
    }
    
    // Kill any existing process
    if (presidioProcess) {
      try {
        presidioProcess.kill();
      } catch (e) {
        console.log('Error killing existing process:', e);
      }
    }
    
    console.log('Starting Presidio server...');
    addToLogBuffer('status', 'starting');
    
    // Set environment variables for the Python process
    const env = { ...process.env };
    // Add the Python path to PATH so it can find dependencies
    if (app.isPackaged) {
      const pythonDirPath = path.dirname(pythonPath);
      env.PATH = pythonDirPath + path.delimiter + env.PATH;
      
      // Also set PYTHONPATH to help find modules
      const sitePackagesPath = path.join(
        process.resourcesPath, 
        'presidio_env', 
        process.platform === 'win32' ? 'Lib/site-packages' : 'lib/python3.8/site-packages'
      );

      // Enhanced approach: Add multiple possible Python version paths
      let pythonPaths = [];
      
      // Check multiple Python version possibilities
      for (const pyVer of ['3.8', '3.9', '3.10', '3.11', '3.12']) {
        const sitePath = path.join(
          process.resourcesPath, 
          'presidio_env', 
          process.platform === 'win32' ? `Lib/site-packages` : `lib/python${pyVer}/site-packages`
        );
        if (fs.existsSync(sitePath)) {
          pythonPaths.push(sitePath);
          console.log(`Found Python site-packages: ${sitePath}`);
        }
      }
      
      // Add lib directory itself for custom modules
      const libPath = path.join(process.resourcesPath, 'presidio_env', 'lib');
      if (fs.existsSync(libPath)) {
        pythonPaths.push(libPath);
        console.log(`Found lib path: ${libPath}`);
      }
      
      // Set PYTHONPATH with all found paths
      if (pythonPaths.length > 0) {
        env.PYTHONPATH = pythonPaths.join(path.delimiter);
        console.log(`Setting PYTHONPATH to: ${env.PYTHONPATH}`);
      } else if (fs.existsSync(sitePackagesPath)) {
        env.PYTHONPATH = sitePackagesPath;
        console.log(`Setting PYTHONPATH to fallback: ${sitePackagesPath}`);
      } else {
        console.warn('Could not find any Python site-packages directories');
      }
      
      // Also set PYTHONHOME to help Python find its standard libraries
      env.PYTHONHOME = path.join(process.resourcesPath, 'presidio_env');
      console.log(`Setting PYTHONHOME to: ${env.PYTHONHOME}`);
    }
    
    // Spawn the process with the environment
    presidioProcess = spawn(pythonPath, [serverPath], { env });
    
    presidioProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`Presidio server: ${output}`);
      
      // Add to log buffer
      addToLogBuffer('log', output);
      
      // Check for server startup indicators
      if (output.includes('Running on http://') || 
          output.includes('Serving Flask app') || 
          output.includes('Debug mode')) {
        
        // Wait for server to be fully responsive
        setTimeout(() => checkServerRunning(), 1000);
      }
    });
    
    presidioProcess.stderr.on('data', (data) => {
      const errorOutput = data.toString();
      
      // Check if this is a regular Flask request log (contains HTTP method and status code)
      const isRequestLog = 
        errorOutput.includes('HTTP/1.1') && 
        (errorOutput.includes('200 -') || 
         errorOutput.includes('204 -') ||
         errorOutput.includes('[35m[1m') ||  // ANSI color codes for Flask messages
         errorOutput.includes('DEBUG in') ||
         errorOutput.includes('INFO in'));
      
      if (isRequestLog) {
        // This is a regular request log, not an error
        console.log(`Presidio server log: ${errorOutput}`);
        
        // Add to log buffer
        addToLogBuffer('log', errorOutput);
        
        // Check for server startup indicators
        if (errorOutput.includes('Running on http://') ||
            errorOutput.includes('Serving Flask app') ||
            errorOutput.includes('Debug mode')) {
          setTimeout(() => checkServerRunning(), 1000);
        }
      } else {
        // This might be an actual error
        console.error(`Presidio server error: ${errorOutput}`);
        
        // Some Flask output comes through stderr even though it's not an error
        if (errorOutput.includes('development server')) {
          setTimeout(() => checkServerRunning(), 1000);
          // Add as regular log
          addToLogBuffer('log', errorOutput);
        } else {
          // Actual error
          addToLogBuffer('error', errorOutput);
        }
      }
    });
    
    presidioProcess.on('error', (error) => {
      console.error('Failed to start Presidio server:', error);
      serverRunning = false;
      
      // Add status and error to log buffer
      addToLogBuffer('status', 'stopped');
      addToLogBuffer('error', `Failed to start server: ${error.message}`);
    });
    
    presidioProcess.on('close', (code) => {
      console.log(`Presidio server process exited with code ${code}`);
      serverRunning = false;
      
      // Add log and status to buffer
      addToLogBuffer('log', `Server process exited with code ${code}`);
      addToLogBuffer('status', 'stopped');
    });
    
    // Set a timer to check if server is up
    healthCheckRetries = 0;
    setTimeout(() => checkServerRunning(), 2000);
    
    return true;
  } catch (error) {
    console.error('Error starting Presidio server:', error);
    addToLogBuffer('error', `Error starting server: ${error.message}`);
    return false;
  }
}

function checkServerRunning() {
  // Reset retry counter if server is already running
  if (serverRunning) {
    healthCheckRetries = 0;
    return;
  }
  
  // Stop retrying after max retries
  if (healthCheckRetries >= MAX_HEALTH_CHECK_RETRIES) {
    console.log(`Max health check retries (${MAX_HEALTH_CHECK_RETRIES}) reached, giving up`);
    addToLogBuffer('error', 'Server health check failed after multiple attempts');
    return;
  }
  
  healthCheckRetries++;
  
  axios.get('http://127.0.0.1:3001/health', { timeout: 1000 })
    .then(response => {
      if (response.status === 200) {
        serverRunning = true;
        healthCheckRetries = 0;
        console.log('Server health check successful, server is running');
        addToLogBuffer('status', 'running');
        addToLogBuffer('log', 'Server health check successful, server is running');
      }
    })
    .catch(err => {
      console.log(`Server health check failed (${healthCheckRetries}/${MAX_HEALTH_CHECK_RETRIES}): ${err.message}`);
      // Try again after a short delay if we haven't reached max retries
      if (healthCheckRetries < MAX_HEALTH_CHECK_RETRIES) {
        setTimeout(() => checkServerRunning(), 1000);
      } else {
        addToLogBuffer('error', 'Server health check failed after multiple attempts');
      }
    });
}

app.whenReady().then(() => {
  createWindow();
  startPresidioServer();
  
  app.on('activate', function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', function () {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  if (presidioProcess) {
    console.log('Stopping Presidio server...');
    presidioProcess.kill();
  }
});

// IPC handlers
ipcMain.handle('get-server-status', () => {
  return serverRunning ? 'running' : 'stopped';
});

ipcMain.handle('restart-server', () => {
  console.log('Restart server requested');
  if (presidioProcess) {
    console.log('Killing existing server process');
    presidioProcess.kill();
  }
  return startPresidioServer();
});

// New handler for app info
ipcMain.handle('get-app-info', () => {
  // Get Python path
  let pythonPath = '';
  try {
    const pythonBinDir = process.platform === 'win32' ? 'Scripts' : 'bin';
    const pythonExe = process.platform === 'win32' ? 'python.exe' : 'python';
    pythonPath = getResourcePath(path.join('presidio_env', pythonBinDir, pythonExe));
  } catch (e) {
    console.error('Error getting Python path:', e);
  }
  
  return {
    appVersion: app.getVersion(),
    electronVersion: process.versions.electron,
    nodeVersion: process.versions.node,
    platform: process.platform,
    arch: process.arch,
    userDataPath: app.getPath('userData'),
    resourcesPath: process.resourcesPath,
    appPath: app.getAppPath(),
    pythonPath: pythonPath,
    isPackaged: app.isPackaged
  };
}); 