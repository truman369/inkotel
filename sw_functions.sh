#!/usr/bin/env bash

#################################################
# Библиотека функций для работы с коммутаторами #
#################################################

# получение модели коммутатора по SNMP
# iso.3.6.1.2.1.1.1.0 = STRING: "D-Link DES-3200-28 Fast Ethernet Switch"
# функция вернет DES-3200-28

function get_sw_model {
    ip=$1
    echo `snmpget -v2c -c public $ip iso.3.6.1.2.1.1.1.0 \
          | grep -oE "[A-Z]{3}-[0-9]{4}[^ ]*" \
          | sed 's/"//g'`
}

# получение максимального количества портов исходя из модели коммутатора
function get_sw_max_ports {
    ip=$1
    echo `expr "$(get_sw_model $ip)" : '.*\([0-9][0-9]\)'`
}

# получение system_location по SNMP
# iso.3.6.1.2.1.1.6.0 = STRING: "ATS (operator)"

function get_sw_location {
    ip=$1
    location=`snmpget -v2c -c public $ip iso.3.6.1.2.1.1.6.0 \
              | cut -d ":" -f 2 \
              | sed 's/^ //;s/"//g' \
              | sed "s/'//g" \
              | sed 's/\///g' \
              | sed 's/\\\//g'`
    if echo $location | grep -iq "iso"; then
        location="(нет данных)"
    fi
    echo $location
}

# получение маршрута по умолчанию для l3 через SNMP
# iso.3.6.1.2.1.4.21.1.7.0.0.0.0 = IpAddress: 62.182.48.36

function get_sw_iproute {
    ip=$1
    echo `snmpget -v2c -c public $ip iso.3.6.1.2.1.4.21.1.7.0.0.0.0 \
          | cut -d ":" -f 2 \
          | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`
}

# форматированная шестнадцатеричная карта портов для вланов
# iso.3.6.1.2.1.17.7.1.4.3.1.4.1 = Hex-STRING: 00 00 00 30 00 00 00 00
# 2 - member, 3 - forbidden, 4 - untagged, следующее значение vlan_id. 
# используются первые 4 байта, побитово означают: 
# если влан принадлежит порту, то 1, если нет - 0.
# странный баг на qtech 57.209, при определенных комбинациях вланов на портах выдает
# iso.3.6.1.2.1.17.7.1.4.3.1.4.1013 = STRING: "@ " вместо Hex-STRING
# на qtech нулевые байты не отображаются, поэтому форматируем до 8 знаков и заполняем нулями
# iso.3.6.1.2.1.17.7.1.4.3.1.2.1013 = Hex-STRING: C0 20
# snmpwalk вместо snmpget, т.к. нужного vlan может не быть, что вызовет ошибку
# а так возвращает пустой результат

function get_ports_mask {
    ip=$1; vlan=$2; unt=$3
    if [[ $unt =~ ^u.* ]]; then
        oid=4
        # untagged
    else
        oid=2
        # all port with vlan
    fi
    echo `snmpwalk -v2c -c public $ip 1.3.6.1.2.1.17.7.1.4.3.1.$oid \
          | grep "\.$vlan =" \
          | cut -d " " -f 4-7 \
          | sed 's/ //g' \
          | xargs printf '%-8s' \
          | sed 's/ /0/g' \
          | sed 's/^/0x/g'`
}

# таблица mac адресов
# iso.3.6.1.2.1.17.7.1.2.2.1.2.1013.0.8.161.43.219.45 = INTEGER: 2

function get_mac_table {
    ip=$1; port=$2; vlan=$3;
    snmpwalk -v2c -c public $ip 1.3.6.1.2.1.17.7.1.2.2.1.2.$vlan \
    | egrep ": $port$" \
    | cut -d " " -f 1 \
    | cut -d "." -f 15-20 \
    | sed 's/\./ /g' \
    | while read mac; do
        printf '%02x:%02x:%02x:%02x:%02x:%02x\n' $mac
    done
}

# список портов по vlan (tagged/untagged)
function get_ports_vlan {
    ip=$1; vlan=$2; tag=$3
    max_ports=$(get_sw_max_ports $ip)
    all_ports=$(get_ports_mask $ip $vlan)
    unt_ports=$(get_ports_mask $ip $vlan "unt")
    mask=0x80000000
    # обнуляем счетчики портов
    untagged_ports=""
    tagged_ports=""
    i=0; while (( $i < $max_ports )); do let "i = i + 1"
        # перемножаем побитово, если маска совпала, проверяем тег
        if `let "all_ports & mask"`; then 
            if `let "unt_ports & mask"`; then
                untagged_ports="${untagged_ports}$i "
            else
                tagged_ports="${tagged_ports}$i "
            fi
        fi
        # сдвигаем маску на 1 бит вправо
        let "mask >>= 1"
    done
    if [[ $tag =~ ^t ]]; then
        echo $tagged_ports
    elif [[ $tag =~ ^u ]]; then
        echo $untagged_ports
    else
        echo "tagged: $tagged_ports"
        echo "untagged: $untagged_ports"
    fi
}

# проверка статуса порта

