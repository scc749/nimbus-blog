#!/usr/bin/env bash
set -euo pipefail

# Network for inter-container DNS
docker network inspect nimbus-net >/dev/null 2>&1 || docker network create nimbus-net

# PostgreSQL
docker pull postgres
docker run -d --name postgres \
  --network nimbus-net \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=myp455w0rd \
  -e POSTGRES_DB=blog_db \
  -p 5432:5432 \
  -v /srv/postgres:/var/lib/postgresql \
  --restart=always \
  postgres

# Redis
docker pull redis
docker run -d --name redis \
  --network nimbus-net \
  -p 6379:6379 \
  -v /srv/redis/data:/data \
  --restart=always \
  redis

# MinIO
docker pull minio/minio:RELEASE.2025-04-22T22-12-26Z
docker run -d --name minio-server \
  --network nimbus-net \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=admin123456 \
  -v /srv/minio/data:/data \
  --restart=always \
  minio/minio:RELEASE.2025-04-22T22-12-26Z server /data --console-address ":9001"
