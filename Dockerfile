# PenFlow All-in-One Container - Replicates ./run.sh prod in single container
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install all required dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    openjdk-11-jre-headless \
    redis-server \
    nginx \
    supervisor \
    netcat \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js and pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs && \
    npm install -g pnpm

# Install Neo4j
RUN wget -O - https://debian.neo4j.com/neotechnology.gpg.key | apt-key add - && \
    echo 'deb https://debian.neo4j.com stable latest' | tee -a /etc/apt/sources.list.d/neo4j.list && \
    apt-get update && \
    apt-get install -y neo4j && \
    rm -rf /var/lib/apt/lists/*

# Configure Neo4j
RUN sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/' /etc/neo4j/neo4j.conf && \
    sed -i 's/#dbms.connector.bolt.listen_address=:7687/dbms.connector.bolt.listen_address=0.0.0.0:7687/' /etc/neo4j/neo4j.conf && \
    sed -i 's/#dbms.connector.http.listen_address=:7474/dbms.connector.http.listen_address=0.0.0.0:7474/' /etc/neo4j/neo4j.conf && \
    neo4j-admin dbms set-initial-password password

# Create penflow user
RUN useradd -m -s /bin/bash penflow

# Clone PenFlow repository
WORKDIR /home/penflow
RUN git clone https://github.com/rb-x/penflow.git penflow && \
    chown -R penflow:penflow /home/penflow

# Install Python dependencies
RUN pip3 install fastapi uvicorn[standard] neo4j redis python-multipart python-dotenv pydantic-settings passlib[bcrypt] python-jose pydantic[email] httpx cryptography google-generativeai

# Build frontend
WORKDIR /home/penflow/penflow/frontend
RUN pnpm install --frozen-lockfile && \
    pnpm build

# Copy built frontend to nginx directory
RUN cp -r dist/* /var/www/html/

# Create nginx config
RUN echo 'server {' > /etc/nginx/sites-available/penflow && \
    echo '    listen 80;' >> /etc/nginx/sites-available/penflow && \
    echo '    server_name localhost;' >> /etc/nginx/sites-available/penflow && \
    echo '    root /var/www/html;' >> /etc/nginx/sites-available/penflow && \
    echo '    index index.html;' >> /etc/nginx/sites-available/penflow && \
    echo '    location / {' >> /etc/nginx/sites-available/penflow && \
    echo '        try_files $uri $uri/ /index.html;' >> /etc/nginx/sites-available/penflow && \
    echo '    }' >> /etc/nginx/sites-available/penflow && \
    echo '    location /api/ {' >> /etc/nginx/sites-available/penflow && \
    echo '        proxy_pass http://localhost:8000/api/;' >> /etc/nginx/sites-available/penflow && \
    echo '        proxy_set_header Host $host;' >> /etc/nginx/sites-available/penflow && \
    echo '        proxy_set_header X-Real-IP $remote_addr;' >> /etc/nginx/sites-available/penflow && \
    echo '    }' >> /etc/nginx/sites-available/penflow && \
    echo '}' >> /etc/nginx/sites-available/penflow && \
    ln -s /etc/nginx/sites-available/penflow /etc/nginx/sites-enabled/ && \
    rm /etc/nginx/sites-enabled/default

# Create backend environment file
RUN echo 'NEO4J_URI=bolt://localhost:7687' > /home/penflow/penflow/backend/.env && \
    echo 'NEO4J_USER=neo4j' >> /home/penflow/penflow/backend/.env && \
    echo 'NEO4J_PASSWORD=password' >> /home/penflow/penflow/backend/.env && \
    echo 'NEO4J_DATABASE=neo4j' >> /home/penflow/penflow/backend/.env && \
    echo 'REDIS_URL=redis://localhost:6379' >> /home/penflow/penflow/backend/.env && \
    echo 'SECRET_KEY=your-secret-key-here-change-in-production' >> /home/penflow/penflow/backend/.env && \
    echo 'ALGORITHM=HS256' >> /home/penflow/penflow/backend/.env && \
    echo 'ACCESS_TOKEN_EXPIRE_MINUTES=11520' >> /home/penflow/penflow/backend/.env && \
    echo 'GOOGLE_API_KEY=' >> /home/penflow/penflow/backend/.env && \
    echo 'BACKEND_CORS_ORIGINS=[\"*\"]' >> /home/penflow/penflow/backend/.env && \
    echo 'PROJECT_NAME=PenFlow' >> /home/penflow/penflow/backend/.env && \
    echo 'API_V1_STR=/api/v1' >> /home/penflow/penflow/backend/.env && \
    echo 'ENABLE_REGISTRATION=false' >> /home/penflow/penflow/backend/.env && \
    chown penflow:penflow /home/penflow/penflow/backend/.env

# Create backend startup script
RUN echo '#!/bin/bash' > /home/penflow/start-backend.sh && \
    echo 'cd /home/penflow/penflow/backend' >> /home/penflow/start-backend.sh && \
    echo 'set -a' >> /home/penflow/start-backend.sh && \
    echo 'source .env' >> /home/penflow/start-backend.sh && \
    echo 'set +a' >> /home/penflow/start-backend.sh && \
    echo 'exec python3 -m uvicorn main:app --host 0.0.0.0 --port 8000' >> /home/penflow/start-backend.sh && \
    chmod +x /home/penflow/start-backend.sh && \
    chown penflow:penflow /home/penflow/start-backend.sh

# Create supervisor configuration for all services
RUN mkdir -p /etc/supervisor/conf.d && \
    echo '[supervisord]' > /etc/supervisor/conf.d/penflow.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '[program:neo4j]' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'command=/usr/bin/neo4j console' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'user=neo4j' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '[program:redis]' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'command=/usr/bin/redis-server' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'user=redis' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '[program:backend]' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'command=/home/penflow/start-backend.sh' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'user=penflow' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '[program:nginx]' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'command=/usr/sbin/nginx -g "daemon off;"' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '' >> /etc/supervisor/conf.d/penflow.conf && \
    echo '[program:create-user]' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'command=/home/penflow/create-user.sh' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'user=penflow' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'autorestart=false' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'startsecs=0' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'stderr_logfile=/dev/stderr' >> /etc/supervisor/conf.d/penflow.conf && \
    echo 'stderr_logfile_maxbytes=0' >> /etc/supervisor/conf.d/penflow.conf

# Create user creation script
RUN echo '#!/bin/bash' > /home/penflow/create-user.sh && \
    echo 'sleep 15' >> /home/penflow/create-user.sh && \
    echo 'cd /home/penflow/penflow/backend' >> /home/penflow/create-user.sh && \
    echo 'set -a' >> /home/penflow/create-user.sh && \
    echo 'source .env' >> /home/penflow/create-user.sh && \
    echo 'set +a' >> /home/penflow/create-user.sh && \
    echo 'python3 create_user.py create admin admin@yourcompany.com' >> /home/penflow/create-user.sh && \
    chmod +x /home/penflow/create-user.sh && \
    chown penflow:penflow /home/penflow/create-user.sh

# Expose ports
EXPOSE 80 8000 7474 7687 6379

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

