'use strict';
// In-page journey harness (#34 S0/S1): inert unless the carrier runs with
// KEYWARD_E2E=1 (verify.rkt / CI / the packaged self-check). glaze exposes no
// JS injection into the webview, so the page asks the carrier at start-up and,
// when the harness is on, runs the journey on the first load and posts the
// report to the carrier, which waits for it.
//
// Every step drives the product UI the way a user does (clicks, typed input,
// keyboard shortcuts) and asserts against real backend state plus two
// host fixtures that answer booleans only (clipboard equality).
(function () {
  const post = (path, body) => glaze.invoke(path, body || {}, { method: 'POST' });
  // The harness flag comes from the carrier (KEYWARD_E2E / KEYWARD_SELFTEST),
  // not from the URL: on the native channel the verifier cannot re-navigate
  // the first load reliably, and in production the context route is refused
  // anyway (the e2e grant is absent), which keeps this file inert.
  const enabled = async () => { try { const c = await glaze.invoke('/api/host/context', {}, { method: 'GET' }); return Boolean(c.e2e); } catch (_) { return false; } };
  window.__e2e = false;
  // Surface page-level failures to the report: a start-up exception must reach
  // CI as a failed step, not as a silent timeout.
  const pageErrors = [];
  window.addEventListener('error', e => pageErrors.push('error: ' + (e.message || e)));
  window.addEventListener('unhandledrejection', e => pageErrors.push('rejection: ' + (e.reason && e.reason.message || e.reason)));
  const steps = {};
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const until = async (fn, ms = 8000) => { const end = Date.now() + ms; let last; while (Date.now() < end) { try { last = await fn(); if (last) return last; } catch (e) { last = e; } await sleep(50); } const fb = document.querySelector('#feedback'); const why = last instanceof Error ? last.message : 'timeout: ' + last; throw new Error(`${why} | feedback: "${fb ? fb.textContent : ''}" | dialog: "${(document.querySelector('#modal .error:not([hidden])') || {}).textContent || ''}"`); };
  const q = (sel, root = document) => until(() => root.querySelector(sel), 8000).catch(e => { throw new Error(`no element ${sel} (inside ${root === document ? 'document' : root.nodeName}) | ${e.message}`); });
  const click = async (action, extra) => { const b = await q(`[data-action="${action}"]${extra || ''}`); if (b.disabled) throw new Error('button disabled: ' + action); b.click(); await sleep(120); };
  // Feedback is written after the RPC round trip, so the wait is part of the assertion.
  const text = async (sel, needle) => until(() => { const el = document.querySelector(sel); const t = el ? el.textContent : ''; return t.includes(needle) && t; });
  const type = async (sel, value) => { const el = await q(sel); el.value = value; el.dispatchEvent(new Event('input', { bubbles: true })); };
  // Progress is best effort: a failed progress post must never end the journey.
  const report = payload => post('/api/host/e2e-report', { payload }).catch(() => false);
  const run = async (name, fn) => { const started = Date.now(); try { await fn(); steps[name] = { ok: true }; } catch (e) { steps[name] = { ok: false, detail: String(e.message || e).slice(0, 400) }; } steps[name].ms = Date.now() - started; await report({ phase: 'step', step: name, steps }); };
  const clipboardMatches = (product, name) => post('/api/host/e2e-clipboard', { product, name });

  const journeySteps = async () => {
    try { await until(() => window.__kwReady === true || window.__kwError, 12000); } catch (e) { pageErrors.push('ready: ' + (e.message || e)); }
    await run('boot', async () => {
      if (window.__kwError) throw new Error(window.__kwError.slice(0, 380));
      if (pageErrors.length) throw new Error(pageErrors.join(' | ').slice(0, 380));
      if (!window.glaze || !window.glaze.invoke) throw new Error('generated client missing: glaze.invoke');
      await text('.main > .empty h1', 'Your keys, kept out of view.');
      await text('.footer .mono', 'No vault selected');
      if (window.__kw.state.vaultPath) throw new Error('a vault is preselected in the harness');
    });
    await run('open-vault', async () => {
      await click('vault');
      await until(() => document.querySelectorAll('.product').length === 3, 10000);
      await text('#feedback', 'Vault opened · 3 products');
    });
    await run('deep-check', async () => {
      await click('check');
      await text('#feedback', 'Deep check finished — 3 sections');
      const checks = window.__kw.state.checks;
      if (!checks.alpha || checks.alpha[7] !== 'no-key') throw new Error('alpha status ' + (checks.alpha && checks.alpha[7]));
      if (window.__kw.state.checks.beta[7] !== 'key-unreadable') throw new Error('beta should report key-unreadable');
      const summary = (await q('.summary')).textContent;
      if (summary !== '3Products0Paired2Attention') throw new Error('summary tiles ' + summary);
    });
    await run('select-product', async () => {
      const row = await q('.product:nth-of-type(1)');
      row.click(); await sleep(200);
      await text('.heading h1', 'alpha');
      await until(() => document.querySelectorAll('.entry').length === 2, 10000);
      await text('.entry .tag', 'Empty value');
    });
    await run('generate-key', async () => {
      await click('generate');
      await click('confirm');
      await text('#feedback', 'Generated update key');
      await until(() => window.__kw.state.checks.alpha[7] === 'ok', 10000);
      await text('.metadata', 'Public and private keys match');
      await until(() => document.querySelectorAll('.entry').length === 6, 10000);
    });
    await run('copy', async () => {
      await click('copy', '[data-name="UPDATE_ED25519_PRIVATE_KEY_B64"]');
      await text('#feedback', 'other apps can read it');
      const m = await clipboardMatches('alpha', 'UPDATE_ED25519_PRIVATE_KEY_B64');
      if (m !== true) throw new Error('clipboard does not hold the entry value');
    });
    await run('copy-as', async () => {
      const more = await q('button[data-action="entry"][data-name="UPDATE_ED25519_PUBLIC_KEY_SPKI_B64"]');
      more.click(); await sleep(120);
      const details = await text('#modal', 'Values are never displayed');
      await click('copyasmenu');
      await click('copyas', '[data-format="pem-public"]');
      const m = await clipboardMatches('alpha', 'UPDATE_ED25519_PUBLIC_KEY_SPKI_B64');
      if (m !== false) throw new Error('clipboard should hold the PEM form, not the stored value');
      await text('#feedback', 'Copied UPDATE_ED25519_PUBLIC_KEY_SPKI_B64');
    });
    await run('add-entry', async () => {
      await click('add');
      await type('#entryName', 'KEYWARD_E2E_ENTRY');
      await type('#entryValue', 'journey-value-not-a-key');
      await click('saveentry');
      await text('#feedback', 'Added KEYWARD_E2E_ENTRY');
      await until(() => document.querySelectorAll('.entry').length === 7, 10000);
      const rows = await window.__kw.rpc('entry-list', { product: 'alpha' });
      if (!rows.some(r => r[0] === 'KEYWARD_E2E_ENTRY' && r[1] === 'set')) throw new Error('entry not stored');
      if (JSON.stringify(rows).includes('journey-value')) throw new Error('value leaked through entry-list');
    });
    await run('duplicate-entry', async () => {
      await click('add');
      await type('#entryName', 'KEYWARD_E2E_ENTRY');
      await type('#entryValue', 'again');
      await click('saveentry');
      const err = await q('#nameError');
      if (err.hidden) throw new Error('duplicate name was accepted');
      await click('cancel');
    });
    await run('delete-entry', async () => {
      const more = await q('button[data-action="entry"][data-name="KEYWARD_E2E_ENTRY"]');
      more.click(); await sleep(120);
      await click('delete');
      await click('confirm');
      await text('#feedback', 'Deleted KEYWARD_E2E_ENTRY');
      await until(() => document.querySelectorAll('.entry').length === 6, 10000);
    });
    await run('import-file', async () => {
      window.__e2eImportPath = await post('/api/host/e2e-import-seed', {});
      await click('importnew');
      await type('#entryName', 'KEYWARD_E2E_IMPORTED');
      await click('saveentry');
      await text('#feedback', 'Imported KEYWARD_E2E_IMPORTED');
      await until(() => document.querySelectorAll('.entry').length === 7, 10000);
    });
    await run('stage', async () => {
      await click('stage');
      await click('confirm');
      await text('#feedback', 'Staged ');
      await text('.rotation .tag', 'Stage 1 · staged');
      await until(() => window.__kw.state.rotation[0] === 'yes' && window.__kw.state.rotation[1] === 'ok', 10000);
      window.__stagedKeyId = window.__kw.state.rotation[3];
    });
    await run('promote-gate', async () => {
      await click('promote');
      const confirm = await q('#modal [data-action="confirm"]');
      confirm.click(); await sleep(120);
      const err = await q('#confirmError');
      if (err.hidden || !document.getElementById('modal').open) throw new Error('promote ran without both confirmations');
      document.getElementById('releaseReady').checked = true;
      document.getElementById('ciReady').checked = true;
    });
    await run('promote', async () => {
      await click('confirm');
      await text('#feedback', 'Promoted ' + window.__stagedKeyId);
      await text('.rotation .tag', 'No rotation in progress');
      const rows = await window.__kw.rpc('entry-list', { product: 'alpha' });
      if (rows.some(r => r[0].startsWith('UPDATE_ED25519_NEXT_'))) throw new Error('NEXT entries survived promote');
      if (!rows.some(r => r[0] === 'RIVET_UPDATE_KEY_ID')) throw new Error('active key id missing');
    });
    await run('snapshots', async () => {
      await click('snapshots');
      const items = await until(() => { const n = document.querySelectorAll('#modal .snapshot').length; return n >= 5 && n; }, 10000);
      await click('restore', '[data-index="0"]');
      await click('confirm');
      await text('#feedback', 'Restored ');
      await click('snapshots');
      await click('close');
    });
    await run('filter', async () => {
      await click('filter', '[data-filter="attention"]');
      await until(() => document.querySelectorAll('.entry').length === 2, 5000);
      await click('filter', '[data-filter="all"]');
      await until(() => document.querySelectorAll('.entry').length >= 6, 5000);
    });
    await run('stray-scan', async () => {
      await click('scan');
      await click('pickscan');
      await text('#modal', 'finding');
      await text('#modal .scanitem', 'signing-notes.md');
      await text('#modal .scanitem', 'Fingerprint ');
      await click('close');
    });
    await run('keyboard', async () => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'r', ctrlKey: true, bubbles: true }));
      await sleep(400);
      await text('#feedback', 'Deep check finished');
    });
    await run('clear-expiry', async () => {
      const s = await until(async () => { const r = await glaze.invoke('/api/host/clipboard', {}, { method: 'GET' }); return r.state === 'cleared' && r; }, 60000);
      await text('#feedback', 'Auto-cleared');
      if ((await clipboardMatches('alpha', 'UPDATE_ED25519_PUBLIC_KEY_SPKI_B64')) !== false) throw new Error('clipboard still holds the copy');
    });
  };
  // The report is always posted, also when something throws outside a step.
  const journey = async () => {
    let crash = null;
    try { await journeySteps(); } catch (e) { crash = String(e && e.message || e).slice(0, 400); }
    const ok = !crash && Object.values(steps).every(s => s.ok);
    await report({ phase: 'done', ok, crash, stepCount: Object.keys(steps).length, steps });
  };
  const start = async () => { if (!(await enabled())) return; window.__e2e = true; await journey(); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
