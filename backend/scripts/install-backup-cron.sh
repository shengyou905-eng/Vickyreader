#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CRON_FILE="/etc/cron.d/zhidu-postgres-backup"

cat <<EOF | sudo tee "$CRON_FILE" > /dev/null
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 3 * * * root POSTGRES_CONTAINER=reader-postgres BACKUP_ROOT=/home/ubuntu/backups/zhidu/daily $BACKEND_DIR/scripts/backup-postgres.sh >> /var/log/zhidu-backup.log 2>&1
EOF

sudo chmod 644 "$CRON_FILE"
sudo systemctl reload cron
printf 'Installed daily backup cron: %s\n' "$CRON_FILE"
