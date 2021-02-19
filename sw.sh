#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

ipdir="$basedir/config/ip/"
# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

# если есть параметры, то запускаем сразу нужную функцию и выходим
if [[ "$#" > 0 ]]; then
    ip=$(full_ip $1); func=$2; shift 2;
    $func $ip $@
    exit
fi

# задаем ассоциативный массив для файлов ip адресов
# ключ - название файла, значение - путь до файла
declare -A ip_files
for zone in `ls $ipdir |grep .ip`; do
    zone_name=`echo $zone | sed "s/.ip$//g"`
    ip_files[$zone_name]=`readlink -f $ipdir/$zone`
done

# TODO: выбор нескольких районов

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

# если вдруг внутри оказались сокращенные ip, преобразуем их
for ip in $ips; do
    full_ips+="$(full_ip $ip) "
done
ips=$full_ips

# запрашиваем действие над коммутаторами
# в дальнейшем вызываем функцию с тем же именем, что и в списке выбора
echo "Что нужно сделать?"
select func in "get_unt_ports_acl" "vlan" "отмена"; do
    case $func in
    "отмена")
        exit
        break
        ;;
    "")
        echo "мимо"
        ;;
    *)
        break
        ;;
    esac
done
echo "Введите параметры через пробел: "
read params

echo "$func: $params"
echo "для коммутаторов: $ips"
echo "Продолжить? [y/n]"
read agree
if [ $agree != "y" ]; then
    exit
fi
for ip in $ips; do
    $func $ip $params
done
