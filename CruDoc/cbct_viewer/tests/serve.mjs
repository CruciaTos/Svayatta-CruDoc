// Small static loopback server for testing the CBCT viewer.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
};

export function createServer({ root, phantom } = {}) {
  const viewerRoot = fileURLToPath(new URL('..', import.meta.url));
  const ROOT = root
    ? (path.isAbsolute(root) ? root : path.resolve(viewerRoot, root))
    : path.resolve(viewerRoot, '../assets/cbct_viewer');
  const PHANTOM = phantom
    ? (path.isAbsolute(phantom) ? phantom : path.resolve(viewerRoot, phantom))
    : path.resolve(viewerRoot, 'dev/phantom');

  const puts = {};

  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (req.method === 'PUT') {
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        puts[url] = Buffer.concat(chunks).length;
        res.writeHead(204);
        res.end();
      });
      return;
    }
    const [baseDir, rel] = url.startsWith('/phantom/')
      ? [PHANTOM, url.slice(9)]
      : [ROOT, url === '/' ? 'index.html' : url.slice(1)];
    const file = path.join(baseDir, rel);
    if (!file.startsWith(path.normalize(baseDir)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Content-Length': fs.statSync(file).size,
    });
    fs.createReadStream(file).pipe(res);
  });

  return {
    server,
    puts,
    start() {
      return new Promise((resolve, reject) => {
        server.listen(0, '127.0.0.1', (err) => {
          if (err) return reject(err);
          const port = server.address().port;
          resolve({ port, base: `http://127.0.0.1:${port}/` });
        });
      });
    },
    close() {
      return new Promise((resolve) => server.close(resolve));
    },
  };
}

