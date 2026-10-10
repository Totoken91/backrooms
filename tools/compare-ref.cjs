'use strict';
// Colour comparison between a reference image and a game capture: mean
// colour, luminance and saturation of named regions (fractions of the image),
// plus a side-by-side PNG for review. No dependency.
// Usage: node tools/compare-ref.cjs ref.png capture.png out.png "zone=x0,y0,x1,y1;..." ["zone=...;..."]
// The second region list (optional) applies to the capture; default: same.
const fs = require('node:fs'), zlib = require('node:zlib');

function decode(file) {
  const b = fs.readFileSync(file);
  if (b.readUInt32BE(0) !== 0x89504e47) throw new Error(file + ': not a PNG');
  let p = 8, w, h, depth, type, idat = [];
  while (p < b.length) {
    const len = b.readUInt32BE(p), kind = b.toString('ascii', p + 4, p + 8), data = b.subarray(p + 8, p + 8 + len);
    if (kind === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); depth = data[8]; type = data[9]; if (data[12]) throw new Error('interlaced PNG'); }
    else if (kind === 'IDAT') idat.push(data);
    else if (kind === 'IEND') break;
    p += 12 + len;
  }
  if (depth !== 8 || ![2, 6].includes(type)) throw new Error(`unsupported PNG (depth ${depth}, type ${type})`);
  const ch = type === 6 ? 4 : 3, raw = zlib.inflateSync(Buffer.concat(idat)), stride = w * ch, out = Buffer.alloc(w * h * 3);
  let prev = Buffer.alloc(stride), line = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= ch ? line[i - ch] : 0, up = prev[i], c = i >= ch ? prev[i - ch] : 0;
      let v = src[i];
      if (f === 1) v += a; else if (f === 2) v += up; else if (f === 3) v += (a + up) >> 1;
      else if (f === 4) { const pa = Math.abs(up - c), pb = Math.abs(a - c), pc = Math.abs(a + up - 2 * c); v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c; }
      line[i] = v & 255;
    }
    for (let x = 0; x < w; x++) for (let c = 0; c < 3; c++) out[(y * w + x) * 3 + c] = line[x * ch + c];
    [prev, line] = [line, prev];
  }
  return { w, h, px: out };
}

const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = b => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function encode(file, w, h, px) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) px.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}

function stats(img, [x0, y0, x1, y1]) {
  let r = 0, g = 0, b = 0, n = 0, l2 = 0;
  for (let y = Math.floor(y0 * img.h); y < Math.floor(y1 * img.h); y++) for (let x = Math.floor(x0 * img.w); x < Math.floor(x1 * img.w); x++) {
    const i = (y * img.w + x) * 3; r += img.px[i]; g += img.px[i + 1]; b += img.px[i + 2];
    const l = 0.2126 * img.px[i] + 0.7152 * img.px[i + 1] + 0.0722 * img.px[i + 2]; l2 += l * l; n++;
  }
  r /= n; g /= n; b /= n;
  const luma = 0.2126 * r + 0.7152 * g + 0.0722 * b, max = Math.max(r, g, b), min = Math.min(r, g, b);
  return { rgb: [r, g, b].map(Math.round), luma: Math.round(luma), sat: +(max ? (max - min) / max : 0).toFixed(2), contrast: Math.round(Math.sqrt(Math.max(0, l2 / n - luma * luma))) };
}

if (require.main !== module) { module.exports = { decode }; return; }
const [refFile, capFile, outFile, refZones, capZones] = process.argv.slice(2);
const parse = s => Object.fromEntries(s.split(';').filter(Boolean).map(z => { const [k, v] = z.split('='); return [k, v.split(',').map(Number)]; }));
const ref = decode(refFile), cap = decode(capFile), rz = parse(refZones), cz = capZones ? parse(capZones) : rz;
console.log('zone'.padEnd(10), 'référence'.padEnd(44), 'capture');
for (const k of Object.keys(rz)) { const a = stats(ref, rz[k]), b = stats(cap, cz[k] || rz[k]); console.log(k.padEnd(10), JSON.stringify(a).padEnd(44), JSON.stringify(b)); }
const all = [stats(ref, [0, 0, 1, 1]), stats(cap, [0, 0, 1, 1])];
console.log('image'.padEnd(10), JSON.stringify(all[0]).padEnd(44), JSON.stringify(all[1]));
// Side by side at a common height.
const H = 540, wa = Math.round(ref.w * H / ref.h), wb = Math.round(cap.w * H / cap.h), W = wa + wb + 8, px = Buffer.alloc(W * H * 3, 20);
for (const [img, w, ox] of [[ref, wa, 0], [cap, wb, wa + 8]]) for (let y = 0; y < H; y++) for (let x = 0; x < w; x++) {
  const sx = Math.min(img.w - 1, Math.floor(x * img.w / w)), sy = Math.min(img.h - 1, Math.floor(y * img.h / H)), s = (sy * img.w + sx) * 3, d = (y * W + ox + x) * 3;
  px[d] = img.px[s]; px[d + 1] = img.px[s + 1]; px[d + 2] = img.px[s + 2];
}
encode(outFile, W, H, px);
console.log('planche :', outFile);
