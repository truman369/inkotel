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

# построчная отправка команд через tt.tcl 
function send_commands {
    ip=$1; shift; commands=$@
    # удаляем последнюю точку с запятой
    commands=`echo $commands | sed 's/;$//'`
    # echo $commands
    expect $basedir/tt.tcl "$ip" "$commands"
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
        #commands+="end; copy run st; y;"
    elif [[ "$model" =~ .*"3026"|"3526"|"3200-28"|"3000"|"3028G"|"1210-28X/ME".* ]]; then
        for vlan in $vlans; do
            if [[ $action == "add" ]]; then
                commands+="create vlan ${vlan} tag ${vlan};"
                commands+="config vlan ${vlan} add tag 25-$max_ports;"
            elif [[ $action == "remove" ]]; then
                commands+="delete vlan $vlan;"
            fi
        done
        #commands+="save;"
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
    unt_ports=`snmpwalk -v2c -c public $ip 1.3.6.1.2.1.17.7.1.4.3.1.4 | grep "\.$vlan =" | cut -d " " -f 4-7 | sed 's/ //g'`
    # странный баг на qtech 57.209, при определенных комбинациях вланов на портах выдает
    # iso.3.6.1.2.1.17.7.1.4.3.1.4.1013 = STRING: "@ " вместо Hex-STRING
    # на qtech нулевые байты не отображаются, поэтому форматируем до 8 знаков и заполняем нулями
    unt_ports=`printf "%-#8s" $unt_ports | sed 's/ /0/g'`
    unt_ports="0x${unt_ports}"
    # начальная маска - первый из 32 бит единичный, соответствует 1 порту.
    mask=0x80000000 
    # перебираем каждый порт
    port=0; while (( $port < $max_ports )); do let "port = port + 1" 
        # перемножаем побитово, если маска совпала, проверяем состояние порта и маки
        if `let "unt_ports & mask"`; then 
            # проверяем, включен ли порт
            if [ `snmpget -v2c -c public $ip 1.3.6.1.2.1.2.2.1.7.$port | cut -d " " -f 4` = 1 ]; then
                acl=$(get_acl "$ip" "$port")
                if [[ "$acl" == "" ]]; then
                    acl=$(snmpwalk -v2c -c public $ip 1.3.6.1.2.1.17.7.1.2.2.1.2.$vlan | egrep ": $port$" | cut -d " " -f 1 | cut -d "." -f 15-20 | sed 's/\./ /g' | while read mac; do
                       printf '%02x:%02x:%02x:%02x:%02x:%02x ' $mac
                    done)
                fi
                echo "$ip $port $acl"
            fi
        fi
        # сдвигаем маску на 1 бит вправо
        let "mask >>= 1"
    done
}