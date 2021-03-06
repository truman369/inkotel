#!/usr/bin/expect
# TCL скрипт для ускоренного подключения к коммутаторам через telnet
# для удобства на скрипт делается символическая ссылка в /usr/local/bin/tt
# пример использования: tt 59.75 - подключиться к 192.168.59.75
# можно использовать как полный, так и укороченный ip
# еще вторым параметром можно передать список команд для выполнения
# сделал для повторного использования другими скриптами
# в этом случае скрипт возвращает полученные данные

# TODO:
# обработка ошибок (например, отсутствие конфигурационных файлов)

# проверяем текущий файл: запущен он напрямую, или это ссылка
# и выставляем соответствующие абсолютные пути для остальных файлов
if { [file type $argv0] == "file" } {
    set basedir [file dirname [file normalize $argv0]]
} elseif { [file type $argv0] == "link" } {
    set basedir [file dirname [file readlink $argv0]]
}

# считываем пароли из файлов для коммутаторов узловых и уровня доступа
# логин и пароль обычным текстом в две строки или одну через пробел
# дополнительных проверок содержимого файла не делаем, не стал усложнять
# при желании можно оптимизировать до нескольких паролей в одном файле

set fp [open "$basedir/config/node_sw.secret" r]
set login_data_node [read $fp]
close $fp

set fp [open "$basedir/config/access_sw.secret" r]
set login_data_access [read $fp]
close $fp

# при запуске без параметров завершаем с ошибкой
if { $argc == 0 } {
    send_error ">>> no parameters\n"
    exit 1
}

# переменная для вывода
set output ""

#отключаем стандартный вывод
log_user 0

# параметры: -d - режим отладки, -v - включаем стандартный вывод
# удаляем последний аргумент и уменьшаем переменную с числом аргументов
set last_arg [lindex $argv end]
if { [regexp {\-} $last_arg] } {
    set argv [lreplace $argv end end]
    incr argc -1
    if { [regexp {d} $last_arg] } {
        exp_internal 1
    }
    if { [regexp {v} $last_arg] } {
        log_user 1
    }
}

# константы для цветов
set no_color "\033\[0m"
set red "\033\[31m"
set boldred "\033\[1;31m"
set green "\033\[32m"
set boldgreen "\033\[1;32m"
set yellow "\033\[33m"
set boldyellow "\033\[1;33m"
set blue "\033\[34m"
set boldblue "\033\[1;34m"
set cyan "\033\[36m"
set boldcyan "\033\[1;36m"
set color $no_color

# параметром передается ip адрес
set ip [lindex $argv 0]

# добавляем проверку на короткий адрес, добавляем приставку
if {[regexp {^(\d+)\.(\d+)$} $ip match]} {
    set pre "192.168."
} else {
    set pre ""
}

# задаем текущую дату и пишем лог в журнал
set d [exec date +%T]
exec echo $d Подключение к $ip >> /home/troitskiy/j_log

# запускаем telnet сессию
spawn telnet $pre$ip

# определяем модель коммутатора по приветствию
expect {
    "DXS-1210-12SC Switch" {
        set model "DXS-1210-12SC A1"
    }
    -re "\[A-Z]{3}-\[0-9]{4}\[^ ]*" {
        set model "$expect_out(0,string)"
    }
    # у qtech нет названия модели, сразу логин
    "in:$" {
        set model "QSW-2800-28T-AC"
    }
    # коммутатор не доступен
    timeout {
        send_error ">>> timed out while connecting\n"
        exit 1
    }
} 

# задаем пароли в зависимости от модели
switch -regexp -- $model {
    {DGS-3627G|DXS-3600-32S|DXS-1210-12SC} {
        set username [lindex $login_data_node 0]
        set password [lindex $login_data_node 1]
    }
    default {
        set username [lindex $login_data_access 0]
        set password [lindex $login_data_access 1]
    }
}

# цвета в строке приветствия, чтобы отличать важность коммутатора
switch -regexp -- $model {
    {3600} { set color $boldred }
    {3627G} { set color $boldyellow }
    {3120} { set color $boldgreen }
    {1210-12SC} { set color $boldblue }
    default { set color $green }
}

# задаем конец строки по модели
switch -regexp -- $model {
    {3627G|3600|3000|3200|3028|3026|3120} {
        set endline "\n\r"
    }
    {1210|QSW} {
        set endline "\r\n"
    }
    {3526} {
        set endline "\r\n\r"
    }
}

# строка приветствия
if {$model == "DXS-1210-12SC A1"} {
    set prompt "*>"
} else {
    set prompt "*#"
}

# логинимся
send "$username\r"
expect "ord:"
send "$password\r"

# если приветствие с решеткой, то передаем управление пользователю
# если снова предлагают ввести username или login, то пароль не подошел
expect {
    -re "ame:$|in:$" {
        send_error ">>> wrong password\n"
        exit 1
    }
    "$prompt" {
        # если есть еще параметр, передаем построчно все команды
        if { $argc > 1 } {
            set commands [split [lindex $argv 1] ";"]
            foreach command $commands {
                # убираем пробелы и табуляции в начале команды
                set command [string trimleft $command]
                send "$command\r"
                expect {
                    # если перешли в конфигурационный режим
                    # ничего не делаем, ждем следующую команду
                    "*)#" {
                        expect "*"
                    }
                    # ввод команды. $endline в конце работает не везде
                    # на 3600, например, идет комбинация, поэтому так
                    -re "$command\(\r)*(\n)*(\r)*" {
                        # добавляем каждую строку вывода в output
                        expect {
                            "*$endline" {
                                append output "$expect_out(buffer)"
                                exp_continue
                            }
                            # многостраничный вывод
                            "All" {
                                send "a"
                                exp_continue
                            }
                            # без -ex ругается на неправильный флаг
                            # т.к. -- используется для передачи параметров
                            -ex "--More--" {
                                send -- " "
                                exp_continue
                            }
                            # просмотр состояния
                            "Refresh" {
                                send "q"
                                exp_continue
                            }
                            # подтверждение сохранения
                            -nocase "y/n]:" {
                                send "y\r"
                                exp_continue
                            }
                            # подтверждение загрузки по tftp на DXS
                            "]?" {
                                send "\r"
                                exp_continue
                            }
                            "$prompt" {}
                        }
                    }
                }
            }
            send "logout\r"
        # если параметров нет, выводим приветствие и передаем управление пользователю
        } else {
            set location [exec $basedir/sw.sh $ip get_sw_location]
            send_user "$yellow$model$no_color \[$cyan$ip$no_color\] $color$location$no_color$endline"
            interact
        }
    }
    timeout {
        send_error ">>> timed out after login attempt\n"
        exit 1
    }
}
# вывод ответа команд
send_user $output
