#!/usr/bin/env bash
# Deploy one image tag of the QuickEats stack: pull, migrate, start.
# Usage: deploy.sh <image-tag>
# Used by Jenkins for both normal deploys and rollbacks.
set -euo pipefail

TAG="${1:?usage: deploy.sh <image-tag>}"
cd "${DEPLOY_DIR:-/opt/quickeats}"

# Shell env overrides IMAGE_TAG from .env.prod
export IMAGE_TAG="$TAG"
dc() { docker compose -p quickeats -f docker-compose.prod.yml --env-file .env.prod "$@"; }

echo "==> Pulling images for $TAG"
dc pull --quiet identity catalog order payment notification admin

# Each service migrates its own database; any failure stops the deploy before the switch.
echo "==> Running migrations"
for svc in identity catalog order payment; do
  dc run --rm "$svc-migrate"
done

echo "==> Starting stack on $TAG"
dc up -d --remove-orphans

# Kong, Prometheus and Grafana only read their mounted config at startup, and compose
# doesn't notice a changed mounted file, so restart them to pick up this commit's
# routes, scrape targets, alert rules and dashboards.
echo "==> Reloading Kong routes and monitoring config"
dc restart kong prometheus grafana
