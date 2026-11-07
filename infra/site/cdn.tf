# CloudFront in front of the private site bucket, serving www.hoangmnguyen.com. DNS is at
# Porkbun, so the certificate's validation record is an output entered by hand (docs/infra.md);
# aws_acm_certificate_validation waits until ACM sees it.

resource "aws_acm_certificate" "site" {
  domain_name       = local.domain
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for dvo in aws_acm_certificate.site.domain_validation_options : dvo.resource_record_name]
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = local.name
  description                       = "Signed requests from CloudFront to ${local.site_bucket}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "rewrite" {
  name    = "${local.name}-rewrite"
  comment = "Map /path/ and extensionless paths to /path/index.html"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/rewrite.js")
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${local.name}-security"
  comment = "HSTS, CSP from csp.txt, nosniff, DENY framing, strict referrer"
  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
    content_security_policy {
      # csp.txt is the single source of truth (scripts/serve.py reads it too): one directive per
      # line, blank lines ignored.
      content_security_policy = join("; ", compact([for line in split("\n", file("${path.module}/csp.txt")) : trimspace(line)]))
      override                = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = local.domain
  aliases             = [local.domain]
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"

  origin {
    origin_id                = "site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "site"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }
  }

  # The bucket grants no s3:ListBucket, so a missing key comes back as 403; both map to the
  # site's 404 page with a real 404 status.
  dynamic "custom_error_response" {
    for_each = [403, 404]
    content {
      error_code            = custom_error_response.value
      response_code         = 404
      response_page_path    = "/404.html"
      error_caching_min_ttl = 60
    }
  }

  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Standard logging needs ACLs enabled on the log bucket before CloudFront adds its grant.
  depends_on = [aws_s3_bucket_ownership_controls.logs]
}
