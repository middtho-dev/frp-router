#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
UTIL_SCRIPT="$FRP_DIR/frpc_util.sh"
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
    sed -i "\|$UTIL_SCRIPT check|d" "$CRON_FILE"
    sed -i "\|$UTIL_SCRIPT info|d" "$CRON_FILE"
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
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$1"
}

get_status() {
    uptime_info=$(uptime | cut -d',' -f1)
    cpu_load=$(top -bn1 | grep "load average" | awk '{print $6}')
    ram_free=$(free -m | awk '/Mem:/ {print $4}')
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    ext_ip=$(wget -qO- https://api.ipify.org)
    echo "📊 *Состояние системы:*

📡 *Внешний IP*: $ext_ip
🕒*$uptime_info*
💽 *RAM*: ${ram_free}Kb
📦 *Диск*: $disk_free
🔥 *CPU*: $cpu_load"
}

if [ "$1" = "check" ]; then
    if ! pidof frpc > /dev/null; then
        send_telegram "⚠️ *$DATE_NOW*

FRPC на *$(uname -n)* не работает. 
Перезапуск..."
        /etc/init.d/frpc restart
        sleep 5
        if pidof frpc > /dev/null; then
            send_telegram "✅ FRPC на *$(uname -n)* успешно перезапущен.

$(get_status)"
        else
            send_telegram "❌ Не удалось перезапустить FRPC на *$(uname -n)*!"
        fi
    fi
elif [ "$1" = "info" ]; then
    HOSTNAME=$(uname -n)
    send_telegram "📊 Состояние системы на *$HOSTNAME*

$(get_status)"
fi
EOF

chmod +x "$UTIL_SCRIPT"

echo -e "${GREEN}Настройка cron...${NC}"
( crontab -l 2>/dev/null | grep -q "$UTIL_SCRIPT check" ) || ( crontab -l 2>/dev/null; echo "*/1 * * * * $UTIL_SCRIPT check" ) | crontab -
( crontab -l 2>/dev/null | grep -q "$UTIL_SCRIPT info" ) || ( crontab -l 2>/dev/null; echo "0 * * * * $UTIL_SCRIPT info" ) | crontab -
/etc/init.d/cron restart

EXT_IP=$(wget -qO- https://api.ipify.org)
MESSAGE="✅ FRPC установлен на *$DEVICE_NAME*

🔹 *Luci:* http://router.kv9.ru:$luci_port
🔹 *SSH:* http://router.kv9.ru:$ssh_port
📡 *Внешний IP*: $EXT_IP"

send_telegram "$MESSAGE"
echo -e "${GREEN}Установка завершена.${NC}"
