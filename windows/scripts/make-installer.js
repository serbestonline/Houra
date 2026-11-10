// Houra'nın kendi kurulum penceresini derler: node scripts/make-installer.js (electron-builder'dan sonra; npm run dist ikisini de yapar).
// electron-builder'ın ürettiği sessiz kurulumu (Houra-Core) içine gömer, görselleri çizer ve dist/Houra-Setup-<sürüm>.exe yazar.
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.join(__dirname, '..'), dist = path.join(root, 'dist');
const { version } = require('../package.json');
const core = path.join(dist, `Houra-Core-${version}.exe`), art = path.join(dist, 'installer-art'), out = path.join(dist, `Houra-Setup-${version}.exe`);
const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options });
  if (result.status !== 0) { console.error(`${path.basename(command)} başarısız oldu`); process.exit(1); }
};
const folderSize = (dir) => fs.readdirSync(dir, { withFileTypes: true })
  .reduce((sum, entry) => sum + (entry.isDirectory() ? folderSize(path.join(dir, entry.name)) : fs.statSync(path.join(dir, entry.name)).size), 0);

// makensis, electron-builder'ın indirdiği NSIS'in içinden alınır; ayrıca kurulum gerekmez.
const cache = process.env.ELECTRON_BUILDER_CACHE ?? { win32: path.join(process.env.LOCALAPPDATA ?? '', 'electron-builder', 'Cache'),
  darwin: path.join(os.homedir(), 'Library', 'Caches', 'electron-builder') }[process.platform] ?? path.join(os.homedir(), '.cache', 'electron-builder');
const nsisRoot = fs.readdirSync(cache).filter((name) => /^nsis-\d/.test(name)).map((name) => path.join(cache, name))
  .flatMap((dir) => fs.readdirSync(dir).map((name) => path.join(dir, name))).find((dir) => fs.existsSync(path.join(dir, 'Include', 'nsDialogs.nsh')));
if (!nsisRoot || !fs.existsSync(core)) { console.error('Önce electron-builder çalışmalı (npm run dist).'); process.exit(1); }
const makensis = path.join(nsisRoot, ...(process.platform === 'win32' ? ['Bin', 'makensis.exe'] : [process.platform === 'darwin' ? 'mac' : 'linux', 'makensis']));

run(require('electron'), [path.join(__dirname, 'installer-art.js'), art, version]);
const posix = (file) => file.split(path.sep).join('/');
run(makensis, ['-V2', '-INPUTCHARSET', 'UTF8', `-DOUT=${posix(out)}`, `-DCORE=${posix(core)}`, `-DART=${posix(art)}`, `-DICON=${posix(path.join(dist, '.icon-ico', 'icon.ico'))}`,
  `-DTOTAL_KB=${Math.round(folderSize(path.join(dist, 'win-unpacked')) / 1024)}`, path.join(root, 'installer', 'installer.nsi')], { env: { ...process.env, NSISDIR: nsisRoot, LC_CTYPE: 'en_US.UTF-8' } });
fs.rmSync(core); fs.rmSync(core + '.blockmap', { force: true }); fs.rmSync(art, { recursive: true });
console.log('Kurulum dosyası:', out);
