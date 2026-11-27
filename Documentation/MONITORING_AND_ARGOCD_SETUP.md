# 📊 Monitoring & ArgoCD Complete Implementation Guide — DC Music

> Comprehensive, step-by-step production setup guide for the **Observability Stack (Prometheus + Grafana + Alertmanager)** and **GitOps Continuous Delivery (ArgoCD)** on AWS EKS (`dcmusic-eks`).

---

## 📑 Table of Contents

1. [Architecture & Component Overview](#1-architecture--component-overview)
2. [Prerequisites & Environment Validation](#2-prerequisites--environment-validation)
3. [Part 1: Monitoring Stack (Prometheus, Grafana, Alertmanager)](#3-part-1-monitoring-stack)
   - [3.1 Stack Architecture & Helm Configuration](#31-stack-architecture--helm-configuration)
   - [3.2 Automated Installation](#32-automated-installation)
   - [3.3 Custom Alerting Rules Explained](#33-custom-alerting-rules-explained)
   - [3.4 Grafana Dashboard Provisioning](#34-grafana-dashboard-provisioning)
   - [3.5 Accessing & Using the UIs](#35-accessing--using-the-uis)
4. [Part 2: ArgoCD (GitOps Continuous Delivery)](#4-part-2-argocd-gitops-continuous-delivery)
   - [4.1 GitOps Architecture & Repository Flow](#41-gitops-architecture--repository-flow)
   - [4.2 Automated Installation & LoadBalancer Provisioning](#42-automated-installation--loadbalancer-provisioning)
   - [4.3 Admin Credentials & Initial Login](#43-admin-credentials--initial-login)
   - [4.4 Deploying Application Manifests (Dev & Prod)](#44-deploying-application-manifests-dev--prod)
   - [4.5 ArgoCD UI Walkthrough & Verification](#45-argocd-ui-walkthrough--verification)
5. [Part 3: Production Alerting Notifications (Slack Integration)](#5-part-3-production-alerting-notifications-slack-integration)
6. [Part 4: Operational Runbook & Troubleshooting](#6-part-4-operational-runbook--troubleshooting)
7. [Part 5: Complete Command Cheat Sheet](#7-part-5-complete-command-cheat-sheet)

---

## 1. Architecture & Component Overview

This production setup combines real-time metric gathering, proactive alerting, visual dashboards, and automated Git-driven deployments:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                AWS EKS CLUSTER: dcmusic-eks                           │
│                                                                                        │
│  ┌── NAMESPACE: dcmusic ────────────────────────────────────────────────────────────┐  │
│  │   • Backend (Spring Boot 3 + Actuator metrics on :8080/actuator/prometheus)       │  │
│  │   • Frontend (React + Vite + Nginx Alpine)                                       │  │
│  │   • MySQL Service / External RDS endpoint connection                             │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│                                        ▲                                               │
│                         Scrapes Metrics│           Deploys Helm Charts                 │
│                                        │                   │                           │
│  ┌── NAMESPACE: monitoring ────────────┴─────┐ ┌── NAMESPACE: argocd ────────────────┴┐ │
│  │  • kube-prometheus-stack (Operator)       │ │  • ArgoCD Server (API + Web UI)       │ │
│  │  • Prometheus (TSDB metrics storage)      │ │  • ArgoCD Repo Server (Pulls GitHub)  │ │
│  │  • Alertmanager (Alert routing & dispatch)│ │  • ArgoCD Application Controller      │ │
│  │  • Node Exporter & kube-state-metrics     │ │  • Application CRDs (Dev & Prod)      │ │
│  │  • Grafana (Pre-loaded DC Music Dashboard)│ └───────────────────────────────────────┘ │
│  └───────────────────────────────────────────┘                     ▲                     │
│               ▲                                                    │ Watches Git Push    │
│               │ AWS Network LoadBalancer                           │                     │
│       ┌───────┴───────┐                                    ┌───────┴──────────────┐      │
│       │ Grafana UI    │                                    │ GitHub Repository    │      │
│       │ http://<LB>:80│                                    │ Prod_DevOps.git      │      │
│       └───────────────┘                                    └──────────────────────┘      │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

| Component | Namespace | Version / Source | Access Method | Credentials |
|---|---|---|---|---|
| **Grafana** | `monitoring` | `kube-prometheus-stack` v55+ | AWS LoadBalancer (Port 80) | `admin` / `admin` |
| **Prometheus** | `monitoring` | Native Operator TSDB | `kubectl port-forward` (Port 9090) | None (Internal) |
| **Alertmanager** | `monitoring` | Native Alertmanager | `kubectl port-forward` (Port 9093) | None (Internal) |
| **ArgoCD Server** | `argocd` | Stable Official Manifests | AWS LoadBalancer (Port 80 / 443) | `admin` / dynamically decoded secret |

---

## 2. Prerequisites & Environment Validation

Execute these commands from your **EC2 Bastion Host** or **Jenkins Agent** before starting:

### 2.1 Verify AWS Identity and EKS Access
```bash
# Check caller identity
aws sts get-caller-identity

# Update kubeconfig to point directly to the cluster
aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1

# Verify node status (All nodes must report 'Ready' on v1.35)
kubectl get nodes -o wide
```

### 2.2 Verify CLI Tooling
```bash
kubectl version --client
helm version
aws --version
git --version
```

### 2.3 Clone or Pull Latest Repository Code

On your **EC2 Jumper / Bastion Host**:

```bash
# If you are setting up the Jumper for the first time (Clone):
git clone https://github.com/DharmendraChakrawarti/Prod_DevOps.git
cd Prod_DevOps

# If the repository is already cloned (Pull latest updates):
cd ~/Prod_DevOps    # Or path to your repo directory
git fetch origin
git checkout main
git pull origin main

# Confirm you are on the latest commit:
git log -n 1 --oneline
```

---

## 3. Part 1: Monitoring Stack

The monitoring infrastructure is provisioned through the official `prometheus-community/kube-prometheus-stack` chart, customized via [monitoring/prometheus/values.yaml](file:///home/dc/Desktop/Prod_DevOps/monitoring/prometheus/values.yaml).

### 3.1 Stack Architecture & Helm Configuration

The configuration is tuned for cloud cost-efficiency and test workloads:
- **Grafana Service:** Configured with `type: LoadBalancer` to assign an AWS Network LoadBalancer automatically without requiring an Ingress Controller or custom DNS.
- **Sidecar Auto-Discovery:** Grafana includes an auto-discovery sidecar scanning the `monitoring` namespace for any ConfigMap labeled `grafana_dashboard=1`.
- **Retention & Storage:** Configured with 7-day metric retention using `emptyDir` ephemeral storage to stay free-tier compliant.
- **Resource Requests & Limits:**
  - Prometheus: 200m CPU / 256Mi RAM requests, 500m CPU / 512Mi RAM limits.
  - Grafana: 100m CPU / 128Mi RAM requests, 250m CPU / 256Mi RAM limits.
  - Alertmanager: 50m CPU / 64Mi RAM requests, 100m CPU / 128Mi RAM limits.

### 3.2 Automated Installation

Execute the installation script:
```bash
chmod +x monitoring/install.sh
./monitoring/install.sh
```

#### What `monitoring/install.sh` executes under the hood:
1. Adds and updates the Helm repository:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   ```
2. Creates the `monitoring` namespace:
   ```bash
   kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
   ```
3. Installs `kube-prometheus-stack` with our tuned values:
   ```bash
   helm install prometheus prometheus-community/kube-prometheus-stack \
       -n monitoring \
       -f monitoring/prometheus/values.yaml \
       --wait --timeout 600s
   ```
4. Applies custom Prometheus alerting rules:
   ```bash
   kubectl apply -f monitoring/prometheus/alerting-rules.yaml -n monitoring
   ```
5. Imports the custom Grafana application dashboard via a labeled ConfigMap:
   ```bash
   kubectl create configmap dcmusic-dashboard \
       --from-file=dcmusic-app.json=monitoring/grafana/app-dashboard.json \
       -n monitoring \
       --dry-run=client -o yaml | \
       kubectl label --local -f - grafana_dashboard=1 -o yaml | \
       kubectl apply -f -
   ```

---

### 3.3 Custom Alerting Rules Explained

Our [monitoring/prometheus/alerting-rules.yaml](file:///home/dc/Desktop/Prod_DevOps/monitoring/prometheus/alerting-rules.yaml) deploys a `PrometheusRule` resource defining 5 critical alerts:

1. **`HighPodCPU`** (Warning):
   - **Trigger:** Pod CPU usage exceeds 80% of its configured limit for 5 minutes.
   - **PromQL:**
     ```promql
     (sum(rate(container_cpu_usage_seconds_total{namespace="dcmusic", container!=""}[5m])) by (pod)
      /
      sum(kube_pod_container_resource_limits{namespace="dcmusic", resource="cpu"}) by (pod)) * 100 > 80
     ```
2. **`PodCrashLooping`** (Critical):
   - **Trigger:** Any pod restarts more than 3 times in 10 minutes.
   - **PromQL:**
     ```promql
     increase(kube_pod_container_status_restarts_total{namespace="dcmusic"}[10m]) > 3
     ```
3. **`HighMemoryUsage`** (Warning):
   - **Trigger:** Memory usage exceeds 85% of limit for 5 minutes.
   - **PromQL:**
     ```promql
     (sum(container_memory_working_set_bytes{namespace="dcmusic", container!=""}) by (pod)
      /
      sum(kube_pod_container_resource_limits{namespace="dcmusic", resource="memory"}) by (pod)) * 100 > 85
     ```
4. **`PodNotReady`** (Warning):
   - **Trigger:** A pod remains in unready state for > 5 minutes.
   - **PromQL:**
     ```promql
     sum by (pod) (kube_pod_status_phase{namespace="dcmusic", phase=~"Pending|Unknown"}) > 0
     ```
5. **`NodeDiskPressure`** (Critical):
   - **Trigger:** EKS worker nodes reporting disk pressure conditions.

---

### 3.4 Grafana Dashboard Provisioning

The application dashboard in [monitoring/grafana/app-dashboard.json](file:///home/dc/Desktop/Prod_DevOps/monitoring/grafana/app-dashboard.json) is automatically mounted into Grafana without manual export/import steps.

**Monitored Panels:**
- **JVM Heap Memory:** Real-time used vs committed vs max heap via Spring Boot Actuator metrics (`jvm_memory_used_bytes{area="heap"}`).
- **HTTP Request Rate & Latency:** Total RPS and p95 response durations.
- **Backend & Frontend Pod CPU/RAM:** Per-container resource consumption against limits.
- **Pod Replicas & Restart Counts:** Active pod availability.

---

### 3.5 Accessing & Using the UIs

#### Access Grafana (Web Browser)
1. Retrieve the public LoadBalancer hostname:
   ```bash
   kubectl get svc prometheus-grafana -n monitoring
   ```
2. Open the URL in your browser:
   - **URL:** `http://<EXTERNAL-IP-OR-AWS-ELB-HOSTNAME>`
   - **Username:** `admin`
   - **Password:** `admin`
3. Click **Dashboards** → **DC Music** to inspect the application dashboard.

#### Access Prometheus Web UI (Port-Forward)
```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
```
Open [http://localhost:9090](http://localhost:9090) in your browser:
- Navigate to **Status** → **Targets** to confirm that node-exporter, kube-state-metrics, and the Spring Boot application are `UP`.
- Navigate to **Alerts** to see active and pending alerts.

#### Access Alertmanager Web UI (Port-Forward)
```bash
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring
```
Open [http://localhost:9093](http://localhost:9093) to view fired alerts or configure alert silences.

---

## 4. Part 2: ArgoCD (GitOps Continuous Delivery)

ArgoCD implements a declarative GitOps deployment model. It continuously monitors your Git repository at `https://github.com/DharmendraChakrawarti/Prod_DevOps.git` and guarantees that the cluster state matches the Helm chart defined in `helm/dcmusic`.

### 4.1 GitOps Architecture & Repository Flow

```
Developer Git Push ──> GitHub (Prod_DevOps.git)
                             │
                             │ Watches: helm/dcmusic/
                             ▼
                    ArgoCD Application Controller
                    ┌─────────────────────────┐
                    │ Compares:               │
                    │   Git Manifests         │
                    │        vs               │
                    │   Live Kubernetes State │
                    └───────────┬─────────────┘
                                │
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
        dcmusic-dev                   dcmusic-prod
        (Auto-Sync + Self-Heal)       (Manual Sync Required)
```

- **`dcmusic-dev`**: Uses automated sync (`syncPolicy.automated.prune=true`, `syncPolicy.automated.selfHeal=true`). Any commit pushed to `main` is applied immediately to EKS. If someone manually changes a pod or service in-cluster, ArgoCD automatically reconciles and reverts it.
- **`dcmusic-prod`**: Has automated sync disabled. Requires an operator to click **Sync** in the UI or run `argocd app sync dcmusic-prod`.

---

### 4.2 Automated Installation & LoadBalancer Provisioning

Run the installation script at [gitops/argocd/install.sh](file:///home/dc/Desktop/Prod_DevOps/gitops/argocd/install.sh):

```bash
chmod +x gitops/argocd/install.sh
./gitops/argocd/install.sh
```

#### What `gitops/argocd/install.sh` executes:
1. Creates the `argocd` namespace:
   ```bash
   kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
   ```
2. Installs official ArgoCD stable release:
   ```bash
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
3. Waits for the controller and server deployments to become available:
   ```bash
   kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
   ```
4. Patches the `argocd-server` service from `ClusterIP` to `LoadBalancer`:
   ```bash
   kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
   ```

---

### 4.3 Admin Credentials & Initial Login

1. **Extract Initial Admin Password:**
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
   ```
   *(Save this output; it is your temporary password).*

2. **Retrieve the ArgoCD Server Public Hostname:**
   ```bash
   kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo
   ```

3. **Log in via Web Browser:**
   - Open: `https://<ARGOCD-LOADBALANCER-HOSTNAME>`
   - Accept the browser's self-signed TLS certificate warning.
   - **Username:** `admin`
   - **Password:** `<retrieved-initial-admin-password>`

4. *(Optional)* Change the Admin Password via CLI:
   ```bash
   # Log in via CLI
   argocd login <ARGOCD-HOST> --username admin --password <OLD_PASSWORD> --insecure

   # Update password
   argocd account update-password
   ```

---

### 4.4 Deploying Application Manifests (Dev & Prod)

The application definitions in `gitops/apps/` connect directly to your GitHub repository and Helm chart:

```bash
# 1. Deploy DEV Environment (Auto-Sync)
kubectl apply -f gitops/apps/dcmusic-dev.yaml

# 2. Deploy PROD Environment (Manual Sync Gate)
kubectl apply -f gitops/apps/dcmusic-prod.yaml
```

#### Manifest Breakdown (`gitops/apps/dcmusic-dev.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dcmusic-dev
  namespace: argocd
  labels:
    app.kubernetes.io/name: dcmusic
    app.kubernetes.io/env: dev
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/DharmendraChakrawarti/Prod_DevOps.git
    targetRevision: main
    path: helm/dcmusic
    helm:
      valueFiles:
        - values.yaml
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: dcmusic
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

---

### 4.5 ArgoCD UI Walkthrough & Verification

1. Log in to the ArgoCD web console.
2. In the **Applications** card view, you will see `dcmusic-dev` and `dcmusic-prod`.
3. Click on **`dcmusic-dev`**:
   - You will see a live graphical tree of all managed resources:
     - `Service/dcmusic-backend`
     - `Service/dcmusic-frontend`
     - `Deployment/dcmusic-backend`
     - `Deployment/dcmusic-frontend`
     - `ConfigMap` and `Secret` resources
     - Under each Deployment: `ReplicaSet` → individual `Pod` nodes.
   - Status indicators:
     - **Synched** (Green circle): Live state equals Git repository.
     - **Healthy** (Green heart): All containers pass readiness probes.

---

## 5. Part 3: Production Alerting Notifications (Slack Integration)

To send Alertmanager notifications directly to a team Slack channel:

1. Open [monitoring/prometheus/values.yaml](file:///home/dc/Desktop/Prod_DevOps/monitoring/prometheus/values.yaml) lines 101–105:
   ```yaml
   alertmanager:
     config:
       receivers:
         - name: 'slack-notifications'
           slack_configs:
             - api_url: 'https://hooks.slack.com/services/T00/B00/XXXXX'
               channel: '#devops-alerts'
               send_resolved: true
               title: '{{ template "slack.default.title" . }}'
               text: '{{ template "slack.default.text" . }}'
   ```
2. Upgrade the Helm release:
   ```bash
   helm upgrade prometheus prometheus-community/kube-prometheus-stack \
       -n monitoring \
       -f monitoring/prometheus/values.yaml
   ```

---

## 6. Part 4: Operational Runbook & Troubleshooting

### Scenario 1: Grafana LoadBalancer stays in `<pending>` state
- **Root Cause:** AWS Subnets in your VPC might be missing public internet gateway routes or public IP allocation tags.
- **Fix:** Check subnet tags:
  ```bash
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=<VPC_ID>" --query "Subnets[*].[SubnetId,Tags]"
  ```
  Ensure public subnets contain the tag:
  `kubernetes.io/role/elb = 1`

### Scenario 2: ArgoCD reports `ComparisonError: repository not found`
- **Root Cause:** Git repo URL mismatch or private repository without SSH key.
- **Fix:** If the repository is private, add credentials in ArgoCD:
  ```bash
  argocd repo add https://github.com/DharmendraChakrawarti/Prod_DevOps.git \
      --username <GITHUB_USERNAME> \
      --password <GITHUB_TOKEN>
  ```

### Scenario 3: Prometheus pods stuck in `Pending`
- **Root Cause:** Insufficient CPU/Memory on worker nodes.
- **Fix:** Inspect node resource allocation:
  ```bash
  kubectl describe nodes | grep -A 8 "Allocated resources"
  ```
  If needed, reduce requests in [monitoring/prometheus/values.yaml](file:///home/dc/Desktop/Prod_DevOps/monitoring/prometheus/values.yaml) or scale node group capacity in `terraform/variables.tf`.

---

## 7. Part 5: Complete Command Cheat Sheet

```bash
# ---------------------------------------------
# 1. Monitoring Stack Verification Commands
# ---------------------------------------------
# Check pod health
kubectl get pods -n monitoring -o wide

# Check Grafana service & LoadBalancer URL
kubectl get svc prometheus-grafana -n monitoring

# Port-forward Prometheus UI
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

# Port-forward Alertmanager UI
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring

# View Alerting Rules
kubectl get prometheusrules -n monitoring

# ---------------------------------------------
# 2. ArgoCD Management Commands
# ---------------------------------------------
# Check ArgoCD pod status
kubectl get pods -n argocd

# Check ArgoCD Server LoadBalancer
kubectl get svc argocd-server -n argocd

# Get ArgoCD initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# List registered GitOps applications
kubectl get applications -n argocd

# Force reconcile / sync an application via kubectl
kubectl patch application dcmusic-dev -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'

# View ArgoCD application sync errors
kubectl describe application dcmusic-dev -n argocd
```
