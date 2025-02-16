#!/bin/bash

# Configuration
BACKUP_DIR="/backup"
MAX_BACKUPS=14
DATE=$(date +%Y-%m-%d_%H-%M-%S)
WEB_ROOT="/var/www"

# Project types
LARAVEL_PROJECTS=""
REACT_PROJECTS=""
OCTOBER_PROJECTS=""
# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"
backup_database() {
    PROJECT_NAME=$1
    PROJECT_PATH=$2
    PROJECT_BACKUP_DIR=$3

    if [ -f "$PROJECT_PATH/.env" ]; then
        echo "Found .env file, checking database configuration..."

        # Get database credentials from .env without displaying them
        eval "$(grep -v '^#' "$PROJECT_PATH/.env" | sed -e 's/^/export /' -e 's/\"//g' -e "s/\'//g")" > /dev/null 2>&1

        if [ ! -z "$DB_DATABASE" ]; then
            echo "Attempting to backup database $DB_DATABASE..."

            # Try database connection first
            if [ -z "$DB_PASSWORD" ]; then
                MYSQL_TEST=$(mysql -h "${DB_HOST:-localhost}" -u "$DB_USERNAME" "$DB_DATABASE" -e "SELECT 1" 2>&1)
            else
                MYSQL_TEST=$(mysql -h "${DB_HOST:-localhost}" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" -e "SELECT 1" 2>&1)
            fi

            if [ $? -eq 0 ]; then
                echo "Database connection successful, creating backup..."

                # Perform backup based on password presence
                if [ -z "$DB_PASSWORD" ]; then
                    mysqldump --single-transaction \
                             -h "${DB_HOST:-localhost}" \
                             -u "$DB_USERNAME" \
                             "$DB_DATABASE" > "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql"
                else
                    mysqldump --single-transaction \
                             -h "${DB_HOST:-localhost}" \
                             -u "$DB_USERNAME" \
                             -p"$DB_PASSWORD" \
                             "$DB_DATABASE" > "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql"
                fi

                if [ $? -eq 0 ]; then
                    echo "Database backup completed."
                    return 0
                else
                    echo "Database backup failed."
                    return 1
                fi
            else
                echo "Database connection failed, skipping backup."
                return 1
            fi
        else
            echo "No database name found in .env, skipping database backup."
            return 1
        fi
    else
        echo "No .env file found, skipping database backup."
        return 1
    fi
}


backup_laravel_project() {
    PROJECT_NAME=$1
    PROJECT_PATH="$WEB_ROOT/$PROJECT_NAME"

    echo "Starting backup for Laravel project $PROJECT_NAME..."

    PROJECT_BACKUP_DIR="$BACKUP_DIR/$PROJECT_NAME"
    mkdir -p "$PROJECT_BACKUP_DIR"

    # Backup database
    backup_database "$PROJECT_NAME" "$PROJECT_PATH" "$PROJECT_BACKUP_DIR"
    DB_BACKUP_SUCCESS=$?

    # Backup all Laravel files
    echo "Backing up Laravel files for $PROJECT_NAME..."
    tar --exclude='./vendor' \
        --exclude='./node_modules' \
    	-czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz" -C "$PROJECT_PATH" .

    # Create final archive based on whether we have a database backup or not
    if [ $DB_BACKUP_SUCCESS -eq 0 ]; then
        echo "Creating final archive with database..."
        tar -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz" \
            -C "$PROJECT_BACKUP_DIR" \
            "${PROJECT_NAME}_db_$DATE.sql" \
            "${PROJECT_NAME}_files_$DATE.tar.gz"

        # Clean up temporary files
        rm "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql"
        rm "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz"
    else
        echo "Creating final archive without database..."
        mv "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz" \
           "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz"
    fi

    upload_and_rotate_backups "$PROJECT_NAME" "$PROJECT_BACKUP_DIR"
}

backup_october_project() {
    PROJECT_NAME=$1
    PROJECT_PATH="$WEB_ROOT/$PROJECT_NAME"

    echo "Starting backup for OctoberCMS project $PROJECT_NAME..."

    PROJECT_BACKUP_DIR="$BACKUP_DIR/$PROJECT_NAME"
    mkdir -p "$PROJECT_BACKUP_DIR"

    # Backup database
    backup_database "$PROJECT_NAME" "$PROJECT_PATH" "$PROJECT_BACKUP_DIR"
    DB_BACKUP_SUCCESS=$?

    # Backup all OctoberCMS files
    echo "Backing up OctoberCMS files for $PROJECT_NAME..."
    tar -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz" -C "$PROJECT_PATH" .

    # Create final archive based on whether we have a database backup or not
    if [ $DB_BACKUP_SUCCESS -eq 0 ]; then
        echo "Creating final archive with database..."
        tar -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz" \
            -C "$PROJECT_BACKUP_DIR" \
            "${PROJECT_NAME}_db_$DATE.sql" \
            "${PROJECT_NAME}_files_$DATE.tar.gz"

        # Clean up temporary files
        rm "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql"
        rm "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz"
    else
        echo "Creating final archive without database..."
        mv "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz" \
           "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz"
    fi

    upload_and_rotate_backups "$PROJECT_NAME" "$PROJECT_BACKUP_DIR"
}

backup_react_project() {
    PROJECT_NAME=$1
    PROJECT_PATH="$WEB_ROOT/$PROJECT_NAME"

    echo "Starting backup for React project $PROJECT_NAME..."

    PROJECT_BACKUP_DIR="$BACKUP_DIR/$PROJECT_NAME"
    mkdir -p "$PROJECT_BACKUP_DIR"

    # Backup all React files
    echo "Backing up React files for $PROJECT_NAME..."
    tar --exclude='./node_modules' \
        --exclude='./build' \
        --exclude='./dist' \
        --exclude='./.next' \
        --exclude='./coverage' \
        -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz" \
        -C "$PROJECT_PATH" .

    upload_and_rotate_backups "$PROJECT_NAME" "$PROJECT_BACKUP_DIR"
}

upload_and_rotate_backups() {
    PROJECT_NAME=$1
    PROJECT_BACKUP_DIR=$2

    echo "Uploading to Google Drive..."
    rclone copy "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz" \
                "gdrive:backups/$PROJECT_NAME/"

    echo "Rotating old backups in Google Drive..."
    REMOTE_FILES=$(rclone lsf "gdrive:backups/$PROJECT_NAME/" | sort -r)
    COUNT=0
    echo "$REMOTE_FILES" | while read -r FILE; do
        COUNT=$((COUNT + 1))
        if [ $COUNT -gt $MAX_BACKUPS ]; then
            echo "Deleting old backup: $FILE"
            rclone delete "gdrive:backups/$PROJECT_NAME/$FILE"
        fi
    done

    # Clean up local backup
    rm "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz"

    echo "Backup completed for $PROJECT_NAME"
    echo "----------------------------------------"
}

# Main backup process
echo "Starting backup process at $(date)"

# Backup Laravel projects
for PROJECT in $LARAVEL_PROJECTS; do
    backup_laravel_project "$PROJECT"
done

# Backup OctoberCMS projects
for PROJECT in $OCTOBER_PROJECTS; do
    backup_october_project "$PROJECT"
done

# Backup React projects
for PROJECT in $REACT_PROJECTS; do
    backup_react_project "$PROJECT"
done

echo "All backups completed at $(date)"
