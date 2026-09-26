# ConnectHub — Deployment Guide

## Overview

ConnectHub uses **Podman (rootless) + Quadlet + systemd** as the primary deployment method, with a `podman-compose.yaml` provided for local development convenience.

## Quick Start (Development)

### Prerequisites
- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (Python package manager)
- Podman 4.x+ **or** Docker 24+
- podman-compose **or** docker compose

### 1. Start Infrastructure Services

```bash
# Using podman-compose
podman-compose -f deploy/podman-compose.yaml up -d

# Using docker compose
docker compose -f deploy/podman-compose.yaml up -d
```

This starts:
- **PostgreSQL 16** on port 5432
- **Redis 7** on port 6379
- **NATS 2.10** (JetStream) on port 4222 (client) and 8222 (monitoring)

### 2. Install Python Dependencies

```bash
uv sync --all-extras
```

### 3. Configure Environment

```bash
cp .env.example .env
# Edit .env with your settings (defaults work for local dev)
```

### 4. Run the API Server

```bash
uv run uvicorn connecthub.main:app --reload --host 0.0.0.0 --port 8000
```

### 5. Verify

```bash
curl http://localhost:8000/health
# → {"status":"healthy","version":"0.1.0","services":{"postgresql":{"status":"up"},...}}
```

## Production Deployment (Quadlet)

### Prerequisites
- Ubuntu Server 22.04+ LTS
- Podman 4.x+ (rootless)
- systemd user lingering enabled

### Setup

1. **Enable lingering** for the service user:
   ```bash
   sudo loginctl enable-linger $USER
   ```

2. **Copy Quadlet files** to the systemd user directory:
   ```bash
   mkdir -p ~/.config/containers/systemd/
   cp deploy/quadlet/*.container ~/.config/containers/systemd/
   cp deploy/quadlet/*.volume ~/.config/containers/systemd/
   cp deploy/quadlet/*.network ~/.config/containers/systemd/
   ```

3. **Reload systemd** and start services:
   ```bash
   systemctl --user daemon-reload
   systemctl --user start connecthub-postgres.service
   systemctl --user start connecthub-redis.service
   systemctl --user start connecthub-nats.service
   systemctl --user start connecthub-api.service
   systemctl --user start connecthub-nginx.service
   ```

4. **Enable on boot**:
   ```bash
   systemctl --user enable connecthub-postgres.service
   systemctl --user enable connecthub-redis.service
   systemctl --user enable connecthub-nats.service
   systemctl --user enable connecthub-api.service
   systemctl --user enable connecthub-nginx.service
   ```

### Service Dependencies

```
connecthub-nginx
  └─ connecthub-api
       ├─ connecthub-postgres
       ├─ connecthub-redis
       └─ connecthub-nats
```

### Monitoring

- **NATS**: `http://localhost:8222` (monitoring dashboard)
- **PostgreSQL**: `pg_isready` via health check
- **Redis**: `redis-cli ping` via health check
- **API Health**: `http://localhost:8000/health`

## File Reference

| File | Purpose |
|:---|:---|
| `quadlet/connecthub.network` | Shared bridge network |
| `quadlet/postgres-data.volume` | PostgreSQL persistent storage |
| `quadlet/redis-data.volume` | Redis persistent storage |
| `quadlet/nats-data.volume` | NATS JetStream persistent storage |
| `quadlet/connecthub-postgres.container` | PostgreSQL 16 service |
| `quadlet/connecthub-redis.container` | Redis 7 service |
| `quadlet/connecthub-nats.container` | NATS 2.10 + JetStream service |
| `quadlet/connecthub-nginx.container` | Nginx reverse proxy |
| `quadlet/connecthub-api.container` | FastAPI backend service |
| `nginx/nginx.conf` | Nginx main configuration |
| `nginx/conf.d/connecthub.conf` | Reverse proxy + TLS config |
| `nats/nats-server.conf` | NATS server configuration |
| `podman-compose.yaml` | Development convenience compose file |
