# Ids of the two CloudFront resources infra/site creates on its first (local) apply. They are
# AWS-generated, so the deploy policy can only be pinned to them after that apply: write them to
# site-ids.auto.tfvars and re-apply this stack (docs/infra.md, step 6). Empty means CI gets no
# access to either resource.

variable "site_origin_access_control_id" {
  description = "infra/site output origin_access_control_id; empty until the first site apply."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[A-Z0-9]*$", var.site_origin_access_control_id))
    error_message = "Expected a CloudFront origin access control id (uppercase letters and digits) or an empty string."
  }
}

variable "site_response_headers_policy_id" {
  description = "infra/site output response_headers_policy_id; empty until the first site apply."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})?$", var.site_response_headers_policy_id))
    error_message = "Expected a CloudFront response headers policy id (a lowercase UUID) or an empty string."
  }
}
