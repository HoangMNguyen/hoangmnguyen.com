/* ============================ CLOUD SYNC =============================
   Anonymous-first sync via Cognito Identity Pools + DynamoDB.
   Fill in CFG from `terraform -chdir=infra/focus-bank output` and your Google
   OAuth client ID. Leave the placeholders and the app still works —
   sync simply stays off.                                              */
const CFG = {
  region:         'us-east-2',            // e.g. 'us-east-1'
  identityPoolId: 'us-east-2:05bc6bce-0739-49b9-8bfa-c35e3febdd6d',  // e.g. 'us-east-1:1234abcd-...'
  googleClientId: '998004519126-rsgaml9bajuaquabvujf76dh5oegej9s.apps.googleusercontent.com',  // ends in .apps.googleusercontent.com
  table:          'FocusBankData',
};

const statusEl = document.getElementById('syncStatus');
const setStatus = (t, ok) => {
  statusEl.textContent = t;
  statusEl.style.color = ok ? 'var(--green)' : 'var(--muted)';
};
if (CFG.identityPoolId.startsWith('PASTE')) {
  setStatus('off — configure AWS to enable');
} else {
  initSync();
}

async function initSync() {
  const [{ CognitoIdentityClient, GetIdCommand, GetCredentialsForIdentityCommand },
         { DynamoDBClient, GetItemCommand, PutItemCommand }] = await Promise.all([
    import('https://esm.sh/@aws-sdk/client-cognito-identity@3.1164.0'),
    import('https://esm.sh/@aws-sdk/client-dynamodb@3.1164.0'),
  ]);

  const ci = new CognitoIdentityClient({ region: CFG.region });
  let googleToken = null;
  let creds = null, credsExpire = 0;
  const linked = () => localStorage.getItem('fb_linked') === '1';

  async function ensureCreds() {
    if (creds && Date.now() < credsExpire - 60000) return;
    const logins = googleToken ? { 'accounts.google.com': googleToken } : undefined;
    if (linked() && !logins) {           // upgraded identity needs its Google token
      setStatus('sign in with Google to sync');
      throw new Error('needs-google');
    }
    let identityId = localStorage.getItem('fb_idid');
    if (!identityId) {
      const r = await ci.send(new GetIdCommand({ IdentityPoolId: CFG.identityPoolId, Logins: logins }));
      identityId = r.IdentityId;
      localStorage.setItem('fb_idid', identityId);
    }
    let out;
    try {
      out = await ci.send(new GetCredentialsForIdentityCommand({ IdentityId: identityId, Logins: logins }));
    } catch (e) {
      if (logins) {                      // Google account already tied to another identity
        localStorage.removeItem('fb_idid');
        const r = await ci.send(new GetIdCommand({ IdentityPoolId: CFG.identityPoolId, Logins: logins }));
        localStorage.setItem('fb_idid', r.IdentityId);
        out = await ci.send(new GetCredentialsForIdentityCommand({ IdentityId: r.IdentityId, Logins: logins }));
      } else throw e;
    }
    const c = out.Credentials;
    creds = { accessKeyId: c.AccessKeyId, secretAccessKey: c.SecretKey, sessionToken: c.SessionToken };
    credsExpire = new Date(c.Expiration).getTime();
  }

  const userId = () => localStorage.getItem('fb_idid');
  const ddb = () => new DynamoDBClient({ region: CFG.region, credentials: creds });

  async function pull() {
    await ensureCreds();
    const r = await ddb().send(new GetItemCommand({
      TableName: CFG.table, Key: { userId: { S: userId() } } }));
    if (!r.Item) return null;
    return { data: JSON.parse(r.Item.data.S), updatedAt: Number(r.Item.updatedAt.N) };
  }

  async function push() {
    await ensureCreds();
    await ddb().send(new PutItemCommand({
      TableName: CFG.table,
      Item: { userId: { S: userId() },
              data: { S: JSON.stringify(window.FB.data) },
              updatedAt: { N: String(Date.now()) } } }));
  }

  // union merge: per-month field-wise max; rewards deduped by name+price
  function merge(a, b) {
    const out = JSON.parse(JSON.stringify(a));
    for (const k of Object.keys(b.months || {})) {
      const x = out.months[k], y = b.months[k];
      out.months[k] = !x ? y : {
        focusSeconds: Math.max(x.focusSeconds, y.focusSeconds),
        distractions: Math.max(x.distractions, y.distractions),
        sessions: Math.max(x.sessions, y.sessions),
        spent: Math.max(x.spent, y.spent),
      };
    }
    for (const r of (b.rewards || [])) {
      const dup = out.rewards.find(o => o.name === r.name && o.price === r.price);
      if (!dup) out.rewards.push(r);
      else if (r.claimed && !dup.claimed) dup.claimed = r.claimed;
    }
    return out;
  }

  const hasActivity = d => Object.keys(d.months || {}).length || (d.rewards || []).length;

  async function firstSync() {
    const cloud = await pull();
    const local = window.FB.data;
    if (!cloud) { if (hasActivity(local)) await push(); return; }
    if (JSON.stringify(cloud.data) === JSON.stringify(local)) return;
    if (!hasActivity(local)) { window.FB.data = cloud.data; window.FB.render(); return; }
    // both sides have history — merge (never silently discard focus time)
    window.FB.data = merge(local, cloud.data);
    window.FB.render();
    await push();
    window.FB.toast('Synced — cloud and local data merged.');
  }

  // debounced save hook, called by the app's save()
  let timer = null;
  window.cloudSave = () => {
    clearTimeout(timer);
    timer = setTimeout(() => push().then(
      () => setStatus(googleToken ? 'synced · Google connected' : 'synced · anonymous', true),
      () => setStatus('offline — will retry on next change')), 1500);
  };
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden' && timer) { clearTimeout(timer); push().catch(()=>{}); }
  });

  // ---- Google upgrade via Google Identity Services ----
  const gis = document.createElement('script');
  gis.src = 'https://accounts.google.com/gsi/client';
  gis.onload = () => {
    google.accounts.id.initialize({
      client_id: CFG.googleClientId,
      auto_select: linked(),
      callback: async resp => {
        googleToken = resp.credential;
        localStorage.setItem('fb_linked', '1');
        creds = null;                    // force re-auth with the Google login
        try {
          await ensureCreds();           // links guest identity → authenticated
          await firstSync();
          setStatus('synced · Google connected', true);
          document.getElementById('syncHint').textContent =
            'Signed in — your data follows you to any device where you sign in.';
        } catch (e) { setStatus('sync error — check console'); console.error(e); }
      },
    });
    google.accounts.id.renderButton(document.getElementById('gBtn'),
      { theme: 'filled_black', size: 'medium', shape: 'pill' });
    if (linked()) google.accounts.id.prompt();  // silent one-tap on return visits
  };
  document.head.appendChild(gis);

  // ---- anonymous sync starts immediately, no interaction needed ----
  if (!linked()) {
    try {
      await ensureCreds();
      await firstSync();
      setStatus('synced · anonymous', true);
    } catch (e) { setStatus('offline — local only'); console.error(e); }
  }
}
