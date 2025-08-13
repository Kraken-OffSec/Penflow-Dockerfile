This is just an all in one version of PenFlow. All credit goes to to original creator at: https://github.com/rb-x/penflow

The credentials are listed in the log output.

# PenFlow Docker Container

This Dockerfile automatically installs and runs [PenFlow](https://github.com/Kraken-OffSec/penflow), a visual methodology tracking platform tailored for offensive security assessments.

## What is PenFlow?

PenFlow is a mind-mapping platform designed specifically for cybersecurity professionals. It helps you visualize, track, and share your security testing methodologies while maintaining complete control over your sensitive data.

### Key Features:
- 🗺️ **Interactive Mind Maps**: Create and navigate complex security testing workflows
- 🤖 **AI-Powered Assistance**: Generate node suggestions and expand methodologies
- 📋 **Command Templates**: Save and reuse CLI commands with variable substitution
- 📊 **Progress Tracking**: Visualize testing progress and methodology coverage
- 🔐 **Self-Hosted**: Run entirely on your infrastructure
- 🔒 **Encrypted Exports**: AES-256-GCM encryption for secure sharing

## Quick Start

### Prerequisites
- Docker installed on your system
- At least 4GB of available RAM
- Ports 5173, 8000, 7474, 7687, 6379, and 8081 available

### Build and Run

1. **Build the Docker image:**
   ```bash
   docker build -t penflow .
   ```

2. **Run the container:**
   ```bash
   docker run
     -d
     --name='PenFlow'
     --net='br0'
     --ip='192.168.70.114'
     --pids-limit 2048
     -e TZ="America/New_York"
     -e HOST_OS="Unraid"
     -e HOST_HOSTNAME="KrakenTower"
     -e HOST_CONTAINERNAME="PenFlow"
     -e 'ADMIN_USERNAME'='ar1ste1a'
     -e 'ADMIN_EMAIL'='ehosinski@krakensec.tech'
     -e 'ADMIN_PASSWORD'='xFWx8Ma$54%gZ^cq'
     -e 'SECRET_KEY'='Dx^6&NPz7MCvRjANk&gz*eD$8hChGQd^'
     -e 'FRONTEND_URL'='http://192.168.70.32:28080'
     -e 'HOST_PORT'='80'
     -e 'HOST_IP'='192.168.70.114'
   ```

   **Note:** No `--privileged` flag needed! This container runs all services directly without Docker-in-Docker.

3. **Monitor the startup process:**
   ```bash
   docker logs -f penflow-container
   ```

   Wait for all services to be ready (this may take 2-3 minutes on first run).

4. **Access the application:**
   - **Frontend (Main App)**: http://localhost:5173
   - **Backend API**: http://localhost:8000
   - **API Documentation**: http://localhost:8000/docs
   - **Neo4j Browser**: http://localhost:7474 (username: `neo4j`, password: `password`)
   - **Redis**: Available on port 6379 (no web interface included)

## Container Architecture

This container runs all PenFlow services directly using supervisor for process management:

- **Frontend**: React 19 + TypeScript + Vite (built and served with `serve`)
- **Backend**: FastAPI (Python 3.12) with pipenv dependencies
- **Database**: Neo4j graph database (Community Edition)
- **Cache**: Redis server
- **Process Manager**: Supervisor manages all services

## Configuration

### Default Credentials
- **Neo4j Database**: 
  - Username: `neo4j`
  - Password: `password`
- **Application**: No authentication required in development mode

### Environment Variables
The container automatically creates a `.env.development` file with secure defaults. To customize:

1. **Access the container:**
   ```bash
   docker exec -it penflow-container bash
   ```

2. **Edit the environment file:**
   ```bash
   cd /home/penflow/penflow
   nano .env.development
   ```

3. **Restart services:**
   ```bash
   ./run.sh stop
   ./run.sh dev
   ```

### Adding AI Features
To enable AI-powered assistance:

1. Get a [Gemini API Key](https://aistudio.google.com/apikey)
2. Access the container and edit the environment file:
   ```bash
   docker exec -it penflow-container bash
   cd /home/penflow/penflow
   nano .env.development
   ```
3. Add your API key:
   ```
   GOOGLE_API_KEY=your_api_key_here
   ```
4. Restart the services:
   ```bash
   ./run.sh stop
   ./run.sh dev
   ```

## Container Management

### View Logs
```bash
# Container logs
docker logs penflow-container

# PenFlow service logs
docker exec -it penflow-container bash
cd /home/penflow/penflow
docker-compose -f docker-compose.dev.yml logs
```

### Stop the Container
```bash
docker stop penflow-container
```

### Start the Container
```bash
docker start penflow-container
```

### Remove the Container
```bash
docker stop penflow-container
docker rm penflow-container
```

## Data Persistence

By default, data is stored inside the container and will be lost when the container is removed. To persist data:

```bash
docker run -d \
  --name penflow-container \
  --privileged \
  -p 5173:5173 \
  -p 8000:8000 \
  -p 7474:7474 \
  -p 7687:7687 \
  -p 6379:6379 \
  -p 8081:8081 \
  -v penflow-neo4j-data:/home/penflow/penflow/neo4j-data-dev \
  -v penflow-redis-data:/home/penflow/penflow/redis-data-dev \
  penflow
```

## Troubleshooting

### Build Issues
- **Docker version**: Ensure you're using a recent version of Docker (20.10+)
- **Build failures**: Check that you have sufficient disk space and memory during build

### Container Won't Start
- Ensure Docker is running on your host system
- Check that required ports are not in use: `netstat -tulpn | grep -E '(5173|8000|7474|7687|6379)'`
- Verify you have sufficient system resources (minimum 2GB RAM recommended)
- Check if the container started: `docker ps -a`

### Services Not Accessible
- Wait a few minutes for all services to fully start (monitor with `docker logs -f penflow-container`)
- Check container logs: `docker logs penflow-container`
- Verify port mappings are correct
- Test individual services:
  ```bash
  curl http://localhost:8000/health  # Backend health check
  curl http://localhost:5173         # Frontend
  ```

### Performance Issues
- Increase Docker memory allocation (recommended: 2GB+)
- Close unnecessary applications to free up resources
- Monitor resource usage: `docker stats penflow-container`

### Service Issues
- Check individual service logs: `docker exec penflow-container supervisorctl status`
- Restart a specific service: `docker exec penflow-container supervisorctl restart <service_name>`
- View service logs: `docker exec penflow-container tail -f /var/log/<service>.log`

## Security Considerations

- This container runs in privileged mode for Docker-in-Docker functionality
- Default credentials are used for development convenience
- For production use, consider the official PenFlow production deployment guide
- The container is designed for local development and testing

## Support

For issues specific to PenFlow functionality, visit:
- [PenFlow GitHub Repository](https://github.com/rb-x/penflow)
- [PenFlow Documentation](https://docs.penflow.sh)

For Docker container issues, please check the troubleshooting section above.
