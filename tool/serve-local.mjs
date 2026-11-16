import { createServer } from 'node:http';
import { createReadStream, statSync, readFileSync } from 'node:fs';
import { resolve, extname, sep } from 'node:path';
import * as tls from 'node:tls';
import { marketSeries } from './local-market-feed.mjs';
import { downloadExpenseWorkbook, ExpenseDownloadError } from '../backend/personal_agent/src/expenses/onedrive-download.mjs';
// Trust the Windows certificate store (useful behind TLS-inspecting proxies), while
// preserving certificate validation for every upstream HTTPS request.
if (process.platform === 'win32' && typeof tls.setDefaultCACertificates === 'function' && typeof tls.getCACertificates === 'function') {
  tls.setDefaultCACertificates([...tls.getCACertificates('default'), ...tls.getCACertificates('system')]);
}
const root = resolve(process.argv[2] ?? 'build/web');
const port = Number(process.argv[3] ?? 7358);
const host = process.argv[4] ?? '127.0.0.1';
const previewHosts = ['localhost', '127.0.0.1', ...(process.argv[5] ?? '').split(',').filter(Boolean)];
const allowedOrigins = previewHosts.map(h => `http://${h}:${port}`);
let agentBase;
try {
  const configured = JSON.parse(readFileSync(resolve('config/dart_defines.local.json'), 'utf8')).PERSONAL_AGENT_API_URL;
  const url = new URL(configured);
  if (url.protocol === 'https:') agentBase = url;
} catch { /* Ordinary static serving remains available without an API proxy. */ }
const agentPaths = new Set(['/api/desktop/calendar', '/api/desktop/markets', '/api/desktop/fitbit', '/api/desktop/fitbit/history', '/api/desktop/fitbit/connect', '/api/desktop/outlook/connect', '/api/desktop/expenses/workbook']);
const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json','.css':'text/css','.wasm':'application/wasm','.png':'image/png','.jpg':'image/jpeg','.svg':'image/svg+xml','.otf':'font/otf','.ttf':'font/ttf'};
createServer(async (req,res) => {
  let path;
  try { path=decodeURIComponent(new URL(req.url,'http://localhost').pathname); } catch { res.writeHead(400).end();return; }
  if (agentPaths.has(path)) {
    if (req.headers.origin && !allowedOrigins.includes(req.headers.origin)) { res.writeHead(403).end(); return; }
    if (!['GET', 'POST'].includes(req.method)) { res.writeHead(405).end(); return; }
    if (!/^Bearer [^\s]{20,8192}$/.test(req.headers.authorization ?? '')) { res.writeHead(401, {'content-type':'application/json','cache-control':'no-store'}).end(JSON.stringify({error:'invalid_session'})); return; }
    if (!agentBase) { res.writeHead(503).end('API locale non configurata'); return; }
    try {
      const chunks = []; let length = 0;
      for await (const chunk of req) { length += chunk.length; if (length > 16384) { res.writeHead(413).end(); return; } chunks.push(chunk); }
      const requested = new URL(req.url, 'http://localhost');
      const upstream = new URL(`${requested.pathname}${requested.search}`, agentBase);
      const response = await fetch(upstream, {method:req.method,
        headers:{authorization:req.headers.authorization,'content-type':'application/json'},
        ...(req.method === 'POST' ? {body:Buffer.concat(chunks)} : {}), signal:AbortSignal.timeout(25000), redirect:'error'});
      res.writeHead(response.status, {'content-type':response.headers.get('content-type') ?? 'application/json','cache-control':'no-store','x-content-type-options':'nosniff'});
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch { if (!res.headersSent) res.writeHead(502, {'content-type':'application/json'}).end(JSON.stringify({error:'local_proxy_unavailable'})); else res.destroy(); }
    return;
  }
  if (path === '/api/local/expenses/workbook' && req.method === 'POST') {
    const origin = req.headers.origin;
    if (origin && !allowedOrigins.includes(origin)) { res.writeHead(403).end(); return; }
    try {
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 8192) { res.writeHead(413).end(); return; } }
      const bytes = await downloadExpenseWorkbook(JSON.parse(body).url);
      res.writeHead(200, { 'content-type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'cache-control': 'no-store' }).end(bytes);
    } catch (error) {
      res.writeHead(error instanceof ExpenseDownloadError ? error.status : 503, { 'content-type': 'application/json' }).end(JSON.stringify({ error: error instanceof ExpenseDownloadError ? error.message : 'Excel non disponibile' }));
    }
    return;
  }
  if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405).end();return; }
  if (path === '/api/local/markets') {
    // Restrict the local proxy to same-origin requests and a fixed upstream.
    const origin = req.headers.origin;
    if (origin && !allowedOrigins.includes(origin)) { res.writeHead(403).end(); return; }
    try {
      const params = new URL(req.url, 'http://localhost').searchParams;
      const data = await marketSeries(params.get('symbol') ?? '', params.get('period') ?? '1d');
      res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' }).end(JSON.stringify(data));
    } catch { res.writeHead(502, { 'content-type': 'application/json' }).end(JSON.stringify({error:'Quotazione non disponibile'})); }
    return;
  }
  let file=resolve(root,'.'+path);
  if (file!==root && !file.startsWith(root+sep)) {res.writeHead(403).end();return;}
  try { if(statSync(file).isDirectory()) file=resolve(file,'index.html'); if(!statSync(file).isFile()) throw new Error(); }
  catch { if(extname(path)) {res.writeHead(404).end();return;} file=resolve(root,'index.html'); }
  res.writeHead(200,{'content-type':types[extname(file)]??'application/octet-stream','cache-control':'no-store','x-content-type-options':'nosniff'});
  if(req.method==='HEAD') {res.end();return;}
  createReadStream(file).on('error',()=>res.destroy()).pipe(res);
}).listen(port,host,()=>console.log(`App locale: http://localhost:${port}${previewHosts.length > 2 ? ` · Rete: http://${previewHosts[2]}:${port}` : ''}`));
