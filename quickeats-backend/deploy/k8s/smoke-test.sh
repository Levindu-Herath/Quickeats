#!/usr/bin/env bash
# After a rollout: check that Kong routes real requests to the services.
# Gives up after ~2.5 minutes with a non-zero exit so Jenkins rolls back.
#
# BASE_URL defaults to Kong's cluster IP (reachable from the node itself).
set -uo pipefail

BASE_URL="${BASE_URL:-http://$(kubectl -n quickeats get svc kong -o jsonpath='{.spec.clusterIP}')}"
ATTEMPTS=30

for attempt in $(seq 1 $ATTEMPTS); do
    failing=""

    notif=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/notification/health" || true)
    [ "$notif" = "200" ] || failing="$failing kong->notification($notif)"

    # A login with no credentials must reach identity and come back 401
    auth=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
        -d '{}' "$BASE_URL/api/v1/auth/login" || true)
    [ "$auth" = "401" ] || failing="$failing kong->identity($auth)"

    # Unauthenticated request to a protected route must reach order and come back 401
    order=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/orders" || true)
    [ "$order" = "401" ] || failing="$failing kong->order($order)"

    dash=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/admin/" || true)
    [ "$dash" = "200" ] || failing="$failing kong->admin($dash)"

    if [ -z "$failing" ]; then
        echo "Smoke test passed against $BASE_URL"
        exit 0
    fi
    echo "[$attempt/$ATTEMPTS] waiting on:$failing"
    sleep 5
done

echo "Smoke test FAILED:$failing"
kubectl -n quickeats get pods
exit 1
