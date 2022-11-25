terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

data "aws_acm_certificate" "acm-cert" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}

resource "aws_acm_certificate_validation" "example" {
  certificate_arn = data.aws_acm_certificate.acm-cert.arn
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.s3-bucket.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

resource "aws_s3_bucket" "s3-bucket" {
  bucket = var.bucket-name

  tags = {
    Name = "My bucket"
  }
}

resource "aws_s3_bucket_policy" "s3-s3_bucket_policy" {
  bucket = aws_s3_bucket.s3-bucket.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "aws_s3_bucket_website_configuration" "s3_bucket" {
  bucket = aws_s3_bucket.s3-bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_acl" "s3_bucket" {
  bucket = aws_s3_bucket.s3-bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "s3_bucket" {
  bucket = aws_s3_bucket.s3-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.s3-bucket.id
  key    = "index.html"
  source = "${path.module}/index.html"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("${path.module}/index.html")
}

resource "aws_s3_object" "object0" {
  bucket = aws_s3_bucket.s3-bucket.id
  key    = "cat0.jpg"
  source = "${path.module}/cat0.jpg"
  etag   = filemd5("${path.module}/cat0.jpg")
}

resource "aws_s3_object" "object1" {
  bucket = aws_s3_bucket.s3-bucket.id
  key    = "cat1.jpg"
  source = "${path.module}/cat1.jpg"
  etag   = filemd5("${path.module}/cat1.jpg")
}

resource "aws_s3_object" "object2" {
  bucket = aws_s3_bucket.s3-bucket.id
  key    = "cat2.jpg"
  source = "${path.module}/cat2.jpg"
  etag   = filemd5("${path.module}/cat2.jpg")
}



resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [
    aws_s3_bucket.s3-bucket
  ]

  origin {
    domain_name = aws_s3_bucket.s3-bucket.bucket_regional_domain_name
    origin_id   = "s3-${var.bucket-name}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"

  aliases = ["www.${var.domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-${var.bucket-name}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 31536000
    default_ttl            = 31536000
    max_ttl                = 31536000
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.acm-cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/404.html"
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "access-identity-${var.bucket-name}.s3.amazonaws.com"
}

data "aws_route53_zone" "my_hosted_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "route53_record" {
  depends_on = [
    aws_cloudfront_distribution.s3_distribution
  ]
  zone_id = data.aws_route53_zone.my_hosted_zone.id
  name    = var.bucket-name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}