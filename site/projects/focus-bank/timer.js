'use strict';
// ------------------------------------------------------------- persistence
const KEY = 'focusbank';
const DEFAULTS = { ratePerHour: 1, distractionPenalty: 1, defaultMinutes: 25 };

function load() {
  let d = {};
  try { d = JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { d = {}; }
  d.settings = Object.assign({}, DEFAULTS, d.settings || {});
  d.months = d.months || {};   // "2026-07": {focusSeconds,distractions,sessions,spent}
  d.rewards = d.rewards || []; // {name,price,claimed,notified}
  return d;
}
let data = load();
function save() {
  localStorage.setItem(KEY, JSON.stringify(data));
  if (window.cloudSave) window.cloudSave();
}

const monthKey = (dt = new Date()) =>
  `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
const monthLabel = k => new Date(k + '-02').toLocaleDateString([], { month: 'long', year: 'numeric' });
const month = (k = monthKey()) =>
  data.months[k] || (data.months[k] = { focusSeconds: 0, distractions: 0, sessions: 0, spent: 0 });
const S = () => data.settings;
const monthNet = k => {
  const m = month(k);
  return m.focusSeconds / 3600 * S().ratePerHour
       - m.distractions * S().distractionPenalty - m.spent;
};
const balance = () => Object.keys(data.months).reduce((t, k) => t + monthNet(k), 0);

const money = v => `${v < 0 ? '−' : ''}$${Math.abs(v).toFixed(2)}`;
function fmtHMS(sec) {
  sec = Math.max(0, Math.round(sec));
  const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
  return h > 0 ? `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`
               : `${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
}

// ------------------------------------------------------------------ session
const st = { active: false, running: false, target: 0, elapsedBefore: 0,
             startedAt: 0, distractions: 0 };
const elapsed = () => st.elapsedBefore + (st.running ? (performance.now() - st.startedAt) / 1000 : 0);
const remaining = () => Math.max(0, st.target - elapsed());

const $ = id => document.getElementById(id);
const CIRC = 2 * Math.PI * 101;

function beep(freq = 880, ms = 180) {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.connect(g); g.connect(ctx.destination);
    o.frequency.value = freq; g.gain.value = 0.06;
    o.start(); o.stop(ctx.currentTime + ms / 1000);
  } catch (e) {}
}
function toast(msg, ms = 5000) {
  const t = document.createElement('div');
  t.className = 'toast'; t.textContent = msg;
  $('toasts').appendChild(t);
  setTimeout(() => t.remove(), ms);
}

function startPause() {
  if (!st.active) {
    const mins = parseFloat($('minutes').value);
    if (!(mins > 0)) { toast('Session length must be a positive number of minutes.'); return; }
    S().defaultMinutes = mins; save();
    Object.assign(st, { active: true, running: true, target: mins * 60,
                        elapsedBefore: 0, startedAt: performance.now(), distractions: 0 });
    $('minutes').disabled = true;
    $('startBtn').textContent = '⏸ Pause';
    $('finishBtn').disabled = false;
  } else if (st.running) {
    st.elapsedBefore = elapsed(); st.running = false;
    $('startBtn').textContent = '▶ Resume';
  } else {
    st.running = true; st.startedAt = performance.now();
    $('startBtn').textContent = '⏸ Pause';
  }
}

function finishSession(early) {
  const secs = Math.min(elapsed(), st.target);
  st.running = false; st.active = false;
  const m = month();
  m.focusSeconds += Math.round(secs); m.sessions += 1; save();
  const earned = secs / 3600 * S().ratePerHour;
  const lost = st.distractions * S().distractionPenalty;
  beep(early ? 660 : 880);
  toast(`${early ? 'Banked early' : "⏰ Time's up"} — focused ${fmtHMS(secs)}. ` +
        `Earned ${money(earned)}, distractions ${money(-lost)}. Net ${money(earned - lost)}.`, 7000);
  st.elapsedBefore = 0; st.distractions = 0;
  $('minutes').disabled = false;
  $('startBtn').textContent = '▶ Start';
  $('finishBtn').disabled = true;
  document.title = 'Focus Bank — earn your rewards';
  render();
}

