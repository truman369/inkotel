#!/usr/bin/env bash

#################################################
# Библиотека функций для работы с коммутаторами #
#################################################

# получение модели коммутатора по SNMP
# iso.3.6.1.2.1.1.1.0 = STRING: "D-Link DES-3200-28 Fast Ethernet Switch"
# функция вернет DES-3200-28

function get_sw_model {
    ip=$1
    echo `snmpget -v2c -c public $ip iso.3.6.1.2.1.1.1.0 |
          grep -oE "[A-Z]{3}-[0-9]{1,4}[^ ]*" |
          sed 's/"//g'`
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
    location=`snmpget -v2c -c public $ip iso.3.6.1.2.1.1.6.0 |
              cut -d ":" -f 2 |
              sed 's/^ //;s/"//g' |
              sed "s/'//g" |
              sed 's/\///g' |
              sed 's/\\\//g'`
    if echo $location | grep -iq "iso"; then
        location="(нет данных)"
    fi
    echo $location
}

# получение маршрута по умолчанию для l3 через SNMP
# iso.3.6.1.2.1.4.21.1.7.0.0.0.0 = IpAddress: 62.182.48.36

function get_sw_iproute {
    ip=$1
    echo `snmpget -v2c -c public $ip iso.3.6.1.2.1.4.21.1.7.0.0.0.0 |
          cut -d ":" -f 2 |
          grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`
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
    echo `snmpwalk -v2c -c public $ip 1.3.6.1.2.1.17.7.1.4.3.1.$oid |
          grep "\.$vlan =" |
          cut -d " " -f 4-7 |
          sed 's/ //g' |
          xargs printf '%-8s' |
          sed 's/ /0/g' |
          sed 's/^/0x/g'`
}

# таблица mac адресов
# iso.3.6.1.2.1.17.7.1.2.2.1.2.1013.0.8.161.43.219.45 = INTEGER: 2

