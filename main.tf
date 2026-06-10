provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_s3_bucket" "my-company-dev-123456" {
  bucket = "riorio-test-bucket"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}
