

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="./backups/govcomm_db_$TIMESTAMP.sql"

echo "Initiating daily secure backup..."

docker exec db pg_dump -U govcomm_user govcomm_db > $BACKUP_FILE

gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase-file ./scripts/backup_pass.txt $BACKUP_FILE

rm $BACKUP_FILE

echo "✅ Encrypted backup completed: ${BACKUP_FILE}.gpg"