# 🎵 DC Music Application

**DC Music** is a comprehensive, full-stack music streaming platform designed to seamlessly handle audio uploading, user-authentication, playlist curation, and smart search functionalities. It features a modern, completely responsive user interface and runs on an enterprise-ready infrastructure utilizing AWS RDS, Docker, and Terraform.

---

## ✨ Features
* **Music Streaming & Uploading:** Users can upload audio files (MP3/WAV) up to 50MB.
* **Smart Search:** Real-time debounced smart search with a dropdown preview of songs, artists, and albums.
* **Library & Playlists:** Create, delete, and add songs to custom playlists. Responsive layout that adapts between mobile and desktop automatically.
* **Persistent Player:** Beautiful, non-interruptive music player fixed to the bottom of the screen featuring volume control, progress seeking, and rapid 10-second skip buttons *(FastForward / Rewind)*.
* **Admin Controls:** An Admin dashboard allowing authorized users to globally approve, reject, or delete uploaded songs.
* **Authentication:** Secure JSON Web Token (JWT) based login and registration.

---

## 🏗️ Technology Stack
### Frontend
* **Framework:** React + Vite
* **Styling:** Tailwind CSS + Lucide Icons
* **State Management:** Redux Toolkit

### Backend
* **Framework:** Java 17 + Spring Boot 3.2
* **Security:** Spring Security & JWT
* **Database:** H2 Database (Local Dev) & AWS RDS MySQL (Production)

### DevOps & Infrastructure
* **Containerization:** Docker & Docker Compose (Frontend uses lightweight Nginx Alpine)
* **Infrastructure as Code (IaC):** Terraform
* **CI/CD:** Jenkins (`Jenkinsfile` integrated)

---

## 🚀 Running Locally (Docker)
The entire application is 100% Dockerized for zero-configuration, one-command startups. The local setup stores persistent database data and uploaded MP3 files accurately on your machine using Docker Volumes. 

**Prerequisites:** Ensure you have [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.

1. Open your terminal at the root directory of this project.
2. Build and launch the containers detached:
   ```bash
   docker-compose up --build -d
   ```
3. Access the application:
   * **Frontend Application:** [http://localhost:5173](http://localhost:5173)
   * **Backend API:** [http://localhost:8080/api](http://localhost:8080/api)

4. To safely stop the containers:
   ```bash
   docker-compose down
   ```

*(Bonus: Because volumes are mapped dynamically in `docker-compose.yml`, uploaded files and H2 user accounts are saved persistently in `backend/data` and `backend/uploads`!)*

---

## ☁️ Cloud & Production Infrastructure (AWS EKS)
This repository includes a production-grade AWS infrastructure managed via Terraform, targeting Kubernetes 1.35 on Amazon Linux 2023 (`AL2023_x86_64_STANDARD`).

👉 **[Read the complete Documentation Directory in Documentation/README.md](Documentation/README.md)** for detailed setup, infrastructure, and deployment guides:
- **[Terraform Setup Guide](Documentation/TERRAFORM_SETUP.md)**: VPC, EKS 1.35, RDS MySQL, ECR, IAM, S3 native lock remote state.
- **[Monitoring & ArgoCD Guide](Documentation/MONITORING_AND_ARGOCD_SETUP.md)**: Prometheus, Grafana, Alertmanager, and ArgoCD setup.
- **[Project Flow Guide](Documentation/PROJECT_FLOW.md)**: End-to-end architecture, network topology, and sequence diagrams.
- **[Jenkins Implementation](Documentation/jenkins_implementation.md)**: CI/CD pipelines for infra (`Jenkinsfile.infra`), teardown (`Jenkinsfile.infra.delete`), and application deploy (`Jenkinsfile`).

### Provisioned AWS Resources
- **VPC & Subnets:** Custom public and private networks with NAT Gateways.
- **EKS Cluster (v1.35):** Managed node group with AL2023 nodes for container orchestration.
- **RDS MySQL 8.0:** Managed database in private subnets with automated backups.
- **ECR Repositories:** Private Elastic Container Registries for backend and frontend images.
- **Load Balancers:** AWS LoadBalancers for external traffic routing to services, Grafana, and ArgoCD.

---

## 📂 Project Structure Overview
- `/frontend`: React + Vite UI application.
- `/backend`: Spring Boot 3 Java API handling logic, JWT Auth, and Audio Uploads.
- `/terraform`: Terraform AWS provision modules (`vpc`, `security`, `ecr`, `rds`, `eks`, `iam`).
- `/helm`: Helm charts for DC Music microservices (`helm/dcmusic`).
- `/monitoring`: Monitoring configs (Prometheus, Grafana dashboard, Alertmanager).
- `/gitops`: ArgoCD manifests and installer (`gitops/apps`, `gitops/argocd`).
- `/Documentation`: All architecture, setup, and runbook documentation.
- `Jenkinsfile`: Application CI/CD pipeline (Test, Build, Scan, Helm Deploy to EKS).
- `Jenkinsfile.infra`: Infrastructure provisioning pipeline.
- `Jenkinsfile.infra.delete`: Infrastructure teardown pipeline.

### Deploying Infrastructure
1. Move to the Terraform directory:
   ```bash
   cd terraform
   ```
2. Initialize remote state backend (S3 with native lockfile):
   ```bash
   chmod +x setup-remote-state.sh
   ./setup-remote-state.sh
   ```
3. Run the Terraform deploy command:
   ```bash
   echo "yes" | terraform init \
     -backend-config="bucket=dcmusic-tf-state-<ACCOUNT_ID>" \
     -backend-config="key=prod/terraform.tfstate" \
     -backend-config="region=ap-south-1" \
     -backend-config="use_lockfile=true"
   terraform apply
   ```

*(You will be prompted to pass an RDS Master password securely through the console or via `TF_VAR_db_password`.)*

---

## 🔄 CI/CD Pipelines
Robust Jenkins pipelines orchestrate full lifecycle management:
1. **`Jenkinsfile.infra`**: 8-stage pipeline to validate, plan, and apply Terraform infrastructure.
2. **`Jenkinsfile`**: Application delivery pipeline building Docker images, scanning with Trivy, pushing to ECR, and deploying via Helm to EKS.
3. **`Jenkinsfile.infra.delete`**: Safe teardown pipeline with interactive confirmation.
