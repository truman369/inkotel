#!/usr/bin/env bash

# скрипт для разбивки ip адресов коммутаторов по районам
# берет список из пингера, парсит html, данные записываются в файлы .ip

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

ipdir="$basedir/config/ip/"

result=`curl -s http://192.168.255.185/pinger/sort_com.php \
        | iconv -f cp1251 \
        | sed "s/<tr><td>/\n/g" \
        | grep "<td>" \
        | sed "s/<\/td><\/tr>//;s/<\/td><td>/|/g" \
        | cut -d "|" -f 1,5 --output-delimiter " "`

declare -A ip_zones

while read ip zone; do
    ip_zones[$zone]+=" $ip"
done <<<$result

for zone in ${!ip_zones[*]}; do
    echo "# Район $zone" > $ipdir/$zone.ip
    for ip in ${ip_zones[$zone]}; do
        echo $ip >> $ipdir/$zone.ip
    done
done
