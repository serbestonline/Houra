// Kurulum penceresinin görsellerini çizer: electron scripts/installer-art.js <çıktı klasörü> <sürüm>
// Her dil (tr, en), hal (welcome, installing, done) ve ekran ölçeği (100, 125, 150, 200) için bir BMP yazar.
const { app, BrowserWindow, nativeImage } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const [out, version] = process.argv.slice(-2);
const W = 560, H = 360;

/** 24 bit, alttan yukarı satırlı BMP; kurulum aracı yalnız bu biçimi yükler. */
function bmp(image) {
  const { width, height } = image.getSize(), px = image.toBitmap(), row = Math.ceil(width * 3 / 4) * 4;
  const file = Buffer.alloc(54 + row * height);
  file.write('BM'); file.writeUInt32LE(file.length, 2); file.writeUInt32LE(54, 10);
  file.writeUInt32LE(40, 14); file.writeInt32LE(width, 18); file.writeInt32LE(height, 22); file.writeUInt16LE(1, 26); file.writeUInt16LE(24, 28);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) px.copy(file, 54 + (height - 1 - y) * row + x * 3, (y * width + x) * 4, (y * width + x) * 4 + 3);
  return file;
}

app.setPath('userData', path.join(out, '.profile'));
app.on('window-all-closed', () => {});   // ölçekler arasında pencere kapanınca uygulama kapanmasın
app.whenReady().then(async () => {
  fs.mkdirSync(out, { recursive: true });
  const icon = pathToFileURL(path.join(__dirname, '..', '..', 'assets', 'icon.png')).href;
  for (const scale of [100, 125, 150, 200]) {
    const size = { width: W * scale / 100, height: H * scale / 100 };
    const win = new BrowserWindow({ show: false, frame: false, useContentSize: true, ...size, webPreferences: { zoomFactor: scale / 100 } });
    for (const lang of ['tr', 'en']) for (const state of ['welcome', 'installing', 'done']) {
      await win.loadFile(path.join(__dirname, '..', 'installer', 'art.html'), { query: { lang, state, version, icon } });
      win.webContents.setZoomFactor(scale / 100);
      await new Promise((done) => setTimeout(done, 350));
      const shot = (await win.webContents.capturePage()).resize({ ...size, quality: 'best' });   // Retina ekranda iki kat büyük gelir
      fs.writeFileSync(path.join(out, `${lang}-${state}-${scale}.bmp`), bmp(nativeImage.createFromBuffer(shot.toPNG())));
    }
    win.destroy();
  }
  fs.rmSync(path.join(out, '.profile'), { recursive: true, force: true });
  app.exit(0);
});
