#!/bin/bash
# =============================================================
#  SETUP REMOTE STATE BACKEND — Run ONCE before terraform init
# =============================================================
#  This script automatically:
#    1. Detects your AWS Account ID dynamically
#    2. Creates a unique S3 bucket for Terraform state (versioned + encrypted + private)
#    3. Prints the exact command to initialize Terraform
#
#  Locking: Terraform >= 1.10 uses native S3 locking (use_lockfile=true),
#  so DynamoDB is NOT needed.
#
#  Usage:
#    cd terraform
#    chmod +x setup-remote-state.sh
#    ./setup-remote-state.sh
# =============================================================

set -e

AWS_REGION="ap-south-1"
PROJECT_NAME="dcmusic"

echo ""
echo "🔍 Detecting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
    echo "❌ Failed to get AWS Account ID. Ensure AWS CLI is configured (run 'aws configure')."
    exit 1
}

BUCKET_NAME="${PROJECT_NAME}-tf-state-${ACCOUNT_ID}"

echo "============================================"
echo "  Setting up Terraform Remote State Backend"
echo "============================================"
echo "  AWS Account:    ${ACCOUNT_ID}"
echo "  Region:         ${AWS_REGION}"
echo "  S3 Bucket:      ${BUCKET_NAME}"
echo "  Locking:        Native S3 (use_lockfile)"
echo "============================================"

# --- Create S3 Bucket ---
echo ""
echo "📦 Checking S3 bucket: ${BUCKET_NAME}..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "   ✅ Bucket already exists, skipping creation."
else
    echo "   Creating S3 bucket..."
    aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"

    # Enable versioning (so you can recover previous state versions)
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled

    # Enable server-side encryption (AES256)
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'

    # Block public access
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration '{
            "BlockPublicAcls": true,
            "IgnorePublicAcls": true,
            "BlockPublicPolicy": true,
            "RestrictPublicBuckets": true
        }'

    echo "   ✅ S3 bucket created (versioned + encrypted + private)!"
fi

echo ""
echo "============================================"
echo "  ✅ Remote State Setup Complete!"
echo "============================================"
echo ""
echo "  Run this command to initialize Terraform with this backend:"
echo ""
echo "  terraform init \\"
echo "    -backend-config=\"bucket=${BUCKET_NAME}\" \\"
echo "    -backend-config=\"key=dev/terraform.tfstate\" \\"
echo "    -backend-config=\"region=${AWS_REGION}\" \\"
echo "    -backend-config=\"use_lockfile=true\" \\"
echo "    -backend-config=\"encrypt=true\""
echo ""
echo "============================================"
