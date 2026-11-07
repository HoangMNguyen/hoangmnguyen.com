terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "hoangmnguyen-site", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}

# Names the site stack (infra/site) creates; the deploy policy is scoped to them, so keep the two
# in step.
locals {
  account_id   = data.aws_caller_identity.current.account_id
  name         = "hoangmnguyen-site"
  github_owner = "HoangMNguyen"
  github_repo  = "hoangmnguyen.com"
  site_bucket  = "${local.name}-${local.account_id}"
  logs_bucket  = "${local.name}-logs-${local.account_id}"
  state_bucket = "pricepulse-tfstate-${local.account_id}"
  state_key    = "site/terraform.tfstate"
  glue_db      = "hoangmnguyen_site"
  domain       = "www.hoangmnguyen.com"
}
