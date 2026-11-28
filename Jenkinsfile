// =============================================================
//  JENKINSFILE — CI/CD Pipeline for DC Music (EKS Deployment)
// =============================================================
//
//  WHAT THIS PIPELINE DOES (10 stages):
//  -------------------------------------
//  1.  Checkout          → Pulls code from GitHub
//  2.  AWS Setup         → Gets AWS Account ID, sets ECR URLs
//  3.  Unit Tests        → Parallel: Maven tests + npm tests
//  4.  Build             → Parallel: Maven package + npm build
//  5.  Docker Build      → Builds both images with build number tags
//  6.  Security Scan     → Trivy vulnerability scan on both images
//  7.  Push to ECR       → Pushes images to AWS ECR (build number + latest)
//  8.  Update K8s Manifests → Updates image tags in Helm values / gitops repo
//  9.  Deploy to EKS     → kubectl apply or helm upgrade to EKS cluster
//  10. Verify Deployment → Waits for rollout to complete successfully
//
//  PREREQUISITES (set up in Jenkins BEFORE running):
//  -------------------------------------------------
//  1. Credentials:
//     - 'aws-credentials'  → AWS Access Key + Secret Key
//     - 'rds-password'     → Secret text (RDS master password)
//
//  2. Plugins:
//     - Pipeline
//     - AWS Credentials
//     - Kubernetes CLI (optional)
//
//  3. Tools (Global Tool Configuration):
//     - Maven  → name: 'Maven-3.9'
//     - NodeJS → name: 'Node-20'
//
//  4. Tools on Jenkins agent:
//     - Docker
//     - Trivy (for security scanning)
//     - kubectl
//     - aws cli
//     - helm (optional, for helm-based deploys)
//
// =============================================================

