#!/usr/bin/env bash
# Deploy one image tag of QuickEats to Kubernetes: secrets, manifests, rollout.
# Used by Jenkins for both normal deploys and rollbacks.
#
# Usage: ENV_PROD=/path/to/.env.prod ECR_REGISTRY=<registry> deploy.sh <image-tag>
#   Without ECR_REGISTRY the images are used by their local names (local k3d test).
set -euo pipefail

TAG="${1:?usage: deploy.sh <image-tag>}"
ENV_FILE="${ENV_PROD:?ENV_PROD must point to the .env.prod file}"
REGISTRY="${ECR_REGISTRY:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NS=quickeats
IMAGES="identity catalog order payment notification admin"

# Value of KEY in the env file: last occurrence wins, CR and surrounding quotes stripped
env_get() {
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r' \
    | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}
require() { [ -n "$(env_get "$1")" ] || { echo "$1 is not set in .env.prod" >&2; exit 1; }; }

for key in POSTGRES_PASSWORD JWT_SECRET GRAFANA_ADMIN_PASSWORD; do require "$key"; done

kubectl apply -f "$HERE/base/namespaces.yaml"

# --- Secrets: only the keys the pods use, never the whole env file ---
echo "==> Secrets"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

pg="$(env_get POSTGRES_PASSWORD)"
{
  # Each database falls back to POSTGRES_PASSWORD when its own password is empty
  for db in IDENTITY CATALOG ORDER PAYMENT; do
    pw="$(env_get "${db}_DB_PASSWORD")"
    echo "${db}_DB_PASSWORD=${pw:-$pg}"
  done
  echo "JWT_SECRET=$(env_get JWT_SECRET)"
  echo "ADMIN_EMAIL=$(env_get ADMIN_EMAIL)"
  echo "ADMIN_PASSWORD=$(env_get ADMIN_PASSWORD)"
} > "$tmp/quickeats.env"
kubectl -n "$NS" create secret generic quickeats-env --from-env-file="$tmp/quickeats.env" \
  --dry-run=client -o yaml | kubectl apply -f -

printf '%s' "$(env_get GRAFANA_ADMIN_PASSWORD)" > "$tmp/grafana-password"
kubectl -n monitoring create secret generic grafana-admin --from-file=password="$tmp/grafana-password" \
  --dry-run=client -o yaml | kubectl apply -f -

# ECR tokens last 12 h; refreshed on every deploy. Pods only pull when their tag
# changes, so a node restart between deploys reuses the cached images.
if [ -n "$REGISTRY" ]; then
  echo "==> Registry credentials"
  echo "$REGISTRY" | docker-credential-ecr-login get | python3 -c '
import base64, json, sys
c = json.load(sys.stdin)
auth = base64.b64encode(f"{c[\"Username\"]}:{c[\"Secret\"]}".encode()).decode()
print(json.dumps({"auths": {c["ServerURL"]: {"auth": auth}}}))' > "$tmp/dockerconfig.json"
  kubectl -n "$NS" create secret generic ecr-pull --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$tmp/dockerconfig.json" --dry-run=client -o yaml | kubectl apply -f -
fi

# --- Manifests: base + this release's image tags ---
echo "==> Applying manifests for $TAG"
release="$HERE/release"   # generated, git-ignored
mkdir -p "$release"
{
  echo "apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "kind: Kustomization"
  echo "resources:"
  echo "  - ../base"
  echo "images:"
  for img in $IMAGES; do
    echo "  - name: quickeats-$img"
    [ -n "$REGISTRY" ] && echo "    newName: $REGISTRY/quickeats-$img"
    echo "    newTag: \"$TAG\""
  done
} > "$release/kustomization.yaml"
kubectl apply -k "$release"

# --- Wait for the rollout; a failure here makes Jenkins roll back ---
# 10 min per resource: a first deploy pulls ~600 MB of third-party images, and the
# first resource waited on absorbs that whole pull.
echo "==> Waiting for rollout"
for kind in statefulset deployment; do
  for res in $(kubectl -n "$NS" get "$kind" -o name); do
    kubectl -n "$NS" rollout status "$res" --timeout=600s
  done
done
echo "==> $TAG rolled out"
