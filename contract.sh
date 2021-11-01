#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# общие функции и константы
source $basedir/common.sh

# библиотека функций для работы с серой базой
source $basedir/ab_functions.sh

# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

# TODO: убрать повторяющийся код
#       вынести логирование из функций в оболочку
#       сохранение и бекап сделать отключаемыми

# set -euo pipefail  # <-- отключил, т.к. фейлится в terminate где read

# debug
# set -x

function print_usage {
    echo "usage:"
    echo "       $0 <contract_id> <function> [<params>]"
    echo "       $0 batch <function> <batch_file> [<params>]"
    echo ""
    echo "function:"
    echo "          block        disable switch port"
    echo "          unblock      enable switch port"
    echo "          terminate    remove port configutation"
    echo ""
    echo "params:"
    echo "        comment - comment on port description for block/unblock"
    echo "                  default (block):   <contract_id> BLOCKED <date>"
    echo "                  default (unblock): <empty>"
    echo ""
    echo "        reportfile - file for report phrases on termination"
    echo "                     default: /dev/null"
    echo ""
    echo "For batch processing, put list of contracts into <batch_file>"
    echo ""
}

# очистка порта при расторжении договора
function terminate {
    local contract=$1; shift
    # файл лога вывода команд, сохраняется, если произошла ошибка
    local logfile="terminate_$contract.log"
    # файл для шаблонных ответов по заявкам
    local resultfile
    if [[ -n "$@" ]]; then
        resultfile=$@
    else
        resultfile="/dev/null"
    fi
    local result="$YELLOW$contract$NO_COLOR: "
    # берем из серой базы коммутатор, порт, айпи адреса абонента
    # айпи адреса в конце, т.к. их может быть несколько
    local sw_ip; local port; local ips
    read -d "\n" sw_ip port ips <<< `get $contract "sw_ip" "port" "ips"`
    # проверяем валидность данных из серой базы
    if [[ $sw_ip == "" || $port == "" ]]; then
        result+="${RED}Wrong switch address or port!$NO_COLOR "
    else
        # смотрим acl на порту коммутатора
        local ip=$(get_acl $sw_ip $port)
        # ищем еще договора с таким ip
        local new_contract=$(find $ip)
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
            # расторгаем в серой базе
            terminate_contract $contract
        # убираем настройки
        else
            # временные костыли, полностью переделать этот раздел!
            local model=$(get_sw_model $sw_ip)
            local vlan=$(echo $ip | cut -d "." -f 3)
            local commands=""
            if [[ ! "$model" =~ .*"3200-28"|"3000"|"3526"|"3028G"|"1210-28X/ME".* ]]; then
                result+="${RED}Model $CYAN$model ${RED}not supported yet, "
                result+="need manual operations!$NO_COLOR "
                result+="\n$CYAN$sw_ip ${YELLOW}port $CYAN$port "
                result+="${YELLOW}vlan $CYAN$vlan ${YELLOW}ip $CYAN$ip$NO_COLOR "
            else
                commands+="config access_profile profile_id 10 delete access_id $port;"
                commands+="config access_profile profile_id 20 delete access_id $port;"
                commands+="config vlan $vlan del $port;"
                commands+="config ports $port st d d \"FREE $contract TERMINATED $(date +'%F')\";"
                if [[ "$model" == "DES-3526" ]]; then
                    local igmp_ports=$(send_commands "$sw_ip" "sh igmp_sn m" |
                        grep "Member ports" |
                        cut -d ':' -f 2 |
                        sed 's/ //g;s/\r//')
                    igmp_ports=$(iterate "$igmp_ports" | sed "s/$port//g;s/ /,/g;s/^,//;s/,$//;s/,,/,/g")
                    commands+="config igmp_snooping multicast_vlan 1500 member_port $igmp_ports;"
                    for i in $(seq 3); do
                        commands+="config limited_multicast_addr ports $port delete multicast_range $i;"
                    done
                else
                    commands+="config igmp_snooping multicast_vlan 1500 delete member_port $port;"
                    for i in $(seq 3); do
                        commands+="config limited_multicast_addr ports $port ipv4 delete profile_id $i;"
                    done
                fi
                if [[ "$model" =~ .*"3000"|"1210-28X/ME".* ]]; then
                    commands+="config bandwidth_control $port tx_rate 102400 rx_rate 102400;"
                fi
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
                    terminate_contract $contract
                else
                    result+="${RED}Something went wrong! Saved log: $logfile$NO_COLOR "
                fi
            fi
            # result+="\n$CYAN$sw_ip ${YELLOW}port $CYAN$port "
            # result+="${YELLOW}vlan $CYAN$vlan ${YELLOW}ip $CYAN$ip$NO_COLOR "
        fi
    fi
    echo -e "$result"
}

