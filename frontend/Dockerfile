# ==============================================================
#  DC Music Frontend — Hardened Multi-Stage Dockerfile
# ==============================================================
#  Stage 1: Build React+Vite app with Node
#  Stage 2: Serve with Nginx (non-root, security headers)
# ==============================================================

# ---- Stage 1: Build the frontend ----
FROM node:20-alpine AS builder
WORKDIR /app

# Copy dependency files first for better layer caching
COPY package.json package-lock.json* ./
RUN npm install

# Copy source and build
COPY . .
RUN npm run build

# ---- Stage 2: Serve with Nginx ----
FROM nginx:alpine

# Labels for image metadata
LABEL maintainer="DC Music DevOps <devops@dcmusic.app>"
LABEL version="1.0"
LABEL description="DC Music React Frontend served by Nginx"

# Copy the built Vite dist into the Nginx web root
COPY --from=builder /app/dist /usr/share/nginx/html

# Custom Nginx configuration with:
#   - Security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection)
#   - SPA routing (try_files fallback to index.html)
#   - Gzip compression for performance
#   - Cache headers for static assets
RUN cat > /etc/nginx/conf.d/default.conf << 'EOF'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml;
    gzip_min_length 256;

    # SPA routing — fallback to index.html for React Router
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets (JS, CSS, images) for 1 year
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Health endpoint for Kubernetes probes
    location /health {
        access_log off;
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF

# Ensure nginx user can write to required directories
RUN chown -R nginx:nginx /var/cache/nginx /var/log/nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

EXPOSE 80

# Healthcheck — verifies Nginx is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:80/health || exit 1

# Run as non-root nginx user
USER nginx

CMD ["nginx", "-g", "daemon off;"]
