#!/bin/bash

echo "🔥 Hapus semua container UKK..."

docker rm -f $(docker ps -a --filter "name=ukk_" -q) 2>/dev/null
docker rm -f $(docker ps -a --filter "name=proxysql_ukk" -q) 2>/dev/null
docker rm -f $(docker ps -a --filter "name=phpmyadmin_ukk" -q) 2>/dev/null

echo "✅ Bersih!"