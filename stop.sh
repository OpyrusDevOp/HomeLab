#!/bin/bash

# List of service directories
SERVICES=("core" "media" "arr" "download")

echo "=== Stopping HomeLab Services ==="

for service in "${SERVICES[@]}"; do
    if [ -d "$service" ]; then
        echo "Stopping $service..."
        docker compose -f "$service/docker-compose.yml" stop
    fi
done

echo "All services stopped."
