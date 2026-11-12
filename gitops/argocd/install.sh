#!/usr/bin/env bash
# ==============================================================
#  ArgoCD Installation Script for EKS
# ==============================================================
#  Installs ArgoCD on the EKS cluster and exposes it via
#  LoadBalancer (no DNS/TLS needed for free-tier setup).
#
#  Prerequisites:
#    - kubectl configured for the EKS cluster
#    - aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1
# ==============================================================

set -euo pipefail

echo "🚀 Installing ArgoCD on EKS cluster..."

# Step 1: Create the argocd namespace
echo "📦 Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Install ArgoCD (stable release)
echo "📥 Installing ArgoCD from official manifests..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Step 3: Wait for ArgoCD server to be ready
echo "⏳ Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Step 4: Expose ArgoCD via LoadBalancer (no DNS/TLS for free-tier)
echo "🌐 Patching ArgoCD server to LoadBalancer type..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Step 5: Get the LoadBalancer URL (may take a minute to provision)
echo "⏳ Waiting for LoadBalancer to be provisioned..."
sleep 30

ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo ""
echo "✅ ============================================"
echo "✅  ArgoCD Installed Successfully!"
echo "✅ ============================================"
echo ""
echo "📋 To get the initial admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "📋 Username: admin"
echo ""
echo "🌐 ArgoCD URL: http://${ARGOCD_URL}"
echo "   (If 'pending', wait a minute and run:)"
echo "   kubectl get svc argocd-server -n argocd"
echo ""
echo "📋 To apply the DC Music applications:"
echo "   kubectl apply -f gitops/apps/dcmusic-dev.yaml"
echo "   kubectl apply -f gitops/apps/dcmusic-prod.yaml"
echo ""
echo "✅ ============================================"
