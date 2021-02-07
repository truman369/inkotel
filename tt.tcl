#!/usr/bin/expect

# TCL скрипт для ускоренного подключения к коммутаторам через telnet
# для удобства на скрипт делается символическая ссылка в /usr/local/bin/tt
# пример использования: tt 59.75 - подключиться к 192.168.59.75
# можно использовать как полный, так и укороченный ip
# еще вторым параметром можно передать список команд для выполнения
# сделал для повторного использования другими скриптами

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
# через стороннюю утилиту xdtool задаем профиль эмулятора терминала
# горячие клавиши alt+n - меню терминал, g - изменить профиль,
# 1 - пункт для коммутаторов уровня доступа, 2 - для узловых
# у меня профили отличаются цветом текста в консоли, узловые ярче
# сделал для привлечения внимания, когда заходишь на узел

expect {
    # узловые коммутаторы
    -re "DGS-3627G|DXS-3600-32S|DXS-1210-12SC" {
        set username [lindex $login_data_node 0]
        set password [lindex $login_data_node 1]
        exec xdotool key alt+n g 2
    }
    # коммутаторы уровня доступа
    ":" {
        set username [lindex $login_data_access 0]
        set password [lindex $login_data_access 1]
        exec xdotool key alt+n g 1
    }
    # коммутатор не доступен
    timeout {
        send_error ">>> timed out while connecting\n"
        exit 1
    }
}

# логинимся
send "$username\r"
expect "*ord:"
send "$password\r"

# если приветствие с решеткой, то передаем управление пользователю
# если снова предлагают ввести username или login, то пароль не подошел
expect {
    -re "ame:$|in:$" {
        send_error ">>> wrong password\n"
        exit 1
    }
    "*#" {
        # если есть еще параметр, передаем построчно все команды
        if { $argc > 1 } {
        # TODO: обработка многостраничного вывода
            set commands [split [lindex $argv 1] "\n"]
            foreach command $commands {
                send "[string trimleft $command]\r"
                expect "*#"
            }
            send "logout\r"
        } else {
            interact
        }
    }
    timeout {
        send_error ">>> timed out after login attempt\n"
        exit 1
    }
}


