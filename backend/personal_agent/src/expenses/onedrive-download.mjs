const MAX_BYTES = 25 * 1024 * 1024;
export class ExpenseDownloadError extends Error {
  constructor(message, status = 422) { super(message); this.status = status; }
}
function allowed(url, source = false) {
  const h = url.hostname.toLowerCase();
  return url.protocol === 'https:' && !url.username && !url.password && (!url.port || url.port === '443') &&
    (['1drv.ms', 'onedrive.live.com', 'api.onedrive.com'].includes(h) || h.endsWith('.sharepoint.com') ||
      // Personal OneDrive files migrated to SharePoint use this Graph download host.
      (!source && (h === 'my.microsoftpersonalcontent.com' || h.endsWith('.1drv.com') || h.endsWith('.onedrive.com') || h.endsWith('.files.live.com'))));
}
export function validateExpenseLink(value) {
  if (typeof value !== 'string' || value.length > 4096) throw new ExpenseDownloadError('Link OneDrive non valido');
  let url;
  try { url = new URL(value.trim()); } catch { throw new ExpenseDownloadError('Link OneDrive non valido'); }
  if (!allowed(url, true)) throw new ExpenseDownloadError('Usa un link HTTPS OneDrive o SharePoint');
  return url.toString();
}
function sharingId(input) {
  return 'u!' + btoa(String.fromCharCode(...new TextEncoder().encode(input))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

// Only Graph receives the bearer token. Its short-lived download redirect is
// fetched without credentials and never saved or exposed to the client.
export async function downloadGraphExpenseWorkbook(value, getAccessToken, fetcher = fetch) {
  const input = validateExpenseLink(value);
  const endpoint = `https://graph.microsoft.com/v1.0/shares/${sharingId(input)}/driveItem/content`;
  let response;
  for (const forceRefresh of [false, true]) {
    response = await fetcher(endpoint, { redirect: 'manual', signal: AbortSignal.timeout(18000), headers: {
      authorization: `Bearer ${await getAccessToken(forceRefresh)}`,
      'cache-control': 'no-cache',
    } });
    if (response.status !== 401 || forceRefresh) break;
    await response.body?.cancel();
  }
  if ([401,403].includes(response.status)) {
    await response.body?.cancel();
    throw new ExpenseDownloadError('Ricollega OneDrive da Fonte Excel con l’account che contiene questo file e consenti la lettura.', 409);
  }
  if (response.status === 404) {
    await response.body?.cancel();
    throw new ExpenseDownloadError('File non trovato: sostituisci il link oppure verifica l’account OneDrive collegato.', 404);
  }
  if ([301,302,303,307,308].includes(response.status)) {
    const location = response.headers.get('location');
    await response.body?.cancel();
    if (location) {
      const bytes = await requestFile(new URL(location), fetcher);
      if (bytes) return bytes;
    }
  } else if (response.ok) {
    const bytes = await readWorkbookResponse(response);
    if (bytes) return bytes;
  } else { await response.body?.cancel(); }
  throw new ExpenseDownloadError('Microsoft non ha restituito un file Excel valido. Riprova l’aggiornamento.', 503);
}
async function readWorkbookResponse(response) {
  if (Number(response.headers.get('content-length') || 0) > MAX_BYTES) {
    await response.body?.cancel();
    throw new ExpenseDownloadError('Excel troppo grande');
  }
  const reader = response.body?.getReader();
  if (!reader) return null;
  let length = 0;
  const parts = [];
  while (true) {
    const {done, value} = await reader.read();
    if (done) break;
    length += value.length;
    if (length > MAX_BYTES) { await reader.cancel(); throw new ExpenseDownloadError('Excel troppo grande'); }
    parts.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.length; }
  return bytes.length >= 4 && bytes[0] === 80 && bytes[1] === 75 && bytes[2] === 3 && bytes[3] === 4 ? bytes : null;
}
async function requestFile(url, fetcher) {
  for (let i = 0; i < 6; i++) {
    if (!allowed(url)) throw new ExpenseDownloadError(`Il link reindirizza fuori da OneDrive (host: ${url.hostname})`);
    const response = await fetcher(url.toString(), { redirect: 'manual', signal: AbortSignal.timeout(18000), headers: { accept: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/octet-stream' } });
    if ([301,302,303,307,308].includes(response.status)) {
      const location = response.headers.get('location');
      await response.body?.cancel();
      if (!location) return null;
      url = new URL(location, url);
      continue;
    }
    if ([401,403].includes(response.status)) {
      await response.body?.cancel();
      throw new ExpenseDownloadError('Microsoft blocca il download automatico del link pubblico. Collega OneDrive da Fonte Excel per leggere il file aggiornato.', 409);
    }
    if (!response.ok || Number(response.headers.get('content-length') || 0) > MAX_BYTES) { await response.body?.cancel(); return null; }
    return readWorkbookResponse(response);
  }
  return null;
}
export async function downloadExpenseWorkbook(value, fetcher = fetch) {
  const input = validateExpenseLink(value);
  const direct = new URL(input);
  direct.searchParams.set('download', '1');
  const encoded = btoa(String.fromCharCode(...new TextEncoder().encode(input))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  const api = new URL(`https://api.onedrive.com/v1.0/shares/u!${encoded}/root/content`);
  let denied;
  for (const candidate of [direct, api]) {
    try {
      const bytes = await requestFile(candidate, fetcher);
      if (bytes) return bytes;
    } catch (error) {
      if (error instanceof ExpenseDownloadError && error.status === 409) { denied = error; continue; }
      if (error instanceof ExpenseDownloadError) throw error;
      if (error?.cause?.code === 'SELF_SIGNED_CERT_IN_CHAIN') {
        throw new ExpenseDownloadError('La rete richiede i certificati di sistema di Windows. Riavvia il server locale aggiornato.', 503);
      }
    }
  }
  if (denied) throw denied;
  throw new ExpenseDownloadError('Link non scaricabile automaticamente. Apri Fonte Excel e collega OneDrive per leggere il file aggiornato.', 409);
}