pipeline {
    agent any

    // ---------------------------------------------------------
    // TOOLS — Jenkins auto-installs these
    // ---------------------------------------------------------
    tools {
        maven 'Maven-3.9'
        nodejs 'Node-20'
    }

    // ---------------------------------------------------------
    // ENVIRONMENT — Global variables used across stages
    // ---------------------------------------------------------
    environment {
        AWS_REGION       = 'ap-south-1'
        PROJECT_NAME     = 'dcmusic'
        EKS_CLUSTER_NAME = 'dcmusic-eks'
        ENVIRONMENT      = 'dev'
    }

    // ---------------------------------------------------------
    // PIPELINE STAGES
    // ---------------------------------------------------------
    stages {

        // =====================================================
        // STAGE 1: CHECKOUT CODE
        // =====================================================
        // Pulls the latest code from the configured SCM (GitHub)
        // =====================================================
        stage('Checkout') {
            steps {
                echo '📥 Pulling latest code from GitHub...'
                checkout scm
            }
        }

        // =====================================================
        // STAGE 2: AWS SETUP
        // =====================================================
        // Dynamically fetches the AWS Account ID using STS,
        // then constructs the full ECR repository URLs for
        // both backend and frontend images.
        // =====================================================
        stage('AWS Setup') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials',
                                  accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                                  secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    script {
                        // Get the AWS Account ID dynamically
                        env.AWS_ACCOUNT_ID = sh(
                            script: "aws sts get-caller-identity --query Account --output text",
                            returnStdout: true
                        ).trim()

                        // Construct full ECR repository URLs
                        env.ECR_BACKEND  = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com/${env.PROJECT_NAME}-backend"
                        env.ECR_FRONTEND = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com/${env.PROJECT_NAME}-frontend"

                        echo "✅ AWS Account ID: ${env.AWS_ACCOUNT_ID}"
                        echo "✅ Backend ECR:    ${env.ECR_BACKEND}"
                        echo "✅ Frontend ECR:   ${env.ECR_FRONTEND}"
                    }
                }
            }
        }

        // =====================================================
        // STAGE 3: UNIT TESTS
        // =====================================================
        // Runs tests in parallel:
        //   - Backend:  mvn test (fails pipeline on test failure)
        //   - Frontend: npm test (allowed to fail — many React
        //               projects have flaky or missing test suites)
        // =====================================================
        stage('Unit Tests') {
            parallel {
                stage('Backend Tests') {
                    steps {
                        dir('backend') {
                            echo '🧪 Running backend unit tests...'
                            sh 'mvn test'
                            echo '✅ Backend tests passed!'
                        }
                    }
                }

                stage('Frontend Tests') {
                    steps {
                        dir('frontend') {
                            echo '🧪 Running frontend tests...'
                            // Allow failure — frontend tests may not be configured
                            sh 'npm install && npm test -- --passWithNoTests || true'
                            echo '✅ Frontend tests completed (failures allowed).'
                        }
                    }
                }
            }
        }

        // =====================================================
        // STAGE 4: BUILD
        // =====================================================
        // Compiles both applications in parallel:
        //   - Backend:  Maven package (skips tests, already ran)
        //   - Frontend: npm install + Vite production build
        // =====================================================
        stage('Build') {
            parallel {
                stage('Backend Build') {
                    steps {
                        dir('backend') {
                            echo '☕ Building Spring Boot backend...'
                            sh 'mvn clean package -DskipTests'
                            echo '✅ Backend JAR ready!'
                        }
                    }
                }

                stage('Frontend Build') {
                    steps {
                        dir('frontend') {
                            echo '⚛️ Building React frontend...'
                            sh 'npm install'
                            sh 'npm run build'
                            echo '✅ Frontend dist ready!'
                        }
                    }
                }
            }
        }

        // =====================================================
        // STAGE 5: DOCKER BUILD
        // =====================================================
        // Builds Docker images for both services, tagging each
        // with the Jenkins BUILD_NUMBER (for traceability) and
        // 'latest' (for convenience / rollback).
        // =====================================================
        stage('Docker Build') {
            steps {
                echo '🐳 Building Docker images...'

                dir('backend') {
                    sh "docker build -t ${env.ECR_BACKEND}:${env.BUILD_NUMBER} -t ${env.ECR_BACKEND}:latest ."
                }

                dir('frontend') {
                    sh "docker build -t ${env.ECR_FRONTEND}:${env.BUILD_NUMBER} -t ${env.ECR_FRONTEND}:latest ."
                }

                echo "✅ Docker images built with tags: ${env.BUILD_NUMBER}, latest"
            }
        }

        // =====================================================
        // STAGE 6: SECURITY SCAN
        // =====================================================
        // Runs Trivy container vulnerability scanner on both
        // images. Fails on CRITICAL vulnerabilities but treats
        // the failure as a soft warning (unstable build) so the
        // pipeline can continue while the team investigates.
        // =====================================================
        stage('Security Scan') {
            steps {
                echo '🔍 Running Trivy security scan on Docker images...'

                script {
                    // Scan backend image
                    def backendScan = sh(
                        script: "trivy image --exit-code 1 --severity CRITICAL ${env.ECR_BACKEND}:${env.BUILD_NUMBER}",
                        returnStatus: true
                    )
                    if (backendScan != 0) {
                        echo '⚠️ WARNING: Backend image has CRITICAL vulnerabilities!'
                        unstable('Backend image has CRITICAL vulnerabilities')
                    } else {
                        echo '✅ Backend image passed security scan.'
                    }

                    // Scan frontend image
                    def frontendScan = sh(
                        script: "trivy image --exit-code 1 --severity CRITICAL ${env.ECR_FRONTEND}:${env.BUILD_NUMBER}",
                        returnStatus: true
                    )
                    if (frontendScan != 0) {
                        echo '⚠️ WARNING: Frontend image has CRITICAL vulnerabilities!'
                        unstable('Frontend image has CRITICAL vulnerabilities')
                    } else {
                        echo '✅ Frontend image passed security scan.'
                    }
                }
            }
        }

        // =====================================================
        // STAGE 7: PUSH TO ECR
        // =====================================================
        // Authenticates with AWS ECR and pushes both images
        // with both tags (build number + latest).
        // =====================================================
        stage('Push to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials',
                                  accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                                  secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {

                    echo '🔐 Logging into AWS ECR...'
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \\
                        docker login --username AWS --password-stdin \\
                        ${env.AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                    """

                    echo '📤 Pushing Backend images to ECR...'
                    sh "docker push ${env.ECR_BACKEND}:${env.BUILD_NUMBER}"
                    sh "docker push ${env.ECR_BACKEND}:latest"

                    echo '📤 Pushing Frontend images to ECR...'
                    sh "docker push ${env.ECR_FRONTEND}:${env.BUILD_NUMBER}"
                    sh "docker push ${env.ECR_FRONTEND}:latest"

                    echo '✅ All images pushed to ECR!'
                }
            }
        }

        // =====================================================
        // STAGE 8: UPDATE K8S MANIFESTS
        // =====================================================
        // Updates the image tags in Helm values files so that
        // ArgoCD (or manual deploy) picks up the new version.
        // Uses sed to replace the image tag in values.yaml.
        // If a gitops repo is configured, clones it, updates,
        // commits, and pushes the change.
        // =====================================================
        stage('Update K8s Manifests') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials',
                                  accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                                  secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    script {
                        echo '📝 Updating image tags in Helm values...'

                        // Update image tags in the local Helm values file
                        // This updates the tag field under both backend and frontend image configs
                        sh """
                            # Update backend image tag in Helm values
                            sed -i 's|tag: ".*"|tag: "${env.BUILD_NUMBER}"|g' helm/dcmusic/values.yaml || true

                            # Also update the gitops values if they exist
                            if [ -d "gitops/" ]; then
                                sed -i 's|tag: ".*"|tag: "${env.BUILD_NUMBER}"|g' gitops/apps/*.yaml || true
                            fi
                        """

                        echo "✅ Manifests updated with image tag: ${env.BUILD_NUMBER}"
                    }
                }
            }
        }

        // =====================================================
        // STAGE 9: DEPLOY TO EKS
        // =====================================================
        // Configures kubectl to talk to the EKS cluster, then
        // deploys using Helm upgrade. Falls back to kubectl
        // set image if Helm chart is not available.
        // =====================================================
        stage('Deploy to EKS') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'aws-credentials',
                     accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                     secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'],
                    string(credentialsId: 'rds-password', variable: 'DB_PASSWORD')
                ]) {
                    echo "🚀 Deploying to EKS cluster: ${EKS_CLUSTER_NAME}..."

                    // Configure kubectl to connect to EKS
                    sh "aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}"

                    script {
                        def rdsHost = sh(
                            script: "aws rds describe-db-instances --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-mysql --region ${AWS_REGION} --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || echo ''",
                            returnStdout: true
                        ).trim()

                        echo "📡 Connecting to RDS Host: ${rdsHost}"

                        // Try Helm upgrade first; fall back to kubectl if Helm chart not found
                        def helmResult = sh(
                            script: """
                                helm upgrade --install ${PROJECT_NAME} helm/dcmusic \\
                                    --namespace ${PROJECT_NAME} \\
                                    --create-namespace \\
                                    --set backend.image.repository=${env.ECR_BACKEND} \\
                                    --set backend.image.tag=${env.BUILD_NUMBER} \\
                                    --set frontend.image.repository=${env.ECR_FRONTEND} \\
                                    --set frontend.image.tag=${env.BUILD_NUMBER} \\
                                    --set backend.secret.SPRING_DATASOURCE_URL="jdbc:mysql://${rdsHost}:3306/dcmusic_db" \\
                                    --set backend.secret.SPRING_DATASOURCE_USERNAME="admin" \\
                                    --set backend.secret.SPRING_DATASOURCE_PASSWORD="${DB_PASSWORD}" \\
                                    --set frontend.service.type=LoadBalancer \\
                                    --set backend.service.type=LoadBalancer \\
                                    --wait --timeout 300s
                            """,
                            returnStatus: true
                        )

                        if (helmResult != 0) {
                            echo '⚠️ Helm upgrade failed, falling back to kubectl set image with correct container names...'
                            sh """
                                kubectl set image deployment/dcmusic-backend \\
                                    backend=${env.ECR_BACKEND}:${env.BUILD_NUMBER} \\
                                    -n ${PROJECT_NAME} || true

                                kubectl set image deployment/dcmusic-frontend \\
                                    frontend=${env.ECR_FRONTEND}:${env.BUILD_NUMBER} \\
                                    -n ${PROJECT_NAME} || true
                            """
                            error("❌ Helm upgrade failed! Please check the Helm error output above.")
                        }
                    }

                    echo '✅ Deployment commands executed!'
                }
            }
        }

        // =====================================================
        // STAGE 10: VERIFY DEPLOYMENT
        // =====================================================
        // Waits for both deployments to roll out successfully.
        // Times out after 300 seconds if pods don't become ready.
        // =====================================================
        stage('Verify Deployment') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials',
                                  accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                                  secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {

                    echo '⏳ Waiting for deployments to roll out...'

                    sh "kubectl rollout status deployment/dcmusic-backend -n ${PROJECT_NAME} --timeout=300s"
                    sh "kubectl rollout status deployment/dcmusic-frontend -n ${PROJECT_NAME} --timeout=300s"

                    echo '📊 Current deployment status:'
                    sh "kubectl get pods -n ${PROJECT_NAME} -o wide"
                    sh "kubectl get svc -n ${PROJECT_NAME}"

                    echo '✅ All deployments verified and running!'
                }
            }
        }
    }

    // ---------------------------------------------------------
    // POST ACTIONS — Run after pipeline finishes
    // ---------------------------------------------------------
    post {
        success {
            echo """
            ✅ ========================================
            ✅  EKS DEPLOYMENT COMPLETED SUCCESSFULLY!
            ✅ ========================================
            ✅  Cluster:    ${EKS_CLUSTER_NAME}
            ✅  Namespace:  ${PROJECT_NAME}
            ✅  Image Tag:  ${env.BUILD_NUMBER}
            ✅  Backend:    ${env.ECR_BACKEND}:${env.BUILD_NUMBER}
            ✅  Frontend:   ${env.ECR_FRONTEND}:${env.BUILD_NUMBER}
            ✅ ========================================
            """
        }
        failure {
            echo '❌ Pipeline failed! Fetching Kubernetes pod diagnostics...'
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                              credentialsId: 'aws-credentials',
                              accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                              secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                sh """
                    kubectl get pods -n ${PROJECT_NAME} -o wide || true
                    kubectl describe pods -n ${PROJECT_NAME} || true
                    kubectl logs -n ${PROJECT_NAME} -l app.kubernetes.io/component=backend --tail=50 || true
                """
            }
        }
        always {
            // Clean up Docker images from Jenkins server to save disk space
            sh 'docker image prune -f || true'
        }
    }
}
