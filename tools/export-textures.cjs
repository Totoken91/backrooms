'use strict';
// Exports the procedural Level 0 finishes of tools/art-materials.js (authored
// for the earlier WebGL prototype) as tiling PNG textures for Godot:
// <name>_albedo.png, <name>_normal.png (tangent space), <name>_rough.png.
// Usage: node tools/export-textures.cjs
const fs = require('node:fs'), path = require('node:path'), zlib = require('node:zlib');
require('./art-materials.js');
const M = globalThis.OutOfFrameMaterials, maps = M.generate();
const out = path.join(__dirname, '../assets/textures');
fs.mkdirSync(out, { recursive: true });
const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = b => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function png(file, w, h, channels, pixel) {
  const raw = Buffer.alloc((w * channels + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * channels + 1)] = 0; for (let x = 0; x < w; x++) { const v = pixel(x, y); for (let c = 0; c < channels; c++) raw[y * (w * channels + 1) + 1 + x * channels + c] = v[c]; } }
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = channels === 3 ? 2 : 0; ihdr[10] = ihdr[11] = ihdr[12] = 0;
  fs.writeFileSync(path.join(out, file), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]));
}
const names = { 0: 'wallpaper', 1: 'carpet', 2: 'ceiling', 3: 'skirting', 4: 'diffuser', 7: 'metal' };
for (const [id, name] of Object.entries(names)) {
  const ox = (id % 4) * M.TILE + M.PAD, oy = Math.floor(id / 4) * M.TILE + M.PAD, N = M.INNER;
  const at = (map, x, y) => { const i = ((oy + y) * M.SIZE + ox + x) * 4; return map.slice(i, i + 4); };
  png(`${name}_albedo.png`, N, N, 3, (x, y) => at(maps.color, x, y));
  // Atlas normals are tangent-space with V increasing downwards; Godot expects
  // OpenGL (Y up), so green is flipped.
  png(`${name}_normal.png`, N, N, 3, (x, y) => { const s = at(maps.surface, x, y); return [s[0], 255 - s[1], s[2]]; });
  png(`${name}_rough.png`, N, N, 1, (x, y) => [at(maps.surface, x, y)[3]]);
}
console.log('textures:', Object.values(names).join(', '));
