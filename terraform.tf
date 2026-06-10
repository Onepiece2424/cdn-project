terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  backend "s3" {
    bucket = "remote-backend-riorio-bucket"
    key    = "dev/terraform.tfstate"
    region = "ap-northeast-1"
  }

  required_version = ">= 1.15.5"
}
