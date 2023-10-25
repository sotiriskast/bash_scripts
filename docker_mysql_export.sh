#!/bin/bash
usage() {
  cat <<EOF
Usage: ${0##*/} [option]
  Options:
    -d            Database name for export (mysqlName)
    -h            Display this message
EOF
  exit 0
}
while getopts d:h flag; do
  # shellcheck disable=SC2220
  case "${flag}" in
  h) usage ;;
  d) database=${OPTARG} ;;
  esac
done
PORT=docker ps -aqf "name=mariadb";
if [ "$database" != '' ]; then
  if docker exec -i "$PORT" mysql -uroot -proot -e "use $database"; then
    echo "export database $database"
    docker exec -i "$PORT" mysqldump -uroot -proot "$database" > "~/Downloads/$database"
    echo "Successfully export database $database"
  else
    echo "Cannot find Database $database for export"
  fi
else
  echo "Please enter correct value "
  usage
fi
