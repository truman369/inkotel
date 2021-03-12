#!/usr/bin/env bash

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
        pre="192.168."
    else
        pre=""
    fi
    echo "$pre$ip"
}