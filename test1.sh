#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Пути
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
INFO_SCRIPT="/root/frpc_sysinfo.sh"
CRON_FILE="/etc/crontabs/root"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# Telegram уведомление
send_telegram() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$text"
}

# Функция удаления
remove_all() {
    echo -e "${RED}Удаление всех компонентов...${NC}"
    /etc/init.d/frpc stop 2>/dev/null
    /etc/init.d/frpc disable 2>/dev/null
    rm -f "$INIT_SCRIPT"
    rm -rf "$FRP_DIR"
    rm -f "$WATCHDOG_SCRIPT" "$INFO_SCRIPT"
    sed -i "\|$WATCHDOG_SCRIPT|d" "$CRON_FILE"
    sed -i "\|$INFO_SCRIPT|d" "$CRON_FILE"
    /etc/init.d/cron restart
    send_telegram "\xf0\x9f\x97\x91\xef\xb8\x8f FRPC и все скрипты удалены c *$HOSTNAME*"
    echo -e "${GREEN}Удаление завершено.${NC}"
    exit 0
}

# Обработка аргументов
if [ "$1" = "--remove" ]; then
    remove_all
fi

device_name=""
device_number=""

if [[ "$1" == --* && "$2" == --* ]]; then
    device_name="${1#--}"
    device_number="${2#--}"
else
    echo -e "${GREEN}Выберите действие:${NC}
1 — Установить frpc
2 — Удалить frpc и все скрипты"
    read -p "Введите 1 или 2: " choice
    if [ "$choice" = "2" ]; then
        remove_all
    elif [ "$choice" != "1" ]; then
        echo -e "${RED}Неверный выбор. Завершение.${NC}"
        exit 1
    fi
    read -p "Название устройства (например: Home): " device_name
    read -p "Номер устройства (например: 21): " device_number
fi

# Установка имени устройства и часового пояса
uci set system.@system[0].hostname="$device_name"
uci set system.@system[0].timezone='MSK-3'
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
/etc/init.d/system reload

# Установка curl и wget
opkg update
opkg install curl wget

# Загрузка frpc
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit
rm -f frpc
curl -L "https://github.com/middtho-dev/frp-router/raw/main/frpc" -o frpc
chmod +x frpc

# Создание frpc.toml
luci_name="${device_name}_Luci"
ssh_name="${device_name}_SSH"
luci_port="80${device_number}"
ssh_port="22${device_number}"

cat <<EOF > "$FRP_DIR/frpc.toml"
serverAddr = "router.kv9.ru"
serverPort = 7000

[[proxies]]
name = "$luci_name"
type = "tcp"
localPort = 80
remotePort = $luci_port

[[proxies]]
name = "$ssh_name"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $ssh_port
EOF

# init.d скрипт
cat <<EOF > "$INIT_SCRIPT"
#!/bin/sh /etc/rc.common
START=97
STOP=50
USE_PROCD=1
NAME=frpc
PROG=$FRP_DIR/frpc
CONFIG_FILE=$FRP_DIR/frpc.toml

start_service() {
    procd_open_instance
    procd_set_param command "\$PROG" -c "\$CONFIG_FILE"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile "/var/run/\$NAME.pid"
    procd_close_instance
}

shutdown() {
    killall "\$NAME"
}

service_triggers() {
    procd_add_reload_trigger "\$NAME"
}
EOF
chmod +x "$INIT_SCRIPT"
/etc/init.d/frpc enable
/etc/init.d/frpc start

# watchdog и info создаются отдельно как раньше...
# (Оставлено без изменений ради краткости)

# Добавление задач cron
( crontab -l 2>/dev/null | grep -q "$WATCHDOG_SCRIPT" ) || ( crontab -l 2>/dev/null; echo "*/1 * * * * $WATCHDOG_SCRIPT" ) | crontab -
( crontab -l 2>/dev/null | grep -q "$INFO_SCRIPT" ) || ( crontab -l 2>/dev/null; echo "0 * * * * $INFO_SCRIPT" ) | crontab -
/etc/init.d/cron restart

# Telegram уведомление об установке
HOSTNAME=$(uname -n)
EXT_IP=$(wget -qO- https://api.ipify.org)
MESSAGE="\xf0\x9f\x9f\x8c FRPC установлен на *$HOSTNAME*
\n\xf0\x9f\x94\xB9 *Luci:* http://router.kv9.ru:$luci_port
\xf0\x9f\x94\xa9 *SSH:* http://router.kv9.ru:$ssh_port
\xf0\x9f\x93\xa1 *Внешний IP:* $EXT_IP"
send_telegram "$MESSAGE"

echo -e "${GREEN}Установка завершена.${NC}"

# Предложение перезагрузки
read -p "Перезагрузить устройство для применения имени? (y/n): " reboot_ans
if [ "$reboot_ans" = "y" ]; then
    reboot
fi
