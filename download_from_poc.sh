#!/bin/bash
usage() {
  cat <<EOF
Usage: ${0##*/} [option]
  Options:
    -f            Name File for download
    -h            Display this message
EOF
  exit 0
}
while getopts f:h flag; do
  # shellcheck disable=SC2220
  case "${flag}" in
  h) usage ;;
  f) file=${OPTARG} ;;
  
  esac
done

if [ "$file" != '' ]; then
  rsync -avzh -P -e "ssh -p222" pocxvu@dedi3501.your-server.de:~/public_html/"$file" /home/sotiris/Documents/FTPDownload/
else
    echo "$file does not exist."
fi


