const { contextBridge, ipcRenderer } = require('electron');

// Expose protected methods that allow the renderer process to use
// the ipcRenderer without exposing the entire object
contextBridge.exposeInMainWorld('presidioAPI', {
  getServerStatus: () => ipcRenderer.invoke('get-server-status'),
  restartServer: () => ipcRenderer.invoke('restart-server'),
  getAppInfo: () => ipcRenderer.invoke('get-app-info'),
  onServerStatusChange: (callback) => {
    // Remove any existing listeners to avoid duplicates
    ipcRenderer.removeAllListeners('server-status');
    // Add the new listener
    ipcRenderer.on('server-status', (_, status) => callback(status));
    // Return a function to remove the listener when no longer needed
    return () => {
      ipcRenderer.removeAllListeners('server-status');
    };
  },
  onServerError: (callback) => {
    // Remove any existing listeners to avoid duplicates
    ipcRenderer.removeAllListeners('server-error');
    // Add the new listener
    ipcRenderer.on('server-error', (_, error) => callback(error));
    // Return a function to remove the listener when no longer needed
    return () => {
      ipcRenderer.removeAllListeners('server-error');
    };
  },
  onServerLog: (callback) => {
    // Remove any existing listeners to avoid duplicates
    ipcRenderer.removeAllListeners('server-log');
    // Add the new listener
    ipcRenderer.on('server-log', (_, log) => callback(log));
    // Return a function to remove the listener when no longer needed
    return () => {
      ipcRenderer.removeAllListeners('server-log');
    };
  },
  onInitLogs: (callback) => {
    // Remove any existing listeners to avoid duplicates
    ipcRenderer.removeAllListeners('init-logs');
    // Add the new listener
    ipcRenderer.on('init-logs', (_, logs) => callback(logs));
    // Return a function to remove the listener when no longer needed
    return () => {
      ipcRenderer.removeAllListeners('init-logs');
    };
  }
}); 