#!/usr/bin/env bash

# сохранение настроек со всех коммутаторов, данные берутся из файла backup.ip
# при запуске с ключом --update этот файл обновляется 
# берутся коммутаторы из базы, обновленные не позднее $update_days
# предполагается, что все файлы лежат в локальном git репозитории $git_dir

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

# общие функции и константы
source $basedir/common.sh

backup_file=$basedir/config/ip/backup.ip
update_days=2
git_dir=$basedir/config/backup/

if [[ ("$#" > 0) && ($1 == "--update") ]]; then
    echo "SELECT INET_NTOA (ip_address) AS ip FROM switches WHERE datediff(now(), last_update) < $update_days ORDER BY last_update ASC;" | mysql -u sw sw_info | tail -n +2 > $backup_file
    echo "Updated: $backup_file"
    exit
fi

ips=`cat $backup_file`

for ip in $ips; do
    echo "Backup $ip"
    result=`backup $ip`
    if [[ "$result" =~ "not" ]]; then
        echo -e "${RED}Error:$NO_COLOR not supported"
    elif [[ "$result" =~ "unsuccessful" ]]; then
        echo -e "${RED}FAIL$NO_COLOR.....trying again"
        backup $ip
    fi
done

cur_date=`date +'%F %T'`
git -C $git_dir add .
git -C $git_dir commit -am "Backup routine script at $cur_date"