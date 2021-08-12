#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# общие функции и константы
source $basedir/common.sh

# библиотека функций для работы с серой базой
source $basedir/ab_functions.sh

# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

# блокировка абонента на порту
function block {
    contract=$1
    flag=$2 # флаг разблокировки
    # берем из серой базы коммутатор, порт, айпи адреса абонента
    # айпи адреса в конце, т.к. их может быть несколько
    read -d "\n" sw_ip port ips <<< `get $contract "sw_ip" "port" "ips"`
    # смотрим acl на порту коммутатора
    ip=$(get_acl $sw_ip $port)
    result="$YELLOW$contract$NO_COLOR: "
    # проверяем, чтобы айпишник совпадал в базе и на коммутаторе
    if [[ $ips != *$ip* || $ip == "" ]]; then
        result+="${RED}ACL error, need manual operations!$NO_COLOR"
    else
        # проверяем, включен ли порт
        port_state=$(get_port_state $sw_ip $port)
        if [[ ( $port_state == "disabled" && $flag == "" ) || \
                ( $port_state == "enabled" && $flag =~ ^u ) ]]; then
            result+="${YELLOW}Warning, port already $port_state!$NO_COLOR"
        elif [[ $port_state == "enabled" && $flag == "" ]]; then
            set_port_state $sw_ip $port "disable" "$contract BLOCKED $(date +'%F')"
            result+="${GREEN}Successfully blocked$NO_COLOR"
            # backup $sw_ip
            # git -C $git_dir add $sw_ip.cfg
            # git -C $git_dir commit -m "$contract block"
            # save $sw_ip
        elif [[ $port_state == "disabled" && $flag =~ ^u ]]; then
            set_port_state $sw_ip $port "enable"
            result+="${GREEN}Successfully unblocked$NO_COLOR"
            # backup $sw_ip
            # git -C $git_dir add $sw_ip.cfg
            # git -C $git_dir commit -m "$contract unblock"
            # save $sw_ip
        else
            result+="${RED}Port state error!$NO_COLOR"
        fi
        result+=" $CYAN$sw_ip port $port$NO_COLOR"
    fi
    echo -e "$result"
}

function print_usage {
    echo "Usage: $0 <contract_id> [unblock]"
    echo "       $0 <path_to_file> [unblock]"
    exit
}

# проверяем параметры
if [[ "$#" < 1 ]]; then
    print_usage
fi
# параметр - номер договора
if [[ $1 =~ ^[0-9]{5}$ ]]; then
    block $1 $2
    exit
fi

# параметр - путь к файлу со списком договоров
contracts=$(cat $1)
if ! [[ $contracts > 0 ]]; then
    echo -e "${RED}Empty list of contracts$NO_COLOR"
    exit 1
fi
for c in $contracts; do
    block $c $2
done

