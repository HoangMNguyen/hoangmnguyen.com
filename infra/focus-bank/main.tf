# Focus Bank sync backend: a Cognito identity pool (anonymous guests with an optional Google
# upgrade) and a DynamoDB table holding one row per identity, enforced by IAM. Applied locally
# with an admin login; the site's CI role has no access to these resources.
#   terraform -chdir=infra/focus-bank init -backend-config="bucket=pricepulse-tfstate-<acct>"
#   terraform -chdir=infra/focus-bank apply

# ---- Data store: one item per user, keyed by Cognito identity id ----
# PROVISIONED (not on-demand) is deliberate: 5 RCU / 5 WCU sits inside the DynamoDB always-free
# tier AND acts as a physical throughput ceiling: excess traffic is throttled, not billed.
resource "aws_dynamodb_table" "data" {
  name           = "FocusBankData"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

# ---- Identity pool: guests allowed, Google as the upgrade provider ----
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "FocusBankIdentities"
  allow_unauthenticated_identities = true

  supported_login_providers = {
    "accounts.google.com" = var.google_client_id
  }
}

# ---- Roles: guests and signed-in users get the SAME row-scoped access ----
locals {
  # Cognito "amr" value each role is assumed with.
  roles = {
    guest = { name = "focusbank-guest-role", amr = "unauthenticated" }
    user  = { name = "focusbank-user-role", amr = "authenticated" }
  }
}

# Policies are built with jsonencode, not aws_iam_policy_document: a data source that reads a
# resource with pending changes (e.g. a tag update) is deferred to apply, and the plan then shows
# every policy as "known after apply" even when nothing in it changes.
resource "aws_iam_role" "this" {
  for_each = local.roles

  name = each.value.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals             = { "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id }
        "ForAnyValue:StringLike" = { "cognito-identity.amazonaws.com:amr" = each.value.amr }
      }
    }]
  })
}

# The LeadingKeys condition means: you may only Get/Put items whose partition key equals YOUR OWN
# Cognito identity id. Row-level security enforced by IAM; no application server needed.
resource "aws_iam_role_policy" "own_row_only" {
  for_each = local.roles

  name = "own-row-only"
  role = aws_iam_role.this[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
      Resource = aws_dynamodb_table.data.arn
      Condition = {
        "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["$${cognito-identity.amazonaws.com:sub}"] }
      }
    }]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    unauthenticated = aws_iam_role.this["guest"].arn
    authenticated   = aws_iam_role.this["user"].arn
  }
}
