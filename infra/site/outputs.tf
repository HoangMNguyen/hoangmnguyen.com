output "distribution_id" {
  description = "Target of the deploy workflow's cache invalidation."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_domain_name" {
  description = "Value of the www CNAME at Porkbun."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_bucket" {
  description = "Bucket the deploy workflow syncs site/ into."
  value       = aws_s3_bucket.site.bucket
}

output "acm_validation_records" {
  description = "DNS record(s) to add at Porkbun so ACM can validate the certificate."
  value = [for dvo in aws_acm_certificate.site.domain_validation_options : {
    name  = dvo.resource_record_name
    type  = dvo.resource_record_type
    value = dvo.resource_record_value
  }]
}

output "athena_workgroup" {
  description = "Workgroup holding the daily-visits named query."
  value       = aws_athena_workgroup.site.name
}

output "origin_access_control_id" {
  description = "Feed into infra/bootstrap (site_origin_access_control_id) so CI can manage only this OAC."
  value       = aws_cloudfront_origin_access_control.site.id
}

output "response_headers_policy_id" {
  description = "Feed into infra/bootstrap (site_response_headers_policy_id) so CI can update only this policy."
  value       = aws_cloudfront_response_headers_policy.security.id
}
