# ☸️ Amazon EKS Cluster Management & Operations Guide — DC Music

> Complete command reference, troubleshooting runbook, and day-2 operations guide for managing the **DCMusic Amazon EKS Cluster** (`dcmusic-eks`) on Kubernetes **v1.35**.

---

## 📑 Table of Contents

1. [Cluster Specifications & Identity](#1-cluster-specifications--identity)
2. [Connection & Kubeconfig Setup](#2-connection--kubeconfig-setup)
3. [Cluster & Node Health Verification](#3-cluster--node-health-verification)
4. [Namespace & Workload Management (`dcmusic`)](#4-namespace--workload-management-dcmusic)
5. [Service & AWS LoadBalancer Discovery](#5-service--aws-loadbalancer-discovery)
6. [Debugging & Log Inspection](#6-debugging--log-inspection)
7. [Scaling & Rolling Updates](#7-scaling--rolling-updates)
8. [ConfigMaps & Secrets Management](#8-configmaps--secrets-management)
9. [IAM Access Entries & User Permission Delegation](#9-iam-access-entries--user-permission-delegation)
10. [Observability & Monitoring Operations (`monitoring`)](#10-observability--monitoring-operations-monitoring)
11. [GitOps ArgoCD Operations (`argocd`)](#11-gitops-argocd-operations-argocd)
12. [Emergency Troubleshooting & Diagnostic One-Liners](#12-emergency-troubleshooting--diagnostic-one-liners)

---

## 1. Cluster Specifications & Identity

| Property | Value |
|---|---|
| **Cluster Name** | `dcmusic-eks` |
| **AWS Account ID** | `328159054985` |
| **AWS Region** | `ap-south-1` (Mumbai) |
| **Kubernetes Version** | `1.35` |
| **Node Group** | 2× `t3.small` (Amazon Linux 2023 - `AL2023_x86_64_STANDARD`) |
| **Authentication Mode** | `API_AND_CONFIG_MAP` |
| **Namespaces** | `dcmusic` (App), `monitoring` (Prometheus/Grafana), `argocd` (GitOps), `kube-system` |

---

## 2. Connection & Kubeconfig Setup

Run these commands on your **local machine**, **EC2 Jumper**, or **Jenkins Agent**:

### 2.1 Verify AWS Identity
```bash
# Verify which IAM identity is active
aws sts get-caller-identity
```

### 2.2 Update Kubeconfig
```bash
# Connect kubectl to the EKS cluster
aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1

# View current context
kubectl config current-context

# View all contexts
kubectl config get-contexts
```

---

## 3. Cluster & Node Health Verification

### 3.1 Check Worker Nodes
```bash
# View nodes with IP, OS image, and Kubernetes version
kubectl get nodes -o wide

# Check CPU and memory consumption per node (requires metrics-server)
kubectl top nodes

# Detailed inspection of a specific node
kubectl describe node <NODE_NAME>

# Check if any nodes have taints or conditions
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
```

### 3.2 Check EKS Core Add-ons
```bash
# Verify CoreDNS, kube-proxy, and AWS VPC CNI
kubectl get pods -n kube-system -o wide

# View EKS Add-ons via AWS CLI
aws eks list-addons --cluster-name dcmusic-eks --region ap-south-1
```

---

## 4. Namespace & Workload Management (`dcmusic`)

### 4.1 Pod Status & Overview
```bash
# List all pods in the dcmusic namespace with status, restarts, and IP
kubectl get pods -n dcmusic -o wide

# Watch pods in real-time
kubectl get pods -n dcmusic -w

# Filter only backend or frontend pods
kubectl get pods -n dcmusic -l app.kubernetes.io/component=backend
kubectl get pods -n dcmusic -l app.kubernetes.io/component=frontend
```

### 4.2 Deployments & ReplicaSets
```bash
# View deployment status
kubectl get deployments -n dcmusic

# View ReplicaSets (useful to see if new pods are being created during rolling updates)
kubectl get rs -n dcmusic

# View HorizontalPodAutoscaler (HPA) targets
kubectl get hpa -n dcmusic
```

---

## 5. Service & AWS LoadBalancer Discovery

### 5.1 Retrieve Public LoadBalancer Hostnames
```bash
# Get all services in the application namespace
kubectl get svc -n dcmusic

# Extract Frontend Public LoadBalancer Hostname directly:
FRONTEND_URL=$(kubectl get svc dcmusic-frontend -n dcmusic -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Frontend URL: http://${FRONTEND_URL}"

# Extract Backend Public LoadBalancer Hostname:
BACKEND_URL=$(kubectl get svc dcmusic-backend -n dcmusic -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Backend URL:  http://${BACKEND_URL}:8080"
```

### 5.2 Test Connectivity from Jumper
```bash
# Test frontend HTTP response
curl -I http://${FRONTEND_URL}/health

# Test backend health probe
curl -I http://${BACKEND_URL}:8080/actuator/health
```

---

## 6. Debugging & Log Inspection

### 6.1 View Live Application Logs
```bash
# Tail backend logs (across all backend replicas)
kubectl logs -n dcmusic -l app.kubernetes.io/component=backend --tail=100 -f

# Tail frontend Nginx access/error logs
kubectl logs -n dcmusic -l app.kubernetes.io/component=frontend --tail=100 -f

# View logs for a specific pod
kubectl logs <POD_NAME> -n dcmusic

# View logs from a previous crashed container instance
kubectl logs <POD_NAME> -n dcmusic --previous
```

### 6.2 Deep Pod Inspection
```bash
# Inspect pod events (shows why a pod failed, OOMKilled, or failed probes)
kubectl describe pod <POD_NAME> -n dcmusic

# Execute an interactive shell inside a running pod
kubectl exec -it <POD_NAME> -n dcmusic -- /bin/sh

# Test backend database connection from inside the backend pod
kubectl exec -it deployment/dcmusic-backend -n dcmusic -- curl -s http://localhost:8080/actuator/health
```

---

## 7. Scaling & Rolling Updates

### 7.1 Manual Scaling
```bash
# Scale backend deployment to 4 replicas
kubectl scale deployment/dcmusic-backend --replicas=4 -n dcmusic

# Scale frontend deployment to 3 replicas
kubectl scale deployment/dcmusic-frontend --replicas=3 -n dcmusic
```

### 7.2 Rolling Restarts & Rollbacks
```bash
# Restart backend pods gracefully (zero-downtime rolling restart)
kubectl rollout restart deployment/dcmusic-backend -n dcmusic

# Check rollout progress
kubectl rollout status deployment/dcmusic-backend -n dcmusic

# View rollout history
kubectl rollout history deployment/dcmusic-backend -n dcmusic

# Rollback to the previous deployment revision
kubectl rollout undo deployment/dcmusic-backend -n dcmusic
```

---

## 8. ConfigMaps & Secrets Management

```bash
# List ConfigMaps
kubectl get configmaps -n dcmusic

# View backend configuration values
kubectl get configmap dcmusic-backend-config -n dcmusic -o yaml

# View frontend configuration values
kubectl get configmap dcmusic-frontend-config -n dcmusic -o yaml

# List secrets
kubectl get secrets -n dcmusic

# Decode backend database password
kubectl get secret dcmusic-backend-secret -n dcmusic -o jsonpath='{.data.SPRING_DATASOURCE_PASSWORD}' | base64 -d && echo
```

---

## 9. IAM Access Entries & User Permission Delegation

Because our cluster uses `authentication_mode = "API_AND_CONFIG_MAP"`, you can grant admin or view access to any IAM user or role via AWS CLI:

### 9.1 List Active Access Entries
```bash
aws eks list-access-entries --cluster-name dcmusic-eks --region ap-south-1
```

### 9.2 Grant EKS Admin Access to a New User / Role
```bash
# 1. Create the access entry for the IAM principal
aws eks create-access-entry \
    --cluster-name dcmusic-eks \
    --principal-arn arn:aws:iam::328159054985:user/<USERNAME> \
    --region ap-south-1

# 2. Associate the Cluster Admin policy
aws eks associate-access-policy \
    --cluster-name dcmusic-eks \
    --principal-arn arn:aws:iam::328159054985:user/<USERNAME> \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster \
    --region ap-south-1
```

---

## 10. Observability & Monitoring Operations (`monitoring`)

```bash
# Check all monitoring stack pods
kubectl get pods -n monitoring -o wide

# Get Grafana LoadBalancer URL
kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo

# Port-forward Prometheus UI (Port 9090)
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

# Port-forward Alertmanager UI (Port 9093)
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring

# Check custom Prometheus alert rules
kubectl get prometheusrules -n monitoring
```

---

## 11. GitOps ArgoCD Operations (`argocd`)

```bash
# Check ArgoCD components
kubectl get pods -n argocd

# Get ArgoCD server LoadBalancer URL
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo

# Retrieve ArgoCD initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Check sync status of GitOps applications
kubectl get applications -n argocd

# Force manual sync of DEV application
kubectl patch application dcmusic-dev -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'
```

---

## 12. Emergency Troubleshooting & Diagnostic One-Liners

| Goal | Command |
|---|---|
| **Find all failing pods in cluster** | `kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded` |
| **Inspect warning / error events** | `kubectl get events -n dcmusic --sort-by='.lastTimestamp'` |
| **Check container resource limits** | `kubectl top pods -n dcmusic` |
| **Kill / force-delete stuck pod** | `kubectl delete pod <POD_NAME> -n dcmusic --grace-period=0 --force` |
| **Test CoreDNS resolution from inside pod** | `kubectl run -it --rm test-dns --image=busybox -n dcmusic -- nslookup dcmusic-backend` |
| **Dump all pod descriptions for support** | `kubectl describe pods -n dcmusic > cluster-debug.txt` |
