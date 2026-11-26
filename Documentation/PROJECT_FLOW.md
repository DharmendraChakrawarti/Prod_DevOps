# 🚀 DC Music — Production DevOps Project Flow

> Complete end-to-end flow from code commit to production deployment on AWS EKS

---

## 📁 Project Structure Overview

```
Prod_DevOps/
│
├── frontend/                    ← React + Vite (Nginx Alpine)
│   ├── Dockerfile               ← Multi-stage build, security hardened
│   └── src/                     ← React components, Redux, Tailwind
│
├── backend/                     ← Spring Boot 3.2 (Java 17)
│   ├── Dockerfile               ← Multi-stage build, non-root user
│   ├── pom.xml                  ← Maven dependencies + Actuator
│   └── src/
│       └── main/resources/
│           ├── application.properties       ← Local (H2)
│           ├── application-aws.properties   ← AWS RDS profile
│           └── application-eks.properties   ← EKS profile (Actuator + Prometheus)
│
├── terraform/                   ← Infrastructure as Code
│   ├── modules/
│   │   ├── vpc/                 ← VPC + Subnets + NAT + EKS tags
│   │   ├── eks/                 ← EKS Cluster + Node Group + OIDC + ALB Role
│   │   ├── iam/                 ← Cluster IAM Role + Node IAM Role
│   │   ├── security/            ← EKS SG + Node SG + RDS SG
│   │   ├── ecr/                 ← Docker image repos (backend + frontend)
│   │   └── rds/                 ← MySQL 8.0 (encrypted, 7-day backups)
│   ├── main.tf                  ← Root — wires all modules
│   ├── variables.tf             ← All configurable inputs
│   ├── outputs.tf               ← EKS endpoint, kubeconfig cmd, RDS, ECR
│   └── provider.tf              ← AWS provider + S3 remote state
│
├── k8s/base/                    ← Raw Kubernetes Manifests
│   ├── namespace.yaml
│   ├── backend/                 ← Deployment, Service, HPA, ConfigMap, Secret
│   ├── frontend/                ← Deployment, Service, HPA, ConfigMap
│   ├── ingress.yaml             ← ALB Ingress (HTTP, no DNS)
│   ├── pdb-backend.yaml         ← Pod Disruption Budget
│   └── pdb-frontend.yaml
│
├── helm/dcmusic/                ← Helm Chart (templated K8s)
│   ├── Chart.yaml
│   ├── values.yaml              ← Default values
│   ├── values-dev.yaml          ← Dev overrides (small resources)
│   ├── values-prod.yaml         ← Prod overrides (HA, large resources)
│   └── templates/               ← 14 Helm templates
│
├── gitops/                      ← ArgoCD GitOps
│   ├── apps/
│   │   ├── dcmusic-dev.yaml     ← ArgoCD App (auto-sync)
│   │   └── dcmusic-prod.yaml    ← ArgoCD App (manual sync)
│   └── argocd/install.sh        ← ArgoCD installer script
│
├── monitoring/                  ← Observability Stack
│   ├── install.sh               ← kube-prometheus-stack installer
│   ├── prometheus/
│   │   ├── values.yaml          ← Prometheus + Grafana config
│   │   └── alerting-rules.yaml  ← Alert rules (CPU, crashes, errors)
│   └── grafana/
│       └── app-dashboard.json   ← Custom DC Music dashboard
│
├── Jenkinsfile                  ← CI/CD Pipeline (10 stages, EKS)
├── Jenkinsfile.infra            ← Infrastructure Pipeline (Terraform)
├── Makefile                     ← 15 developer shortcut commands
├── docker-compose.yml           ← Local development
└── PROJECT_FLOW.md              ← ⬅ THIS FILE
```

---

## 🔄 Complete End-to-End Flow

