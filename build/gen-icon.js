// Generates Digital Pat's icon — pink gradient with a white kitten-face glyph.
// Pure-JS PNG encoder, no deps. Run with: node build/gen-icon.js
// Then `iconutil -c icns -o build/icon.icns build/icon.iconset`.

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const cfg = JSON.parse(fs.readFileSync(path.resolve(__dirname, '..', 'app.config.json'), 'utf8'));
const [GRAD_TOP, GRAD_BOT] = cfg.iconGradient;

function hex(c) { return [parseInt(c.slice(1,3),16), parseInt(c.slice(3,5),16), parseInt(c.slice(5,7),16)]; }
const TOP_RGB = hex(GRAD_TOP);
const BOT_RGB = hex(GRAD_BOT);

function makePng(width, height, pixelFn) {
  const ch = 4;
  const row = width * ch;
  const raw = Buffer.alloc((row + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (row + 1)] = 0;
    for (let x = 0; x < width; x++) {
      const [r, g, b, a] = pixelFn(x, y);
      const o = y * (row + 1) + 1 + x * ch;
      raw[o] = r; raw[o+1] = g; raw[o+2] = b; raw[o+3] = a;
    }
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  const crcTable = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
    return t;
  })();
  const crc32 = (buf) => { let c = 0xffffffff; for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
    const t = Buffer.from(type, 'ascii');
    const c = Buffer.alloc(4); c.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
    return Buffer.concat([len, t, data, c]);
  };
  const sig = Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

function squircleAlpha(x, y, size, n = 5) {
  const cx = (x - size/2 + 0.5) / (size/2);
  const cy = (y - size/2 + 0.5) / (size/2);
  const r = Math.pow(Math.abs(cx), n) + Math.pow(Math.abs(cy), n);
  if (r < 0.78) return 1;
  if (r < 0.82) return (0.82 - r) / 0.04;
  return 0;
}

function bgColor(y, size) {
  const t = y / size;
  return [
    Math.round(TOP_RGB[0] * (1-t) + BOT_RGB[0] * t),
    Math.round(TOP_RGB[1] * (1-t) + BOT_RGB[1] * t),
    Math.round(TOP_RGB[2] * (1-t) + BOT_RGB[2] * t),
  ];
}

// --- SDFs (unit coords 0..1) ---
function sdCircle(px, py, cx, cy, r) { const dx = px-cx, dy = py-cy; return Math.sqrt(dx*dx+dy*dy) - r; }
function sdTriangle(px, py, ax, ay, bx, by, cx, cy) {
  const e0x=bx-ax, e0y=by-ay, e1x=cx-bx, e1y=cy-by, e2x=ax-cx, e2y=ay-cy;
  const v0x=px-ax, v0y=py-ay, v1x=px-bx, v1y=py-by, v2x=px-cx, v2y=py-cy;
  const cl = (t)=>Math.max(0,Math.min(1,t));
  const p0x=v0x-e0x*cl((v0x*e0x+v0y*e0y)/(e0x*e0x+e0y*e0y)), p0y=v0y-e0y*cl((v0x*e0x+v0y*e0y)/(e0x*e0x+e0y*e0y));
  const p1x=v1x-e1x*cl((v1x*e1x+v1y*e1y)/(e1x*e1x+e1y*e1y)), p1y=v1y-e1y*cl((v1x*e1x+v1y*e1y)/(e1x*e1x+e1y*e1y));
  const p2x=v2x-e2x*cl((v2x*e2x+v2y*e2y)/(e2x*e2x+e2y*e2y)), p2y=v2y-e2y*cl((v2x*e2x+v2y*e2y)/(e2x*e2x+e2y*e2y));
  const s = Math.sign(e0x*e2y - e0y*e2x);
  const d0x=p0x*p0x+p0y*p0y, d0y=s*(v0x*e0y-v0y*e0x);
  const d1x=p1x*p1x+p1y*p1y, d1y=s*(v1x*e1y-v1y*e1x);
  const d2x=p2x*p2x+p2y*p2y, d2y=s*(v2x*e2y-v2y*e2x);
  const dx=Math.min(d0x,d1x,d2x), dy=Math.min(d0y,d1y,d2y);
  return -Math.sqrt(dx)*Math.sign(dy);
}

// Kitten head silhouette: head circle + two pointed ears.
function headAlpha(ux, uy) {
  const head = sdCircle(ux, uy, 0.50, 0.55, 0.28);
  const earL = sdTriangle(ux, uy, 0.27, 0.48, 0.30, 0.16, 0.52, 0.40);
  const earR = sdTriangle(ux, uy, 0.73, 0.48, 0.70, 0.16, 0.48, 0.40);
  const d = Math.min(head, earL, earR);
  if (d < -0.004) return 1;
  if (d < 0.004) return (0.004 - d) / 0.008;
  return 0;
}

// Face details that show the gradient *through* the white glyph (eyes, nose).
function faceCut(ux, uy) {
  const eyeL = sdCircle(ux, uy, 0.40, 0.56, 0.045);
  const eyeR = sdCircle(ux, uy, 0.60, 0.56, 0.045);
  const nose = sdCircle(ux, uy, 0.50, 0.66, 0.028);
  const d = Math.min(eyeL, eyeR, nose);
  if (d < -0.003) return 1;
  if (d < 0.003) return (0.003 - d) / 0.006;
  return 0;
}

function renderAt(size) {
  return makePng(size, size, (x, y) => {
    const a = squircleAlpha(x, y, size);
    if (a <= 0) return [0,0,0,0];
    const ux = x / size, uy = y / size;
    const [r,g,b] = bgColor(y, size);
    const ga = headAlpha(ux, uy);
    if (ga > 0) {
      const cut = faceCut(ux, uy);          // 1 = show gradient (eye/nose), 0 = white fur
      const fr = Math.round(r * cut + 255 * (1-cut));
      const fg = Math.round(g * cut + 255 * (1-cut));
      const fb = Math.round(b * cut + 255 * (1-cut));
      // blend white-fur glyph over gradient by ga
      const or = Math.round(r * (1-ga) + fr * ga);
      const og = Math.round(g * (1-ga) + fg * ga);
      const ob = Math.round(b * (1-ga) + fb * ga);
      return [or, og, ob, Math.round(255 * a)];
    }
    return [r, g, b, Math.round(255 * a)];
  });
}

const outDir = path.resolve(__dirname);
fs.writeFileSync(path.join(outDir, 'icon-1024.png'), renderAt(1024));

const iconset = path.join(outDir, 'icon.iconset');
fs.rmSync(iconset, { recursive: true, force: true });
fs.mkdirSync(iconset, { recursive: true });
for (const s of [16, 32, 128, 256, 512]) {
  fs.writeFileSync(path.join(iconset, `icon_${s}x${s}.png`), renderAt(s));
  fs.writeFileSync(path.join(iconset, `icon_${s}x${s}@2x.png`), renderAt(s * 2));
}
fs.writeFileSync(path.join(iconset, 'icon_512x512@2x.png'), renderAt(1024));
console.log('icon generated for', cfg.name);