// ------------------------------------------------------------------- shop
let selectedReward = -1;

function claimReward() {
  const r = data.rewards[selectedReward];
  if (!r) { toast('Select a reward in the list first.'); return; }
  if (r.claimed) { toast(`Already claimed on ${r.claimed}. Want it again? Add it as a new reward.`); return; }
  const bal = balance();
  if (bal < r.price) {
    toast(`"${r.name}" costs $${r.price.toFixed(2)} — you need ${money(r.price - bal)} more. Keep focusing!`);
    return;
  }
  if (!confirm(`Spend $${r.price.toFixed(2)} on "${r.name}"? It will be deducted from your balance — go treat yourself!`)) return;
  month().spent = +(month().spent + r.price).toFixed(2);
  r.claimed = new Date().toISOString().slice(0, 10);
  save(); render();
}

function checkAffordable() {
  const bal = balance();
  data.rewards.forEach(r => {
    if (r.claimed) return;
    if (bal >= r.price && !r.notified) {
      r.notified = true; save(); beep(1040);
      toast(`🎉 Reward unlocked! You can now afford "${r.name}" ($${r.price.toFixed(2)}). Claim it whenever you're ready.`, 8000);
    } else if (bal < r.price && r.notified) {
      r.notified = false; save();
    }
  });
}

// ------------------------------------------------------------------- render
function render() {
  const bal = balance(), k = monthKey(), m = month(k);
  $('balance').textContent = money(bal);
  $('balance').classList.toggle('neg', bal < 0);
  $('monthStats').textContent =
    `${monthLabel(k)}: ${money(monthNet(k))} · ${fmtHMS(m.focusSeconds)} focused · ` +
    `${m.distractions} distractions · $${m.spent.toFixed(2)} spent`;

  // shop
  const sb = $('shopBody'); sb.innerHTML = '';
  data.rewards.forEach((r, i) => {
    const tr = document.createElement('tr');
    if (i === selectedReward) tr.className = 'sel';
    let status, cls = '';
    if (r.claimed) { status = `✅ claimed ${r.claimed}`; cls = 'dim'; }
    else if (bal >= r.price) { status = '🎉 affordable!'; cls = 'aff'; }
    else status = `${money(r.price - bal)} to go`;
    tr.innerHTML = `<td>${escapeHtml(r.name)}</td>` +
                   `<td class="num">$${r.price.toFixed(2)}</td>` +
                   `<td class="${cls}">${status}</td>`;
    tr.onclick = () => { selectedReward = (selectedReward === i ? -1 : i); render(); };
    sb.appendChild(tr);
  });
  $('shopEmpty').style.display = data.rewards.length ? 'none' : '';

  // history with running balance (oldest → newest, shown newest first)
  const hb = $('histBody'); hb.innerHTML = '';
  const keys = Object.keys(data.months).sort();
  let running = 0;
  const rows = keys.map(kk => {
    const net = monthNet(kk); running += net;
    return { kk, mo: data.months[kk], net, running };
  });
  rows.reverse().forEach(({ kk, mo, net, running }) => {
    const tr = document.createElement('tr');
    tr.innerHTML =
      `<td>${monthLabel(kk)}</td><td class="num">${fmtHMS(mo.focusSeconds)}</td>` +
      `<td class="num">${mo.distractions}</td><td class="num">$${mo.spent.toFixed(2)}</td>` +
      `<td class="num ${net < 0 ? 'negc' : 'pos'}">${money(net)}</td>` +
      `<td class="num ${running < 0 ? 'negc' : 'pos'}">${money(running)}</td>`;
    hb.appendChild(tr);
  });
  $('histEmpty').style.display = keys.length ? 'none' : '';

  checkAffordable();
}

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, c =>
    ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
}

