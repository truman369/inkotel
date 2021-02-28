#!/usr/bin/expect
# TCL скрипт для ускоренного подключения к коммутаторам через telnet
# для удобства на скрипт делается символическая ссылка в /usr/local/bin/tt
# пример использования: tt 59.75 - подключиться к 192.168.59.75
# можно использовать как полный, так и укороченный ip
# еще вторым параметром можно передать список команд для выполнения
# сделал для повторного использования другими скриптами
# в этом случае скрипт возвращает полученные данные

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

# для отладки
# exp_internal 1

# константы для цветов
set no_color "\033\[0m"
set red "\033\[1;31m"
set green "\033\[1;32m"
set yellow "\033\[1;33m"
set blue "\033\[1;36m"
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

# определяем тип коммутатора (узловой или доступа) по названию модели
# устанавливаем цвет текста приветствия в зависимости от типа
set is_qtech false

# TODO оптимизировать блок распознавания модели

set prompt "*#"

expect {
    # костыль 1210
    -re "DXS-1210-12SC login:" {
        set username [lindex $login_data_node 0]
        set password [lindex $login_data_node 1]
        set color $yellow
        set prompt "*>"
    }
    # узловые коммутаторы
    -re "DGS-3627G|DXS-3600-32S|DXS-1210-12SC 10GbE" {
        set username [lindex $login_data_node 0]
        set password [lindex $login_data_node 1]
        set color $red
    }
    # коммутаторы уровня доступа qtech
    "in:$" {
        set is_qtech true
        set username [lindex $login_data_access 0]
        set password [lindex $login_data_access 1]
        set color $blue

    }
    # коммутаторы уровня доступа dlink
    -re "ame: *$" {
        set username [lindex $login_data_access 0]
        set password [lindex $login_data_access 1]
        set color $green
    }
    # коммутатор не доступен
    timeout {
        send_error ">>> timed out while connecting\n"
        exit 1
    }
}

# логинимся
send "$username\r"
# заодно смотрим, какое окончание строки на этой модели коммутатора
expect {
    -re "\n\r(.*)ord:" {
        set endline "\n\r"
    }
    -re "\r\n(.*)ord:" {
        set endline "\r\n"
    }
}
send "$password\r"

# костыль 1210
if { $prompt == "*>"} {
    set endline "\r\n"
}

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
                set command [string trimleft $command]
                send "$command\r"
                if {$is_qtech == true} {
                    expect {
                        # находимся в конфигурационном режиме
                        "*)#" {
                            expect "*"
                        }
                        # ввод команды
                        "$command$endline" {
                            expect {
                                # добавляем каждую строку вывода в output
                                "*$endline" {
                                    append output "$expect_out(buffer)"
                                    exp_continue
                                }
                                # если многостраничный вывод
                                -ex "--More--" {
                                    send -- " "
                                    exp_continue
                                }
                                # пока не встретим решетку
                                "$prompt" {}
                            }
                        }
                    }
                } else {
                    # D-LINK
                    # пропускаем две строки: первая - сама команда
                    # вторая - подтверждение команды на коммутаторе
                    # с концом строки не очень ясно на разных моделях
                    expect -re "$command\(\r)?$endline"
                    expect -re "(\r)?($endline)+"
                    # оставшееся записываем в вывод построчно до решетки
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
                        # просмотр состояния
                        "Refresh" {
                            send "q"
                            exp_continue
                        }
                        "$prompt" {}
                    }
                }
            }
            send "logout\r"
        } else {
            set location [exec $basedir/sw.sh $ip get_sw_location]
            send_user "Connected to $color$ip$no_color $location$endline"
            interact
        }
    }
    timeout {
        send_error ">>> timed out after login attempt\n"
        exit 1
    }
}
send_user $output