```mermaid
flowchart TB
    subgraph PHASE_1["PHASE 1 — Infrastructure Provisioning"]
        direction TB
        T1["1. terraform init\n(S3 remote state)"]
        T2["2. terraform plan\n(preview changes)"]
        T3["3. terraform apply\n(create resources)"]
        T1 --> T2 --> T3

        T3 --> VPC["VPC\n10.0.0.0/16"]
        T3 --> EKS["EKS Cluster\n(dcmusic-eks)"]
        T3 --> RDS_I["RDS MySQL\n(db.t3.micro)"]
        T3 --> ECR_I["ECR Repos\n(backend + frontend)"]
        T3 --> IAM_I["IAM Roles\n(cluster + nodes)"]
    end

    subgraph PHASE_2["PHASE 2 — Cluster Setup"]
        direction TB
        K1["4. aws eks update-kubeconfig"]
        K2["5. Install AWS LB Controller\n(Helm)"]
        K3["6. Install ArgoCD\n(kubectl apply)"]
        K4["7. Install Prometheus + Grafana\n(Helm)"]
        K1 --> K2 --> K3 --> K4
    end

    subgraph PHASE_3["PHASE 3 — CI Pipeline (Jenkins)"]
        direction TB
        J1["8. Developer pushes code\n(git push)"]
        J2["9. Jenkins Webhook triggered"]
        J3["10. Checkout code"]
        J4["11. Run Unit Tests\n(Maven + npm)"]
        J5["12. Build Artifacts\n(JAR + dist)"]
        J6["13. Docker Build\n(multi-stage)"]
        J7["14. Trivy Security Scan"]
        J8["15. Push to ECR\n(tagged: build-N + latest)"]
        J1 --> J2 --> J3 --> J4 --> J5 --> J6 --> J7 --> J8
    end

    subgraph PHASE_4["PHASE 4 — CD Pipeline (ArgoCD)"]
        direction TB
        A1["16. Jenkins updates image tag\nin Helm values.yaml"]
        A2["17. Git commit + push\nto GitOps repo"]
        A3["18. ArgoCD detects\nmanifest change"]
        A4["19. ArgoCD syncs:\napply to EKS"]
        A5["20. Rolling Update\n(zero downtime)"]
        A1 --> A2 --> A3 --> A4 --> A5
    end

    subgraph PHASE_5["PHASE 5 — Live Application"]
        direction TB
        L1["21. ALB routes traffic\n(HTTP :80)"]
        L2["22. Frontend pods\n(Nginx → React SPA)"]
        L3["23. Backend pods\n(Spring Boot API)"]
        L4["24. RDS MySQL\n(persistent data)"]
        L1 --> L2
        L1 --> L3
        L3 --> L4
    end

    subgraph PHASE_6["PHASE 6 — Monitoring"]
        direction TB
        M1["25. Prometheus scrapes\n/actuator/prometheus"]
        M2["26. Grafana dashboards\n(request rate, latency, JVM)"]
        M3["27. Alertmanager\n(Slack/Email on failures)"]
        M1 --> M2
        M1 --> M3
    end

    PHASE_1 --> PHASE_2
    PHASE_2 --> PHASE_3
    PHASE_3 --> PHASE_4
    PHASE_4 --> PHASE_5
    PHASE_5 --> PHASE_6
```

---

## 🏗️ AWS Infrastructure Architecture

```mermaid
flowchart TB
    INET["☁️ Internet"]

    subgraph AWS["AWS (ap-south-1)"]
        subgraph VPC["VPC — 10.0.0.0/16"]
            subgraph PUB["Public Subnets (10.0.1.0/24, 10.0.2.0/24)"]
                ALB["Application\nLoad Balancer\n(HTTP :80)"]
                IGW["Internet\nGateway"]
                NAT["NAT Gateway\n(single, cost-optimized)"]
            end

            subgraph PRIV["Private Subnets (10.0.10.0/24, 10.0.11.0/24)"]
                subgraph EKS["EKS Cluster — dcmusic-eks"]
                    subgraph NS1["namespace: dcmusic"]
                        FE_POD["Frontend Pods\n(Nginx, 2 replicas)\nHPA: 2→4"]
                        BE_POD["Backend Pods\n(Spring Boot, 2 replicas)\nHPA: 2→5"]
                    end
                    subgraph NS2["namespace: argocd"]
                        ARGO["ArgoCD Server"]
                    end
                    subgraph NS3["namespace: monitoring"]
                        PROM["Prometheus"]
                        GRAF["Grafana"]
                    end
                end
                RDS_DB["RDS MySQL 8.0\n(db.t3.micro)\nEncrypted, 7-day backups"]
            end
        end

        ECR_R["ECR Repos\ndcmusic-backend\ndcmusic-frontend"]
        S3["S3 Bucket\nTerraform State"]
    end

    INET --> IGW --> ALB
    ALB --> FE_POD
    ALB --> BE_POD
    BE_POD --> RDS_DB
    NAT --> INET
    EKS -.->|"Pull images"| ECR_R
    EKS -.->|"Outbound via"| NAT
```

---

## ⚙️ Jenkins CI Pipeline Flow (10 Stages)

