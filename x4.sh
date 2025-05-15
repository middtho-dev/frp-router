#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
UTIL_SCRIPT="$FRP_DIR/frpc_util.sh"
TIME_SYNC_SCRIPT="$FRP_DIR/sync_time.sh"
CRON_FILE="/etc/crontabs/root"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

DEVICE_NAME=""
DEVICE_NUMBER=""

if [[ "$1" == --* ]]; then
    DEVICE_NAME="${1#--}"
fi

if [[ "$2" == --* ]]; then
    DEVICE_NUMBER="${2#--}"
fi

send_telegram() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$text"
}

remove_all() {
    echo -e "${RED}Удаление всех компонентов...${NC}"
    /etc/init.d/frpc stop 2>/dev/null
    /etc/init.d/frpc disable 2>/dev/null
    rm -f "$INIT_SCRIPT"
    rm -rf "$FRP_DIR"
    sed -i "\|$UTIL_SCRIPT|d" "$CRON_FILE"
    sed -i "\|$TIME_SYNC_SCRIPT|d" "$CRON_FILE"
    /etc/init.d/cron restart
    send_telegram "🗑️ FRPC и все скрипты удалены c *$(uname -n)*"
    echo -e "${GREEN}Удаление завершено.${NC}"
    exit 0
}

if [ -z "$DEVICE_NAME" ] || [ -z "$DEVICE_NUMBER" ]; then
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

    read -p "Название устройства (например: Home): " DEVICE_NAME
    read -p "Номер устройства (например: 21): " DEVICE_NUMBER
fi

echo -e "${GREEN}Установка пакетов...${NC}"
opkg update
opkg install curl wget ntpd

echo -e "${GREEN}Подготовка каталога и загрузка frpc...${NC}"
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit
rm -f frpc
curl -L "https://github.com/middtho-dev/frp-router/raw/main/frpc" -o frpc
chmod +x frpc

luci_name="${DEVICE_NAME}_Luci"
ssh_name="${DEVICE_NAME}_SSH"
luci_port="80${DEVICE_NUMBER}"
ssh_port="22${DEVICE_NUMBER}"

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

echo -e "${GREEN}Настройка имени и зоны...${NC}"
uci set system.@system[0].hostname="$DEVICE_NAME"
uci set system.@system[0].timezone='MSK-3'
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
/etc/init.d/system reload

# Скрипт синхронизации времени через 20 сек после загрузки
cat <<'EOF' > "$TIME_SYNC_SCRIPT"
#!/bin/sh
sleep 20
ntpd -q -p pool.ntp.org && echo "1" > /tmp/time_synced.flag || echo "0" > /tmp/time_synced.flag
EOF

chmod +x "$TIME_SYNC_SCRIPT"

# Утилита мониторинга
cat <<'EOF' > "$UTIL_SCRIPT"
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
MSG_ID_FILE="/tmp/frpc_status_msg_id"
HOSTNAME=$(uname -n)

send_or_edit_message() {
    TEXT="$1"
    if [ -f "$MSG_ID_FILE" ]; then
        MSG_ID=$(cat "$MSG_ID_FILE")
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" \
            -d chat_id="$CHAT_ID" \
            -d message_id="$MSG_ID" \
            -d parse_mode=Markdown \
            --data-urlencode "text=$TEXT"
    else
        MSG_ID=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d chat_id="$CHAT_ID" \
            -d parse_mode=Markdown \
            --data-urlencode "text=$TEXT" | grep -o '"message_id":[0-9]*' | cut -d':' -f2)
        echo "$MSG_ID" > "$MSG_ID_FILE"
    fi
}

send_once() {
    TEXT=$(cat)
    MSG_ID=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$TEXT" | grep -o '"message_id":[0-9]*' | cut -d':' -f2)
    echo "$MSG_ID" > "$MSG_ID_FILE"
}

check_frpc() {
    if pidof frpc > /dev/null; then
        echo "✅ *FRPC работает*"
    else
        /etc/init.d/frpc restart
        sleep 2
        if pidof frpc > /dev/null; then
            echo "♻️ *FRPC перезапущен*"
        else
            echo "❌ *FRPC не запущен*"
        fi
    fi
}

get_status() {
    uptime_info=$(uptime | awk -F'up ' '{print $2}' | cut -d',' -f1 | xargs)
    load=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1)
    cores=$(grep -c ^processor /proc/cpuinfo)
    cpu_load=$(awk -v l="$load" -v c="$cores" 'BEGIN { printf "%.0f%%", (l/c)*100 }')
    ram_free=$(free | awk '/Mem:/ {printf "%.0f", $4/1024}')
    ram_total=$(free | awk '/Mem:/ {printf "%.0f", $2/1024}')
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    disk_total=$(df -h / | awk 'NR==2 {print $2}')
    ext_ip=$(wget -qO- https://api.ipify.org)
    local_time=$(date '+%Y-%m-%d %H:%M:%S')
    frpc_status=$(check_frpc)

    if [ -f /tmp/time_synced.flag ] && [ "$(cat /tmp/time_synced.flag)" = "1" ]; then
        time_synced="Да"
    else
        time_synced="Нет"
    fi

    echo "📊 *Система: $HOSTNAME*

📡 IP: $ext_ip
💽 RAM: ${ram_free}Mb / ${ram_total}Mb
📦 Диск: ${disk_free} / ${disk_total}
🕒 Аптайм: $uptime_info
🔥 CPU: $cpu_load
🕰 Время: $local_time
🔄 Синхронизация времени: *$time_synced*

$frpc_status"
}

if [ "$1" = "send_once" ]; then
    send_once
    exit 0
fi

if [ "$1" = "get_status" ]; then
    get_status
    exit 0
fi

if [ "$1" = "loop" ]; then
    sleep 10
    while true; do
        get_status | send_or_edit_message
        sleep $((RANDOM % 5 + 1))
    done
fi
EOF

chmod +x "$UTIL_SCRIPT"

echo -e "${GREEN}Настройка автозапуска...${NC}"
( crontab -l 2>/dev/null | grep -q "$UTIL_SCRIPT loop" ) || ( crontab -l 2>/dev/null; echo "@reboot $UTIL_SCRIPT loop" ) | crontab -
( crontab -l 2>/dev/null | grep -q "$TIME_SYNC_SCRIPT" ) || ( crontab -l 2>/dev/null; echo "@reboot $TIME_SYNC_SCRIPT" ) | crontab -
/etc/init.d/cron restart

EXT_IP=$(wget -qO- https://api.ipify.org)
INIT_MSG="✅ FRPC установлен на *$DEVICE_NAME*

🔹 *Luci:* http://router.kv9.ru:$luci_port
🔹 *SSH:* http://router.kv9.ru:$ssh_port
📡 *Внешний IP*: $EXT_IP"

send_telegram "$INIT_MSG"

# Первая отправка статуса и сохранение message_id
echo -e "${GREEN}Отправка первого статус-сообщения...${NC}"
get_status_cmd="$UTIL_SCRIPT get_status"
send_msg_cmd="$UTIL_SCRIPT send_once"
sh -c "$get_status_cmd | $send_msg_cmd"

# Стартуем фоновый статус-луп сразу
"$UTIL_SCRIPT" loop &

echo -e "${GREEN}Установка завершена.${NC}"