function get_mac_table {
    ip=$1; port=$2; vlan=$3;
    snmpwalk -v2c -c public $ip 1.3.6.1.2.1.17.7.1.2.2.1.2.$vlan |
    egrep ": $port$" |
    cut -d " " -f 1 |
    cut -d "." -f 15-20 |
    sed 's/\./ /g' |
    while read mac; do
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
    for i in `seq $max_ports`; do
        # перемножаем побитово, если маска совпала, проверяем тег
        if `let "all_ports & mask"`; then 
            if `let "unt_ports & mask"`; then
                untagged_ports+="$i "
            else
                tagged_ports+="$i "
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
    if [[ `snmpget -v2c -c public $ip 1.3.6.1.2.1.2.2.1.7.$port | cut -d " " -f 4` = 1 ]]; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

# построчная отправка команд через tt.tcl 
function send_commands {
    ip=$1; shift; commands=$@
    # удаляем последнюю точку с запятой
    # TODO: протестировать на разных моделях, действительно ли это нужно делать
    # на gpon LTP наоборот не срабатывает одна команда, если в конце нет символа ;
    # в причинах не разбирался, пока сделал костыль в виде ;;
    commands=`echo $commands | sed 's/;$//'`
    if [[ $commands > 0 ]]; then
        # echo $commands
        expect $basedir/tt.tcl "$ip" "$commands"
    fi
}

# преобразование маски подсети из префикса
function prefix2mask {
    prefix=$1;
    for (( i=0; i < 32; i++ )); do
        if [[ $i -lt $prefix ]]; then
            bit=1
        else
            bit=0
        fi
        if [[ $(( i % 8 )) -eq 0 ]]; then
            spacer=" "
        else
            spacer=""
        fi
        bitmask+="${spacer}${bit}"
    done
    for octet in $bitmask; do
        mask+="$(( 2#$octet ))."
    done
    echo $mask | sed 's/.$//g'
}

# вывод arp таблицы по ip интерфейса
function get_ipif_arp {
    ipif_ip=$1
    # iso.3.6.1.2.1.4.20.1.2.62.182.50.1 = INTEGER: 5253
    ipif_id=$(snmpget -v2c -c public $ipif_ip 1.3.6.1.2.1.4.20.1.2.$ipif_ip |
              cut -d ":" -f 2 |
              sed 's/^ //g')
    # 1.3.6.1.2.1.4.22.1.2.5273.62.182.52.249 = Hex-STRING: 18 0F 76 26 B7 48
    result=$(snmpwalk -v2c -c public $ipif_ip 1.3.6.1.2.1.4.22.1.2.$ipif_id |
             sed "s/^.*$ipif_id.//;s/ = Hex-STRING: /\t/;s/ $//;s/ /:/g" |
             # исключаем первую и последнюю строки - широковещательный и адрес сети
             grep -v 'FF:FF:FF:FF:FF:FF')
    echo "$result"
}

# mac адрес по ip из arp таблицы
# по умолчанию префикс 24, для белых надо указывать, если сетка разбита
function arp {
    IFS=/ read -r ip prefix <<< "$1"
    if [[ $prefix == "" ]]; then prefix=24; fi
    ip=$(full_ip $ip)
    mask=$(prefix2mask $prefix)
    IFS=. read -r i1 i2 i3 i4 <<< "$ip"
    IFS=. read -r m1 m2 m3 m4 <<< "$mask"
    gw_ip="$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$(((i4 & m4)+1))"
    if [[ "$i1.$i2" != "192.168" && $prefix == 24 ]]; then
        echo -e "${RED}Using standart /24 prefix!$NO_COLOR"
    fi
    result=$(get_ipif_arp $gw_ip)
    if [[ $ip != $gw_ip ]]; then
        echo "$result" | grep -w "$ip" | cut -f 2
    else
        echo "$result"
    fi
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
        commands="copy run st"
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
            acl=$(send_commands "$ip" "sh conf cur inc \"port $port p\";" |
                  grep "profile_id 10"|
                  sed 's/  / /g' |
                  cut -d " " -f 10)
            echo "$acl"
        done
    else
        echo "$ip: $model not supported"
    fi    
}

# сохранение настроек на tftp
function backup {
    ip=$(full_ip $1)
    model=$(get_sw_model $ip)
    net=`echo $ip | cut -d "." -f 3`
    # TODO: разобраться с багом, протестировать на других длинных командах
    # На модели DXS-1210-28S выявился баг, когда путь+имя больше 25 символов
    # \r\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C\u001b[C$\u001b[0K
    # внутри имени во время ответа коммутатора, из-за этого не отрабатывает expect
    # поэтому временно укорочен путь с cfg/backup до backup
    backup_dir="backup"
    server="192.168.$net.250"
    case $model in
        "DES-3026" )
            commands="upload configuration $server $backup_dir/$ip.cfg"
        ;;
        "DGS-3000"* | "DGS-3627G" | "DGS-3120"* | *"C1" )
            commands="upload cfg_toTFTP $server dest_file $backup_dir/$ip.cfg"
        ;;
        "DES-3526" | "DES-3028G" | "DES-3200"* | "DGS-1210"* )
            commands="upload cfg_toTFTP $server $backup_dir/$ip.cfg"
        ;;
        "DXS-3600-32S" | "DXS-1210-28S" )
            commands="copy running-config tftp: //$server/$backup_dir/$ip.cfg"
        ;;
        "QSW"* )
            commands="copy running-config tftp://$server/$backup_dir/$ip.cfg"
        ;;
        # у LTP команда срабатывает, только когда в самом конце символ ;
        # т.к. у меня последний такой символ обрезается, добавил костыль ;;
        # TODO: разобраться, почему так происходит
        "LTP"* )
            commands="copy fs://config tftp://$server/$backup_dir/$ip.cfg;;"
        ;;
        "DXS-1210-12SC" )
            if [[ "$ip" == "192.168.57.1" ]]; then
                commands="copy running-config tftp://$server/$backup_dir/$ip.cfg"
            else
                # у DXS-1210-12SC A1 конфиг в бинарном формате
                commands="copy startup-config tftp://$server/$backup_dir/$ip.bin"
            fi
        ;;
        * )
            commands=""
        ;;
    esac
    if [[ $commands == "" ]]; then
        echo "$ip: $model not supported"
    else
        send_commands "$ip" "$commands"
    fi
}