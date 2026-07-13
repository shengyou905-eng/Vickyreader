#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${POSTGRES_CONTAINER:-reader-postgres}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/ubuntu/backups/zhidu/daily}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_DIR="$BACKUP_ROOT/$STAMP"

mkdir -p "$TARGET_DIR"
docker exec "$CONTAINER_NAME" sh -lc \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$TARGET_DIR/database.dump"
test -s "$TARGET_DIR/database.dump"
docker exec -i "$CONTAINER_NAME" pg_restore -l \
  < "$TARGET_DIR/database.dump" > /dev/null
sha256sum "$TARGET_DIR/database.dump" > "$TARGET_DIR/SHA256SUMS"

find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
  -mtime "+$RETENTION_DAYS" -exec rm -rf -- {} +

printf 'Backup complete: %s\n' "$TARGET_DIR"
