#!/usr/bin/env bash
# ==============================================================
#  Monitoring Stack Installation Script
# ==============================================================
#  Installs kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
#  via Helm on the EKS cluster.
#
#  Prerequisites:
#    - kubectl configured for the EKS cluster
#    - helm v3 installed
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Installing monitoring stack on EKS cluster..."

# Step 1: Add Prometheus community Helm repo
echo "📦 Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Step 2: Create monitoring namespace
echo "📦 Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Install kube-prometheus-stack with custom values
echo "📥 Installing kube-prometheus-stack..."
helm install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f "${SCRIPT_DIR}/prometheus/values.yaml" \
    --wait --timeout 600s

# Step 4: Apply custom alerting rules
echo "📋 Applying custom alerting rules..."
kubectl apply -f "${SCRIPT_DIR}/prometheus/alerting-rules.yaml" -n monitoring

# Step 5: Import Grafana dashboard (via ConfigMap)
echo "📊 Importing Grafana app dashboard..."
kubectl create configmap dcmusic-dashboard \
    --from-file=dcmusic-app.json="${SCRIPT_DIR}/grafana/app-dashboard.json" \
    -n monitoring \
    --dry-run=client -o yaml | \
    kubectl label --local -f - grafana_dashboard=1 -o yaml | \
    kubectl apply -f -

# Step 6: Show access info
GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo ""
echo "✅ ============================================"
echo "✅  Monitoring Stack Installed Successfully!"
echo "✅ ============================================"
echo ""
echo "📊 Grafana:"
echo "   URL:      http://${GRAFANA_URL}"
echo "   Username: admin"
echo "   Password: admin"
echo "   (If URL is 'pending', run: kubectl get svc prometheus-grafana -n monitoring)"
echo ""
echo "📈 Prometheus:"
echo "   kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring"
echo ""
echo "🔔 Alertmanager:"
echo "   kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring"
echo ""
echo "✅ ============================================"
