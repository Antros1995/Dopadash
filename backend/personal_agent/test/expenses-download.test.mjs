import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateExpenseLink, downloadExpenseWorkbook, downloadGraphExpenseWorkbook } from '../src/expenses/onedrive-download.mjs';
test('accepts Microsoft sharing links and rejects internal or credential URLs', () => {
  assert.match(validateExpenseLink('https://1drv.ms/x/example'), /^https:/);
  for (const url of ['http://localhost/a','https://127.0.0.1/a','https://evil.example/a','https://user:password@onedrive.live.com/a']) assert.throws(()=>validateExpenseLink(url));
});
test('follows only Microsoft redirects and returns actual xlsx bytes', async () => {
  const bytes = new Uint8Array([80,75,3,4,10]);
  const result = await downloadExpenseWorkbook('https://1drv.ms/x/example', async url =>
    url.includes('1drv.ms') ? new Response(null,{status:302,headers:{location:'https://public.files.1drv.com/file'}}) : new Response(bytes));
  assert.deepEqual(result,bytes);
  await assert.rejects(downloadExpenseWorkbook('https://1drv.ms/x/example',async()=>new Response(null,{status:302,headers:{location:'https://127.0.0.1/internal'}})));
});
test('login HTML and expired links are never substituted with financial data', async () => {
  await assert.rejects(downloadExpenseWorkbook('https://1drv.ms/x/example',async()=>new Response('<html>Login</html>')), /Link non scaricabile/);
});
test('reports Microsoft authentication explicitly after both download methods are denied', async () => {
  let requests = 0;
  await assert.rejects(downloadExpenseWorkbook('https://1drv.ms/x/example', async () => {
    requests++; return new Response(null, { status: 401 });
  }), /blocca il download automatico/);
  assert.equal(requests, 2);
});
test('Graph renews authorization and never leaks bearer to the download host', async () => {
  const bytes = new Uint8Array([80,75,3,4,22]);
  const refreshes = [];
  let calls = 0;
  const download = async (url, options) => {
    calls++;
    if (url.startsWith('https://graph.microsoft.com/')) {
      assert.match(url, /\/shares\/u![A-Za-z0-9_-]+\/driveItem\/content$/);
      assert.ok(options.headers.authorization);
      return calls === 1 ? new Response(null,{status:401}) : new Response(null,{status:302,headers:{location:'https://public.files.1drv.com/file'}});
    }
    assert.equal(options.headers.authorization, undefined);
    return new Response(bytes);
  };
  assert.deepEqual(await downloadGraphExpenseWorkbook('https://1drv.ms/x/example', async force => { refreshes.push(force); return 'private-token'; }, download), bytes);
  assert.deepEqual(refreshes, [false, true]);
});
test('Graph refuses external redirect and requires consent instead of fake data', async () => {
  await assert.rejects(downloadGraphExpenseWorkbook('https://1drv.ms/x/example',async()=> 'private-token',async()=> new Response(null,{status:302,headers:{location:'https://evil.example/file'}})), /fuori da OneDrive/);
  await assert.rejects(downloadGraphExpenseWorkbook('https://1drv.ms/x/example',async()=> 'private-token',async()=> new Response(null,{status:403})), /Ricollega OneDrive/);
});
test('personal OneDrive download accepts its Microsoft content host without forwarding credentials', async () => {
  const bytes = new Uint8Array([80,75,3,4,23]);
  let contentRequests = 0;
  const result = await downloadGraphExpenseWorkbook('https://1drv.ms/x/example', async () => 'private-token', async (url, options) => {
    if (url.startsWith('https://graph.microsoft.com/')) return new Response(null, {status:302,headers:{location:'https://my.microsoftpersonalcontent.com/personal/example/_layouts/15/download.aspx?tempauth=private'}});
    assert.equal(new URL(url).hostname, 'my.microsoftpersonalcontent.com');
    assert.equal(options.headers.authorization, undefined);
    contentRequests++;
    return new Response(bytes);
  });
  assert.deepEqual(result, bytes);
  assert.equal(contentRequests, 1);
  assert.throws(() => validateExpenseLink('https://my.microsoftpersonalcontent.com/file'));
});
test('personal OneDrive download rejects lookalike hosts, credentials, non-HTTPS and private redirects', async () => {
  for (const location of [
    'https://my.microsoftpersonalcontent.com.evil.example/file?secret=hidden',
    'https://evilmy.microsoftpersonalcontent.com/file',
    'https://127.0.0.1/file',
    'http://my.microsoftpersonalcontent.com/file',
    'https://user:password@my.microsoftpersonalcontent.com/file',
    'https://my.microsoftpersonalcontent.com:8443/file',
  ]) {
    let requests = 0;
    await assert.rejects(downloadGraphExpenseWorkbook('https://1drv.ms/x/example', async () => 'private-token', async () => {
      requests++;
      return new Response(null, {status:302,headers:{location}});
    }), error => {
      assert.match(error.message, /fuori da OneDrive/);
      assert.ok(!error.message.includes('hidden') && !error.message.includes('password'));
      return true;
    });
    assert.equal(requests, 1);
  }
});
