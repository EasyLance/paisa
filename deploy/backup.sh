#!/usr/bin/env bash
# Nightly database export into <checkout>/dbbackup, run from cron.
#
#   ./deploy/backup.sh
#
# Install once, as the service user (elance on the live droplet):
#
#   (crontab -l 2>/dev/null; echo '45 21 * * * /var/www/projects/Financial-App/deploy/backup.sh 2>&1 | logger -t paisa-backup') | crontab -
#
# The files stay on this droplet: they cover a bad migration or a mistaken
# wipe, not losing the box itself.
set -euo pipefail

# shellcheck source=deploy/lib-db.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-db.sh"

# The app directory is readable by the other sites on this box; the dumps are not.
umask 077
BACKUP_DIR="$APP_DIR/dbbackup"
ensure_backup_dir
FILE="$BACKUP_DIR/$DB_NAME-$(date +%Y%m%d-%H%M%S).sql.gz"

dump --single-transaction --routines --triggers "$DB_NAME" | gzip > "$FILE"
gzip -t "$FILE"
echo "$(du -h "$FILE" | cut -f1) written to $FILE"

# ponytail: keeps 14 days so a shared disk can't fill; raise it if older ones matter.
find "$BACKUP_DIR" -name "$DB_NAME-*.sql.gz" -mtime +14 -delete
