'use strict';
// Contact sheet of same-size PNG captures: node tools/contact-sheet.cjs out.png cols a.png b.png ...
const { decode } = require('./compare-ref.cjs');
const fs = require('node:fs'), zlib = require('node:zlib');
const [out, colsArg, ...files] = process.argv.slice(2);
const imgs = files.map(decode), cols = +colsArg, w = imgs[0].w, h = imgs[0].h, gap = 4;
const W = cols * w + (cols - 1) * gap, rows = Math.ceil(imgs.length / cols), H = rows * h + (rows - 1) * gap;
const px = Buffer.alloc(W * H * 3, 40);
imgs.forEach((im, k) => {
  const ox = (k % cols) * (w + gap), oy = Math.floor(k / cols) * (h + gap);
  for (let y = 0; y < h; y++) im.px.copy(px, ((oy + y) * W + ox) * 3, y * w * 3, (y + 1) * w * 3);
});
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) px.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3);
const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = b => { let c = 0xffffffff; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const ch = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
const ih = Buffer.alloc(13); ih.writeUInt32BE(W, 0); ih.writeUInt32BE(H, 4); ih[8] = 8; ih[9] = 2;
fs.writeFileSync(out, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), ch('IHDR', ih), ch('IDAT', zlib.deflateSync(raw)), ch('IEND', Buffer.alloc(0))]));
