#!/bin/bash
usage() {
  cat <<EOF
Usage: ${0##*/} [option]
  Options:
    -d            Database name for save (mysqlName)
    -l            Location for import mysql file (~/Documents/mysql.sql)
    -h            Display this message
EOF
  exit 0
}
while getopts d:l:h flag; do
  # shellcheck disable=SC2220
  case "${flag}" in
  h) usage ;;
  d) destination=${OPTARG} ;;
  l) location=${OPTARG} ;;
  esac
done
PORT=$(docker ps -aqf "name=mariadb");
if [ "$destination" != '' ] && [ "$location" != '' ]; then
  if ! docker exec -i "$PORT" mariadb -uroot -proot -e "use $destination"; then
    echo "create new database $destination"
    docker exec -i "$PORT" mariadb -uroot -proot -e "create database $destination"
    docker exec -i "$PORT" mariadb -uroot -proot "$destination" < "$location"
    echo "Successfully import data to database $destination"
  else
    echo "drop old database $destination"
    docker exec -i "$PORT" mariadb -uroot -proot -e "drop database $destination"
    echo "Create new database $destination"
    docker exec -i "$PORT" mariadb -uroot -proot -e "create database $destination"
    docker exec -i "$PORT" mariadb -uroot -proot "$destination" < "$location"
    echo "Successfully import data to database $destination"
  fi
else
  echo "Please enter correct value"
  usage
fi
