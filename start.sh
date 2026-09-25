#!/bin/bash

# Check if .env exists
if [ ! -f .env ]; then
  echo "Error: .env file not found. Please run ./setup.sh first."
  exit 1
fi

# List of service directories
SERVICES=("core" "media" "arr" "download")

echo "=== Starting HomeLab Services ==="

for service in "${SERVICES[@]}"; do
  if [ -d "$service" ]; then
    echo "Starting $service..."
    docker compose --env-file .env -f "$service/docker-compose.yml" up -d
    
  else
    echo "Warning: Directory $service not found. Skipping."
  fi
done
docker compose --project-directory . -f ./obsidian-sync/docker-compose.yml up -d

echo "All services started."
