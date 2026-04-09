#!/bin/bash
set -e

FILENAME=${OUTPUT_FILENAME:-"ukk_accounts_database.csv"}
CSV_FILE="/mnt/kredensial/$FILENAME"
TEMP_CSV="/tmp/setup.csv"
JSON_DATA="/tmp/data.json"

echo "nama,kelas,db_user,db_pass,database_name" > "$TEMP_CSV"
echo "[" > "$JSON_DATA"

declare -A USED_USERNAMES
FIRST_ENTRY=true

IFS=',' read -ra ADDR <<< "$STUDENT_DATA"

for entry in "${ADDR[@]}"; do
    RAW_NAME=$(echo "$entry" | cut -d'|' -f1)
    RAW_CLASS=$(echo "$entry" | cut -d'|' -f2 | tr '[:upper:]' '[:lower:]' | sed 's/ //g')
    DISPLAY_NAME=$(echo "$RAW_NAME" | tr '_' ' ')
    
    FORMATTED_CLASS="${RAW_CLASS^^}" 
    
    CLEAN_EVENT=$(echo "$EVENT" | tr '[:upper:]' '[:lower:]' | sed 's/ //g')

    FIRST_NAME=$(echo "$RAW_NAME" | cut -d'_' -f1 | tr '[:upper:]' '[:lower:]')
    SECOND_NAME=$(echo "$RAW_NAME" | cut -d'_' -f2 | tr '[:upper:]' '[:lower:]')
    
    if [ ${#FIRST_NAME} -le 1 ] && [ -n "$SECOND_NAME" ]; then
        BASE_NAME="${FIRST_NAME}${SECOND_NAME}"
    else
        BASE_NAME="$FIRST_NAME"
    fi

    USER_NAME="${BASE_NAME}_${RAW_CLASS}"
    COUNTER=1
    ORIGINAL_USER_NAME=$USER_NAME
    while [[ -n "${USED_USERNAMES[$USER_NAME]}" ]]; do
        USER_NAME="${ORIGINAL_USER_NAME}${COUNTER}"
        COUNTER=$((COUNTER+1))
    done

    USED_USERNAMES[$USER_NAME]=1
    USER_NAME=${USER_NAME:0:32}

    DB_NAME="db_${CLEAN_EVENT}_$USER_NAME"
    DB_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)

    echo "Processing: $DISPLAY_NAME - $FORMATTED_CLASS"

    MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
    MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root -e "CREATE USER IF NOT EXISTS '$USER_NAME'@'%' IDENTIFIED BY '$DB_PASS';"
    MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$USER_NAME'@'%';"
    MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root -e "FLUSH PRIVILEGES;"
    
    echo "$DISPLAY_NAME,$FORMATTED_CLASS,$USER_NAME,$DB_PASS,$DB_NAME" >> "$TEMP_CSV"

    if [ "$FIRST_ENTRY" = true ]; then
        FIRST_ENTRY=false
    else
        echo "," >> "$JSON_DATA"
    fi
    
    echo "[\"$DISPLAY_NAME\", \"$FORMATTED_CLASS\", \"$USER_NAME\", \"$DB_PASS\", \"$DB_NAME\"]" >> "$JSON_DATA"
done

echo "]" >> "$JSON_DATA"

if [ -n "$SHEET_API_URL" ]; then
    echo "Sending data to Google Sheets..."
    
    CLEAN_URL=$(echo "$SHEET_API_URL" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    
    curl -L -X POST "$CLEAN_URL" \
        -H "Content-Type: application/json" \
        -d @"$JSON_DATA" || true
fi

cp "$TEMP_CSV" "$CSV_FILE"
chmod 777 "$CSV_FILE"
echo "Done! Data sent to Spreadsheet and CSV created."
