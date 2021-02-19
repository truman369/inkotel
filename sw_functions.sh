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
    elif [[ "$model" =~ .*"3526"|"3200-28"|"3000"|"3028G"|"1210-28X/ME".* ]]; then
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
    ip=$1; shift; ports=$@; commands="";
    model=$(get_sw_model $ip)
    if [[ "$model" =~ "QSW".* ]]; then
        for port in $ports; do
            commands+="sh am int eth 1/$port;"
        done
        result=`send_commands "$ip" "$commands"`
        # начинаем считывать построчно результат, если натыкаемся на строчку с Ethernet,
        # то ставим флаг, что проверяем конфиг порта, идем дальше, пока не найдем ip-pool
        # если снова наткнулись на Ethernet, значит am не указан, обнуляем флаг
        out=$(
            echo "$result" | while read line; do
                if [[ "$line" =~ "Ethernet" ]]; then
                    if [[ $port_flag == true ]]; then
                        port_flag=false
                        echo "null"
                    else
                        echo "$line" | cut -d "/" -f 2
                        port_flag=true
                    fi
                fi
                if [[ ($port_flag == true) && ("$line" =~ "ip-pool") ]]; then
                    port_flag=false
                    echo -en "$line" | cut -d " " -f 3 | sed 's/ //g'
                fi
            done
        )
        i=0; out2=""
        for line in $out; do
            if [[ $line > 0 ]]; then
                let i+=1
                out2+="$line "
                if [[ $(($i % 2)) -eq 0 ]]; then
                    out2+="\n"
                fi
            fi
        done
        echo -en $out2
        #echo "Output: $out"
    elif [[ "$model" =~ .*"3526"|"3200-28"|"3000"|"3028G"|"1210-28X/ME".* ]]; then
        for port in $ports; do
            commands+="sh conf cur inc \"10 add access_id $port ip s\";"
        done
        result=`send_commands "$ip" "$commands" | sed 's/source_/\n/g' | grep "^ip" | tr -d '[:alpha:]'`
        # config access_profile profile_id 10 add access_id 1 ip source_ip 1.2.3.4 port 1 permit
        i=0
        echo "$result" | while read line; do
            acl=`echo $line | cut -d " " -f 1`
            port=`echo $line | cut -d " " -f 2`
            echo "$port $acl"
        done
    else
        echo "$ip: $model not supported"
    fi    
    #echo "$result"
}

# подумать над форматом, и случай, когда пустой результат