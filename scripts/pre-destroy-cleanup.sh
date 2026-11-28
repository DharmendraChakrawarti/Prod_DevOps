#!/usr/bin/env bash
# ==============================================================
#  scripts/pre-destroy-cleanup.sh — Safe Pre-Teardown Script
# ==============================================================
#  Cleans up dynamic Kubernetes LoadBalancers and orphaned
#  security groups before running Terraform destroy or
#  Jenkinsfile.infra.delete.
# ==============================================================
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-dcmusic-eks}"
VPC_NAME="${VPC_NAME:-dcmusic-vpc}"

echo "🧹 ====================================================="
echo "🧹  Starting Pre-Destroy Cleanup for ${CLUSTER_NAME}"
echo "🧹 ====================================================="

# 1. Update Kubeconfig and delete Kubernetes LoadBalancers
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "🔧 Connecting to EKS cluster..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

    echo "🗑️ Deleting Kubernetes LoadBalancer services in dcmusic & monitoring..."
    kubectl delete svc -n dcmusic --all --timeout=60s || true
    kubectl delete svc -n monitoring --all --timeout=60s || true

    echo "⏳ Waiting 25s for AWS to de-register Load Balancer ENIs..."
    sleep 25
else
    echo "ℹ️ Cluster ${CLUSTER_NAME} not found or already deleted. Skipping kubectl cleanup."
fi

# 2. Find VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${VPC_NAME}" --region "$REGION" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
    echo "🔍 Checking for orphaned k8s-elb Security Groups in ${VPC_ID}..."
    SG_IDS=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" --region "$REGION" --query 'SecurityGroups[?starts_with(GroupName, `k8s-elb`)].GroupId' --output text 2>/dev/null || echo "")

    if [ -n "$SG_IDS" ]; then
        for sg in $SG_IDS; do
            echo "   Deleting security group: $sg"
            aws ec2 revoke-security-group-ingress --group-id "$sg" --protocol -1 --source-group "$sg" --region "$REGION" 2>/dev/null || true
            aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null || true
        done
        echo "✅ Orphaned security groups deleted."
    else
        echo "✅ No orphaned k8s-elb security groups found."
    fi
fi

echo ""
echo "✅ ====================================================="
echo "✅  Pre-destroy cleanup complete!"
echo "✅  Safe to run Jenkinsfile.infra.delete or terraform destroy"
echo "✅ ====================================================="
