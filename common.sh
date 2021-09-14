#!/usr/bin/env bash

git_dir=$basedir/config/backup/

# константы для цветов
NO_COLOR="\e[39m"
GRAY="\e[90m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"

# преобразование сокращенного ip адреса в полный
function full_ip {
    local ip=$1
    local rx='([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
    local prefix='(/[0-9]{1,2})?'
    local result
    if [[ $ip =~ ^$rx\.$rx$prefix$ ]]; then
        result="192.168.$ip"
    elif [[ $ip =~ ^$rx\.$rx\.$rx\.$rx$prefix$ ]]; then
        result="$ip"
    else
        result=""
    fi
    echo "$result"
}

# проверка, что значение содержится в списке
function in_list {
    local value=$1; shift; local list=$@
    [[ $list =~ (^|[[:space:]])$value($|[[:space:]]) ]] && return 0 || return 1
}

# функция для подтверждения каких либо действий
function agree(){
    local agree
    echo -e "Press ${YELLOW}[y]${NO_COLOR} to continue, any key to exit"
    read -s -n 1 agree
    if [[ $agree == "y" ]]; then
        echo -e "${GREEN}Confirmed${NO_COLOR}"
        return 0
    else
        echo -e "${RED}Interrupted${NO_COLOR}"
        exit 0
    fi
}

# функция для перечисления списков портов с сокращениями, например 1-2,5,7-10
function iterate {
    local result=""
    IFS=','
    for l in $1; do
        # return default IFS value
        IFS=$' \t\n'
        local start=$(cut -d '-' -s -f 1 <<< $l)
        local end=$(cut -d '-' -s -f 2 <<< $l)
        if [[ $start ]]; then
            for i in $(seq $start $end); do
                result+="$i "
            done
        else
            result+="$l "
        fi
    done
    IFS=$' \t\n'
    echo $result
}