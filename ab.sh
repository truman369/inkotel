#!/usr/bin/env bash

# все файлы ищем относительно директории запуска файла
basedir=$(dirname $(realpath $0))

# общие функции и константы
source $basedir/common.sh

# библиотека функций для работы с серой базой
source $basedir/ab_functions.sh

# если есть параметры, то запускаем сразу нужную функцию и выходим
if [[ "$#" > 0 ]]; then
    $func $@
    exit
fi