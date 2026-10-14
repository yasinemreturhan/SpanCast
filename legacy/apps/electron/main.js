const { app, BrowserWindow, ipcMain, desktopCapturer, session, shell } = require('electron');
const path = require('path');

// macOS'ta ekran kaydı izni gereklidir; uygulama başlamadan önce kontrol edilmez
// çünkü izin isteği ancak desktopCapturer.getSources() çağrısında tetiklenir.

function createWindow() {
  const win = new BrowserWindow({
    width: 640,
    height: 620,
    resizable: false,
    title: 'UniversalShare',
    backgroundColor: '#0f1117',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      // Self-signed sertifikalar için webSecurity devre dışı bırakılmaz;
      // bunun yerine certificate-error olayı kullanılır.
    },
  });

  win.loadFile('index.html');
  win.setMenuBarVisibility(false);

  // Ushare sunucuları self-signed sertifika kullanır; parmak izi kontrolü
  // renderer tarafında yapılır, burada bağlantıya izin ver.
  win.webContents.on('certificate-error', (event, _url, _err, _cert, callback) => {
    event.preventDefault();
    callback(true);
  });
}

// Ekran/pencere kaynaklarını listele — renderer'dan çağrılır.
ipcMain.handle('get-sources', async (_event, types) => {
  const sources = await desktopCapturer.getSources({
    types: types ?? ['screen', 'window'],
    thumbnailSize: { width: 320, height: 180 },
  });
  return sources.map(s => ({
    id: s.id,
    name: s.name,
    thumbnail: s.thumbnail.toDataURL(),
  }));
});

// Harici URL'leri varsayılan tarayıcıda aç.
ipcMain.handle('open-external', (_event, url) => shell.openExternal(url));

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
