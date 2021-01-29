#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

ipdir="$basedir/config/ip/"
# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

#~ commands=$(<$basedir/config/test.cfg)

#~ for c in $commands; do
    #~ echo $c
#~ done


# задаем ассоциативный массив для файлов ip адресов
# ключ - название файла, значение - путь до файла
declare -A ip_files
for zone in `ls $ipdir |grep .ip`; do
    zone_name=`echo $zone | sed "s/.ip$//g"`
    ip_files[$zone_name]=`readlink -f $ipdir/$zone`
done

# запрашиваем список ip адресов либо из файла, либо вручную
echo "Выберите диапазон ip адресов из файлов"
PS3='Ваш ответ: '
select answer in ${!ip_files[*]} "ввести вручную" "отмена"; do
    case $answer in
    "Отмена")
        exit
        break
        ;;
    "")
        echo "мимо"
        ;;
    "ввести вручную")
        echo "Введите ip адреса через пробел:"
        read ips
        break
        ;;
    *)
        # удаляем из файла комментарии и пустые строки
        ips=`egrep -v "^$|^#" ${ip_files[$answer]}`
        break
        ;;
    esac
done

# запрашиваем действие над коммутаторами
# тут мы вызываем функцию с тем же именем, что и в списке выбора
echo "Что нужно сделать?"
select answer in "vlan_add" "отмена"; do
    case $answer in
    "Отмена")
        exit
        break
        ;;
    "")
        echo "мимо"
        ;;
    *)
        $answer $ips
        break
        ;;
    esac
done




