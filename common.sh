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
    ip=$1
    rx='([1-9]?[0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
    if [[ $ip =~ ^$rx\.$rx$ ]]; then
        result="192.168.$ip"
    elif [[ $ip =~ ^$rx\.$rx\.$rx\.$rx$ ]]; then
        result="$ip"
    else
        result=""
    fi
    echo "$result"
}

# проверка, что значение содержится в списке
function in_list {
    value=$1; shift; list=$@
    [[ $list =~ (^|[[:space:]])$value($|[[:space:]]) ]] && return 0 || return 1
}

# функция для подтверждения каких либо действий
function agree(){
    local agree
    echo -e "Press ${YELLOW}[y]${NO_COLOR} to continue, any key to exit"
    read -s -n 1 agree
    if [[ $agree == "y" ]]; then
        return 0
    else
        echo -e "Interrupted"
        exit 0
    fi
}