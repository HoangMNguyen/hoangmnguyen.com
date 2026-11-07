terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# us-east-1 for everything: CloudFront only accepts ACM certificates from this region.
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "hoangmnguyen-site", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}

# infra/bootstrap scopes the deploy role to these names; keep the two in step.
locals {
  name        = "hoangmnguyen-site"
  domain      = "www.hoangmnguyen.com"
  account_id  = data.aws_caller_identity.current.account_id
  site_bucket = "${local.name}-${local.account_id}"
  logs_bucket = "${local.name}-logs-${local.account_id}"
  glue_db     = "hoangmnguyen_site"
}
