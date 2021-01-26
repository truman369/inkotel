#!/usr/bin/env bash

# Библиотека функций для работы с коммутаторами

# SNMP

# Получение модели коммутатора
# В качестве параметра передаем ip адрес
# пример строки SNMP: 
# iso.3.6.1.2.1.1.1.0 = STRING: "D-Link DES-3200-28 Fast Ethernet Switch"
# функция вернет DES-3200-28

function get_sw_model {
    echo `snmpget -v2c -c public $1 iso.3.6.1.2.1.1.1.0 | grep -oE "[A-Z]{3}-[0-9]{4}[^ ]*"`
}

# получение максимального количества портов исходя из модели коммутатора
function get_sw_max_ports {
    echo `expr "$(get_sw_model $1)" : '.*\([0-9][0-9]\)'`
}

# Получение system_location 
# В качестве параметра передаем ip адрес
# пример строки SNMP: 
# iso.3.6.1.2.1.1.6.0 = STRING: "ATS (operator)"

function get_sw_location {
    echo `snmpget -v2c -c public $1 iso.3.6.1.2.1.1.6.0 | cut -d ":" -f 2 | sed 's/^ //;s/"//g' | sed "s/'//g" | sed 's/\///g' | sed 's/\\\//g'`
}

# Получение маршрута по умолчанию для l3
# В качестве параметра передаем ip адрес
# пример строки SNMP: 
# iso.3.6.1.2.1.4.21.1.7.0.0.0.0 = IpAddress: 62.182.48.36

function get_sw_iproute {
    echo `snmpget -v2c -c public $1 iso.3.6.1.2.1.4.21.1.7.0.0.0.0 |cut -d ":" -f 2| grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`
}



