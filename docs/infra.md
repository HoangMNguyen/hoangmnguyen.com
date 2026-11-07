# Infrastructure: www.hoangmnguyen.com

Static files in `site/` served from a private S3 bucket through CloudFront in us-east-1. DNS stays
at Porkbun; its records are edited by hand. Terraform state lives in the existing pricepulse state
bucket (`pricepulse-tfstate-<account_id>`) under `site/`, locked with S3 lock files.

| Stack | State key | Applied by |
| --- | --- | --- |
| `infra/bootstrap` | `site/bootstrap.tfstate` | you, locally, once (admin login) |
| `infra/site` | `site/terraform.tfstate` | you for the first apply, then GitHub Actions |

`.github/workflows/deploy.yml` plans `infra/site` on pull requests (plan in the run summary) and,
on pushes to `main`, applies it, syncs `site/` to the bucket and invalidates `/*`. Every job is
skipped until the `AWS_ROLE_ARN` repository variable exists.

## What `infra/site` creates

- **Site bucket** `hoangmnguyen-site-<account_id>`: public access blocked, SSE-S3, bucket policy
  that lets only this distribution read objects (origin access control, `AWS:SourceArn`).
- **Log bucket** `hoangmnguyen-site-logs-<account_id>`: CloudFront access logs under
  `cloudfront/`, Athena results under `athena-results/`; everything expires after 90 days.
- **ACM certificate** for `www.hoangmnguyen.com`, DNS-validated through a CNAME you add at Porkbun.
- **CloudFront distribution**: alias `www.hoangmnguyen.com`, PriceClass_100, HTTP/2 and HTTP/3,
  HTTP redirected to HTTPS, managed CachingOptimized policy with compression, `index.html` as the
  root object, and a viewer-request function (`infra/site/functions/rewrite.js`) mapping `/path/`
  and `/path` to `/path/index.html`. 403 and 404 from S3 both return `/404.html` with status 404.
- **Response headers policy**: HSTS (`max-age=31536000`), the Content-Security-Policy built from
  the non-empty lines of `infra/site/csp.txt` joined with `; ` (the same file `scripts/serve.py`
  uses locally), `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: strict-origin-when-cross-origin`.
- **Analytics**: Glue database `hoangmnguyen_site` with table `cloudfront_logs` over the access
  logs, Athena workgroup `hoangmnguyen-site` with the named query `daily-visits`.

Cache headers set by the upload: HTML, CSS, JS and other files `no-cache` (browsers revalidate
with the ETag; deploys invalidate CloudFront), fonts under `/assets/fonts/` (content-hashed
names) `public, max-age=31536000, immutable`, PDFs `public, max-age=3600`.

### Access-log choice: legacy standard logging to S3

CloudFront offers two ways to write standard access logs to S3:

- **Legacy standard logging** (chosen): free apart from S3 storage; files use the documented
  tab-separated W3C layout that the Athena table in `infra/site/analytics.tf` reads as-is; one
  `logging_config` block and two extra S3 permissions (`s3:GetBucketAcl`, `s3:PutBucketAcl`) on
  the deploy role.
- **Standard logging v2** (CloudWatch vended log delivery): lets the log bucket keep ACLs
  disabled and can write Parquet with Hive-style partitions, but bills $0.25 per GB delivered and
  needs three more resources (delivery source, destination, delivery), a delivery bucket policy
  and a set of `logs:*Delivery*` plus `cloudfront:AllowVendedLogDeliveryForResource` permissions,
  several of which only accept `*`.

For a personal site the extra cost and moving parts buy nothing the 90-day, unpartitioned table
cannot answer. The price of the legacy path is that the log bucket has ACLs enabled
(`BucketOwnerPreferred`); CloudFront adds a single grant for its log-delivery account, and public
access stays blocked.

## Deploy role (`infra/bootstrap`)

`hoangmnguyen-site-deploy` trusts the account's existing GitHub OIDC provider (owned by pricepulse,
read with a data source, never created here) for exactly two subjects of
`HoangMNguyen/hoangmnguyen.com`: pushes to `main` and pull requests, audience `sts.amazonaws.com`.
GitHub may embed numeric owner/repo IDs in the subject, so the ID-embedded variants of the same two
subjects are allowed too; owner and repository names stay pinned.

Its inline policy grants only what `infra/site` and the upload/invalidation steps call, and no IAM
actions, so the role cannot change its own trust or permissions:

| Area | Actions | Resources |
| --- | --- | --- |
| State | `s3:ListBucket` (prefixes `site/*`, `env:/*`); `s3:GetObject`, `s3:PutObject`; `s3:DeleteObject` on the lock file | `site/terraform.tfstate` and `site/terraform.tfstate.tflock` only |
| Buckets | create/delete, `GetBucket*` and the other bucket-config reads, policy, public access block, ownership controls, encryption, lifecycle, tagging, `PutBucketAcl` (log delivery grant) | the site and log buckets |
| Upload | `s3:PutObject`, `s3:DeleteObject` | site bucket objects |
| Distribution | create (only with tag `Project=hoangmnguyen-site`); get, update, delete, invalidations, tags (only when tagged `Project=hoangmnguyen-site`); tag-on-create (only for untagged distributions) | `distribution/*` + tag conditions |
| Functions | create, describe, get, update, publish, delete | `function/hoangmnguyen-site-*` |
| OAC, response headers policies | create, get, update, delete | `origin-access-control/*`, `response-headers-policy/*` |
| Cache policies | `ListCachePolicies`, `GetCachePolicy` (read-only) | `*` |
| ACM | `RequestCertificate` (only `www.hoangmnguyen.com`, DNS validation); describe, list tags; tag/untag/delete only when tagged `Project=hoangmnguyen-site` | `*` for the request, `certificate/*` in us-east-1 otherwise |
| Glue | database and table CRUD, partition-index and tag reads, tagging | catalog, `database/hoangmnguyen_site`, `table/hoangmnguyen_site/*` |
| Athena | workgroup CRUD and tags, named query create/get/delete | `workgroup/hoangmnguyen-site` |

