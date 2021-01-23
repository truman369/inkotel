#!/usr/bin/env bash
# удаляем из базы данных все события старше 3 дней
echo "delete from SystemEvents where datediff(now(), ReceivedAt) > 3; optimize table SystemEvents;" | mysql -u rsyslog -prsyslog Syslog 1>/dev/null
