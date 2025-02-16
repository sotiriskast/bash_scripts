#!/bin/bash

#NEED TO INSTAL gclone FOR RUN THIS CONFIG
# Configuration
BACKUP_DIR="/backup"
MAX_BACKUPS=14
DATE=$(date +%Y-%m-%d_%H-%M-%S)
WEB_ROOT="/var/www"

# Project types
LARAVEL_PROJECTS=""
OCTOBER_PROJECTS=""
REACT_PROJECTS=""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

backup_laravel_project() {
    PROJECT_NAME=$1
    PROJECT_PATH="$WEB_ROOT/$PROJECT_NAME"
    
    echo "Starting backup for Laravel project $PROJECT_NAME..."
    
    PROJECT_BACKUP_DIR="$BACKUP_DIR/$PROJECT_NAME"
    mkdir -p "$PROJECT_BACKUP_DIR"
    
    # Backup database from .env
    if [ -f "$PROJECT_PATH/.env" ]; then
        echo "Found .env file, backing up database..."
        eval "$(grep -v '^#' "$PROJECT_PATH/.env" | sed -e 's/^/export /' -e 's/\"//g' -e "s/\'//g")"
        
        if [ ! -z "$DB_DATABASE" ]; then
            echo "Backing up database $DB_DATABASE..."
            mysqldump -h "${DB_HOST:-localhost}" \
                     -u "$DB_USERNAME" \
                     -p"$DB_PASSWORD" \
                     "$DB_DATABASE" | gzip > "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql.gz"
        fi
    fi
    
    # Backup Laravel files
    echo "Backing up Laravel files for $PROJECT_NAME..."
    tar --exclude='./vendor' \
        --exclude='./node_modules' \
        --exclude='./storage/logs/*' \
        --exclude='./storage/framework/cache/*' \
        --exclude='./storage/framework/sessions/*' \
        --exclude='./storage/framework/views/*' \
        --exclude='./public/storage' \
        --exclude='./bootstrap/cache/*' \
        -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz" \
        -C "$PROJECT_PATH" .
    
    create_final_archive "$PROJECT_NAME" "$PROJECT_BACKUP_DIR"
}

backup_october_project() {
    PROJECT_NAME=$1
    PROJECT_PATH="$WEB_ROOT/$PROJECT_NAME"
    
    echo "Starting backup for OctoberCMS project $PROJECT_NAME..."
    
    PROJECT_BACKUP_DIR="$BACKUP_DIR/$PROJECT_NAME"
    mkdir -p "$PROJECT_BACKUP_DIR"
    
    # Backup database from .env
    if [ -f "$PROJECT_PATH/.env" ]; then
        echo "Found .env file, backing up database..."
        eval "$(grep -v '^#' "$PROJECT_PATH/.env" | sed -e 's/^/export /' -e 's/\"//g' -e "s/\'//g")"
        
        if [ ! -z "$DB_DATABASE" ]; then
            echo "Backing up database $DB_DATABASE..."
            mysqldump -h "${DB_HOST:-localhost}" \
                     -u "$DB_USERNAME" \
                     -p"$DB_PASSWORD" \
                     --ignore-table="$DB_DATABASE.deferred_bindings" \
                     --ignore-table="$DB_DATABASE.sessions" \
                     --ignore-table="$DB_DATABASE.cache" \
                     "$DB_DATABASE" | gzip > "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql.gz"
        fi
    fi
    
    # Backup OctoberCMS files
    echo "Backing up OctoberCMS files for $PROJECT_NAME..."
    tar --exclude='./vendor' \
        --exclude='./node_modules' \
        --exclude='./storage/logs/*' \
        --exclude='./storage/framework/cache/*' \
        --exclude='./storage/framework/sessions/*' \
        --exclude='./storage/framework/views/*' \
        --exclude='./storage/cms/cache/*' \
        --exclude='./storage/cms/combiner/*' \
        --exclude='./storage/cms/twig/*' \
        --exclude='./storage/temp/*' \
        -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz" \
        -C "$PROJECT_PATH" .
    
    create_final_archive "$PROJECT_NAME" "$PROJECT_BACKUP_DIR"
}

backup_react_project() {
    PROJECT_NAME=$1
    PROJECT_PATH="$WEB_ROOT/$PROJECT_NAME"
    
    echo "Starting backup for React project $PROJECT_NAME..."
    
    PROJECT_BACKUP_DIR="$BACKUP_DIR/$PROJECT_NAME"
    mkdir -p "$PROJECT_BACKUP_DIR"
    
    # Backup React files
    echo "Backing up files for $PROJECT_NAME..."
    tar --exclude='./node_modules' \
        --exclude='./build' \
        --exclude='./dist' \
        --exclude='./.next' \
        --exclude='./coverage' \
        -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz" \
        -C "$PROJECT_PATH" .
    
    upload_and_rotate_backups "$PROJECT_NAME" "$PROJECT_BACKUP_DIR"
}

create_final_archive() {
    PROJECT_NAME=$1
    PROJECT_BACKUP_DIR=$2
    
    echo "Creating final archive..."
    if [ -f "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql.gz" ]; then
        tar -czf "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz" \
            -C "$PROJECT_BACKUP_DIR" \
            "${PROJECT_NAME}_db_$DATE.sql.gz" \
            "${PROJECT_NAME}_files_$DATE.tar.gz"
        
        # Clean up temporary files
        rm "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_db_$DATE.sql.gz"
        rm "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz"
    else
        mv "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_files_$DATE.tar.gz" \
           "$PROJECT_BACKUP_DIR/${PROJECT_NAME}_backup_$DATE.tar.gz"
    fi
    
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
