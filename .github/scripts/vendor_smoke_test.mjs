// Chạy bởi vendor_smoke_test.py: node vendor_smoke_test.mjs <url> [<url>...]
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const failures = [];
const ev = (page, fn) => page.evaluate(fn).catch(e => { console.log('    error: ' + e.message.split('\n')[0]); return false; });
const check = (ok, msg) => { console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) failures.push(msg); };

const browser = await chromium.launch();
for (const url of process.argv.slice(2)) {
  console.log('== ' + url);
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  const bad = [], errs = [];
  page.on('response', r => { if (r.status() >= 400 && r.url().includes('/.fancyindex/')) bad.push(r.status() + ' ' + r.url()); });
  page.on('pageerror', e => errs.push(e.message));
  page.on('dialog', d => { errs.push('dialog: ' + d.message()); d.dismiss(); });

  await page.goto(url);
  await page.waitForFunction(() => window.ace && window.marked && window.DOMPurify && window.jsyaml && window.JSZip && window.Terminal,
    null, { timeout: 15000 }).catch(() => {});
  const g = await page.evaluate(() => ({
    ace: typeof ace, marked: typeof (window.marked && marked.parse), DOMPurify: typeof (window.DOMPurify && DOMPurify.sanitize),
    jsyaml: typeof (window.jsyaml && jsyaml.loadAll), JSZip: typeof (window.JSZip && JSZip.loadAsync), Terminal: typeof window.Terminal
  }));
  for (const [k, v] of Object.entries(g)) check(v !== 'undefined', `global ${k} loaded (${v})`);
  check(await ev(page, () => DOMPurify.sanitize(marked.parse('# T\n<img src=x onerror=alert(1)>')).includes('<h1')
    && !DOMPurify.sanitize(marked.parse('<img src=x onerror=alert(1)>')).includes('onerror')), 'markdown render + sanitize');
  check(await ev(page, () => { const t = new Terminal({ rows: 5 }); const d = document.createElement('div');
    document.body.appendChild(d); t.open(d); t.writeln('hi'); return !!d.querySelector('.xterm'); }), 'xterm terminal opens');

  await page.click('tr[data-n="doc.pdf"]', { timeout: 5000 }).catch(() => {});
  await page.waitForFunction(() => /Page 1 \/ 1/.test((document.getElementById('pdfPageInfo') || {}).textContent || ''),
    null, { timeout: 20000 }).catch(() => {});
  check(await ev(page, () => { const c = document.getElementById('pdfCanvas'); return !!c && c.width > 50; }), 'pdf.js renders the PDF');

  await page.reload(); await page.waitForTimeout(800);
  await page.click('tr[data-n="conf.yaml"]', { timeout: 5000 }).catch(() => {}); await page.waitForTimeout(1500);
  check(await ev(page, () => !!document.querySelector('.ace_editor')), 'Ace editor opens YAML');
  check(await ev(page, () => /YAML Error \(Line \d+\)/.test((document.querySelector('.yaml-alert') || {}).textContent || '')),
    'YAML linter reports the syntax error');

  await page.reload(); await page.waitForTimeout(800);
  await page.click('tr[data-n="ha.yaml"]', { timeout: 5000 }).catch(() => {}); await page.waitForTimeout(1500);
  check(await ev(page, () => /Valid Home Assistant YAML/.test((document.querySelector('.yaml-alert') || {}).textContent || '')),
    'YAML linter accepts valid Home Assistant YAML (!include, !secret, anchors, !!set, YAML 1.1)');

  await page.reload(); await page.waitForTimeout(800);
  await page.click('tr[data-n="arch.zip"]', { timeout: 5000 }).catch(() => {}); await page.waitForTimeout(1500);
  check(await ev(page, () => ((document.querySelector('.arch-list') || {}).innerText || '').includes('inner/file.txt')), 'zip preview lists entries');

  check(bad.length === 0, 'no failed asset requests ' + (bad.length ? JSON.stringify(bad) : ''));
  check(errs.length === 0, 'no JavaScript errors ' + (errs.length ? JSON.stringify(errs) : ''));
  await page.close();
}
await browser.close();
console.log(failures.length ? `SMOKE TEST FAILED (${failures.length})` : 'SMOKE TEST PASSED');
process.exit(failures.length ? 1 : 0);
