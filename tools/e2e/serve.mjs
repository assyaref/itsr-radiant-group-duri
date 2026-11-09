// Minimal static server for build/web on 127.0.0.1:5000 (loopback only).
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
const root = process.argv[2];
const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json",
  ".css": "text/css", ".png": "image/png", ".wasm": "application/wasm", ".otf": "font/otf", ".ttf": "font/ttf",
  ".ico": "image/x-icon", ".svg": "image/svg+xml", ".frag": "text/plain", ".bin": "application/octet-stream" };
createServer(async (req, res) => {
  let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (p.endsWith("/")) p += "index.html";
  const file = normalize(join(root, p));
  if (!file.startsWith(normalize(root))) { res.writeHead(403).end(); return; }
  try {
    const data = await readFile(file);
    res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" }).end(data);
  } catch { res.writeHead(404).end("not found"); }
}).listen(5000, "127.0.0.1", () => console.log("serving on http://localhost:5000"));
