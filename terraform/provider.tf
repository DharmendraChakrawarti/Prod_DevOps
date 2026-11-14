# =============================================================
#  TERRAFORM PROVIDER & BACKEND CONFIGURATION
# =============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Required for fetching the OIDC TLS certificate thumbprint
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # -----------------------------------------------------------
  # STATE BACKEND: LOCAL
  # -----------------------------------------------------------
  # S3 backend is commented out because your AWS Organization SCP
  # denies S3 bucket creation/listing (p-5dyi8gbe).
  # Terraform will store its state locally in terraform/terraform.tfstate
  # -----------------------------------------------------------
  # backend "s3" {
  #   bucket         = "dcmusic-tf-state-bucket"
  #   key            = "dev/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "dcmusic-tf-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