# универсальная функция блокировки/разблокировки по номеру договора
function change_port {
    local state=$1; local contract=$2; shift 2;
    # port description
    local comment
    # приставка для отображения в логах
    local pre=""
    if [[ -n "$@" ]]; then
        comment=$@
    elif [[ $state =~ ^d ]]; then
        comment="$contract BLOCKED $(date +'%F')"
    elif [[ $state =~ ^e ]]; then
        pre="un"
        comment=""
    fi
    # лог для ошибок
    local logfile="blocking_$contract.log"
    # берем из серой базы коммутатор, порт, айпи адреса абонента
    # айпи адреса в конце, т.к. их может быть несколько
    local sw_ip; local port; local ips
    read -d "\n" sw_ip port ips <<< `get $contract "sw_ip" "port" "ips"`
    # смотрим acl на порту коммутатора
    local ip=$(get_acl $sw_ip $port)
    local result="${YELLOW}${contract}${NO_COLOR}: "
    # проверяем, чтобы айпишник совпадал в базе и на коммутаторе
    if [[ $ips != *$ip* || $ip == "" ]]; then
        result+="${RED}ACL error, need manual operations!${NO_COLOR}"
    else
        # проверяем, включен ли порт
        local port_state=$(get_port_state $sw_ip $port)
        if [[ -z "$port_state" ]]; then
            result+="${RED}Port state error!${NO_COLOR}"
        # get возвращает *abled, а для set нужно *able
        elif [[ "$port_state" == "${state}d" ]]; then
            result+="${YELLOW}Warning, port already ${port_state}!${NO_COLOR}"
        else
            if (set_port_state "$sw_ip" "$port" "$state" "$comment" \
                && backup $sw_ip \
                && git -C $git_dir add $sw_ip.cfg \
                && git -C $git_dir commit -m "$contract ${pre}block" \
                && save $sw_ip \
                )>$logfile
            then
                result+="${GREEN}Successfully ${pre}blocked${NO_COLOR}"
                rm $logfile
            else
                result+="${RED}Something went wrong! Saved log: ${YELLOW}${logfile}${NO_COLOR}"
            fi
        fi
        result+="\n       ${CYAN}${sw_ip} port ${port}${NO_COLOR}"
    fi
    echo -e "$result"
}

# блокировка абонента на порту
function block {
    change_port "disable" $@
}
# разблокировка абонента на порту
function unblock {
    change_port "enable" $@
}

################################################################################

# проверяем минимальное количество обязательных параметров
if [[ $# < 2 || ($1 == "batch" && $# < 3) ]]; then
    echo -e "${RED}Not enough required parameters${NO_COLOR}\n"
    print_usage
    exit
fi

funcs=(block unblock terminate)

if in_list $2 "${funcs[@]}"; then
    func=$2
else
    echo -e "${RED}Wrong function$NO_COLOR\n"
    exit
fi

params=""
if [[ $1 =~ ^[0-9]{5}$ ]]; then
    contract=$1
    shift 2; params=$@;
    get $contract
    echo -e "You are going to ${YELLOW}${func}${NO_COLOR} this client"
    if agree; then
        eval $func $contract $params
    fi
elif [[ $1 == "batch" ]]; then
    batch_file=$3
    shift 3; params=$@;
    if ! [[ -f $batch_file ]]; then
        echo -e "${RED}Batch file ${CYAN}${batch_file}${RED} not found${NO_COLOR}\n"
        exit
    fi
    declare -a contracts
    declare -i skipped=0
    declare -i found=0
    while read line; do
        l+=1
        if [[ $line =~ ^[0-9]{5}$ ]]; then
            contracts+=($line)
            found+=1
        else
            skipped+=1
        fi        
    done <$batch_file
    if [[ $found > 0 ]]; then
        result="${GREEN}OK${NO_COLOR}"
    else
        result="${RED}FAIL${NO_COLOR}"
    fi
    echo -e "Checking batch file: $result (found: $found skipped: $skipped)"
    if [[ $found > 0 ]]; then
        echo -e "Contracts to ${YELLOW}${func}${NO_COLOR}:\n${CYAN}${contracts[@]}${NO_COLOR}"
        if agree; then
            for c in "${contracts[@]}"; do
                eval $func $c $params
            done
        fi
    else
        echo -e "${RED}No contracts found in batch file ${CYAN}${batch_file}${NO_COLOR}"
        exit
    fi
else
    echo -e "${RED}Wrong first parameter$NO_COLOR Expected 'batch' or contract_id \n"
    print_usage
    exit
fi
