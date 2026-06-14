provider "aws" {
  region = "ap-northeast-1"
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
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
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
