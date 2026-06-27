provider "aws" {
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# オリジン
resource "aws_s3_bucket" "my-company-dev-123456" {
  bucket = "riorio-test-bucket"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

# パブリックアクセスをブロック（CloudFront 経由のみ許可）
resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.my-company-dev-123456.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront ディストリビューション
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.main.arn

  origin {
    domain_name              = aws_s3_bucket.my-company-dev-123456.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400    # 1日
    max_ttl     = 31536000 # 1年
  }

  # SPA の場合は 403/404 を index.html にリダイレクト
  # custom_error_response {
  #   error_code         = 403
  #   response_code      = 200
  #   response_page_path = "/index.html"
  # }

  # custom_error_response {
  #   error_code         = 404
  #   response_code      = 200
  #   response_page_path = "/index.html"
  # }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # ログ設定を追加
  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/" # ログファイルのフォルダ名
    include_cookies = false
  }
}

# OAC
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# IAMポリシー
data "aws_iam_policy_document" "s3_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.my-company-dev-123456.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

# バケットポリシー
resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.my-company-dev-123456.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "aws_wafv2_web_acl" "main" {
  provider = aws.virginia

  name        = "managed-rule-main"
  description = "Main of a managed rule."
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rule-1"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          action_to_use {
            count {}
          }

          name = "SizeRestrictions_QUERYSTRING"
        }

        rule_action_override {
          action_to_use {
            count {}
          }

          name = "NoUserAgent_HEADER"
        }

        scope_down_statement {
          geo_match_statement {
            country_codes = ["JP"]
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cfn-request-log"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "block-test"
    priority = 0

    action {
      block {}
    }

    statement {
      byte_match_statement {
        positional_constraint = "CONTAINS"

        search_string = "waf-test"

        field_to_match {
          query_string {}
        }

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-test"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Tag1 = "Value1"
    Tag2 = "Value2"
  }

  token_domains = ["mywebsite.com", "myotherwebsite.com"]

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cfn-request-log"
    sampled_requests_enabled   = true
  }
}

# ログ保存専用のバケット
resource "aws_s3_bucket" "logs" {
  bucket = "riorio-test-logs"
}

# CloudFront からの書き込みを許可するACL設定
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  bucket     = aws_s3_bucket.logs.id
  acl        = "log-delivery-write" # CloudFrontがログを書き込むための権限
  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.my-company-dev-123456.id
  versioning_configuration {
    status = "Enabled"
  }
}

# GitHub Actions 用 IAM ポリシー
resource "aws_iam_policy" "github_actions" {
  name = "github-actions-deploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.my-company-dev-123456.arn}",
          "${aws_s3_bucket.my-company-dev-123456.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = [aws_cloudfront_distribution.cdn.arn]
      }
    ]
  })
}

# 通知用 SNS トピック
resource "aws_sns_topic" "alert" {
  name = "${var.project_name}-alert"
}

# メール通知の設定
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alert.arn
  protocol  = "email"
  endpoint  = "your-email@example.com" # 通知先メールアドレス
}

resource "aws_cloudwatch_metric_alarm" "error_rate_4xx" {
  alarm_name          = "${var.project_name}-4xx-error-rate"
  alarm_description   = "CloudFront 4xxエラー率が10%を超えました"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2  # 2回連続で閾値を超えたら発火
  threshold           = 10 # 10% 以上

  # エラー率を計算（4xxエラー数 ÷ 総リクエスト数）
  metric_query {
    id          = "error_rate"
    expression  = "errors / requests * 100"
    label       = "4xx Error Rate"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "4xxErrorRate"
      period      = 300 # 5分間隔
      stat        = "Average"
      dimensions = {
        DistributionId = aws_cloudfront_distribution.cdn.id
        Region         = "Global"
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "Requests"
      period      = 300
      stat        = "Sum"
      dimensions = {
        DistributionId = aws_cloudfront_distribution.cdn.id
        Region         = "Global"
      }
    }
  }

  alarm_actions = [aws_sns_topic.alert.arn] # アラーム発火時に SNS へ通知
  ok_actions    = [aws_sns_topic.alert.arn] # 正常に戻った時にも通知
}

resource "aws_cloudwatch_metric_alarm" "error_rate_5xx" {
  alarm_name          = "${var.project_name}-5xx-error-rate"
  alarm_description   = "CloudFront 5xxエラー率が1%を超えました"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1 # 1% 以上（5xxは致命的なので低めに設定）

  metric_query {
    id          = "error_rate"
    expression  = "errors / requests * 100"
    label       = "5xx Error Rate"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "5xxErrorRate"
      period      = 300
      stat        = "Average"
      dimensions = {
        DistributionId = aws_cloudfront_distribution.cdn.id
        Region         = "Global"
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "Requests"
      period      = 300
      stat        = "Sum"
      dimensions = {
        DistributionId = aws_cloudfront_distribution.cdn.id
        Region         = "Global"
      }
    }
  }

  alarm_actions = [aws_sns_topic.alert.arn]
  ok_actions    = [aws_sns_topic.alert.arn]
}

resource "aws_cloudwatch_metric_alarm" "request_count" {
  alarm_name          = "${var.project_name}-request-count"
  alarm_description   = "CloudFront リクエスト数が急増しています（DDoS の可能性）"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 1000 # 5分間で1000リクエスト以上

  namespace   = "AWS/CloudFront"
  metric_name = "Requests"
  period      = 300
  statistic   = "Sum"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.alert.arn]
  ok_actions    = [aws_sns_topic.alert.arn]
}
