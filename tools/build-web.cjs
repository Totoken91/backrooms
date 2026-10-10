'use strict';
// Exports the Web build and injects the raw pointer-lock patch.
// Usage: node tools/build-web.cjs   (GODOT_BIN overrides the Godot executable)
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const out = path.join(root, 'build/web');
const candidates = [
  process.env.GODOT_BIN,
  'C:/Users/kenny/Documents/Codex/2026-10-09/files-mentioned-by-the-user-les/work/tools/godot-4.6/Godot_v4.6-stable_win64_console.exe',
  'godot',
].filter(Boolean);
const godot = candidates.find(p => p === 'godot' || fs.existsSync(p));

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const run = spawnSync(godot, ['--headless', '--path', root, '--export-release', 'Web', path.join(out, 'index.html')], { encoding: 'utf8' });
process.stdout.write(run.stdout.split('\n').filter(l => /error|warn/i.test(l)).join('\n'));
if (run.status !== 0 || !fs.existsSync(path.join(out, 'index.html'))) {
  console.error(run.stderr);
  process.exit(1);
}
fs.copyFileSync(path.join(root, 'web/raw-pointer.js'), path.join(out, 'raw-pointer.js'));
const html = path.join(out, 'index.html');
const page = fs.readFileSync(html, 'utf8');
// The patch must run before the engine script requests pointer lock.
fs.writeFileSync(html, page.replace('<head>', '<head>\n<script src="raw-pointer.js"></script>'));
const size = fs.readdirSync(out).map(f => `${f} ${(fs.statSync(path.join(out, f)).size / 1e6).toFixed(1)} Mo`);
console.log('\nbuild/web :', size.join(', '));
