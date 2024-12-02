#!/bin/bash

# Step 1: Get environment variables
[ -z "${MYSQL_HOST_FILE}" ] || { MYSQL_HOST=$(head -1 "${MYSQL_HOST_FILE}"); }
[ -z "${MYSQL_HOST}" ] && { echo "=> MYSQL_HOST cannot be empty" && exit 1; }

[ -z "${MYSQL_USER_FILE}" ] || { MYSQL_USER=$(head -1 "${MYSQL_USER_FILE}"); }
[ -z "${MYSQL_USER}" ] && { echo "=> MYSQL_USER cannot be empty" && exit 1; }

[ -z "${MYSQL_PASS_FILE}" ] || { MYSQL_PASS=$(head -1 "${MYSQL_PASS_FILE}"); }
[ -z "${MYSQL_PASS:=$MYSQL_PASSWORD}" ] && { echo "=> MYSQL_PASS cannot be empty" && exit 1; }

[ -z "${MYSQL_DATABASE_FILE}" ] || { MYSQL_DATABASE=$(cat "${MYSQL_DATABASE_FILE}"); }
[ -z "${GZIP_LEVEL}" ] && { GZIP_LEVEL=6; }

BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d%H%M)

echo "=> Backup started at $(date "+%Y-%m-%d %H:%M:%S")"

# Step 2: Get the list of databases to back up
DATABASES=${MYSQL_DATABASE:-$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Step 3: Loop through each database and back it up
for db in ${DATABASES}
do
  if  [[ "$db" != "information_schema" ]] \
      && [[ "$db" != "performance_schema" ]] \
      && [[ "$db" != "mysql" ]] \
      && [[ "$db" != "sys" ]] \
      && [[ "$db" != _* ]]
  then
    echo "==> Dumping database: $db"
    FILENAME="$BACKUP_DIR/$DATE.$db.sql"
    LATEST="$BACKUP_DIR/latest.$db.sql"

    # Step 4: Perform the backup
    if mysqldump --single-transaction -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db" > "$FILENAME"
    then
      # Compress the backup file
      if [ -z "${USE_PLAIN_SQL}" ]; then
        echo "==> Compressing $db with LEVEL $GZIP_LEVEL"
        gzip "-$GZIP_LEVEL" -f "$FILENAME"
        FILENAME="${FILENAME}.gz"
      fi

      # Calculate file size in KB
      FILE_SIZE_KB=$(du -k "$FILENAME" | cut -f1)
      BACKUP_TIME=$(date "+%Y-%m-%d %H:%M:%S")
      BASENAME=$(basename "$FILENAME")

      # Step 5: Log backup details into MySQL
      mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" <<EOF
USE $MYSQL_DATABASE;
INSERT INTO backup_log (database_name, backup_file, backup_size, backup_date)
VALUES ('$db', '$BASENAME', $FILE_SIZE_KB, '$BACKUP_TIME');
EOF

      echo "==> Backup of $db logged successfully."

      # Create a symlink for the latest backup
      echo "==> Creating symlink to latest backup: $BASENAME"
      rm -f "$LATEST"
      ln -s "$FILENAME" "$LATEST"

    else
      echo "==> Backup failed for database: $db"
      rm -rf "$FILENAME"
    fi
  fi
done

echo "=> Backup process finished at $(date "+%Y-%m-%d %H:%M:%S")"



