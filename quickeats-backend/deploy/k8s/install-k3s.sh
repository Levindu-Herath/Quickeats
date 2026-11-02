#!/usr/bin/env bash
# One-time setup on the QuickEats server: install k3s and give the ubuntu and
# jenkins users kubectl access. Run as ubuntu: bash install-k3s.sh
#
# Port 80 must be free first (the old docker compose stack's Kong used it).
set -euo pipefail

K3S_CHANNEL="${K3S_CHANNEL:-v1.33}"   # minor version is pinned; patches come from the channel

if ss -ltn '( sport = :80 )' | grep -q LISTEN; then
  echo "Port 80 is in use. Stop the docker compose stack first." >&2
  exit 1
fi

# Traefik is disabled: Kong is the ingress, exposed by k3s ServiceLB on port 80.
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL="$K3S_CHANNEL" sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 600

for user in ubuntu jenkins; do
  home="$(getent passwd "$user" | cut -d: -f6)" || continue
  sudo mkdir -p "$home/.kube"
  sudo cp /etc/rancher/k3s/k3s.yaml "$home/.kube/config"
  sudo chown -R "$user:" "$home/.kube"
  sudo chmod 600 "$home/.kube/config"
done

# k3s's kubectl reads the root-only /etc/rancher/k3s/k3s.yaml unless KUBECONFIG is set
# (Jenkins sets it in the Jenkinsfile)
grep -q 'KUBECONFIG=' ~/.bashrc || echo 'export KUBECONFIG="$HOME/.kube/config"' >> ~/.bashrc
export KUBECONFIG="$HOME/.kube/config"

# The node registers a few seconds after k3s starts; `wait` fails if it doesn't exist yet
for _ in $(seq 60); do
  sudo k3s kubectl get nodes -o name 2>/dev/null | grep -q . && break
  sleep 2
done
sudo k3s kubectl wait --for=condition=Ready node --all --timeout=120s
kubectl get nodes -o wide
sudo -u jenkins env KUBECONFIG="$(getent passwd jenkins | cut -d: -f6)/.kube/config" kubectl get nodes
