#!/usr/bin/env bash

#################################################
#  Библиотека функций для работы с серой базой  #
#################################################


# нахождение номера договора по ip адресу
function contract {
    ip=$1
    result="not found"
    # сначала делаем поиск по ip, т.к. в серой базе поиск идет по частичному совпадению, может вылезти несколько договоров
    # например, для 2 в последнем октете поиск выведет также и 20, 21, 203 и т.д., поэтому создаем список возможных договоров
    # потом для каждого договора проводим обратную операцию, вычисляем айпи адреса, числящиеся за данным договором
    # далее сопоставляем полученные данные и находим искомое соответствие
    contracts=`curl -sd "ip=$ip&go99=1" 192.168.255.251/poisk_test.php |
               iconv -f cp1251 |
               grep -oE "[0-9]{5}</td>" |
               sed 's/<\/td>//g'`
    for contract in $contracts; do
        contract_ips=`curl -sd "nome_dogo=$contract&go=1" 192.168.255.251/bil.php |
                      iconv -f cp1251 |
                      grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`
        for contract_ip in $contract_ips; do
            if [ $contract_ip == $ip ]; then
                result=$contract
            fi
        done
    done
    echo "$result"
}

# последний платеж
function last_pay {
    contract=$1
    result=`curl -s http://192.168.255.251/bil_pay.php?nome_dogo=$contract |
            iconv -f cp1251 |
            sed -n '/<center>/{h;bo};H;/<\/table>/{g;/<tr><td>/p;q};:o' |
            grep  "^<tr><td>" |
            grep -oE "[0-9]{2}-[0-9]{2}-[0-9]{4}" |
            tail -1`
    echo "$result"
}

# внутренний id абонента в серой базе
function get_id {
    contract=$1
    result=`curl -sd "dogovor=$contract&startt=1" 192.168.255.251/poisk_test.php |
            iconv -f cp1251 |
            grep id_aabon |
            grep -oE "[0-9]*"`
    echo "$result"
}