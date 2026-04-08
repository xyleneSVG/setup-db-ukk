docker rm -f ukk_database ukk_phpmyadmin
docker compose down -v --remove-orphans
docker compose up -d --build