#!/bin/bash
# ==========================================
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ .env not found!"
  exit 1
fi
# ==========================================
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Api-Key: $WAHA_API_KEY" ${WAHA_URL/sendText/sessions})
if [ "$STATUS" == "200" ]; then
    echo "✅ Remote WAHA Online!"
else
    echo "❌ Remote WAHA Offline ($STATUS)"
    exit 1
fi
# ==========================================
read -p "Tekan [ENTER] untuk mulai setup database..."
if [ -f setup.sh ]; then
    chmod +x setup.sh
    ./setup.sh
fi