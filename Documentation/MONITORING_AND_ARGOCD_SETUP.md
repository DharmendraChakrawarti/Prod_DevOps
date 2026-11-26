# Monitoring & ArgoCD Setup Guide

This guide provides step-by-step instructions for deploying and configuring **Prometheus + Grafana + Alertmanager** and **ArgoCD** on your AWS EKS cluster (`dcmusic-eks`).

---

## 📋 Prerequisites

Run these commands from your **EC2 Bastion Host** (or any machine with AWS CLI, `kubectl`, and `helm` configured):

1. **Verify AWS Identity & EKS Connection:**
   ```bash
   aws sts get-caller-identity
   aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1
   kubectl get nodes
   ```

2. **Pull the Latest Code:**
   ```bash
   cd ~/Prod_DevOps    # Or path to your repository clone
   git pull origin main
   ```

---

## 📊 Section 1: Monitoring Stack (Prometheus + Grafana + Alertmanager)

The monitoring stack uses the official `kube-prometheus-stack` Helm chart, preconfigured for lightweight resource footprints and automatic dashboard provisioning.

### 1.1 Run Automated Installation

```bash
chmod +x monitoring/install.sh
./monitoring/install.sh
```

### 1.2 What the Script Configures
- **Helm Repo:** Adds `prometheus-community` repository.
- **Namespace:** Creates `monitoring`.
- **Values Applied:** Uses `monitoring/prometheus/values.yaml` (free-tier resource requests/limits, LoadBalancer service for Grafana).
- **Alert Rules:** Deploys custom Prometheus rules (`monitoring/prometheus/alerting-rules.yaml`) for high CPU/RAM and pod restarts.
- **Grafana Dashboard:** Ingests the pre-built application dashboard (`monitoring/grafana/app-dashboard.json`) via labeled ConfigMap.

### 1.3 Accessing Grafana
1. Get the LoadBalancer external hostname:
   ```bash
   kubectl get svc prometheus-grafana -n monitoring
   ```
2. Open the browser to:
   - **URL:** `http://<EXTERNAL-IP>`
   - **Username:** `admin`
   - **Password:** `admin`
3. Navigate to **Dashboards** to view the imported **DC Music Application** metrics dashboard.

### 1.4 Accessing Prometheus & Alertmanager (Port-Forward)
Since Prometheus and Alertmanager do not have public LoadBalancers attached for security:

- **Prometheus:**
  ```bash
  kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
  # Open http://localhost:9090
  ```
- **Alertmanager:**
  ```bash
  kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring
  # Open http://localhost:9093
  ```

---

## 🐙 Section 2: ArgoCD (GitOps Setup)

ArgoCD automates deployments of your Helm charts directly from GitHub into the EKS cluster.

### 2.1 Run Automated Installation

```bash
chmod +x gitops/argocd/install.sh
./gitops/argocd/install.sh
```

### 2.2 Retrieve Admin Password & URL
1. **Get Admin Password:**
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
   ```
2. **Get LoadBalancer URL:**
   ```bash
   kubectl get svc argocd-server -n argocd
   ```
3. Open `https://<EXTERNAL-IP>` in your browser (bypass self-signed TLS warning if shown):
   - **Username:** `admin`
   - **Password:** `<retrieved-password>`

### 2.3 Deploy DC Music Applications via ArgoCD

Both application definitions already point to your repository: `https://github.com/DharmendraChakrawarti/Prod_DevOps.git`.

- **Deploy Dev Environment (Automated sync & self-healing):**
  ```bash
  kubectl apply -f gitops/apps/dcmusic-dev.yaml
  ```
- **Deploy Prod Environment (Manual sync via ArgoCD UI/CLI):**
  ```bash
  kubectl apply -f gitops/apps/dcmusic-prod.yaml
  ```

### 2.4 Verify Application Status
```bash
kubectl get applications -n argocd
```
Log into the ArgoCD dashboard to see the live dependency graph and synchronization state.

---

## 🛠️ Section 3: Troubleshooting & Common Commands

| Task | Command |
|---|---|
| Check monitoring pods | `kubectl get pods -n monitoring` |
| Check ArgoCD pods | `kubectl get pods -n argocd` |
| View Grafana logs | `kubectl logs -n monitoring -l app.kubernetes.io/name=grafana` |
| View ArgoCD server logs | `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server` |
| Force Sync Dev App | `kubectl get app dcmusic-dev -n argocd -o yaml` |
