# Athena over the CloudFront access logs. The table follows the standard-logging (W3C, tab-
# separated, gzipped, two header lines) layout from the CloudFront developer guide. Logs are not
# partitioned; the 90-day expiry keeps every scan small.

locals {
  # Field order of CloudFront standard log files.
  log_columns = [
    ["date", "date"],
    ["time", "string"],
    ["x_edge_location", "string"],
    ["sc_bytes", "bigint"],
    ["c_ip", "string"],
    ["cs_method", "string"],
    ["cs_host", "string"],
    ["cs_uri_stem", "string"],
    ["sc_status", "int"],
    ["cs_referrer", "string"],
    ["cs_user_agent", "string"],
    ["cs_uri_query", "string"],
    ["cs_cookie", "string"],
    ["x_edge_result_type", "string"],
    ["x_edge_request_id", "string"],
    ["x_host_header", "string"],
    ["cs_protocol", "string"],
    ["cs_bytes", "bigint"],
    ["time_taken", "float"],
    ["x_forwarded_for", "string"],
    ["ssl_protocol", "string"],
    ["ssl_cipher", "string"],
    ["x_edge_response_result_type", "string"],
    ["cs_protocol_version", "string"],
    ["fle_status", "string"],
    ["fle_encrypted_fields", "int"],
    ["c_port", "int"],
    ["time_to_first_byte", "float"],
    ["x_edge_detailed_result_type", "string"],
    ["sc_content_type", "string"],
    ["sc_content_len", "bigint"],
    ["sc_range_start", "bigint"],
    ["sc_range_end", "bigint"],
  ]
}

resource "aws_glue_catalog_database" "site" {
  name        = local.glue_db
  description = "CloudFront access logs for ${local.domain}"
}

resource "aws_glue_catalog_table" "access_logs" {
  name          = "cloudfront_logs"
  database_name = aws_glue_catalog_database.site.name
  table_type    = "EXTERNAL_TABLE"
  parameters = {
    EXTERNAL                 = "TRUE"
    "skip.header.line.count" = "2"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.logs.bucket}/cloudfront/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "field.delim"          = "\t"
        "serialization.format" = "\t"
      }
    }

    dynamic "columns" {
      for_each = local.log_columns
      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }
}

resource "aws_athena_workgroup" "site" {
  name          = local.name
  description   = "Queries over the ${local.domain} access logs"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false
    result_configuration {
      # Outside the table location, and expired with the logs by the bucket lifecycle rule.
      output_location = "s3://${aws_s3_bucket.logs.bucket}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

resource "aws_athena_named_query" "daily_visits" {
  name        = "daily-visits"
  description = "HTML page views per day: GET, status 200, common bots and tools excluded"
  workgroup   = aws_athena_workgroup.site.id
  database    = aws_glue_catalog_database.site.name
  query       = <<-SQL
    SELECT
      "date" AS day,
      count(*) AS page_views,
      count(DISTINCT c_ip) AS unique_ips
    FROM ${aws_glue_catalog_table.access_logs.name}
    WHERE sc_status = 200
      AND cs_method = 'GET'
      AND sc_content_type LIKE 'text/html%'
      AND cs_user_agent <> '-'
      AND NOT regexp_like(
        lower(url_decode(cs_user_agent)),
        'bot|crawl|spider|slurp|facebookexternalhit|whatsapp|preview|lighthouse|headless|curl|wget|python|go-http-client|okhttp|java/|libwww|httpclient|scan|monitor'
      )
    GROUP BY "date"
    ORDER BY day DESC
  SQL
}
