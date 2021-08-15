#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# общие функции и константы
source $basedir/common.sh

# библиотека функций для работы с серой базой
source $basedir/ab_functions.sh

# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

# очистка порта при расторжении договора
function terminate {
    contract=$1
    # файл лога вывода команд, сохраняется, если произошла ошибка
    logfile="terminate_$contract.log"
    # файл для шаблонных ответов по заявкам
    if [[ $2 ]]; then
        resultfile=$2
    else
        resultfile="/dev/null"
    fi
    result="$YELLOW$contract$NO_COLOR: "
    # берем из серой базы коммутатор, порт, айпи адреса абонента
    # айпи адреса в конце, т.к. их может быть несколько
    read -d "\n" sw_ip port ips <<< `get $contract "sw_ip" "port" "ips"`
    # проверяем валидность данных из серой базы
    if [[ $sw_ip == "" || $port == "" ]]; then
        result+="${RED}Wrong switch address or port!$NO_COLOR "
    else
        # смотрим acl на порту коммутатора
        ip=$(get_acl $sw_ip $port)
        # ищем еще договора с таким ip
        new_contract=$(find $ip)
        if [[ $new_contract =~ ^[0-9]{5}$ ]]; then
            IFS=' ' read new_sw_ip new_port <<< $(echo $(get $new_contract "sw_ip" "port"))
        fi
        # проверяем, что в биллинге айпишника нет
        if [[ $ips ]]; then
            result+="${RED}Found address in billing: $CYAN$ips$NO_COLOR "
        # если acl нет, на всякий случай проверяем вручную
        elif [[ $ip == "" ]]; then
            result+="${RED}ACL error, need manual operations!$NO_COLOR "
        # проверяем, другие договора на этом порту
        elif [[ "$new_sw_ip" == "$sw_ip" && "$new_port" == "$port" ]]; then
            result+="${YELLOW}Warning, port used by $CYAN$new_contract$NO_COLOR "
            echo "$contract На порту подключен абонент $new_contract." \
                "Настройки убирать не требуется. Договор расторг. Выполнено." >> $resultfile
        # убираем настройки
        else
            # временные костыли, полностью переделать этот раздел!
            model=$(get_sw_model $sw_ip)
            vlan=$(echo $ip | cut -d "." -f 3)
            commands=""
            if [[ ! "$model" =~ .*"3200-28"|"3000"|"3028G"|"1210-28X/ME".* ]]; then
                result+="${RED}Model $CYAN$model ${RED}not supported, "
                result+="need manual operations!$NO_COLOR "
            else
                commands+="config access_profile profile_id 10 delete access_id $port;"
                commands+="config access_profile profile_id 20 delete access_id $port;"
                commands+="config vlan $vlan del $port;"
                commands+="config ports $port st d d \"FREE $contract TERMINATED $(date +'%F')\";"
                commands+="config igmp_snooping multicast_vlan 1500 delete member_port $port;"
                commands+="config limited_multicast_addr ports $port ipv4 delete profile_id 1;"
                commands+="config limited_multicast_addr ports $port ipv4 delete profile_id 2;"
                commands+="config limited_multicast_addr ports $port ipv4 delete profile_id 3;"
                if (send_commands "$sw_ip" "$commands" \
                    && backup $sw_ip \
                    && git -C $git_dir add $sw_ip.cfg \
                    && git -C $git_dir commit -m "$contract termination" \
                    && save $sw_ip)>$logfile
                then
                    result+="${GREEN}Successfully terminated$NO_COLOR "
                    echo "$contract Настройки на порту убрал," \
                        "договор расторг. Выполнено." >> $resultfile
                    rm $logfile
                else
                    result+="${RED}Something went wrong! Saved log: $logfile$NO_COLOR "
                fi
            fi
            result+="\n$CYAN$sw_ip ${YELLOW}port $CYAN$port "
            result+="${YELLOW}vlan $CYAN$vlan ${YELLOW}ip $CYAN$ip$NO_COLOR "
        fi
    fi
    echo -e "$result"
}

function print_usage {
    echo "Usage: $0 <contract_id> [resultfile]"
    echo "       $0 <path_to_file> [resultfile]"
    exit
}

# проверяем параметры
if [[ "$#" < 1 ]]; then
    print_usage
fi
# параметр - номер договора
if [[ $1 =~ ^[0-9]{5}$ ]]; then
    terminate $1 $2
    exit
fi

# параметр - путь к файлу со списком договоров
contracts=$(cat $1)
if ! [[ $contracts > 0 ]]; then
    echo -e "${RED}Empty list of contracts$NO_COLOR"
    exit 1
fi
for c in $contracts; do
    terminate $c $2
done

