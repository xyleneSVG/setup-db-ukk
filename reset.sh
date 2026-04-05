#!/bin/bash

echo "🔥 Hapus semua container UKK..."

docker rm -f $(docker ps -a --filter "name=ukk_" -q) 2>/dev/null

echo "✅ Bersih!"