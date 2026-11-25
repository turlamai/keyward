'use strict';
// Keyward UI (#34): the landed prototype (design/prototype/app.js) wired to the
// carrier. Structure, copy, dialogs and feedback are the prototype's; the
// sample state is replaced by typed RPC results. Values never reach this page:
// copying goes through the carrier (api/host/copy), which puts the value on
// the clipboard and owns the auto-clear timer.
const $ = s => document.querySelector(s);
const icons = {key:'<circle cx="8" cy="15" r="5"/><path d="m12 11 9-9m-4 4 3 3m-6 0 3 3"/>',check:'<path d="m5 12 4 4L19 6"/>',lock:'<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',copy:'<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V3H3v13h5"/>',history:'<path d="M3 11a9 9 0 1 1 2 7M3 4v7h7m2-4v6l4 2"/>',scan:'<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/><circle cx="11" cy="11" r="4"/><path d="m14 14 4 4"/>',folder:'<path d="M3 7V4h6l3 3h9v13H3z"/>',arrow:'<path d="M4 12h16m-6-6 6 6-6 6"/>',close:'<path d="m6 6 12 12M6 18 18 6"/>',more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>'};
const icon = n => `<svg class="od-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[n]||icons.key}</svg>`;
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const btn = (label, action, cls='', extra='') => `<button type="button" class="${cls}" data-action="${action}" ${extra}>${label}</button>`;
// ---- transport ------------------------------------------------------------
// glaze.invoke (generated /glaze/api.js) is transport neutral: GLZ1 messages on
// the native channel, same-origin fetch on the development HTTP adapter.
async function post(path, body) { return glaze.invoke(path, body || {}, { method: 'POST' }); }
async function get(path) { return glaze.invoke(path, {}, { method: 'GET' }); }
const rpc = (name, args) => post("/api/rpc/" + name, args);
// ---- purpose and export knowledge (was macos-host ContentView.swift) -----
function entryPurpose(name) {
  switch (name) {
    case 'UPDATE_ED25519_PRIVATE_KEY_B64': return 'Consumed by the release workflow (CI manifest signing)';
    case 'UPDATE_ED25519_PUBLIC_KEY_SPKI_B64': return 'Pasted into the Racket-side updater (SPKI form)';
    case 'UPDATE_ED25519_PUBLIC_KEY_RAW_TAIL32_B64': return 'Pasted into the macOS Swift host UpdateService (raw 32-byte form)';
    case 'RIVET_UPDATE_KEY_ID': return 'Written into the signed update manifest';
    case 'UPDATE_ED25519_NEXT_PRIVATE_KEY_B64': return 'Staged next key — swap it into CI after the phase-1 release ships (Promote)';
    case 'UPDATE_ED25519_NEXT_PUBLIC_KEY_SPKI_B64': return 'Staged next anchor — embed in app source during rotation phase 1';
    case 'UPDATE_ED25519_NEXT_PUBLIC_KEY_RAW_TAIL32_B64': return 'Staged next anchor (raw 32B) — macOS host UpdateService in phase 1';
    case 'UPDATE_ED25519_NEXT_KEY_ID': return 'Key id the staged key takes over at Promote';
    default:
      if (name.endsWith('_FPR')) return 'Pairing anchor for Deep Check';
      if (name.startsWith('UPDATE_ED25519_NEXT_')) return 'Staged rotation key — phase-1 material; Promote moves it to the active names';
      if (name.startsWith('LICENSE_') || name.startsWith('PERMIT_')) return 'Commercial signing — different lifecycle from update keys';
      return 'No known consumer — confirm what reads it before deleting';
  }
}
const exportFormats = name => name.includes('PRIVATE')
  ? [['sparkle-private','Sparkle private key (sign_update)'],['pem-private','PKCS#8 PEM'],['tauri-key','Tauri / minisign secret key (unencrypted)']]
  : name.includes('PUBLIC')
  ? [['sparkle-public','Sparkle SUPublicEDKey'],['tauri-pub','Tauri / minisign .pub file'],['tauri-pub-b64','Tauri pubkey for tauri.conf.json (base64)'],['pem-public','SPKI PEM']]
  : [];
// ---- state ------------------------------------------------------------------
// products: store-info rows [name, entries, keyId, fingerprint, lightStatus]
// checks:   check-store rows [name, entries, empty, keyId, kind, fingerprint, paired, status]
const state = { context: {}, vaultPath: '', products: [], checks: {}, fileStatus: '', selected: 0, filter: 'all', entries: [], rotation: null, snapshots: [], busy: false };
let timer = null, remaining = 0, trigger = null, pending = null, scanResults = null, scanPath = '';
const product = () => state.products[state.selected] || null;
const empties = p => { const c = state.checks[p[0]]; return c ? (c[2] ? c[2].split(',').length : 0) : (/^empty:(\d+)$/.exec(p[4]) || [])[1] || 0; };
const checkStatus = p => (state.checks[p[0]] || [])[7] || '';
const paired = p => checkStatus(p) === 'ok';
const hasWarning = p => checkStatus(p) ? ['pair-mismatch','missing-public','key-unreadable'].includes(checkStatus(p)) || empties(p) > 0 : /^empty:(\d+)$/.test(p[4]);
function stateLabel(p) {
  if (!Number(p[1])) return 'No entries';
  const n = empties(p);
  if (n) return `${n} empty entries`;
  switch (checkStatus(p)) {
    case '': return 'Not checked';
    case 'ok': return 'Pair verified';
    case 'no-key': return 'No signing key';
    case 'pair-mismatch': return 'Keys do not pair';
    case 'missing-public': return 'Missing public key';
    default: return 'Key unreadable';
  }
}
const entryGroup = e => e[1] === 'empty' ? 'empty' : e[0].startsWith('UPDATE_ED25519_NEXT_') ? 'staged' : 'other';
function message(text) { state.feedback = text; const f = $('#feedback'); if (f) f.textContent = text; }
function fail(e, where) { const text = `Could not complete: ${e.message || e}`; message(text); const slot = where && $(where); if (slot) { slot.textContent = text; slot.hidden = false; } }
// ---- data -------------------------------------------------------------------
async function refresh() {
  if (!state.vaultPath) { state.products = []; state.checks = {}; state.entries = []; state.rotation = null; return; }
  const [products, check] = await Promise.all([rpc('store-info', {}), rpc('check-store', {})]);
  state.products = products || [];
  state.checks = {};
  for (const row of check || []) { if (row[0] === '(file)') state.fileStatus = row[7]; else state.checks[row[0]] = row; }
  if (state.selected >= state.products.length) state.selected = Math.max(0, state.products.length - 1);
  await refreshProduct();
}
async function refreshProduct() {
  const p = product();
  if (!p) { state.entries = []; state.rotation = null; return; }
  const [entries, rotation] = await Promise.all([rpc('entry-list', { product: p[0] }), rpc('rotation-status', { product: p[0] })]);
  state.entries = entries || [];
  state.rotation = rotation;
}
async function load() {
  try {
    state.context = await get('/api/host/context');
    const path = await rpc('store-path', {});
    if (path) {
      state.vaultPath = path;
      try { await refresh(); } catch (e) { state.vaultPath = ''; message(`The saved vault could not be read: ${e.message || e}`); }
    }
    render();
    window.__kwReady = true;
  } catch (e) { window.__kwError = String(e && e.stack || e); message(`Keyward could not start: ${e.message || e}`); throw e; }
}
async function openVault(path) {
  await rpc('store-open', { path });
  state.vaultPath = path; state.selected = 0; state.filter = 'all';
  await refresh(); render();
  message(`Vault opened · ${state.products.length} products. Values stay off screen.`);
}
// ---- views ------------------------------------------------------------------
function render() {
  const p = product(), pairedCount = state.products.filter(paired).length, warnings = state.products.filter(hasWarning).length;
  const vault = Boolean(state.vaultPath);
  $('#app').innerHTML = `<div class="shell"><aside class="sidebar"><div class="brand"><span class="brandmark">${icon('key')}</span><div><strong>Keyward</strong><small>Release-signing key vault</small></div></div><div class="summary"><div class="od-stat"><strong>${vault?state.products.length:0}</strong><small>Products</small></div><div class="od-stat"><strong>${vault?pairedCount:0}</strong><small>Paired</small></div><div class="od-stat"><strong>${vault?warnings:0}</strong><small>Attention</small></div></div><nav aria-label="Products"><div class="navlabel">Products</div>${vault?state.products.map((q,i)=>`<button type="button" class="product" aria-current="${state.selected===i}" data-product="${i}"><span class="dot ${!Number(q[1])?'neutral':hasWarning(q)?'warn':''}"></span><span class="od-field"><span class="name">${esc(q[0])}</span><small>${stateLabel(q)}</small></span><span class="count">${esc(q[1])}</span></button>`).join(''):'<p class="small muted">No vault selected</p>'}</nav><div class="sidebottom">${btn(icon('history')+' <span class="lbl">Snapshots</span>','snapshots','quiet',!vault?'disabled':'')}${btn(icon('scan')+' <span class="lbl">Scan for stray keys</span>','scan','quiet',!vault?'disabled':'')}${btn(icon('folder')+' <span class="lbl">Choose vault…</span>','vault','quiet')}<p class="trust">Values stay off screen.<br>Vaults and snapshots are plain text on disk.</p></div><select class="mobilepicker" id="productPicker" aria-label="Select product" ${!vault?'disabled':''}>${state.products.map((q,i)=>`<option value="${i}" ${state.selected===i?'selected':''}>${esc(q[0])}</option>`).join('')}</select></aside><main class="main"><div class="topline"><span class="breadcrumb">Vault / ${vault?'Products':'Get started'}</span></div>${vault&&p?mainView(p):emptyView()}</main><footer class="footer"><p id="feedback" role="status" aria-live="polite">${state.feedback||''}</p><span class="mono">${vault?esc(state.vaultPath):'No vault selected'}</span></footer></div>`;
}
function emptyView() { return `<div class="empty">${icon('key')}<h1>Your keys, kept out of view.</h1><p>Choose a signing-key vault to review its products, verify key pairs and manage a safe rotation.</p>${btn('Choose Vault…','vault','primary')}<p class="small">The vault and its history remain plain text.<br>Use a trusted folder and separate encrypted backups.</p></div>`; }
function mainView(p) {
  const entries = state.entries.map(e => ({ name: e[0], group: entryGroup(e) })).filter(e => state.filter==='all'||state.filter==='attention'&&e.group==='empty'||state.filter==='staged'&&e.group==='staged');
  const c = state.checks[p[0]];
  const pairing = paired(p) ? 'Public and private keys match' : checkStatus(p) === 'no-key' ? 'No signing key for this product' : checkStatus(p) ? 'Run Deep Check, then review the entries' : 'Run Deep Check to review';
  const canGenerate = checkStatus(p) === 'no-key';
  return `<header class="heading"><div><div class="eyebrow">Release-signing keys</div><h1>${esc(p[0])}</h1><p><span class="status ${hasWarning(p)?'warn':''}">${icon(hasWarning(p)?'lock':'check')}${stateLabel(p)}</span></p></div><div class="actions">${btn(icon('history')+' Snapshots','snapshots')}${btn(icon('check')+' Deep Check','check')}${canGenerate?btn(icon('key')+' Generate update key…','generate'):''}</div></header><dl class="metadata"><div><dt>Active key ID</dt><dd class="mono">${esc((c&&c[3])||p[2]||'Not configured')}</dd></div><div><dt>Fingerprint · SHA-256 prefix</dt><dd class="mono">${esc((c&&c[5])||p[3]||'Not available')}</dd></div><div><dt>Pairing</dt><dd class="small">${pairing}</dd></div></dl>${rotationView()}<section aria-labelledby="entriesTitle"><div class="sectionhead entrieshead"><div><h2 id="entriesTitle">Entries <span class="count">${state.entries.length}</span></h2><p>Names and purposes only. Values are never displayed.</p></div><div class="actions">${btn('Import file…','importnew')}${btn('Add entry…','add','')}</div></div><div class="filters" role="group" aria-label="Filter entries">${[['all','All entries'],['staged','Staged'],['attention','Needs attention']].map(([id,label])=>btn(label,'filter','filter',`data-filter="${id}" aria-pressed="${state.filter===id}"`)).join('')}</div>${entries.length?entries.map(e=>`<article class="entry">${icon('lock')}<div class="entrymain">${btn(esc(e.name),'entry','entryname',`data-name="${esc(e.name)}"`)}<p>${esc(entryPurpose(e.name))}</p></div>${e.group==='empty'?'<span class="tag warn">Empty value</span>':e.group==='staged'?'<span class="tag">Staged</span>':''}<div class="entryactions">${e.group!=='empty'?btn(icon('copy')+' Copy','copy','quiet',`data-name="${esc(e.name)}"`):btn('Import…','import','quiet',`data-name="${esc(e.name)}"`)}${btn(icon('more'),'entry','icon quiet',`aria-label="Actions for ${esc(e.name)}" data-name="${esc(e.name)}"`)}</div></article>`).join(''):`<div class="empty"><h3>${state.entries.length?'No matching entries':'No entries yet'}</h3><p>${state.entries.length?'Choose All entries to return to the complete list.':'Add an entry to start organizing this product’s signing keys.'}</p>${btn(state.entries.length?'Show all entries':'Add entry…',state.entries.length?'resetfilter':'add')}</div>`}</section>`;
}
function rotationView() {
  const r = state.rotation || ['no','-','-','-','-','-'];
  const staged = r[0] === 'yes';
  return `<section class="rotation" aria-labelledby="rotationTitle"><div class="sectionhead"><div><div class="eyebrow">Two-stage key rotation</div><h2 id="rotationTitle">${staged?'Ship trust before switching keys.':'Prepare the next signing key.'}</h2></div><span class="tag">${staged?'Stage 1 · staged':'No rotation in progress'}</span></div>${staged?`<p class="small muted">Next key <span class="mono">${esc(r[3])}</span> · <span class="mono">${esc(r[2])}</span></p><ol class="steps"><li class="step done"><span class="stepnum">01 / READY</span><h3>Stage &amp; verify</h3><p>The next key pair has passed pairing.</p></li><li class="step current"><span class="stepnum">02 / NEXT</span><h3>Ship public anchors</h3><p>Add the next public anchors. Ship a release signed with the current key.</p></li><li class="step"><span class="stepnum">03 / THEN</span><h3>Switch &amp; promote</h3><p>After that release ships, switch the CI secret to the staged key. Then promote.</p></li></ol><div class="rotationfoot"><p>Promote replaces the active key and removes staged entries. A snapshot is saved first.</p><div class="actions">${btn('Discard…','discard','quiet danger')}${btn('Review promotion '+icon('arrow'),'promote')}</div></div>`:`<p class="muted">Stage a new key pair while keeping the current signing key active. Review the changes before continuing.</p><div class="rotationfoot"><p>Existing releases keep trusting the current key until the new public anchors ship.</p>${btn('Stage next key…','stage')}</div>`}</section>`;
}
// ---- dialogs ----------------------------------------------------------------
function openDialog(title, description, body, foot='') {
  trigger = document.activeElement;
  const d = $('#modal');
  d.innerHTML = `<div class="modalhead"><div><h2 id="modalTitle">${title}</h2><p>${description}</p></div>${btn(icon('close'),'close','icon','aria-label="Close dialog"')}</div><div class="modalbody">${body}</div><div class="modalfoot">${foot||btn('Done','close','primary')}</div>`;
  if (!d.open) d.showModal();
  const focus = d.querySelector('[data-action="cancel"]')||d.querySelector('input:not([type=checkbox]):not([readonly])')||d.querySelector('[data-action="close"]');
  focus?.focus();
}
function closeDialog() {
  const previous = trigger;
  $('#modal').close(); pending = null;
  if (previous?.isConnected) previous.focus();
  else {
    const name = previous?.dataset.name;
    const same = name ? [...document.querySelectorAll('button[data-name]')].find(b => b.dataset.name === name) : null;
    (same||document.querySelector('[data-action="check"]')||document.querySelector('[data-action="vault"]'))?.focus();
  }
}
function confirmation(kind, title, description, body, label) {
  pending = kind;
  openDialog(title, description, body, btn(label,'confirm','danger')+btn('Cancel','cancel','primary','autofocus'));
}
function showSnapshots() {
  const list = state.snapshots;
  openDialog('Store snapshots', 'Every change saves a copy before modifying the vault.', `<div class="notice">Snapshots are plain text beside the vault. They are recovery copies, not encrypted backups. Restoring affects the whole vault.</div><p class="error" id="dialogError" hidden></p>${list.length?list.map((s,i)=>`<div class="snapshot"><div class="od-field"><strong class="mono">${esc(s[0])}</strong><small>${esc(s[1])} bytes</small></div>${btn('Restore…','restore','',`data-index="${i}"`)}</div>`).join(''):'<p class="muted">No snapshots yet. The first change to the vault saves one.</p>'}`, btn('Close','close'));
}
function scanBody() {
  return `<div class="notice">Only paths, line numbers and fingerprints are shown. The vault and its .history folder are excluded from the scan.</div><div class="field"><label for="scanPath">Folder to scan</label><input id="scanPath" value="${esc(scanPath||'')}" readonly></div><p class="error" id="dialogError" hidden></p>${scanResults===null?'<p class="muted">Choose Scan folder to look for signing-key material outside the vault.</p>':scanResults.length?`<p class="status warn">${scanResults.length} finding${scanResults.length===1?'':'s'} · review these files</p>${scanResults.map(([path,line,kind,fp])=>`<div class="scanitem"><strong class="mono">${esc(path)}</strong><p>${line?'line '+esc(line)+' · ':''}${esc(kind)}</p><span class="mono">Fingerprint ${esc(fp)}</span></div>`).join('')}`:'<p class="status">'+icon('check')+'No signing-key material found outside the vault.</p>'}`;
}
function showScan() {
  openDialog('Scan for stray keys', 'Find signing-key material outside the vault without displaying its value.', scanBody(), btn('Close','close')+btn(scanResults===null?'Scan folder':'Scan again','pickscan','primary'));
}
function showEntry(name) {
  const e = state.entries.find(e => e[0] === name);
  if (!e) return;
  const group = entryGroup(e);
  openDialog('Entry details', 'Values are never displayed.', `<div class="field"><span class="small muted">Name</span><strong class="mono fullvalue">${esc(e[0])}</strong></div><div class="field"><span class="small muted">Purpose</span><p>${esc(entryPurpose(e[0]))}</p></div><span class="tag ${group==='empty'?'warn':''}">${group==='empty'?'Empty value':group==='staged'?'Staged key':'Stored entry'}</span><p class="error" id="dialogError" hidden></p>`, btn('Delete…','delete','danger',`data-name="${esc(e[0])}"`)+btn(group==='empty'?'Import…':'Copy',group==='empty'?'import':'copy','',`data-name="${esc(e[0])}"`)+(exportFormats(e[0]).length&&group!=='empty'?btn('Copy as…','copyasmenu','',`data-name="${esc(e[0])}"`):'')+btn('Done','close','primary'));
}
function showCopyAs(name) {
  openDialog('Copy as…', 'The converted value is placed on the clipboard for 30 seconds.', `<div class="field"><span class="small muted">Entry</span><strong class="mono">${esc(name)}</strong></div><p class="error" id="dialogError" hidden></p>${exportFormats(name).map(([format,label])=>`<div class="snapshot"><div class="od-field"><strong>${esc(label)}</strong><small class="mono">${esc(format)}</small></div>${btn(icon('copy')+' Copy','copyas','',`data-name="${esc(name)}" data-format="${format}"`)}</div>`).join('')}`, btn('Cancel','cancel'));
}
// ---- clipboard --------------------------------------------------------------
async function copyEntry(name, format) {
  const r = await post('/api/host/copy', { product: product()[0], name, format: format || '' });
  startCountdown(name, r.seconds);
}
function startCountdown(name, seconds) {
  clearInterval(timer);
  remaining = seconds;
  message(`Copied ${name} — the raw value is on the clipboard; other apps can read it. Auto-clears in ${remaining}s unless something else is copied first.`);
  timer = setInterval(async () => {
    remaining--;
    let s = null;
    try { s = await get('/api/host/clipboard'); } catch (_) { /* keep counting */ }
    if (s && s.state === 'cleared') { clearInterval(timer); remaining = 0; message('Auto-cleared the copied key from the clipboard.'); return; }
    if (s && s.state === 'kept') { clearInterval(timer); remaining = 0; message('Something else was copied — Keyward left the clipboard alone.'); return; }
    // The countdown rewrites only its own line: a message from another action
    // (Deep Check, a dialog…) stays on screen while the copy is still pending.
    if (!String(state.feedback || '').startsWith('Copied ')) return;
    if (!remaining) { clearInterval(timer); message('The copy is still on the clipboard — clear it yourself if you no longer need it.'); }
    else message(`Copied ${name} — the raw value is on the clipboard; other apps can read it. Auto-clears in ${remaining}s unless something else is copied first.`);
  }, 1000);
}
// ---- actions ----------------------------------------------------------------
async function act(action, b) {
  const p = product();
  switch (action) {
    case 'close': case 'cancel': closeDialog(); break;
    case 'vault': {
      if (window.__e2e) { await openVault((await post('/api/host/e2e-fixtures', {})).vaultPath); return; }
      const pick = await post('/api/dialog/open', { title: 'Choose a signing-key vault' });
      if (pick.path) { await openVault(pick.path); }
      break; }
    case 'filter': state.filter = b.dataset.filter; render(); document.querySelector(`[data-filter="${state.filter}"]`)?.focus(); break;
    case 'resetfilter': state.filter = 'all'; render(); document.querySelector('[data-filter="all"]')?.focus(); break;
    case 'snapshots': state.snapshots = await rpc('snapshot-list', {}); showSnapshots(); break;
    case 'scan': showScan(); break;
    case 'pickscan': {
      const dir = window.__e2e ? await post('/api/host/e2e-stray-seed', {}) : (await post('/api/dialog/open', { title: 'Choose a folder to scan', folder: true })).path;
      if (dir) { scanPath = dir; scanResults = await rpc('stray-scan-tree', { dir }); }
      showScan(); break; }
    case 'copy': await copyEntry(b.dataset.name); if ($('#modal').open) closeDialog(); break;
    case 'copyasmenu': showCopyAs(b.dataset.name); break;
    case 'copyas': await copyEntry(b.dataset.name, b.dataset.format); closeDialog(); break;
    case 'entry': showEntry(b.dataset.name); break;
    case 'check': b.disabled = true; b.textContent = 'Checking…'; message('Reviewing every entry…'); await refresh(); render(); message(`Deep check finished — ${state.products.length} sections reviewed${state.fileStatus&&state.fileStatus!=='clean'?` · ${state.fileStatus}`:''}.`); document.querySelector('[data-action="check"]')?.focus(); break;
    case 'generate':
      confirmation('generate', 'Generate an update key?', `A new Ed25519 pair is written for ${esc(p[0])} under the family update-key names.`, `<p>The key is generated and collected straight into the vault; no key file is left behind. A snapshot is saved first.</p>`, 'Generate key'); break;
    case 'promote':
      if (!state.rotation || state.rotation[0] !== 'yes') return;
      confirmation('promote', 'Promote the staged signing key?', 'Review the release handoff before changing the active key.', `<p>The active signing entries will take the staged values. NEXT entries will be removed. A whole-vault snapshot is saved first.</p><p class="small muted">Key pairing of the staged pair is ${state.rotation[1]==='ok'?'verified':'not verified'}. Keyward cannot verify your external release or CI configuration.</p><label class="checkrow"><input id="releaseReady" type="checkbox"><span>The phase-1 release shipped with the new public anchors, signed by the old key.</span></label><label class="checkrow"><input id="ciReady" type="checkbox"><span>After that release shipped, I switched the CI signing secret to the staged private key.</span></label><p class="error" id="confirmError" hidden>Confirm both handoff steps before promoting.</p>`, 'Promote');
      $('#modal [data-action="confirm"]').disabled = state.rotation[1] !== 'ok'; break;
    case 'discard': confirmation('discard', 'Discard the staged key?', 'The active signing key stays unchanged.', `<p>The staged key and NEXT entries will be removed. A snapshot is saved first and can restore the vault.</p>`, 'Discard staged key'); break;
    case 'stage': confirmation('stage', 'Stage the next signing key?', 'Keep the current signing key active.', `<p>A new pair is staged for the two-stage release handoff. A snapshot is saved first.</p>`, 'Stage key'); break;
    case 'delete': confirmation({ type: 'delete', name: b.dataset.name }, 'Delete this entry?', 'Check its consumer before removing it.', `<p class="mono">${esc(b.dataset.name)}</p><p>${esc(entryPurpose(b.dataset.name))}</p><p>A consuming release workflow may fail after deletion. A snapshot is saved first; restoring it replaces the whole vault.</p>`, 'Delete entry'); break;
    case 'restore': confirmation({ type: 'restore', index: Number(b.dataset.index) }, 'Restore this vault snapshot?', 'This replaces every product’s current entries.', `<p>Restore the vault to <strong class="mono">${esc(state.snapshots[Number(b.dataset.index)][0])}</strong>?</p><p>A snapshot of the current vault will be saved first. Changes after the selected snapshot will be replaced.</p>`, 'Restore vault'); break;
    case 'confirm': {
      if (pending === 'promote' && (!$('#releaseReady').checked || !$('#ciReady').checked)) { $('#confirmError').hidden = false; $('#releaseReady').focus(); return; }
      const operation = pending, name = p[0];
      try {
        if (operation === 'promote') { const r = await rpc('rotation-promote', { product: name }); await refresh(); render(); closeDialog(); message(`Promoted ${r[0]} · fingerprint ${r[1]}. Move the retired key to a secure archive.`); }
        if (operation === 'discard') { await rpc('rotation-cancel', { product: name }); await refresh(); render(); closeDialog(); message('Staged key discarded · the active signing key is unchanged.'); }
        if (operation === 'stage') { const r = await rpc('rotation-start', { product: name }); await refresh(); render(); closeDialog(); message(`Staged ${r[0]} · fingerprint ${r[1]}. Pairing is verified by Deep Check.`); }
        if (operation === 'generate') { const r = await rpc('keypair-generate', { product: name }); await refresh(); render(); closeDialog(); message(`Generated update key ${r[0]} · fingerprint ${r[1]}.`); }
        if (operation?.type === 'delete') { await rpc('entry-delete', { product: name, name: operation.name }); await refresh(); state.filter = 'all'; render(); closeDialog(); message(`Deleted ${operation.name} · a recovery snapshot was saved.`); }
        if (operation?.type === 'restore') { const stamp = state.snapshots[operation.index][0]; await rpc('snapshot-restore', { stamp }); state.snapshots = await rpc('snapshot-list', {}); await refresh(); state.filter = 'all'; render(); closeDialog(); message(`Restored ${stamp} · a snapshot of the previous state was saved first.`); }
      } catch (e) { fail(e, '#dialogError'); }
      break; }
    case 'add': case 'importnew': case 'import': {
      const importing = action === 'import';
      const picking = action === 'importnew';
      let path = '';
      if (window.__e2e) path = window.__e2eImportPath || '';
      else if (picking || importing) {
        const pick = await post('/api/dialog/open', { title: 'Choose a key file to import' });
        if (!pick.path) return;
        path = pick.path;
      }
      // Without a file there is nothing to import: say so instead of opening an import dialog with no source.
      if ((importing || picking) && !path) { message('No file was chosen — nothing was imported.'); return; }
      openDialog(importing||picking ? 'Import key file' : 'Add entry', importing||picking ? 'The file is collected into the vault as one entry; no copy is left outside.' : 'The value is written to the vault and never shown.', `<div class="field"><label for="entryName">Entry name</label><input id="entryName" autocomplete="off" value="${importing?esc(b.dataset.name):''}" ${importing?'readonly':''}><p class="error" id="nameError" hidden>Use a unique entry name: letters, digits and underscores.</p></div>${importing||picking?`<div class="field"><span class="small muted">File</span><p class="mono fullvalue">${esc(path)}</p></div>`:`<div class="field"><label for="entryValue">Value</label><input id="entryValue" type="password" autocomplete="off" spellcheck="false"><p class="small muted">Hidden while typing. It is stored as a single line and never displayed again.</p></div>`}<p class="error" id="dialogError" hidden></p>`, btn('Cancel','cancel')+btn(importing||picking?'Import file':'Add entry','saveentry','primary',`data-path="${esc(path)}"`));
      break; }
    case 'saveentry': {
      const name = $('#entryName').value.trim(), path = b.dataset.path;
      const invalid = !/^[A-Za-z][A-Za-z0-9_.-]{1,100}$/.test(name) || (!path && state.entries.some(e => e[0] === name));
      $('#nameError').hidden = !invalid;
      if (invalid) { $('#entryName').focus(); return; }
      try {
        if (path) { const fp = await rpc('entry-import-file', { product: p[0], name, filePath: path }); await refresh(); render(); closeDialog(); message(`Imported ${name} · ${fp === 'ok' ? 'stored' : 'fingerprint ' + fp}. The source file is untouched.`); }
        else {
          const field = $('#entryValue');
          const value = field ? field.value : '';
          if (!value) { field?.focus(); if (!field) fail(new Error('The entry form is incomplete — close it and try again.'), '#dialogError'); return; }
          await rpc('entry-set', { product: p[0], name, value });
          $('#entryValue').value = '';
          await refresh(); state.filter = 'all'; render(); closeDialog(); message(`Added ${name} · value stored and kept off screen.`);
        }
      } catch (e) { fail(e, '#dialogError'); }
      break; }
  }
}
document.addEventListener('click', async e => {
  const b = e.target.closest('button');
  if (!b || b.disabled) return;
  if (b.dataset.product !== undefined) { state.selected = Number(b.dataset.product); state.filter = 'all'; try { await refreshProduct(); } catch (err) { fail(err); } render(); document.querySelector(`[data-product="${state.selected}"]`)?.focus(); return; }
  if (!b.dataset.action) return;
  try { await act(b.dataset.action, b); } catch (err) { fail(err, $('#modal').open ? '#dialogError' : null); }
});
document.addEventListener('change', async e => { if (e.target.id === 'productPicker') { state.selected = Number(e.target.value); state.filter = 'all'; try { await refreshProduct(); } catch (err) { fail(err); } render(); $('#productPicker').focus(); } });
document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && $('#modal').open) {
    if (e.target.tagName === 'INPUT' && e.target.type !== 'checkbox' && $('#modal [data-action="saveentry"]')) { e.preventDefault(); act('saveentry', $('#modal [data-action="saveentry"]')); }
    else if (pending) { e.preventDefault(); closeDialog(); }
  }
  if ((e.metaKey || e.ctrlKey) && ['o','r','l'].includes(e.key.toLowerCase())) {
    e.preventDefault();
    if ($('#modal').open) closeDialog();
    const action = { o: 'vault', r: 'check', l: 'snapshots' }[e.key.toLowerCase()];
    if (!state.vaultPath && action !== 'vault') return;
    act(action, document.querySelector(`[data-action="${action}"]`) || document.createElement('button'));
  }
});
$('#modal').addEventListener('cancel', e => { e.preventDefault(); closeDialog(); });
window.__kw = { state, refresh, rpc, post, get, act };
load();
