#!/bin/bash

# --- 1. LOAD ENV ---
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
  echo "✅ File .env berhasil dimuat."
else
  echo "❌ Error: File .env tidak ditemukan!"
  exit 1
fi

# --- 2. CEK ARGS WAHA ---
USE_WAHA=false
if [[ "$1" == "--waha" ]]; then
    echo "📡 Mengecek koneksi WAHA..."
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Api-Key: $WAHA_API_KEY" ${WAHA_URL/sendText/sessions})
    if [ "$STATUS" == "200" ]; then
        echo "✅ WAHA Online! Peserta akan dikirimi pesan."
        USE_WAHA=true
    else
        echo "❌ WAHA Offline ($STATUS). Script akan lanjut tanpa kirim pesan."
    fi
fi

echo "nama,username,password,port" > "$OUTPUT_FILE"

# --- 3. FUNCTIONS ---
gen_pass() { tr -dc A-Za-z0-9 </dev/urandom | head -c 6; }
gen_user() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z'; }
gen_kelas() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ' | sed 's/xiii//'; }

send_wa() {
  local target_phone="$1"
  local raw_message="$2"
  local escaped_message=$(echo "$raw_message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
  curl -s -X 'POST' "$WAHA_URL" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H "X-Api-Key: $WAHA_API_KEY" \
    -d "{ \"chatId\": \"${target_phone}@c.us\", \"text\": \"$escaped_message\", \"session\": \"default\" }" > /dev/null
}

safe_mysql_exec() {
  local container="$1"
  local sql="$2"
  local attempt=1
  until docker exec -i "$container" mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" -e "$sql" &>/dev/null; do
    echo "⏳ [$attempt] Menunggu privilege $container siap..."
    sleep 3
    ((attempt++))
    if [ $attempt -gt 10 ]; then return 1; fi
  done
}

generate_pma_config() {
  echo "📝 Membuat konfigurasi phpMyAdmin (Cookie Mode)..."
  local pma_file="$(pwd)/pma_config.php"

  cat > "$pma_file" <<PHP
<?php
\$cfg['blowfish_secret'] = '32_random_characters_for_cookie_auth_123';
\$cfg['LoginCookieRecycle'] = true;
\$cfg['ServerDefault'] = 1;
\$i = 1;
PHP

  local tmp_i=0
  IFS=',' read -r -a TMP_ARRAY <<< "$STUDENT_DATA"
  for tmp_item in "${TMP_ARRAY[@]}"; do
    local tmp_nama_raw=$(echo "$tmp_item" | cut -d '|' -f1)
    local tmp_kelas_raw=$(echo "$tmp_item" | cut -d '|' -f2)
    local tmp_port=$((DB_BASE_PORT + tmp_i))
    local tmp_nama=$(echo "$tmp_nama_raw" | sed 's/_/ /g')

    cat >> "$pma_file" <<EOF
\$cfg['Servers'][\$i]['verbose'] = '$tmp_nama ($tmp_kelas_raw)';
\$cfg['Servers'][\$i]['host'] = '172.17.0.1';
\$cfg['Servers'][\$i]['port'] = $tmp_port;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$i++;
EOF
    ((tmp_i++))
  done
  echo "?>" >> "$pma_file"
}

# --- 4. DEPLOY CONTAINERS ---
IFS=',' read -r -a DATA_ARRAY <<< "$STUDENT_DATA"
i=0
for item in "${DATA_ARRAY[@]}"; do
  nama_raw=$(echo "$item" | cut -d '|' -f1)
  kelas_raw=$(echo "$item" | cut -d '|' -f2)
  wa_number=$(echo "$item" | cut -d '|' -f3)
  nama=$(echo "$nama_raw" | sed 's/_/ /g')
  
  userbase=$(gen_user "$nama_raw")
  kelas_slug=$(gen_kelas "$kelas_raw")
  username="${userbase}_${kelas_slug}"
  password=$(gen_pass)
  port=$((DB_BASE_PORT + i))
  container_name="ukk_${username}"

  echo "🚀 Deploy: $container_name (Port: $port)"
  docker rm -f "$container_name" 2>/dev/null
  docker run -d --name "$container_name" -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" -p ${port}:3306 --health-cmd="mariadb-admin ping -u root -p${DB_ROOT_PASSWORD} --silent" --health-interval=2s mariadb:"${DB_VERSION}"
  
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$container_name")" = "healthy" ]; do sleep 1; done

  SQL="CREATE USER IF NOT EXISTS '$username'@'%' IDENTIFIED BY '$password';
       GRANT ALL PRIVILEGES ON *.* TO '$username'@'%' WITH GRANT OPTION;
       GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$DB_ROOT_PASSWORD' WITH GRANT OPTION;
       FLUSH PRIVILEGES;"
  
  safe_mysql_exec "$container_name" "$SQL"

  # --- CLEAN MESSAGE MODEL ---
  CLEAN_MSG=$(echo -e "Halo $nama! 👋\n\nAkun Database UKK kamu:\n👤 User: $username\n🔑 Pass: $password\n🌐 Port: $port\n🖥️ Host: $SERVER_HOST\n\n🛡️ *PENTING (SSL Error)*:\nJika login lewat Terminal/CMD gagal karena SSL, gunakan perintah:\nmariadb -h $SERVER_HOST -P $port -u $username -p --ssl-verify-server-cert=0\n\nLogin phpMyAdmin: http://$SERVER_HOST:${PMA_PORT}")
  
  if [ "$USE_WAHA" = true ]; then
      echo "📲 Mengirim WA ke $wa_number..."
      send_wa "$wa_number" "$CLEAN_MSG"
  else
      echo -e "\n💬 [PREVIEW PESAN]\n$CLEAN_MSG\n----------------------"
  fi
  
  echo "$nama_raw,$username,$password,$port" >> "$OUTPUT_FILE"
  ((i++))
done

# --- 5. SETUP PHPMYADMIN ---
generate_pma_config
docker rm -f phpmyadmin_ukk 2>/dev/null
docker run -d --name phpmyadmin_ukk -v $(pwd)/pma_config.php:/etc/phpmyadmin/conf.d/config.php -p ${PMA_PORT}:80 phpmyadmin

echo -e "\n🏁 SELESAI!"
echo "🌍 Link phpMyAdmin: http://$SERVER_HOST:$PMA_PORT"