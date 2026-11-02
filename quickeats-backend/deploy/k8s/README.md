# QuickEats on Kubernetes (k3s)

Production runs on a single-node [k3s](https://k3s.io) cluster on EC2 (provisioned by
[`../../terraform`](../../terraform)). Jenkins builds the images, pushes them to ECR and
deploys with `kubectl apply -k`.

```
                         ┌──────────────── namespace: quickeats ────────────────┐
 internet ──:80──► Kong ─┼─► identity ─► identity-db   (Postgres, StatefulSet)    │
   (ServiceLB)           ├─► catalog  ─► catalog-db                               │
                         ├─► order    ─► order-db        ┌──► Kafka (KRaft)       │
                         ├─► payment  ─► payment-db      │    Redis               │
                         ├─► notification (WebSocket) ───┘                        │
                         └─► admin (React, nginx)                                 │
                         └────────────────────────────────────────────────────────┘
   namespace: monitoring   Prometheus ◄─ kubelet/cAdvisor, kube-state-metrics,
                           Grafana       node-exporter, Kong /metrics
```

## Layout

| Path | What |
|---|---|
| `base/data/` | One Postgres server per service from a shared template (`postgres/`), Redis, Kafka |
| `base/apps/` | The five Go services and the admin dashboard |
| `base/gateway/` | Kong (DB-less); routes are `../../../infra/kong/kong.yml`, shared with local docker compose |
| `base/monitoring/` | Prometheus (Kubernetes service discovery + alert rules), Grafana (provisioned dashboard), node-exporter, kube-state-metrics |
| `deploy.sh` | Creates the Secrets, renders `base` with the release's image tags, applies, waits for rollout |
| `smoke-test.sh` | End-to-end requests through Kong after a rollout |
| `install-k3s.sh` | One-time server setup |

## How a release works

1. Jenkins builds and pushes `quickeats-<service>:<git sha>` to ECR.
2. `deploy.sh` refreshes the `quickeats-env`, `grafana-admin` and `ecr-pull` Secrets, then
   applies `base` with the new tags.
3. Each service rolls with `maxUnavailable: 0`: the new pod first runs its init containers
   (copy the SQL baked into the image → `migrate up` on the service's own database → idempotent
   seed), then must pass its readiness probe before the old pod is stopped. **No downtime.**
4. `smoke-test.sh` calls the services through Kong. On success the tag is recorded on the
   namespace (`quickeats.io/release`); on failure Jenkins redeploys the previous tag.

Config changes roll automatically too: ConfigMaps are generated from files with a content
hash in their name, so editing `kong.yml` or an alert rule restarts only the pod that uses it.

## Design choices

- **Migrations ship inside the service image**, so a schema change can never be deployed
  without the code that needs it, and a failed migration blocks the rollout instead of
  breaking the running pods.
- **Startup ordering without crash loops:** each service's first init container waits until
  its own database and Kafka accept connections, so a cold start converges with zero restarts.
- **Probes:** a startup probe gives slow starters 150 s; liveness restarts hung processes;
  readiness keeps traffic away from pods that aren't ready.
- **No dropped requests on rollout:** a 5 s `preStop` sleep keeps the old pod serving until
  Kong and kube-proxy have stopped routing to it (found with a load test that lost 1 of 188
  requests without it).
- **Security:** Go services run as non-root (UID 65532) with a read-only root filesystem and
  no Linux capabilities; Secrets hold only the keys each pod needs; Prometheus and
  kube-state-metrics have read-only RBAC limited to what they scrape.
- **Resource limits on everything:** four Postgres servers, Kafka, monitoring and Jenkins
  builds share one 8 GiB node.

## Operating it

```bash
kubectl -n quickeats get pods
kubectl -n quickeats rollout history deployment/order
kubectl -n quickeats rollout undo deployment/order      # manual rollback of one service
kubectl -n quickeats logs deploy/order -f
```

Grafana and Prometheus are NodePorts that the security group keeps private; reach them
with an SSH tunnel:

```bash
ssh -i <key>.pem -L 3000:localhost:30300 -L 9090:localhost:30090 ubuntu@<elastic-ip>
# http://localhost:3000 (admin / GRAFANA_ADMIN_PASSWORD), http://localhost:9090
```

## Local test cluster

The same manifests and script run against k3s in Docker:

```bash
docker run -d --name qe-k3s --privileged -p 16443:6443 -p 8088:80 \
  rancher/k3s:v1.33.5-k3s1 server --disable traefik --tls-san 127.0.0.1
# build the six images as quickeats-<name>:local, then
docker save quickeats-{identity,catalog,order,payment,notification,admin}:local \
  | docker exec -i qe-k3s ctr images import -
ENV_PROD=test.env bash deploy.sh local          # no ECR_REGISTRY = local image names
BASE_URL=http://localhost:8088 bash smoke-test.sh
```
