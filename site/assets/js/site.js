// Live minute ring: the site's signature, echoing Focus Bank's countdown.
const CIRC = 2 * Math.PI * 76;
const ring = document.getElementById('minRing');
const clockText = document.getElementById('clockText');

function tick() {
  const now = new Date();
  const frac = (now.getSeconds() + now.getMilliseconds() / 1000) / 60;
  ring.style.strokeDashoffset = CIRC * (1 - frac);
  clockText.textContent = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

if (ring && clockText) {
  tick();
  setInterval(tick, 1000);
}

const year = document.getElementById('yr');
if (year) year.textContent = new Date().getFullYear();
