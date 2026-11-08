# hoangmnguyen.com

Source for [www.hoangmnguyen.com](https://www.hoangmnguyen.com): Hoang Nguyen's landing page, plus [Focus Bank](https://www.hoangmnguyen.com/projects/focus-bank/), a gamified focus timer with optional cloud sync.

## Layout

| Path | What it is |
|---|---|
| `site/` | Static site root uploaded to S3 (HTML, CSS, JS, self-hosted fonts, resume PDF) |
| `site/projects/focus-bank/` | Focus Bank web app (Cognito identity pool + DynamoDB sync) |
| `infra/account/` | Shared account foundations: GitHub OIDC provider, Terraform state bucket, the account budget (applied locally) |
| `infra/bootstrap/` | IAM deploy role for GitHub Actions (applied once, locally) |
| `infra/site/` | S3, CloudFront, ACM certificate, access logs, Athena visit counts |
| `infra/site/csp.txt` | Content-Security-Policy, one directive per line; used by CloudFront and the local preview |
| `infra/focus-bank/` | Focus Bank's sync backend in us-east-2: DynamoDB table, Cognito identity pool, IAM roles (applied locally) |
| `scripts/serve.py` | Local preview with the production security headers |

## Local preview

```sh
python3 scripts/serve.py        # http://localhost:8000
```

## Deploy

Pull requests run `terraform plan`; merges to `main` apply Terraform, sync `site/` to S3, and invalidate CloudFront. One-time setup and DNS steps: [docs/infra.md](docs/infra.md). Focus Bank backend setup: [docs/focus-bank-sync.md](docs/focus-bank-sync.md).
