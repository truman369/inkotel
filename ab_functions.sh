#!/usr/bin/env bash

#################################################
#  Библиотека функций для работы с серой базой  #
#################################################

base_url="http://192.168.255.251"
ab_secret="$basedir/config/ab.secret"
cookie="$basedir/config/ab.cookie"

# нахождение номера договора по ip адресу
function find {
    local ip=$(full_ip $1)
    local result="not found"
    # сначала делаем поиск по ip, т.к. в серой базе поиск идет по частичному совпадению
    # может вылезти несколько договоров: например, для 2 в последнем октете 
    # поиск выведет также и 20, 21, 203 и т.д., поэтому создаем список возможных договоров
    # потом для каждого договора проводим обратную операцию: 
    # вычисляем айпи адреса, числящиеся за данным договором
    # далее сопоставляем полученные данные и находим искомое соответствие
    local contracts=`curl -s -d "ip=$ip" -d "go99=1" "$base_url/poisk_test.php" |
               grep -oE "[0-9]{5}</td>" |
               sed 's/<\/td>//g'`
    for contract in $contracts; do
        local contract_ips=$(ips $contract)
        for contract_ip in $contract_ips; do
            if [ $contract_ip == $ip ]; then
                result=$contract
            fi
        done
    done
    echo "$result"
}

# нахождение ip по номеру договора
function ips {
    local contract=$1
    local result=`curl -s -d "nome_dogo=$contract" -d "go=1" "$base_url/bil.php" |
            grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`
    echo "$result"
}

# последний платеж
function last_pay {
    local contract=$1
    local result=`curl -s --get -d "nome_dogo=$contract" "$base_url/bil_pay.php" |
            sed -n '/<center>/{h;bo};H;/<\/table>/{g;/<tr><td>/p;q};:o' |
            grep  "^<tr><td>" |
            grep -oE "[0-9]{2}-[0-9]{2}-[0-9]{4}" |
            tail -1`
    echo "$result"
}

# внутренний id абонента в серой базе
function get_id {
    local contract=$1
    local result=`curl -s -d "dogovor=$contract" -d "startt=1" "$base_url/poisk_test.php" |
            grep "id_aabon" |
            grep -oE "[0-9]*"`
    echo "$result"
}

# авторизация в серой базе, обновляет cookie-файл для последующего использования
function auth {
    # логин в файле должен быть закодирован в cp1251, например, %D2%F0%EE%E8%F6%EA%E8%E9
    read user pass <<< $(cat $ab_secret)
    local result=$(curl -s --cookie-jar $cookie \
                 -d "username=$user" \
                 -d "password=$pass" \
                 -d "temp_user_pass=1" \
                 "$base_url/index.php" |
                 iconv -f "cp1251")
    if [[ "$result" =~ "Кто ты?" ]]; then
        echo "Auth error"
    else
        echo "OK"
    fi
}

# проверка авторизации
function check_auth {
    local result=$(curl -s --cookie $cookie "$base_url/index.php" | iconv -f "cp1251")
    if [[ "$result" =~ "Кто ты?" ]]; then
        result=$(auth)
    else
        result="OK"
    fi
    if [[ "$result" != "OK" ]]; then
        echo $result
        exit 1
    fi
}

# выборка данных из серой базы
function get {
    local contract=$1; shift; local params=$@;
    local ips=$(ips $contract)
    local id=$(get_id $contract)
    # проверка авторизации
    check_auth
    # дальше лютые костыли
    local result=`curl -s --cookie $cookie --get -d "id_aabon=$id" "$base_url/index.php" |
            iconv -f "cp1251"`
    local street=`echo "$result" |
            grep -A 1 "ulitsa" |
            grep -oE ">.*</option><option value=\"1-ая Заводская" |
            cut -d '<' -f 1 |
            sed 's/^>//;s/ *$//'`
    IFS=";"
    read name organization house room sw_ip port length <<< `echo "$result" |
        grep "input size=" |
        egrep -w "fio|organizatsiya|dom|kvartira|loyalnost|port|dlina_cab" |
        awk -F'[="]' -v ORS=';' '{print $12}'`
    local sw_ip=$(full_ip $sw_ip)
    IFS=' '
    if [[ $params ]]; then
        for p in $params; do
            echo "${!p}"
        done
    else
        echo -e "$YELLOW$contract$NO_COLOR $BLUE$name $organization$NO_COLOR"
        echo -e "$CYAN$ips$NO_COLOR"
        echo -e "$BLUE$street $house - $room$NO_COLOR"
        echo -e "$GREEN$sw_ip$NO_COLOR $YELLOW$port$NO_COLOR $MAGENTA$length$NO_COLOR"
    fi
}