function get_port_state {
    ip=$1; port=$2
    if [ `snmpget -v2c -c public $ip 1.3.6.1.2.1.2.2.1.7.$port | cut -d " " -f 4` = 1 ]; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

# построчная отправка команд через tt.tcl 
function send_commands {
    ip=$1; shift; commands=$@
    # удаляем последнюю точку с запятой
    commands=`echo $commands | sed 's/;$//'`
    if [[ $commands > 0 ]]; then
        # echo $commands
        expect $basedir/tt.tcl "$ip" "$commands"
    fi
}

# преобразование сокращенного ip адреса в полный
function full_ip {
    ip=$1
    rx='([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
    if [[ $ip =~ ^$rx\.$rx$ ]]; then
        pre="192.168."
    else
        pre=""
    fi
    echo "$pre$ip"
}

function show {
    ip=$1
    echo """
    ==============================
    IP:         $ip
    MODEL:      $(get_sw_model $ip)
    LOCATION:   $(get_sw_location $ip)
    ==============================
    """
}

# функция для работы с vlan на коммутаторах

# TODO: возможность выбирать порты для настройки
function vlan {
    ip=$1; action=$2; shift 2; vlans=$@; commands=""
    max_ports=$(get_sw_max_ports $ip)
    model=$(get_sw_model $ip)
    if [[ "$model" =~ "QSW".* ]]; then
        commands+="conf t;"
        for vlan in $vlans; do
            if [[ $action == "add" ]]; then
                commands+="vlan $vlan;"
                commands+="    name $vlan;"
                commands+="exit;"
                commands+="int eth 1/25-$max_ports;"
                commands+="    switchport trunk allowed vlan add $vlan;"
                commands+="exit;"
            elif [[ $action == "remove" ]]; then
                commands+="no vlan $vlan;"
                commands+="int eth 1/25-$max_ports;"
                commands+="    switchport trunk allowed vlan remove $vlan;"
                commands+="exit;"
            fi
        done
    elif [[ "$model" =~ .*"3026"|"3526"|"3200-28"|"3000"|"3028G"|"1210-28X/ME".* ]]; then
        for vlan in $vlans; do
            if [[ $action == "add" ]]; then
                commands+="create vlan ${vlan} tag ${vlan};"
                commands+="config vlan ${vlan} add tag 25-$max_ports;"
            elif [[ $action == "remove" ]]; then
                commands+="delete vlan $vlan;"
            fi
        done
    else
        echo "$ip: $model not supported"
    fi
    send_commands "$ip" "$commands"
}

function save {
    ip=$1
    model=$(get_sw_model $ip)
    if [[ "$model" =~ "QSW".* || "$model" =~ .*"3600".* ]]; then
        commands="copy run st; y"
    else
        commands="save"
    fi
    echo "Saving $model $ip"
    send_commands $ip $commands
}

function vlan_change_unt {
    ip=$1; port=$2; vlan_old=$3; vlan_new=$4
    model=$(get_sw_model $ip)
    echo "Processing $model $ip port $port vlan $vlan_old -> $vlan_new"
    if [[ "$model" =~ "QSW".* ]]; then
        commands="conf t;int eth 1/$port;switchport access vlan $vlan_new;end"
    elif [[ "$model" =~ .*"3026"|"3526"|"3200-28"|"3000"|"3028G"|"1210-28X/ME".* ]]; then
        commands="conf vlan $vlan_old del $port; conf vlan $vlan_new add unt $port"
    else
        echo "$ip: $model not supported"
    fi
    send_commands "$ip" "$commands" 
}

# функция нахождения ip по acl на передаваемых портах
function get_acl {
    ip=$1; shift; ports=$@;
    model=$(get_sw_model $ip)
    if [[ "$model" =~ "QSW".* ]]; then
        for port in $ports; do
            acl=`send_commands "$ip" "sh am int eth 1/$port;" | grep ip-pool`
            acl=`echo $acl | cut -d " " -f 3`
            echo "$acl"
        done
    elif [[ "$model" =~ .*"3526"|"3200-28"|"3000"|"3028G"|"1210-28X/ME".* ]]; then
        for port in $ports; do
            #acl=`send_commands "$ip" "sh conf cur inc \"10 add access_id $port ip s\";" | grep config | cut -d " " -f 10`
            acl=`send_commands "$ip" "sh conf cur inc \"port $port p\";" | grep "profile_id 10"| sed 's/  / /g' |cut -d " " -f 10`

            echo "$acl"
        done

    else
        echo "$ip: $model not supported"
    fi    
}

function get_unt_ports_acl {
    ip=$1; vlan=$2
    max_ports=$(get_sw_max_ports $ip)
    #ищем нетегированные порты
    unt_mask=$(get_ports_mask $ip $vlan "untagged")
    # начальная маска - первый из 32 бит единичный, соответствует 1 порту.
    # 10000000000000000000000000000000
    mask=0x80000000 
    # перебираем каждый порт
    for port in `seq $max_ports`; do
        # перемножаем побитово, если маска совпала, и порт включен, считываем acl
        let "result = unt_mask & mask"
        if [[ ($result != 0) && $(get_port_state $ip $port) ]]; then
            acl=$(get_acl "$ip" "$port")
            # если правил нет, вместо них выводим mac адрес на порту
            if [[ "$acl" == "" ]]; then
                acl=$(get_mac_table $ip $port $vlan)
            fi
            echo "$ip $port $acl"
        fi
        # сдвигаем маску на 1 бит вправо
        let "mask >>= 1"
    done
}