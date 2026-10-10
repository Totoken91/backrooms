'use strict';
// Compares the game's direct and indirect light (captures with
// `tune=debug_view:8 raw` and `tune=debug_view:9 raw`) with the Cycles diffuse
// passes (render_scene.py "passes"), on a 3 × 3 grid: luminance of E / π and
// the game / Cycles ratio.
// Usage: node tools/measure-gi.cjs direct.png indirect.png passes.json
const { decode } = require('./compare-ref.cjs');
const fs = require('node:fs');
const lin = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
function grid(file) {
  const img = decode(file), out = [];
  for (let row = 0; row < 3; row++) for (let col = 0; col < 3; col++) {
    const s = [0, 0, 0]; let n = 0;
    for (let y = Math.floor(row * img.h / 3); y < Math.floor((row + 1) * img.h / 3); y += 3)
      for (let x = Math.floor(col * img.w / 3); x < Math.floor((col + 1) * img.w / 3); x += 3) {
        const i = (y * img.w + x) * 3; for (let c = 0; c < 3; c++) s[c] += lin(img.px[i + c]); n++;
      }
    out.push(s.map(v => v / n));
  }
  return out;
}
const [dFile, iFile, pFile] = process.argv.slice(2);
const gd = grid(dFile), gi = grid(iFile), t = JSON.parse(fs.readFileSync(pFile));
const L = c => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
const names = ['hautG', 'hautC', 'hautD', 'milG', 'milC', 'milD', 'basG', 'basC', 'basD'];
const f = v => v.toFixed(3);
console.log('zone    direct C / jeu  (ratio)   indirect C / jeu  (ratio)   indirect b/r C / jeu');
let sd = 0, si = 0;
names.forEach((n, i) => {
  const rd = L(gd[i]) / L(t.DiffDir[i]), ri = L(gi[i]) / L(t.DiffInd[i]);
  sd += Math.log(rd); si += Math.log(ri);
  console.log(n.padEnd(7), f(L(t.DiffDir[i])), '/', f(L(gd[i])), `(${rd.toFixed(2)})`.padEnd(8), '   ', f(L(t.DiffInd[i])), '/', f(L(gi[i])), `(${ri.toFixed(2)})`.padEnd(8), '   ', (t.DiffInd[i][2] / t.DiffInd[i][0]).toFixed(2), '/', (gi[i][2] / gi[i][0]).toFixed(2));
});
console.log('moyenne géométrique des ratios : direct', Math.exp(sd / 9).toFixed(2), ' indirect', Math.exp(si / 9).toFixed(2));
