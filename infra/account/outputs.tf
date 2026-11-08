output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "budget_name" {
  value = aws_budgets_budget.account.name
}
