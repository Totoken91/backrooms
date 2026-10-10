'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../build/web');
const port = Number(process.argv[2] || 8770);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Port invalide');
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.glb': 'model/gltf-binary', '.gltf': 'model/gltf+json', '.wasm': 'application/wasm', '.woff2': 'font/woff2', '.ogg': 'audio/ogg', '.mp3': 'audio/mpeg' };
const server = http.createServer((req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { Allow: 'GET, HEAD' }); return res.end(); }
  let name;
  try { name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); }
  catch { res.writeHead(400); return res.end('Bad request'); }
  if (name.includes('\0')) { res.writeHead(400); return res.end(); }
  const target = path.resolve(root, '.' + (name.endsWith('/') ? name + 'index.html' : name));
  const rel = path.relative(root, target);
  if (rel.startsWith('..') || path.isAbsolute(rel)) { res.writeHead(403); return res.end('Forbidden'); }
  fs.realpath(target, (err, real) => {
    if (err) { res.writeHead(404); return res.end('Not found'); }
    const realRel = path.relative(root, real);
    if (realRel.startsWith('..') || path.isAbsolute(realRel)) { res.writeHead(403); return res.end('Forbidden'); }
    fs.stat(real, (statErr, stat) => {
      if (statErr || !stat.isFile()) { res.writeHead(404); return res.end('Not found'); }
      res.writeHead(200, { 'Content-Type': mime[path.extname(real).toLowerCase()] || 'application/octet-stream', 'Content-Length': stat.size });
      if (req.method === 'HEAD') return res.end();
      const stream = fs.createReadStream(real);
      stream.on('error', () => res.destroy());
      stream.pipe(res);
    });
  });
});
server.on('error', err => { console.error(err.message); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => console.log(`Hors Plan (Godot) : http://127.0.0.1:${port}/ (Ctrl+C pour arrêter)`));
