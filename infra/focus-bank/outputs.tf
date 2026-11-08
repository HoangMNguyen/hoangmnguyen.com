# The three values site/projects/focus-bank/sync.js needs in its CFG block.

output "identity_pool_id" {
  description = "CFG.identityPoolId in the app."
  value       = aws_cognito_identity_pool.main.id
}

output "region" {
  description = "CFG.region in the app."
  value       = data.aws_region.current.region
}

output "table_name" {
  description = "CFG.table in the app."
  value       = aws_dynamodb_table.data.name
}
