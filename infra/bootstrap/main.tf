# One-time bootstrap, applied locally with an admin login: the IAM role GitHub Actions assumes to
# plan/apply infra/site and upload the site. The role has no IAM permissions, so it cannot widen
# its own trust or policy; changes to either are a human apply of this stack.
#   terraform -chdir=infra/bootstrap init -backend-config="bucket=pricepulse-tfstate-<acct>"
#   terraform -chdir=infra/bootstrap apply

# The account's GitHub OIDC provider is owned by the pricepulse stack; reference it, never create
# a second one (an account allows one provider per URL).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Pushes to main (apply + upload) and pull requests (plan) only. GitHub may embed the owner
    # and repo IDs in the subject (`repo:<owner>@<id>/<repo>@<id>:<scope>`; pricepulse hit this),
    # so both forms are allowed; wildcards cover only the numeric IDs, names stay pinned.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.github_owner}/${local.github_repo}:ref:refs/heads/main",
        "repo:${local.github_owner}/${local.github_repo}:pull_request",
        "repo:${local.github_owner}@*/${local.github_repo}@*:ref:refs/heads/main",
        "repo:${local.github_owner}@*/${local.github_repo}@*:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${local.name}-deploy"
  description          = "GitHub Actions deploy role for ${local.github_owner}/${local.github_repo}"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