// ------------------------------------------------------------------- loop
function tick() {
  if (st.active) {
    const rem = remaining(), frac = st.target ? rem / st.target : 0;
    $('timeText').textContent = fmtHMS(rem);
    $('stateText').textContent = st.running ? 'focusing…' : 'paused';
    document.title = `${fmtHMS(rem)} · Focus Bank`;
    const ring = $('ringProg');
    ring.style.strokeDashoffset = CIRC * (1 - frac);
    ring.style.stroke = frac > 0.25 ? 'var(--accent)' : frac > 0.1 ? 'var(--amber)' : 'var(--red)';
    const val = Math.min(elapsed(), st.target) / 3600 * S().ratePerHour
              - st.distractions * S().distractionPenalty;
    $('sessionValue').textContent = `Session value: ${money(val)}`;
    if (st.running && rem <= 0) finishSession(false);
  } else {
    const mins = parseFloat($('minutes').value) || S().defaultMinutes;
    $('timeText').textContent = fmtHMS(mins * 60);
    $('stateText').textContent = 'ready';
    $('ringProg').style.strokeDashoffset = 0;
    $('ringProg').style.stroke = 'var(--accent)';
    $('sessionValue').innerHTML = '&nbsp;';
  }
  requestAnimationFrame(tick);
}

// -------------------------------------------------------------- wire up UI
$('startBtn').onclick = startPause;
$('finishBtn').onclick = () => finishSession(true);
$('distractBtn').onclick = () => {
  month().distractions += 1;
  if (st.active) st.distractions += 1;
  save(); beep(300, 120); render();
};
$('saveSettings').onclick = () => {
  const rate = parseFloat($('rate').value), pen = parseFloat($('penalty').value);
  if (!(rate >= 0) || !(pen >= 0)) { toast('Rate and penalty must be non-negative numbers.'); return; }
  S().ratePerHour = rate; S().distractionPenalty = pen; save();
  $('distractBtn').textContent = `😵 I got distracted (−$${pen.toFixed(2)})`;
  toast('Settings saved.'); render();
};
$('addReward').onclick = () => { $('rName').value = ''; $('rPrice').value = ''; $('rewardDialog').showModal(); };
$('rCancel').onclick = () => $('rewardDialog').close();
$('rSave').onclick = () => {
  const name = $('rName').value.trim(), price = parseFloat($('rPrice').value);
  if (!name || !(price > 0)) { toast('Give the reward a name and a positive price.'); return; }
  data.rewards.push({ name, price: +price.toFixed(2), claimed: null, notified: false });
  save(); $('rewardDialog').close(); render();
};
$('claimReward').onclick = claimReward;
$('delReward').onclick = () => {
  const r = data.rewards[selectedReward];
  if (!r) { toast('Select a reward in the list first.'); return; }
  if (confirm(`Remove "${r.name}" from the shop?`)) {
    data.rewards.splice(selectedReward, 1); selectedReward = -1; save(); render();
  }
};
$('exportBtn').onclick = () => {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'focus_bank_data.json'; a.click(); URL.revokeObjectURL(a.href);
};
$('importBtn').onclick = () => $('importFile').click();
$('importFile').onchange = e => {
  const f = e.target.files[0]; if (!f) return;
  f.text().then(txt => {
    try {
      const d = JSON.parse(txt);
      if (!d.months || !d.settings) throw 0;
      data = d; data.rewards = data.rewards || []; save(); render();
      toast('Data imported.');
    } catch { toast("That file doesn't look like a Focus Bank export."); }
  });
  e.target.value = '';
};
window.addEventListener('beforeunload', e => {
  if (st.active && elapsed() > 5) { e.preventDefault(); e.returnValue = ''; }
});

// init
$('minutes').value = S().defaultMinutes;
$('rate').value = S().ratePerHour;
$('penalty').value = S().distractionPenalty;
$('distractBtn').textContent = `😵 I got distracted (−$${S().distractionPenalty.toFixed(2)})`;
render(); tick();

// bridge for the cloud sync module
window.FB = {
  get data() { return data; },
  set data(d) { data = d; localStorage.setItem(KEY, JSON.stringify(data)); },
  render, toast
};
