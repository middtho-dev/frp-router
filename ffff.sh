#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
UTIL_SCRIPT="$FRP_DIR/frpc_util.sh"
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
        --data-urlencode "text=$text" > /dev/null
}

remove_all() {
    echo -e "${RED}Удаление всех компонентов...${NC}"
    /etc/init.d/frpc stop 2>/dev/null
    /etc/init.d/frpc disable 2>/dev/null
    rm -f "$INIT_SCRIPT"
    rm -rf "$FRP_DIR"
    sed -i "\|$UTIL_SCRIPT|d" /etc/rc.local 2>/dev/null
    send_telegram "🗑️ FRPC и скрипты удалены с *$(uname -n)*"
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

echo -e "${GREEN}Проверка curl и wget...${NC}"
opkg update
opkg install curl wget

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

echo -e "${GREEN}Настройка имени и часового пояса...${NC}"
uci set system.@system[0].hostname="$DEVICE_NAME"
uci set system.@system[0].timezone='MSK-3'
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
/etc/init.d/system reload

cat <<'EOF' > "$UTIL_SCRIPT"
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
MSG_ID_FILE="/root/.status_msg_id"
HOSTNAME="$(uname -n)"

send_telegram() {
    local text="$1"
    local resp=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$text")
    echo "$resp" | grep -o '"message_id":[0-9]*' | cut -d':' -f2
}

edit_telegram() {
    local msg_id="$1"
    local text="$2"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" \
        -d chat_id="$CHAT_ID" \
        -d message_id="$msg_id" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$text" > /dev/null
}

check_frpc() {
    if pidof frpc > /dev/null; then
        echo "✅ FRPC работает"
    else
        /etc/init.d/frpc restart
        sleep 5
        if pidof frpc > /dev/null; then
            echo "✅ FRPC перезапущен"
        else
            echo "❌ FRPC не запустился"
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
    current_time=$(date '+%Y-%m-%d %H:%M:%S')

    frpc_status=$(check_frpc)

    echo "📊 *Система: $HOSTNAME*
$frpc_status"
а
📡 IP: $ext_ip
🕰️ Время: $current_time
💽 RAM: ${ram_free}Mb / ${ram_total}Mb
📦 Диск: ${disk_free} / ${disk_total}
🕒 Аптайм: $uptime_info
🔥 CPU: $cpu_load
}

init_status_message() {
    local msg_id=$(send_telegram "$(get_status)")
    echo "$msg_id" > "$MSG_ID_FILE"
}

start_monitor() {
    local msg_id=""
    [ -f "$MSG_ID_FILE" ] && msg_id=$(cat "$MSG_ID_FILE")

    if [ -z "$msg_id" ]; then
        init_status_message
        msg_id=$(cat "$MSG_ID_FILE")
    fi

    while true; do
        edit_telegram "$msg_id" "$(get_status)"
        sleep $((RANDOM % 5 + 1))
    done
}

if [ "$1" = "init" ]; then
    init_status_message
elif [ "$1" = "info" ]; then
    start_monitor &
fi
EOF

chmod +x "$UTIL_SCRIPT"

# Настраиваем автозапуск мониторинга в rc.local
if ! grep -q "$UTIL_SCRIPT info" /etc/rc.local 2>/dev/null; then
    sed -i "/^exit 0/i $UTIL_SCRIPT info &" /etc/rc.local 2>/dev/null || echo "$UTIL_SCRIPT info &" >> /etc/rc.local
fi

# Стартовый статус и фоновый мониторинг
"$UTIL_SCRIPT" init
"$UTIL_SCRIPT" info &

echo -e "${GREEN}Установка и настройка завершены.${NC}"
