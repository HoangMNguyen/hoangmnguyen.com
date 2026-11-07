# Focus Bank — cloud sync setup (anonymous + optional Google)

Three steps: create a Google OAuth client, deploy the CloudFormation stack,
paste three values into the app. ~20 minutes.

## 1. Google OAuth client (free)

1. Go to https://console.cloud.google.com → create a project (e.g. "focus-bank").
2. APIs & Services → OAuth consent screen → External → fill in app name +
   your email → add `hoangmnguyen.com` as an authorized domain → save.
   (You can leave it in "Testing" mode and add your own Google account as a
   test user, or publish it — no verification needed since you request no
   sensitive scopes.)
3. APIs & Services → Credentials → Create credentials → OAuth client ID →
   Web application.
   - Authorized JavaScript origins: `https://www.hoangmnguyen.com`
     and `http://localhost:8000` (for local testing).
4. Copy the **Client ID** (ends in `.apps.googleusercontent.com`).
## 2. Deploy the AWS stack

1. AWS Console → CloudFormation → Create stack → "With new resources" →
   upload `infra/focus-bank/cloudformation.yaml`.
2. Parameters:
   - `GoogleClientId`: paste the client ID from step 1.
   - `BudgetEmail`: your email (creates a $5/month alert), or leave blank.
3. Check the "I acknowledge that this template may create IAM resources
   with custom names" box → Create stack. Takes ~2 minutes.
4. When status is CREATE_COMPLETE, open the **Outputs** tab and copy
   `IdentityPoolId`, `Region`, and `TableName`.

What it creates: a DynamoDB table (provisioned at the free tier's 5 read /
5 write units — a hard throughput ceiling, so it cannot generate a bill),
a Cognito identity pool that allows anonymous guests and accepts Google
sign-ins, and two IAM roles that only permit each identity to read/write
the DynamoDB row whose key equals its own identity ID.

## 3. Configure the app

Open `site/projects/focus-bank/sync.js`, find the `CFG` block near the top:

```js
const CFG = {
  region:         'PASTE_REGION',
  identityPoolId: 'PASTE_IDENTITY_POOL_ID',
  googleClientId: 'PASTE_GOOGLE_CLIENT_ID',
  table:          'FocusBankData',
};
```

Paste the three values, then commit and push to `main`. GitHub Actions uploads
the site and clears the CloudFront cache.

## How it behaves

- **First visit (no action needed):** the browser gets an anonymous Cognito
  identity and starts syncing to its own DynamoDB row. Status shows
  "synced · anonymous".
- **Sign in with Google:** the guest identity is upgraded in place — same
  identity ID, same data. From then on any device you sign into with that
  Google account sees the same balance and history.
- **Merging:** if both the device and the cloud have history, they're
  merged (per-month field-wise maximum, rewards deduplicated) so focus
  time is never silently discarded.
- **Offline:** the app always works from localStorage; sync retries on the
  next change.
- **Saves are debounced** (1.5 s) and flushed when the tab is hidden, so a
  full session writes only a handful of DynamoDB items.

## Cost recap

Cognito identity pools: free. DynamoDB at 5/5 provisioned units: $0 (always
free tier) and physically incapable of scaling its own bill. No Lambda, no
API Gateway. The optional AWS Budget emails you at 80% and forecast-100%
of $5/month.

## Notes & limits

- Anonymous identities are per-browser: clearing site data before signing
  in with Google orphans that identity's row (harmless — a few KB).
- Google ID tokens expire after ~1 hour; the app silently re-prompts via
  One Tap on return visits. Mid-session token expiry just delays sync
  until the next sign-in.
- If a Google account was already linked on another browser's identity,
  signing in adopts that identity (your synced data wins) — the app
  handles this automatically.
