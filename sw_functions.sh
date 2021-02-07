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
# $commands - multiline string
function send_commands {
    ip=$1; commands=$2
    #~ expect $basedir/../test.tcl "$ip" "$commands"
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

function sw_info {
    ip=$1
    echo """
    ==============================
    IP:         $ip
    MODEL:      $(get_sw_model $ip)
    LOCATION:   $(get_sw_location $ip)
    ==============================
    """
}

# функция добавления транзитных vlan на коммутаторы
function vlan_add { 
# TODO: проверка модели и конфиг для qtech
    ip=$1; vlans=$2; commands=""
    max_ports=$(get_sw_max_ports $ip)
    for vlan in $vlans; do
        commands=${commands}"""
        create vlan $vlan tag $vlan
        config vlan $vlan add tag 25-$max_ports
        """
    done
    commands=${commands}"save"
    send_commands "$ip" "$commands"
}

# функция полного удаления vlan с коммутатора
function vlan_remove {
# TODO: проверка модели и конфиг для qtech
    ip=$1; vlans=$2; commands=""
    for vlan in $vlans; do
        # не забываем про многострочность, даже если одна команда
        commands=${commands}"""
        delete vlan $vlan
        """
    done
    commands=${commands}"save"
    send_commands "$ip" "$commands"
}
