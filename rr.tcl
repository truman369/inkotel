#!/usr/bin/expect

# TCL скрипт для проверки либо смены маршрутов на районных коммутаторах l3
# для удобства на скрипт делается символическая ссылка в /usr/local/bin/rr
# пример: rr 47.53 37 - перевести 192.168.47.53 на 62.182.48.37
# без параметров просто выводим список текущих маршрутов

# проверяем текущий файл: запущен он напрямую, или это ссылка
# и выставляем соответствующие абсолютные пути для остальных файлов
if { [file type $argv0] == "file" } {
    set basedir [file dirname [file normalize $argv0]]
} elseif { [file type $argv0] == "link" } {
    set basedir [file dirname [file readlink $argv0]]
}

#отключаем стандартный вывод
log_user 0

# проверяем количество и валидность параметров
if { $argc == 0 } {
    # запускаем скрипт вывода всех маршрутов
    puts [exec $basedir/show_iproute_l3.sh]
    exit
} elseif { $argc == 2 } {
    # если параметра два, то задаем переменные
    set ip [lindex $argv 0]
    set ro [lindex $argv 1]
    # считываем ip адреса из файла, пропуская пустые строки и комментарии
    # и проверяем, входит ли в данный список наш айпи
    if { [lsearch [exec egrep -v "^$|^#" "$basedir/config/ip/l3.ip"] 192.168.$ip] == -1 } {
        send_error ">>> wrong ip\n"
        exit 1
    }
    # проверяем валидность маршрута, их всего четыре, все просто
    if { $ro < 35 || $ro > 38 } {
        send_error ">>> wrong route\n"
        exit 1
    }
} else {
    send_error ">>> wrong parameters count\n"
    exit 1
}

# открываем для чтения файл с логином и паролем для узловых коммутаторов
# в файле должен быть один логин и один пароль в две строки или одну через пробел
# дополнительных проверок содержимого файла не делаем, не стал усложнять
set fp [open "$basedir/config/node_sw.secret" r]
set login_data [read $fp]
close $fp
set username [lindex $login_data 0]
set password [lindex $login_data 1]


# устанавливаем telnet сессию с коммутатором
spawn telnet 192.168.$ip

# проверка на модель, маршруты меняем только на 3627G
expect {
    # если приглашение содержит модель DGS-3627G, логинимся
    -re "DGS-3627G" {    
        send "$username\r"
        expect "*ord:"
        send "$password\r"
    }
    # все остальное
    ":" {
        send_error ">>> wrong switch type\n"
        exit 1
    }
    # коммутатор не доступен
    timeout {
        send_error ">>> timed out while connecting\n"
        exit 1
    }
}

expect {
    # если пароль не угадали
    -re "\[F|f]ail" {
        send_error ">>> wrong password\n"
        exit 1
    }
    # если все норм
    "*#" {
        # удаляем все старые маршруты, если они есть
        send "delete iproute default 62.182.48.35\r" 
        send "delete iproute default 62.182.48.36\r"
        send "delete iproute default 62.182.48.37\r"
        send "delete iproute default 62.182.48.38\r"
        # добавляем маршрут по умолчанию
        send "create iproute default 62.182.48.$ro 1 primary\r"
        # по завершению сохраняемся и выходим
        expect "*#"
        send "save\n logout\r"
    }
    # что-то пошло не так
    timeout {
        send_error ">>> timed out after login attempt\n"
        exit 1
    }
}
# отображаем обновленный список маршрутов
send_user [exec $basedir/show_iproute_l3.sh]
