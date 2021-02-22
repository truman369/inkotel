#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

# берем ip районных коммутаторов l3
# убираем закомментированные строки
# -v инвертировать
ips=`egrep -v "^$|^#" "$basedir/config/ip/l3.ip"`

# для наглядности и удобства очищаем экран
# выводим список коммутаторов с маршрутами
# каждый маршрут выделяем своим цветом
clear
for ip in $ips; do
    location=$(get_sw_location $ip)
    iproute=$(get_sw_iproute $ip)
    case $iproute in
    "62.182.48.35")
        # голубой
        text_color="\033[1;36m"
        ;;
    "62.182.48.36")
        # зеленый
        text_color="\033[1;32m"
        ;;
    "62.182.48.37")
        # фиолетовый
        text_color="\033[1;35m"
        ;;
    *)
        # обычный белый
        text_color="\033[0m"
        ;;
    esac
    # -e обрабатывать escape последовательности
    echo -e "$text_color$ip ($location) - $iproute"  
done
echo -en "\n"
