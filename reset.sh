#!/bin/bash

echo "🔥 Hapus semua container UKK..."

docker rm -f $(docker ps -aq)

echo "✅ Bersih!"