```mermaid
flowchart LR
    subgraph JENKINSFILE["Jenkinsfile — 10-Stage EKS Pipeline"]
        direction LR
        S1["1️⃣ Checkout\n(git pull)"]
        S2["2️⃣ AWS Setup\n(get account ID,\nset ECR URLs)"]
        S3["3️⃣ Unit Tests\n(Maven + npm\nin parallel)"]
        S4["4️⃣ Build\n(JAR + dist\nin parallel)"]
        S5["5️⃣ Docker Build\n(both images)"]
        S6["6️⃣ Trivy Scan\n(vulnerability\ncheck)"]
        S7["7️⃣ Push to ECR\n(tag: build-N\n+ latest)"]
        S8["8️⃣ Update\nK8s Manifests\n(image tag)"]
        S9["9️⃣ Deploy to EKS\n(helm upgrade)"]
        S10["🔟 Verify\n(rollout status)"]

        S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7 --> S8 --> S9 --> S10
    end
```

```mermaid
flowchart LR
    subgraph JENKINSFILE_INFRA["Jenkinsfile.infra — Infrastructure Pipeline"]
        direction LR
        I1["1️⃣ Checkout"]
        I2["2️⃣ TF Init\n(S3 backend)"]
        I3["3️⃣ TF Plan\n(save plan)"]
        I4["4️⃣ Manual\nApproval ⏸️"]
        I5["5️⃣ TF Apply\n(create infra)"]
        I6["6️⃣ Update\nKubeconfig"]

        I1 --> I2 --> I3 --> I4 --> I5 --> I6
    end
```

---

## 🔄 ArgoCD GitOps Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant JK as Jenkins
    participant ECR as AWS ECR
    participant GO as GitOps Repo
    participant AC as ArgoCD
    participant EKS as EKS Cluster

    Dev->>GH: git push (app code)
    GH->>JK: Webhook trigger
    JK->>JK: Build + Test + Docker
    JK->>ECR: Push image (build-42)
    JK->>GO: Update image tag in values.yaml
    Note over GO: image.tag: "build-42"

    loop Every 3 minutes
        AC->>GO: Check for changes
    end
    AC->>AC: Detected drift!
    AC->>EKS: kubectl apply (rolling update)
    EKS->>ECR: Pull new image
    EKS->>EKS: Rolling deployment
    Note over EKS: Zero downtime ✅
```

---

## 📊 Monitoring Flow

```mermaid
flowchart LR
    subgraph Sources["Metrics Sources"]
        BE["/actuator/prometheus\n(Spring Boot)"]
        FE["nginx_stub_status\n(Frontend)"]
        NODE["node-exporter\n(Host metrics)"]
        KSM["kube-state-metrics\n(K8s objects)"]
    end

    subgraph Stack["Monitoring Stack"]
        PROM["Prometheus\n(scrape every 15s)"]
        GRAF["Grafana\n(dashboards)"]
        ALERT["Alertmanager\n(route alerts)"]
    end

    subgraph Alerts["Alert Rules"]
        A1["🔴 PodCrashLooping\n(restarts > 3)"]
        A2["🔴 HighErrorRate\n(5xx > 5%)"]
        A3["🟡 HighPodCPU\n(> 80% for 5m)"]
        A4["🟡 HighMemory\n(> 85% for 5m)"]
        A5["🟡 PodNotReady\n(> 5 min)"]
    end

    subgraph Dashboards["Grafana Panels"]
        D1["HTTP Request Rate"]
        D2["Response Time P50/P95/P99"]
        D3["Error Rate %"]
        D4["JVM Heap Usage"]
        D5["Pod CPU / Memory"]
    end

    BE --> PROM
    FE --> PROM
    NODE --> PROM
    KSM --> PROM
    PROM --> GRAF
    PROM --> ALERT
    ALERT --> A1
    ALERT --> A2
    ALERT --> A3
    ALERT --> A4
    ALERT --> A5
    GRAF --> D1
    GRAF --> D2
    GRAF --> D3
    GRAF --> D4
    GRAF --> D5
```

---

## 🔧 Terraform Module Dependency Graph

```mermaid
flowchart TD
    VPC["modules/vpc\n(VPC, Subnets, NAT,\nIGW, Route Tables)"]
    IAM["modules/iam\n(Cluster Role,\nNode Role)"]
    SEC["modules/security\n(EKS Cluster SG,\nNode SG, RDS SG)"]
    ECR["modules/ecr\n(Backend Repo,\nFrontend Repo)"]
    EKS["modules/eks\n(EKS Cluster, Node Group,\nAdd-ons, OIDC, LB Role)"]
    RDS["modules/rds\n(MySQL 8.0,\nSubnet Group)"]

    VPC --> SEC
    VPC --> EKS
    VPC --> RDS
    IAM --> EKS
    SEC --> EKS
    SEC --> RDS