# Exactly what infra/site and the upload/invalidation steps need. Resources are pinned by name
# where the ARN carries one, by the Project tag where the ARN only carries an AWS-generated id
# (distributions, certificates), and by exact id for the origin access control and response
# headers policy (fed back from infra/site after the first local apply). `*` remains only where
# AWS has no resource-level permission; each case is commented.
data "aws_iam_policy_document" "deploy" {
  # --- Terraform state: only the site stack's key and its lock file ---------------------------
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.state_bucket}"]
    # site/* for the state; env:/* is the S3 backend's workspace listing at init.
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["site/*", "env:/*"]
    }
  }
  statement {
    sid     = "StateReadWrite"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::${local.state_bucket}/${local.state_key}",
      "arn:aws:s3:::${local.state_bucket}/${local.state_key}.tflock",
    ]
  }
  statement {
    sid       = "StateUnlock"
    actions   = ["s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/${local.state_key}.tflock"]
  }

  # --- Site and log buckets ---------------------------------------------------------------------
  statement {
    sid = "SiteBuckets"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetBucket*",
      "s3:GetAccelerateConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketTagging",
      "s3:TagResource",
      "s3:UntagResource",
      "s3:ListTagsForResource",
      # CloudFront standard logging adds its log-delivery grant to the log bucket's ACL with the
      # caller's credentials when logging is enabled on the distribution.
      "s3:PutBucketAcl",
    ]
    resources = [
      "arn:aws:s3:::${local.site_bucket}",
      "arn:aws:s3:::${local.logs_bucket}",
    ]
  }
  statement {
    sid       = "SiteUpload"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.site_bucket}/*"]
  }

  # --- CloudFront --------------------------------------------------------------------------------
  # Distribution ARNs carry an AWS-generated id, so they are matched by the Project tag that the
  # provider's default_tags send on create (CreateDistributionWithTags).
  statement {
    sid       = "DistributionCreate"
    actions   = ["cloudfront:CreateDistribution"]
    resources = ["arn:aws:cloudfront::${local.account_id}:distribution/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [local.name]
    }
  }
  # Tag-on-create, and tagging any untagged distribution. Distributions tagged for another project
  # (pricepulse) cannot be re-tagged into this role's reach.
  statement {
    sid       = "DistributionTagOnCreate"
    actions   = ["cloudfront:TagResource"]
    resources = ["arn:aws:cloudfront::${local.account_id}:distribution/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [local.name]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Project"
      values   = ["true"]
    }
  }
  statement {
    sid = "DistributionManage"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListTagsForResource",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
    ]
    resources = ["arn:aws:cloudfront::${local.account_id}:distribution/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.name]
    }
  }
  statement {
    sid = "Functions"
    actions = [
      "cloudfront:CreateFunction",
      "cloudfront:DescribeFunction",
      "cloudfront:GetFunction",
      "cloudfront:UpdateFunction",
      "cloudfront:PublishFunction",
      "cloudfront:DeleteFunction",
    ]
    resources = ["arn:aws:cloudfront::${local.account_id}:function/${local.name}-*"]
  }
  # Origin access control and response headers policy: AWS-generated ids, untaggable, and their
  # Create* actions have no resource-level permission. The first site apply is local (admin), so
  # CI never creates or deletes either; it may only read and update the two infra/site owns,
  # pinned by the ids in site-ids.auto.tfvars (docs/infra.md, step 6). Until those ids are set the
  # statements are absent. A change that would replace either resource fails in CI by design and
  # is applied locally.
  dynamic "statement" {
    for_each = var.site_origin_access_control_id == "" ? [] : [var.site_origin_access_control_id]
    content {
      sid = "SiteOriginAccessControl"
      actions = [
        "cloudfront:GetOriginAccessControl",
        "cloudfront:GetOriginAccessControlConfig",
        "cloudfront:UpdateOriginAccessControl",
      ]
      resources = ["arn:aws:cloudfront::${local.account_id}:origin-access-control/${statement.value}"]
    }
  }
  dynamic "statement" {
    for_each = var.site_response_headers_policy_id == "" ? [] : [var.site_response_headers_policy_id]
    content {
      sid = "SiteResponseHeadersPolicy"
      actions = [
        "cloudfront:GetResponseHeadersPolicy",
        "cloudfront:GetResponseHeadersPolicyConfig",
        "cloudfront:UpdateResponseHeadersPolicy",
      ]
      resources = ["arn:aws:cloudfront::${local.account_id}:response-headers-policy/${statement.value}"]
    }
  }
  # Read-only lookup of the AWS-managed CachingOptimized policy by name: ListCachePolicies has no
  # resource-level permission, and managed policies are not account resources.
  statement {
    sid       = "ManagedCachePolicyRead"
    actions   = ["cloudfront:ListCachePolicies", "cloudfront:GetCachePolicy"]
    resources = ["*"]
  }

  # --- ACM (CloudFront certificates live in us-east-1) ------------------------------------------
  # RequestCertificate has no resource-level permission; the condition keys pin what it may ask for.
  statement {
    sid       = "CertificateRequest"
    actions   = ["acm:RequestCertificate"]
    resources = ["*"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "acm:DomainNames"
      values   = [local.domain]
    }
    condition {
      test     = "StringEquals"
      variable = "acm:ValidationMethod"
      values   = ["DNS"]
    }
  }
  statement {
    sid       = "CertificateRead"
    actions   = ["acm:DescribeCertificate", "acm:ListTagsForCertificate"]
    resources = ["arn:aws:acm:us-east-1:${local.account_id}:certificate/*"]
  }
  statement {
    sid       = "CertificateTagOnCreate"
    actions   = ["acm:AddTagsToCertificate"]
    resources = ["arn:aws:acm:us-east-1:${local.account_id}:certificate/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [local.name]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Project"
      values   = ["true"]
    }
  }
  statement {
    sid = "CertificateManage"
    actions = [
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:DeleteCertificate",
    ]
    resources = ["arn:aws:acm:us-east-1:${local.account_id}:certificate/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.name]
    }
  }

  # --- Access-log analytics -----------------------------------------------------------------------
  statement {
    sid = "GlueCatalog"
    actions = [
      "glue:CreateDatabase",
      "glue:GetDatabase",
      "glue:UpdateDatabase",
      "glue:DeleteDatabase",
      "glue:CreateTable",
      "glue:GetTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:GetPartitionIndexes",
      "glue:GetTags",
      "glue:TagResource",
      "glue:UntagResource",
    ]
    resources = [
      "arn:aws:glue:us-east-1:${local.account_id}:catalog",
      "arn:aws:glue:us-east-1:${local.account_id}:database/${local.glue_db}",
      "arn:aws:glue:us-east-1:${local.account_id}:table/${local.glue_db}/*",
    ]
  }
  statement {
    sid = "AthenaWorkgroup"
    actions = [
      "athena:CreateWorkGroup",
      "athena:GetWorkGroup",
      "athena:UpdateWorkGroup",
      "athena:DeleteWorkGroup",
      "athena:ListTagsForResource",
      "athena:TagResource",
      "athena:UntagResource",
      "athena:CreateNamedQuery",
      "athena:GetNamedQuery",
      "athena:DeleteNamedQuery",
    ]
    resources = ["arn:aws:athena:us-east-1:${local.account_id}:workgroup/${local.name}"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${local.name}-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

output "role_arn" {
  description = "Set as the AWS_ROLE_ARN repository variable."
  value       = aws_iam_role.deploy.arn
}
