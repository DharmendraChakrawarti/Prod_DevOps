# ==============================================================
#  DC Music Backend — Hardened Multi-Stage Dockerfile
# ==============================================================
#  Stage 1: Build with Maven
#  Stage 2: Minimal JRE runtime with non-root user & healthcheck
# ==============================================================

# ---- Stage 1: Build the backend JAR ----
FROM maven:3.9.6-eclipse-temurin-17 AS builder
WORKDIR /app

# Copy dependency descriptor first for better layer caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and build (skip tests — they run in CI)
COPY src ./src
RUN mvn clean package -DskipTests

# ---- Stage 2: Minimal runtime image ----
FROM eclipse-temurin:17-jre-alpine

# Labels for image metadata
LABEL maintainer="DC Music DevOps <devops@dcmusic.app>"
LABEL version="1.0"
LABEL description="DC Music Spring Boot Backend API"

WORKDIR /app

# Install curl for healthcheck (minimal addition to alpine)
RUN apk add --no-cache curl

# Create non-root user for security
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Create application directories with correct ownership
RUN mkdir -p /app/data /app/uploads && \
    chown -R appuser:appgroup /app

# Copy the built JAR from the builder stage
COPY --from=builder --chown=appuser:appgroup /app/target/backend-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080

# Healthcheck — verifies the Spring Boot Actuator health endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Switch to non-root user
USER appuser

# JVM tuning flags:
#   MaxRAMPercentage=75.0 — use up to 75% of container memory limit
#   UseG1GC              — G1 garbage collector (best for containerized apps)
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-XX:+UseG1GC", "-jar", "app.jar"]
