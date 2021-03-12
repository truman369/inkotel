#!/usr/bin/env bash

# сохранение настроек со всех коммутаторов, данные берутся из файла backup.ip
# при запуске с ключом --update этот файл обновляется 
# берутся коммутаторы из базы, обновленные не позднее $update_days
# предполагается, что все файлы лежат в локальном git репозитории $git_dir

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

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
    backup $ip
done

cur_date=`date +'%F %T'`
git -C $git_dir commit -am "Routine script at $cur_date"