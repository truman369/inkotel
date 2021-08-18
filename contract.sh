#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# общие функции и константы
source $basedir/common.sh

# библиотека функций для работы с серой базой
source $basedir/ab_functions.sh

# библиотека функций для работы с коммутаторами
source $basedir/sw_functions.sh

set -euo pipefail
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

function block(){
    echo "block $1 params $2"
}
function unblock(){
    echo "unblock $1 params $2"
}
function terminate(){
    echo "terminate $1 params $2"
}

# проверяем минимальное количество обязательных параметров
if [[ $# < 2 || ($1 == "batch" && $# < 3) ]]; then
    echo -e "${RED}Too few required parameters${NO_COLOR}\n"
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
    eval $func $contract $params
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
        for c in "${contracts[@]}"; do
            eval $func $c $params
        done
    else
        echo -e "${RED}No contracts found in batch file ${CYAN}${batch_file}${NO_COLOR}"
        exit
    fi
else
    echo -e "${RED}Wrong first parameter$NO_COLOR\n"
    print_usage
    exit
fi
