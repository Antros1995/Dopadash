import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";

const root = resolve(process.argv[2] ?? "build/web");
const port = Number(process.argv[3] ?? "7358");

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".wasm", "application/wasm"],
]);

async function existingFile(pathname) {
  const candidate = resolve(root, `.${pathname}`);
  if (candidate !== root && !candidate.startsWith(`${root}${sep}`)) return null;
  try {
    const info = await stat(candidate);
    if (info.isFile()) return candidate;
    if (info.isDirectory()) return resolve(candidate, "index.html");
  } catch {
    // Flutter is a single-page app: unknown routes return index.html.
  }
  return resolve(root, "index.html");
}

createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(
      new URL(request.url ?? "/", "http://localhost").pathname,
    );
    const file = await existingFile(pathname);
    if (!file) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    response.writeHead(200, {
      "content-type": contentTypes.get(extname(file)) ?? "application/octet-stream",
      "cache-control": extname(file) === ".html" ? "no-store" : "public, max-age=3600",
      "x-content-type-options": "nosniff",
    });
    createReadStream(file).pipe(response);
  } catch {
    response.writeHead(500).end("Internal server error");
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`Dashboard disponibile su http://localhost:${port}`);
});
