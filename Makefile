# ==============================================================
#  Makefile — DC Music Developer Shortcuts
# ==============================================================
#  Usage: make <target>
#
#  Local Dev:
#    make dev-up      — Start local stack with docker-compose
#    make dev-down    — Stop local stack
#
#  Build:
#    make build       — Build backend JAR + frontend dist
#    make docker      — Build both Docker images
#
#  Terraform:
#    make tf-init     — Initialize Terraform
#    make tf-plan     — Preview infra changes
#    make tf-apply    — Apply infra changes
#
#  EKS:
#    make eks-config  — Configure kubectl for dcmusic-eks
#    make k8s-apply   — Apply raw k8s manifests
#    make helm-dev    — Deploy with Helm (dev values)
#    make helm-prod   — Deploy with Helm (prod values)
#    make status      — Show all resources in dcmusic namespace
#    make logs-be     — Follow backend pod logs
#    make logs-fe     — Follow frontend pod logs
#
#  GitOps & Monitoring:
#    make argo-install  — Install ArgoCD on EKS
#    make mon-install   — Install monitoring stack
# ==============================================================

.PHONY: dev-up dev-down build docker \
        tf-init tf-plan tf-apply \
        eks-config k8s-apply helm-dev helm-prod \
        argo-install mon-install \
        status logs-be logs-fe help

# ---- Configuration ----
PROJECT_NAME     := dcmusic
AWS_REGION       := ap-south-1
EKS_CLUSTER_NAME := dcmusic-eks
NAMESPACE        := dcmusic

# ---- Help ----
help:
	@echo ""
	@echo "DC Music — Available Make Targets:"
	@echo ""
	@echo "  Local Dev:"
	@echo "    dev-up       Start local stack with docker-compose"
	@echo "    dev-down     Stop local stack"
	@echo ""
	@echo "  Build:"
	@echo "    build        Build backend + frontend"
	@echo "    docker       Build Docker images"
	@echo ""
	@echo "  Terraform:"
	@echo "    tf-init      Initialize Terraform"
	@echo "    tf-plan      Preview infra changes"
	@echo "    tf-apply     Apply infra changes"
	@echo ""
	@echo "  EKS:"
	@echo "    eks-config   Configure kubectl for EKS"
	@echo "    k8s-apply    Apply k8s manifests"
	@echo "    helm-dev     Deploy Helm chart (dev)"
	@echo "    helm-prod    Deploy Helm chart (prod)"
	@echo "    status       Show namespace resources"
	@echo "    logs-be      Follow backend logs"
	@echo "    logs-fe      Follow frontend logs"
	@echo ""
	@echo "  GitOps & Monitoring:"
	@echo "    argo-install Install ArgoCD"
	@echo "    mon-install  Install monitoring stack"
	@echo ""

# ---- Local Development ----

## Start local docker-compose stack (with rebuild)
dev-up:
	@echo "🐳 Starting local dev stack..."
	docker-compose up --build -d
	@echo "✅ Dev stack running! Backend: http://localhost:8080  Frontend: http://localhost:3000"

## Stop local docker-compose stack
dev-down:
	@echo "🛑 Stopping local dev stack..."
	docker-compose down
	@echo "✅ Dev stack stopped."

# ---- Build ----

## Build backend JAR and frontend dist in parallel
build:
	@echo "🔨 Building backend and frontend in parallel..."
	$(MAKE) -j2 _build-backend _build-frontend
	@echo "✅ Build complete!"

_build-backend:
	@echo "☕ Building Spring Boot backend..."
	cd backend && mvn clean package -DskipTests

_build-frontend:
	@echo "⚛️ Building React frontend..."
	cd frontend && npm install && npm run build

## Build both Docker images
docker:
	@echo "🐳 Building Docker images..."
	docker build -t $(PROJECT_NAME)-backend:latest ./backend
	docker build -t $(PROJECT_NAME)-frontend:latest ./frontend
	@echo "✅ Docker images built!"

# ---- Terraform ----

## Initialize Terraform with S3 backend
tf-init:
	@echo "🏗️ Initializing Terraform..."
	cd terraform && terraform init

## Preview Terraform infrastructure changes
tf-plan:
	@echo "📋 Planning Terraform changes..."
	cd terraform && terraform plan

## Apply Terraform infrastructure changes (with auto-approve — use carefully!)
tf-apply:
	@echo "🚀 Applying Terraform changes..."
	cd terraform && terraform apply

# ---- EKS / Kubernetes ----

## Configure kubectl to connect to dcmusic-eks cluster
eks-config:
	@echo "🔧 Configuring kubectl for EKS..."
	aws eks update-kubeconfig --name $(EKS_CLUSTER_NAME) --region $(AWS_REGION)
	@echo "✅ kubectl configured! Verify with: kubectl get nodes"

## Apply raw Kubernetes manifests from k8s/base/
k8s-apply:
	@echo "📦 Applying k8s manifests..."
	kubectl apply -f k8s/base/ -R
	@echo "✅ Manifests applied!"

## Deploy or upgrade Helm chart with dev values
helm-dev:
	@echo "🚀 Deploying to EKS (dev)..."
	helm upgrade --install $(PROJECT_NAME) helm/$(PROJECT_NAME) \
		-f helm/$(PROJECT_NAME)/values-dev.yaml \
		-n $(NAMESPACE) \
		--create-namespace \
		--wait
	@echo "✅ Dev deployment complete!"

## Deploy or upgrade Helm chart with prod values
helm-prod:
	@echo "🚀 Deploying to EKS (prod)..."
	helm upgrade --install $(PROJECT_NAME) helm/$(PROJECT_NAME) \
		-f helm/$(PROJECT_NAME)/values-prod.yaml \
		-n $(NAMESPACE) \
		--wait
	@echo "✅ Prod deployment complete!"

# ---- GitOps & Monitoring ----

## Install ArgoCD on EKS
argo-install:
	@echo "🚀 Installing ArgoCD..."
	bash gitops/argocd/install.sh

## Install monitoring stack (kube-prometheus-stack)
mon-install:
	@echo "📊 Installing monitoring stack..."
	bash monitoring/install.sh

# ---- Observability ----

## Show all resources in dcmusic namespace
status:
	@echo "📊 Resources in namespace: $(NAMESPACE)"
	kubectl get all -n $(NAMESPACE)

## Follow backend pod logs
logs-be:
	@echo "📋 Following backend logs (Ctrl+C to stop)..."
	kubectl logs -f -l app=$(PROJECT_NAME)-backend -n $(NAMESPACE)

## Follow frontend pod logs
logs-fe:
	@echo "📋 Following frontend logs (Ctrl+C to stop)..."
	kubectl logs -f -l app=$(PROJECT_NAME)-frontend -n $(NAMESPACE)
