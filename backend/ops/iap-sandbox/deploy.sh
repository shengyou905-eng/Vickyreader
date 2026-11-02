#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/ubuntu/apps/zhidu-iap-sandbox
RELEASE="$PWD"
[[ "$RELEASE" == "$ROOT/releases/"* ]] || exit 1
check_guard() {
  test ! -f "$ROOT/STOPPED"
  systemctl is-active --quiet zhidu-iap-sandbox-guard
  node -e 'const s=require(process.argv[1]);if(!s.healthy||Date.now()-Date.parse(s.checkedAt)>15000)process.exit(1)' "$ROOT/guard-status.json"
}
stop_on_error() {
  docker stop --time 5 zhidu-iap-sandbox-api zhidu-iap-sandbox-init zhidu-iap-sandbox-deps zhidu-iap-sandbox-postgres >/dev/null 2>&1 || true
  printf 'Deployment failed; Sandbox containers stopped. Production not restarted.\n' >&2
}
trap stop_on_error ERR
check_guard
test ! -e "$ROOT/initialized"
for name in zhidu-iap-sandbox-api zhidu-iap-sandbox-postgres; do
  if docker container inspect "$name" >/dev/null 2>&1; then exit 1; fi
done
NODE_IMAGE=node:22.22.2-bookworm-slim
docker pull "$NODE_IMAGE"
NODE_IMAGE=$(docker image inspect "$NODE_IMAGE" --format '{{index .RepoDigests 0}}')
PG_IMAGE=$(docker image inspect postgres:16 --format '{{.Id}}')
check_guard
docker network create --label zhidu.environment=iap-sandbox zhidu-iap-sandbox
docker volume create --label zhidu.environment=iap-sandbox zhidu-iap-sandbox-pgdata
COMMON=(--cpus=0.5 --memory=384m --memory-swap=384m --pids-limit=128 --log-driver=json-file --log-opt=max-size=10m --log-opt=max-file=3 --restart=no --label zhidu.environment=iap-sandbox)
docker run --rm --name zhidu-iap-sandbox-deps "${COMMON[@]}" --user "$(id -u):$(id -g)" \
  --env NODE_OPTIONS=--max-old-space-size=192 --env npm_config_cache=/tmp/npm-cache \
  --mount "type=bind,src=$RELEASE,dst=/app" --workdir /app "$NODE_IMAGE" \
  npm ci --omit=dev --ignore-scripts --no-audit --no-fund
check_guard
docker run -d --name zhidu-iap-sandbox-postgres "${COMMON[@]}" \
  --network zhidu-iap-sandbox --network-alias sandbox-db \
  --env-file "$ROOT/config/db.env" \
  --mount type=volume,src=zhidu-iap-sandbox-pgdata,dst=/var/lib/postgresql/data \
  --health-cmd='pg_isready -U zhidu_sandbox_admin -d zhidu_iap_sandbox' \
  --health-interval=10s --health-timeout=5s --health-retries=3 \
  "$PG_IMAGE" -c shared_buffers=64MB -c max_connections=20 -c work_mem=2MB -c maintenance_work_mem=32MB
for i in $(seq 1 30); do
  if docker exec zhidu-iap-sandbox-postgres pg_isready -U zhidu_sandbox_admin -d zhidu_iap_sandbox >/dev/null; then break; fi
  sleep 2
done
check_guard
docker run --rm --name zhidu-iap-sandbox-init "${COMMON[@]}" \
  --network zhidu-iap-sandbox --user "$(id -u):$(id -g)" --read-only \
  --env-file "$ROOT/config/db.env" --env NODE_OPTIONS=--max-old-space-size=192 \
  --mount "type=bind,src=$RELEASE,dst=/app,readonly" \
  --mount "type=bind,src=$ROOT/config/roles.json,dst=/config/roles.json,readonly" \
  --workdir /app "$NODE_IMAGE" node ops/iap-sandbox/initialize.cjs
touch "$ROOT/initialized"
check_guard
docker run -d --name zhidu-iap-sandbox-api "${COMMON[@]}" \
  --network zhidu-iap-sandbox --user "$(id -u):$(id -g)" --read-only \
  --cap-drop=ALL --security-opt=no-new-privileges:true --tmpfs /tmp:rw,noexec,nosuid,size=32m \
  --publish 127.0.0.1:3001:3000 --env-file "$ROOT/config/app.env" \
  --mount "type=bind,src=$RELEASE,dst=/app,readonly" --workdir /app \
  --health-cmd='node -e "fetch(\"http://127.0.0.1:3000/api/health\").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"' \
  --health-interval=15s --health-timeout=5s --health-retries=3 \
  "$NODE_IMAGE" node server.js
printf 'Sandbox containers started with IAP disabled; production configuration unchanged.\n'