```

---

## 🚀 Deployment Options

### Option A: Raw Kubernetes Manifests
```bash
# Quick deploy — direct kubectl
kubectl apply -f k8s/base/namespace.yaml
kubectl create secret generic dcmusic-db-secret \
  --from-literal=SPRING_DATASOURCE_URL="jdbc:mysql://RDS_ENDPOINT/dcmusic_db" \
  --from-literal=SPRING_DATASOURCE_USERNAME="admin" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="YourPassword" \
  -n dcmusic
kubectl apply -f k8s/base/ -R
```

### Option B: Helm Chart (Recommended)
```bash
# Templated deploy — Helm
helm upgrade --install dcmusic helm/dcmusic \
  -f helm/dcmusic/values-dev.yaml \
  -n dcmusic --create-namespace \
  --set database.host=RDS_ENDPOINT
```

### Option C: ArgoCD GitOps (Production)
```bash
# Declarative deploy — ArgoCD watches Git
kubectl apply -f gitops/apps/dcmusic-dev.yaml
# ArgoCD auto-syncs from Helm chart in repo
```

---

## 🎯 Scaling Architecture

```mermaid
flowchart TD
    subgraph AutoScaling["Auto-Scaling Stack"]
        HPA_BE["HPA: Backend\nmin 2 → max 5\nCPU target: 70%"]
        HPA_FE["HPA: Frontend\nmin 2 → max 4\nCPU target: 70%"]
        CA["Cluster Autoscaler\nmin 1 → max 3 nodes"]
        PDB_BE["PDB: Backend\nminAvailable: 1"]
        PDB_FE["PDB: Frontend\nminAvailable: 1"]
    end

    TRAFFIC["📈 Traffic Spike"] --> HPA_BE
    TRAFFIC --> HPA_FE
    HPA_BE -->|"More pods needed\nthan nodes can fit"| CA
    HPA_FE -->|"More pods needed\nthan nodes can fit"| CA
    CA -->|"Adds t3.small\nnodes"| NEW_NODE["New EKS Node"]
    PDB_BE -->|"Ensures at least 1 pod\nduring disruption"| SAFE["Zero-Downtime\nGuaranteed ✅"]
    PDB_FE --> SAFE
```

---

## 💰 Cost Breakdown (AWS Free Tier Account)

| Resource | Monthly Cost | Free Tier? |
|---|---|---|
| EKS Control Plane | ~$73 | ❌ No |
| 2× t3.small Nodes | ~$33 | ❌ No |
| NAT Gateway | ~$32 | ❌ No |
| ALB | ~$22 | ❌ No |
| RDS db.t3.micro | ~$0 | ✅ Yes (12 months) |
| ECR (500MB) | ~$0 | ✅ Yes |
| S3 (TF state) | ~$0.01 | ✅ Yes |
| **TOTAL** | **~$160/mo** | |

> **💡 Cost Saving Tips:**
> - Run `terraform destroy` when not using the cluster
> - Scale nodes to 0 during off-hours: `aws eks update-nodegroup-config --scaling-config minSize=0,desiredSize=0`
> - Use `make dev-up` for local Docker development (free) instead of EKS

---

## 🏃 Quick Start Commands (Makefile)

```bash
# Local Development (Free)
make dev-up              # Start with docker-compose
make dev-down            # Stop containers

# Infrastructure
make tf-init             # Initialize Terraform
make tf-plan             # Preview changes
make tf-apply            # Create AWS resources

# EKS Deployment
make eks-config          # Configure kubectl
make helm-dev            # Deploy to EKS (dev)
make helm-prod           # Deploy to EKS (prod)

# Monitoring & Tools
make argo-install        # Install ArgoCD
make mon-install         # Install Prometheus + Grafana

# Debugging
make status              # kubectl get all -n dcmusic
make logs-be             # Backend pod logs
make logs-fe             # Frontend pod logs
```

---

## 📋 Implementation Order

```
Step 1  → terraform init + apply          (create VPC, EKS, RDS, ECR, IAM)
Step 2  → aws eks update-kubeconfig       (configure kubectl)
Step 3  → Install AWS LB Controller       (enables ALB Ingress)
Step 4  → docker build + push to ECR      (push app images)
Step 5  → helm install dcmusic            (deploy app to EKS)
Step 6  → Verify: kubectl get ingress     (get ALB URL → access app)
Step 7  → Install ArgoCD                  (enable GitOps auto-deploy)
Step 8  → Install Prometheus + Grafana    (enable monitoring)
Step 9  → Configure Jenkins pipeline      (automate CI/CD)
Step 10 → Push code → watch it auto-deploy! 🎉
```

---

*For detailed step-by-step commands, see the [Implementation Guide](../../../.gemini/antigravity/brain/e2de5541-ba7d-483e-a928-7394fc0beabf/implementation-guide.md)*
