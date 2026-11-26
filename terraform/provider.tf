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
  # STATE BACKEND: S3 (Partial Config)
  # -----------------------------------------------------------
  # Uses partial backend configuration. Actual values (bucket,
  # region, key) are passed at 'terraform init' time via
  # -backend-config flags. This keeps account-specific values
  # out of committed code.
  #
  # The Jenkins pipeline (Jenkinsfile.infra) auto-creates the
  # S3 bucket and passes config to terraform init.
  #
  # For local dev, run:
  #   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  #   terraform init \
  #     -backend-config="bucket=dcmusic-tf-state-${ACCOUNT_ID}" \
  #     -backend-config="key=dev/terraform.tfstate" \
  #     -backend-config="region=ap-south-1" \
  #     -backend-config="use_lockfile=true" \
  #     -backend-config="encrypt=true"
  # -----------------------------------------------------------
  backend "s3" {}
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
