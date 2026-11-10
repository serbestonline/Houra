// Derinlik simgesinin tepsi hali, 32×32 BGRA olarak elle çizilir: koyu yuvarlak kare üstünde beyaz çizgiler.
// Boşta iki kare ve nokta; oturumda dış kare ilerledikçe (üst ortadan, saat yönünde) çizilir; molada yalnız dış kare.
const SIZE = 32;

/** Yuvarlak karenin kenarına işaretli uzaklık (içeride eksi). */
function roundedBox(x, y, half, radius) {
  const qx = Math.abs(x) - half + radius, qy = Math.abs(y) - half + radius;
  return Math.min(Math.max(qx, qy), 0) + Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - radius;
}

const cover = (distance) => Math.max(0, Math.min(1, 0.5 - distance));   // bir piksellik kenar yumuşatma

function glyph(phase, progress) {
  const out = Buffer.alloc(SIZE * SIZE * 4);
  for (let py = 0; py < SIZE; py++) {
    for (let px = 0; px < SIZE; px++) {
      const x = px + 0.5 - SIZE / 2, y = py + 0.5 - SIZE / 2;
      const outer = cover(Math.abs(roundedBox(x, y, 10, 5.5)) - 1.2);
      let white;
      if (phase === 'idle') {
        white = Math.max(outer, 0.7 * cover(Math.abs(roundedBox(x, y, 5, 2.6)) - 1), cover(Math.hypot(x, y) - 1.9));
      } else if (phase === 'rest') {
        white = outer;
      } else {
        const turn = (Math.atan2(x, -y) / (2 * Math.PI) + 1) % 1;   // üst ortadan saat yönünde 0–1
        white = outer * (turn <= progress ? 1 : 0.3);
      }
      const background = cover(roundedBox(x, y, 15, 7));
      const v = Math.round(255 * (0.07 * (1 - white) + white)), i = (py * SIZE + px) * 4;
      out[i] = v; out[i + 1] = v; out[i + 2] = v; out[i + 3] = Math.round(255 * background);
    }
  }
  return out;
}

module.exports = { glyph, SIZE };
