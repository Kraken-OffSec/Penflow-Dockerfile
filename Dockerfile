# PenFlow All-in-One Container
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Environment variables with defaults
ENV ADMIN_USERNAME='penflow'
ENV ADMIN_EMAIL='penflow@krakensec.tech'
ENV ADMIN_PASSWORD='password'
ENV SECRET_KEY='secret-key-change-in-production'
ENV FRONTEND_URL="http://192.168.70.66:80"

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

# Create data directories for persistence
RUN mkdir -p /data/frontend /data/backend /data/uploads /data/config && \
    chown -R penflow:penflow /data

# Copy built frontend to nginx directory and data directory
RUN cp -r dist/* /var/www/html/ && \
    cp -r dist/* /data/frontend/

# Create nginx config with CORS support
RUN echo 'server {' > /etc/nginx/sites-available/penflow && \
    echo '    listen 80;' >> /etc/nginx/sites-available/penflow && \
    echo '    server_name localhost;' >> /etc/nginx/sites-available/penflow && \
    echo '    root /data/frontend;' >> /etc/nginx/sites-available/penflow && \
    echo '    index index.html;' >> /etc/nginx/sites-available/penflow && \
    echo '    ' >> /etc/nginx/sites-available/penflow && \
    echo '    # Add CORS headers for all requests' >> /etc/nginx/sites-available/penflow && \
    echo '    add_header Access-Control-Allow-Origin "*" always;' >> /etc/nginx/sites-available/penflow && \
    echo '    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;' >> /etc/nginx/sites-available/penflow && \
    echo '    add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization" always;' >> /etc/nginx/sites-available/penflow && \
    echo '    ' >> /etc/nginx/sites-available/penflow && \
    echo '    # Handle preflight requests' >> /etc/nginx/sites-available/penflow && \
    echo '    location ~ ^/api/ {' >> /etc/nginx/sites-available/penflow && \
    echo '        if ($request_method = OPTIONS) {' >> /etc/nginx/sites-available/penflow && \
    echo '            add_header Access-Control-Allow-Origin "*";' >> /etc/nginx/sites-available/penflow && \
    echo '            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";' >> /etc/nginx/sites-available/penflow && \
    echo '            add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization";' >> /etc/nginx/sites-available/penflow && \
    echo '            add_header Content-Length 0;' >> /etc/nginx/sites-available/penflow && \
    echo '            add_header Content-Type text/plain;' >> /etc/nginx/sites-available/penflow && \
    echo '            return 200;' >> /etc/nginx/sites-available/penflow && \
    echo '        }' >> /etc/nginx/sites-available/penflow && \
    echo '        proxy_pass http://localhost:8000;' >> /etc/nginx/sites-available/penflow && \
    echo '        proxy_set_header Host $host;' >> /etc/nginx/sites-available/penflow && \
    echo '        proxy_set_header X-Real-IP $remote_addr;' >> /etc/nginx/sites-available/penflow && \
    echo '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' >> /etc/nginx/sites-available/penflow && \
    echo '    }' >> /etc/nginx/sites-available/penflow && \
    echo '    ' >> /etc/nginx/sites-available/penflow && \
    echo '    location / {' >> /etc/nginx/sites-available/penflow && \
    echo '        try_files $uri $uri/ /index.html;' >> /etc/nginx/sites-available/penflow && \
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
    echo 'if [ -n "$ADMIN_PASSWORD" ]; then' >> /home/penflow/create-user.sh && \
    echo '  python3 create_user.py create "$ADMIN_USERNAME" "$ADMIN_EMAIL" "$ADMIN_PASSWORD"' >> /home/penflow/create-user.sh && \
    echo 'else' >> /home/penflow/create-user.sh && \
    echo '  python3 create_user.py create "$ADMIN_USERNAME" "$ADMIN_EMAIL"' >> /home/penflow/create-user.sh && \
    echo 'fi' >> /home/penflow/create-user.sh && \
    chmod +x /home/penflow/create-user.sh && \
    chown penflow:penflow /home/penflow/create-user.sh

# Expose ports
EXPOSE 80 8000 7474 7687 6379

# Create startup script that handles environment variables
RUN echo '#!/bin/bash' > /start-penflow.sh && \
    echo 'echo "Starting PenFlow with configuration:"' >> /start-penflow.sh && \
    echo 'echo "Admin Username: $ADMIN_USERNAME"' >> /start-penflow.sh && \
    echo 'echo "Admin Email: $ADMIN_EMAIL"' >> /start-penflow.sh && \
    echo 'echo "Frontend URL: $FRONTEND_URL"' >> /start-penflow.sh && \
    echo '' >> /start-penflow.sh && \

    echo '' >> /start-penflow.sh && \
    echo '# Ensure data directories exist and copy defaults if needed' >> /start-penflow.sh && \
    echo 'if [ ! -f /data/frontend/index.html ]; then' >> /start-penflow.sh && \
    echo '  echo "Copying default frontend files..."' >> /start-penflow.sh && \
    echo '  cp -r /var/www/html/* /data/frontend/' >> /start-penflow.sh && \
    echo 'fi' >> /start-penflow.sh && \
    echo '' >> /start-penflow.sh && \
    echo '# Update backend .env with dynamic values' >> /start-penflow.sh && \
    echo 'if [ ! -f /data/config/.env ]; then' >> /start-penflow.sh && \
    echo '  echo "Creating new .env file..."' >> /start-penflow.sh && \
    echo '  cat > /data/config/.env << EOF' >> /start-penflow.sh && \
    echo 'NEO4J_URI=bolt://localhost:7687' >> /start-penflow.sh && \
    echo 'NEO4J_USER=neo4j' >> /start-penflow.sh && \
    echo 'NEO4J_PASSWORD=password' >> /start-penflow.sh && \
    echo 'NEO4J_DATABASE=neo4j' >> /start-penflow.sh && \
    echo 'REDIS_URL=redis://localhost:6379' >> /start-penflow.sh && \
    echo 'SECRET_KEY="$SECRET_KEY"' >> /start-penflow.sh && \
    echo 'ALGORITHM=HS256' >> /start-penflow.sh && \
    echo 'ACCESS_TOKEN_EXPIRE_MINUTES=11520' >> /start-penflow.sh && \
    echo 'GOOGLE_API_KEY=' >> /start-penflow.sh && \
    echo 'BACKEND_CORS_ORIGINS=[\"*\"]' >> /start-penflow.sh && \
    echo 'PROJECT_NAME=PenFlow' >> /start-penflow.sh && \
    echo 'API_V1_STR=/api/v1' >> /start-penflow.sh && \
    echo 'ENABLE_REGISTRATION=false' >> /start-penflow.sh && \
    echo 'EOF' >> /start-penflow.sh && \
    echo '  chown penflow:penflow /data/config/.env' >> /start-penflow.sh && \
    echo 'else' >> /start-penflow.sh && \
    echo '  echo "Using existing .env file..."' >> /start-penflow.sh && \
    echo 'fi' >> /start-penflow.sh && \
    echo '' >> /start-penflow.sh && \
    echo '# Create symlink from app directory to config' >> /start-penflow.sh && \
    echo 'ln -sf /data/config/.env /home/penflow/penflow/backend/.env' >> /start-penflow.sh && \
    echo '' >> /start-penflow.sh && \

    echo '' >> /start-penflow.sh && \
    echo '# Start supervisor' >> /start-penflow.sh && \
    echo 'exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf' >> /start-penflow.sh && \
    chmod +x /start-penflow.sh

# Start with dynamic configuration script
CMD ["/start-penflow.sh"]

