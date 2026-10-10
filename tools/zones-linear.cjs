'use strict';
// Mean linear colour (sRGB decoded) of a capture over a 3 × 3 grid, rows top
// to bottom, in the layout of render_scene.py's passes JSON.
// Usage: node tools/zones-linear.cjs capture.png
const { decode } = require('./compare-ref.cjs');
const img = decode(process.argv[2]);
const lin = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
const grid = [];
for (let row = 0; row < 3; row++) for (let col = 0; col < 3; col++) {
  const s = [0, 0, 0]; let n = 0;
  for (let y = Math.floor(row * img.h / 3); y < Math.floor((row + 1) * img.h / 3); y += 3)
    for (let x = Math.floor(col * img.w / 3); x < Math.floor((col + 1) * img.w / 3); x += 3) {
      const i = (y * img.w + x) * 3; for (let c = 0; c < 3; c++) s[c] += lin(img.px[i + c]); n++;
    }
  grid.push(s.map(v => +(v / n).toFixed(4)));
}
console.log(JSON.stringify(grid));
