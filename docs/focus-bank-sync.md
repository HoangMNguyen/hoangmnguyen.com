# Focus Bank — cloud sync setup (anonymous + optional Google)

Three steps: create a Google OAuth client, apply the Terraform stack in
`infra/focus-bank/`, paste three values into the app. ~20 minutes.

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

## 2. Apply the AWS stack

The stack is applied locally with an admin login (the site's CI role has no
access to it). State lives in the pricepulse state bucket under
`focus-bank/terraform.tfstate`; the resources live in `us-east-2`.

```sh
terraform -chdir=infra/focus-bank init -backend-config="bucket=pricepulse-tfstate-<acct>"
terraform -chdir=infra/focus-bank apply -var="google_client_id=<client id from step 1>"
```

`google_client_id` defaults to the live client, so the `-var` is only needed
for a new one. After the apply, `terraform -chdir=infra/focus-bank output`
prints `identity_pool_id`, `region`, and `table_name`.

What it creates: a DynamoDB table (provisioned at the free tier's 5 read /
5 write units — a hard throughput ceiling, so it cannot generate a bill),
a Cognito identity pool that allows anonymous guests and accepts Google
sign-ins, and two IAM roles that only permit each identity to read/write
the DynamoDB row whose key equals its own identity ID.

The table, pool, roles, and role attachment were first created by a
CloudFormation stack (`Focus-Bank`), which was retired after Terraform
imported them; `infra/focus-bank/imports.tf` records the ids.

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
API Gateway. This stack has no budget of its own: AWS budgets are
account-wide, so the single account budget in `infra/account/` covers it.

## Notes & limits

- Anonymous identities are per-browser: clearing site data before signing
  in with Google orphans that identity's row (harmless — a few KB).
- Google ID tokens expire after ~1 hour; the app silently re-prompts via
  One Tap on return visits. Mid-session token expiry just delays sync
  until the next sign-in.
- If a Google account was already linked on another browser's identity,
  signing in adopts that identity (your synced data wins) — the app
  handles this automatically.
