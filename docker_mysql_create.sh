#!/bin/bash
usage() {
  cat <<EOF
Usage: ${0##*/} [option]
  Options:
    -d            Database name for save (mysqlName)
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
PORT=$(docker ps -aqf "name=mariadb");
if [ "$database" == '' ]; then
   echo "Please write a database name (-d 'database_name')"
   exit 0
fi
if [ "$database" != '' ]; then
  if ! docker exec -i "$PORT" mysql -uroot -proot -e "use $database"; then
    echo "create new database $database"
    docker exec -i "$PORT" mariadb -uroot -proot -e "create database $database"
    echo "Succesfully create database $database"
  else
    echo "$database are exist. Do you want to drop old database $database (y/n): [y]"
    read -s -n 1 drop_mysql
    if [[ $drop_mysql == 'y' || $drop_mysql == '' ]]; then
       docker exec -i "$PORT" mariadb -uroot -proot -e "drop database $database"
       echo "Create new database $database"
       docker exec -i "$PORT" mariadb -uroot -proot -e "create database $database"
       echo "Successfully create database $database"
    else
       echo "Abort"
    fi
    
  fi
else
  echo "Please enter correct value "
  usage
fi