Where `*` (or a resource-type wildcard) remains, AWS gives no narrower option:
`cloudfront:ListCachePolicies` and `acm:RequestCertificate` have no resource-level permissions
(the managed cache policy is AWS-owned, read-only access); origin access controls and response
headers policies are addressed by AWS-generated ids and cannot be tagged; distributions and
certificates are also id-addressed, so they are fenced by the `Project` tag instead. The role does
not run Athena queries, so it has no access to `athena-results/` objects.

## One-time setup

Run from the repository root. Requires the AWS CLI v2, Terraform >= 1.10 and `gh`.

1. **Log in** with an admin identity:

   ```sh
   aws login
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   ```

2. **Apply the bootstrap** (creates the deploy role):

   ```sh
   terraform -chdir=infra/bootstrap init -backend-config="bucket=pricepulse-tfstate-$ACCOUNT_ID"
   terraform -chdir=infra/bootstrap apply
   ```

3. **Set the repository variables** (variables, not secrets; neither value is sensitive). Setting
   them enables the workflow, so do not push to `main` until step 5 has finished.

   ```sh
   gh variable set AWS_ROLE_ARN --repo HoangMNguyen/hoangmnguyen.com \
     --body "$(terraform -chdir=infra/bootstrap output -raw role_arn)"
   gh variable set TF_STATE_BUCKET --repo HoangMNguyen/hoangmnguyen.com \
     --body "pricepulse-tfstate-$ACCOUNT_ID"
   ```

4. **First site apply, part 1: the certificate.** The full apply waits for DNS validation, so
   create the certificate first and read its validation record:

   ```sh
   terraform -chdir=infra/site init -backend-config="bucket=pricepulse-tfstate-$ACCOUNT_ID"
   terraform -chdir=infra/site apply -target=aws_acm_certificate.site
   terraform -chdir=infra/site output acm_validation_records
   ```

   (`terraform -chdir=infra/site state show aws_acm_certificate.site` shows the same record under
   `domain_validation_options`.)

   At Porkbun (Domain Management → hoangmnguyen.com → DNS), add each record as type **CNAME**.
   Porkbun appends the domain to the host, so for a name of `_abc123.www.hoangmnguyen.com.` enter
   host `_abc123.www`; the answer is the `value` (`_xyz.….acm-validations.aws.`). Leave the record
   in place permanently: ACM uses it to renew the certificate.

5. **First site apply, part 2: everything else.**

   ```sh
   terraform -chdir=infra/site apply
   ```

   This waits until ACM sees the CNAME (usually a few minutes), then creates the distribution
   (5–15 minutes). Then upload the site by running the workflow once:

   ```sh
   gh workflow run deploy.yml --repo HoangMNguyen/hoangmnguyen.com --ref main
   ```

   Check it on the CloudFront domain before touching `www`:
   `terraform -chdir=infra/site output -raw distribution_domain_name`.

6. **Porkbun cutover.** In the DNS records for hoangmnguyen.com:
   1. Delete the broken `www` CNAME.
   2. Delete Porkbun's parked records on the bare domain (the ALIAS/A records with an empty host
      pointing at Porkbun's parking page). Leave the `pricepulse` records and the ACM validation
      CNAME alone.
   3. Add a CNAME with host `www` and answer = the `distribution_domain_name` output
      (`dxxxxxxxxxxxx.cloudfront.net`).
   4. Under **URL Forwarding** for hoangmnguyen.com, forward the bare domain (empty subdomain) to
      `https://www.hoangmnguyen.com`, type **Permanent (301)**, include the URI path, no wildcard.

7. **Google sign-in (Focus Bank).** Google Cloud Console → APIs & Services → Credentials → the
   Focus Bank OAuth client → Authorized JavaScript origins → add `https://www.hoangmnguyen.com`.

Verify:

```sh
curl -sI https://www.hoangmnguyen.com/ | grep -iE '^(HTTP|strict-transport|content-security)'
curl -sI https://www.hoangmnguyen.com/projects/focus-bank | head -1   # 200 via the rewrite
curl -sI https://www.hoangmnguyen.com/nope | head -1                  # 404
curl -sI http://hoangmnguyen.com/ | grep -iE '^(HTTP|location)'       # 301 to www
```

## Day to day

- Change the site or `infra/site`, open a pull request: the `plan` job checks formatting, validates
  and posts the plan to the run summary. Merge: the `deploy` job applies, uploads and invalidates.
- Change the CSP: edit `infra/site/csp.txt`; the next apply updates the response headers policy.
- Change the deploy role (`infra/bootstrap`): apply locally with an admin login; the role cannot
  modify itself.

## Visits

Athena console → workgroup `hoangmnguyen-site` → Saved queries → `daily-visits`: HTML page views
(GET, status 200, `text/html`) and distinct client IPs per day, with common bots, crawlers,
link-preview fetchers and HTTP tools excluded by user agent. Logs arrive within about an hour and
are kept 90 days.
