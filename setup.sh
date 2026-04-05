#!/bin/bash
# ==========================================
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
  echo "✅ File .env berhasil dimuat."
else
  echo "❌ Error: File .env tidak ditemukan!"
  exit 1
fi
# ==========================================
echo "📊 Menyiapkan file output: $OUTPUT_FILE"
echo "nama,kelas,username,password,port" > "$OUTPUT_FILE"
# ==========================================
gen_pass() { tr -dc A-Za-z0-9 </dev/urandom | head -c 6; }
gen_user() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z'; }
gen_kelas() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ' | sed 's/xiii//'; }

send_wa() {
  local target_phone="$1"
  local raw_message="$2"
  local escaped_message=$(echo "$raw_message" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
  local response=$(curl -s -X 'POST' "$WAHA_URL" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H "X-Api-Key: $WAHA_API_KEY" \
    -d "{ \"chatId\": \"${target_phone}@c.us\", \"text\": \"$escaped_message\", \"session\": \"default\" }")
  echo "📡 Response: $response"
}
# ==========================================
echo "🔐 Memeriksa konfigurasi SSL..."
mkdir -p "$SSL_PATH"
if [ ! -f "$SSL_PATH/ca.pem" ]; then
  echo "🔑 Generating SSL Certificates untuk $SERVER_HOST..."
  openssl genrsa 2048 > "$SSL_PATH/ca-key.pem"
  openssl req -new -x509 -nodes -days 3650 -key "$SSL_PATH/ca-key.pem" -out "$SSL_PATH/ca.pem" -subj "/CN=MariaDB-CA"
  openssl genrsa 2048 > "$SSL_PATH/server-key.pem"
  openssl req -new -key "$SSL_PATH/server-key.pem" -out "$SSL_PATH/server.csr" -subj "/CN=$SERVER_HOST"
  openssl x509 -req -in "$SSL_PATH/server.csr" -days 3650 -CA "$SSL_PATH/ca.pem" -CAkey "$SSL_PATH/ca-key.pem" -set_serial 01 -out "$SSL_PATH/server-cert.pem"
  chmod 755 "$SSL_PATH"
  chmod 644 "$SSL_PATH"/*.pem
  echo "✅ SSL Berhasil dibuat."
fi
# ==========================================
IFS=',' read -r -a DATA_ARRAY <<< "$STUDENT_DATA"
i=0
for item in "${DATA_ARRAY[@]}"
do
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

  echo "🚀 [1/4] Membuat container: $container_name (Port: $port)"
  docker rm -f "$container_name" 2>/dev/null
  docker run -d \
    --name "$container_name" \
    -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
    -p ${port}:3306 \
    -v $(pwd)/my.cnf:/etc/mysql/conf.d/z-custom.cnf \
    -v $(pwd)/"$SSL_PATH":/etc/mysql/ssl \
    --memory="${CONTAINER_MEMORY}" \
    --cpus="${CONTAINER_CPUS}" \
    --health-cmd="mariadb-admin ping -h localhost --silent" \
    --health-interval=5s \
    --health-timeout=3s \
    --health-retries=10 \
    mariadb:"${DB_VERSION}"

  echo "⏳ [2/4] Menunggu database stabil..."
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$container_name")" = "healthy" ]; do 
    sleep 2
  done
  sleep 5

  echo "👤 [3/4] Membuat user database: $username"
  docker exec "$container_name" mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" -e "DROP USER IF EXISTS '$username'@'%';"
  docker exec "$container_name" mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" -e "CREATE USER '$username'@'%' IDENTIFIED BY '$password';"
  docker exec "$container_name" mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO '$username'@'%' WITH GRANT OPTION;"
  docker exec "$container_name" mariadb -h 127.0.0.1 -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

  echo "📲 [4/4] Mengirim notifikasi WhatsApp ke $wa_number..."
  CLEAN_MSG=$(echo -e "Halo $nama! 👋\n\nAkun Database UKK kamu:\n👤 User: $username\n🔑 Pass: $password\n🌐 Port: $port\n🖥️ Host: $SERVER_HOST\n\n🛡️ *PENTING (SSL Error)*:\nJika login lewat Terminal/CMD gagal karena SSL, gunakan perintah:\nmariadb -h $SERVER_HOST -P $port -u $username -p --ssl-verify-server-cert=0\n\nLogin phpMyAdmin: http://$SERVER_HOST:${PMA_PORT}")
  
  send_wa "$wa_number" "$CLEAN_MSG"
  
  echo "$nama,$kelas_raw,$username,$password,$port" >> "$OUTPUT_FILE"
  echo "✅ Selesai untuk $nama."
  echo "------------------------------------------"
  ((i++))
done

echo "🌐 Menjalankan phpMyAdmin Global..."
docker rm -f phpmyadmin_ukk 2>/dev/null
docker run -d --name phpmyadmin_ukk -e PMA_ARBITRARY=1 -p ${PMA_PORT}:80 phpmyadmin
echo "🏁 SEMUA PROSES SELESAI!"