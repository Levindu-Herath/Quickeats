terraform {
  required_version = ">= 1.10" # S3 native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State lives in S3 so it survives a lost laptop. The bucket is created once by hand
  # (see README.md), because Terraform can't store its state in a bucket it hasn't made yet.
  backend "s3" {
    bucket       = "quickeats-tfstate-256130491262"
    key          = "prod/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "quickeats"
      ManagedBy = "terraform"
    }
  }
}
