#!/bin/bash

while true
do
  clear

  echo "=== STATUS CONTAINER ==="
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

  echo ""
  echo "=== CONNECTION ACTIVE ==="

  for c in $(docker ps --format "{{.Names}}" | grep container_)
  do
    echo "---- $c ----"

    docker exec $c mysql -uroot -proot123 -e "
    SELECT USER, HOST, COMMAND, TIME 
    FROM INFORMATION_SCHEMA.PROCESSLIST
    WHERE USER NOT IN ('root','healthcheck','mariadb.sys');
    " 2>/dev/null

    echo ""
  done

  sleep 5
done