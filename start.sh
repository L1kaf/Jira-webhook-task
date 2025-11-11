#!/bin/bash

CONTAINER_NAME="jira_webhook_issue"
IMAGE_NAME="jira_webhook_image"

echo "Stopping and removing old container (if exists)..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

echo "Building Docker image..."
docker build -t "$IMAGE_NAME" .

echo "Starting new container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -p 8095:80 \
  -v "./scripts:/scripts" \
  -v "./.env:/scripts/.env" \
  -v "./logs:/var/log" \
  --restart unless-stopped \
  "$IMAGE_NAME"
