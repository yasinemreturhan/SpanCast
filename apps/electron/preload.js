const { contextBridge, ipcRenderer } = require('electron');

// Ana süreçle güvenli köprü — renderer sayfasına minimal API sağlar.
contextBridge.exposeInMainWorld('ushare', {
  getSources: (types) => ipcRenderer.invoke('get-sources', types),
  openExternal: (url) => ipcRenderer.invoke('open-external', url),
});
