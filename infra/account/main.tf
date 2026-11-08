# Account foundations: the pieces several projects in this account depend on, owned by no single
# project. Applied locally with an admin login, before infra/bootstrap and infra/site:
#   terraform -chdir=infra/account init -backend-config="bucket=pricepulse-tfstate-<acct>"
#   terraform -chdir=infra/account apply
#
# The OIDC provider and the state bucket were created by pricepulse (its infra/envs/dev and
# infra/bootstrap stacks) and adopted here with the import blocks below; pricepulse removed them
# from its state and now reads the provider with a data source, as infra/bootstrap here does.
# The import blocks are no-ops once the resources are in this stack's state.

# --- GitHub Actions OIDC provider ----------------------------------------------------------------
# Trusted by hoangmnguyen-site-deploy and pricepulse-dev-github-deploy. An account allows one
# provider per URL, so replacing it would break both deploy roles: never destroy it.
import {
  to = aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's certificate chain via its own trust store; the thumbprint is legacy and
  # kept as created so the provider is not modified.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  lifecycle {
    prevent_destroy = true
  }
}

# --- Terraform state bucket ----------------------------------------------------------------------
# Holds every stack's state: account/ (this stack), site/ (hoangmnguyen.com), dev/ and bootstrap/
# (pricepulse). The name keeps its pricepulse prefix because every backend config points at it.
import {
  to = aws_s3_bucket.tfstate
  id = local.state_bucket
}

import {
  to = aws_s3_bucket_versioning.tfstate
  id = local.state_bucket
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.tfstate
  id = local.state_bucket
}

import {
  to = aws_s3_bucket_public_access_block.tfstate
  id = local.state_bucket
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Cost guardrail ------------------------------------------------------------------------------
# The account's only budget. Budgets are account-wide whatever their name, so one budget replaces
# the per-project ones (pricepulse-dev-monthly, focus-bank-monthly-cap, My Zero-Spend Budget) that
# all watched the same total.
resource "aws_budgets_budget" "account" {
  name         = "account-monthly"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [local.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [local.alert_email]
  }
}
