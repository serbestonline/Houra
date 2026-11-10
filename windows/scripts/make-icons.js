// Sources/IconData.swift içindeki Phosphor ikonlarını src/shared/icons.js dosyasına çevirir: node scripts/make-icons.js
const fs = require('node:fs'), path = require('node:path');
const swift = fs.readFileSync(path.join(__dirname, '../../Sources/IconData.swift'), 'utf8');
const icons = [...swift.matchAll(/^\s*\("([^"]+)", "([^"]+)", "([^"]*)"\),?$/gm)].map((m) => [m[1], m[2], m[3]]);
fs.writeFileSync(path.join(__dirname, '../src/shared/icons.js'),
  `// Bu dosya üretildi (scripts/make-icons.js): Phosphor ikonları (MIT lisansı, phosphoricons.com), dolu ağırlık, 256×256.\n`
  + `// Her satır: ad, SVG çizim yolu, Türkçe/İngilizce arama kelimeleri.\n`
  + `(function (root) {\n  const ICONS = ${JSON.stringify(icons).replaceAll('],[', '],\n    [')};\n`
  + `  if (typeof module !== 'undefined' && module.exports) module.exports = ICONS; else root.ICONS = ICONS;\n})(this);\n`);
console.log(icons.length, 'ikon');
