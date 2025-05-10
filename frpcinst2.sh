#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Константы
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
STATUS_SCRIPT="/root/frpc_status.sh"
CRON_FILE="/etc/crontabs/root"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
HOSTNAME=$(uname -n)

ask_action() {
    echo -e "${GREEN}Выберите действие:${NC}"
    select choice in "Установить FRPC" "Удалить FRPC"; do
        case $REPLY in
            1) install_frpc; break ;;
            2) remove_frpc; break ;;
            *) echo "Неверный выбор" ;;
        esac
    done
}

install_frpc() {
    echo -e "${GREEN}Проверяю curl и wget...${NC}"
    opkg update
    opkg install curl wget

    echo -e "${GREEN}Подготовка каталога и загрузка frpc...${NC}"
    mkdir -p "$FRP_DIR"
    cd "$FRP_DIR" || exit

    [ -f "$FRP_DIR/frpc" ] && rm -f "$FRP_DIR/frpc"

    curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "frpc"
    chmod +x frpc

    echo -e "${GREEN}frpc скачан.${NC}"

    echo -e "${GREEN}Настройка frpc.toml...${NC}"
    read -p "Имя прокси Luci (например: Home_Luci): " luci_name
    read -p "Удалённый порт Luci (например: 8081): " luci_port
    read -p "Имя прокси SSH (например: Home_SSH): " ssh_name
    read -p "Удалённый порт SSH (например: 2201): " ssh_port

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

    echo -e "${GREEN}frpc.toml создан.${NC}"

    # init.d
    echo -e "${GREEN}Создание /etc/init.d/frpc...${NC}"
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

    # watchdog
    echo -e "${GREEN}Создание watchdog скрипта...${NC}"
    cat <<EOF > "$WATCHDOG_SCRIPT"
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
HOSTNAME=$(uname -n)

EXT_IP=\$(wget -qO- https://api.ipify.org)
RAM_FREE=\$(awk '/MemFree/ {printf "%.0f", \$2/1024}' /proc/meminfo)
RAM_TOTAL=\$(awk '/MemTotal/ {printf "%.0f", \$2/1024}' /proc/meminfo)
DISK_FREE=\$(df -h / | awk 'NR==2 {print \$4}')
CPU_LOAD=\$(awk '{print \$1}' /proc/loadavg)
UPTIME_SEC=\$(awk '{print int(\$1)}' /proc/uptime)
DAYS=\$((UPTIME_SEC / 86400))
HOURS=\$(( (UPTIME_SEC % 86400) / 3600 ))
MINS=\$(( (UPTIME_SEC % 3600) / 60))
UPTIME="\${DAYS}д \${HOURS}ч \${MINS}м"

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MESSAGE="⚠️ \$HOSTNAME\nFRPC не работает, пытаюсь перезапустить..."
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
    /etc/init.d/frpc restart
    sleep 5
    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MESSAGE="✅ \$HOSTNAME\nFRPC успешно перезапущен!\nСостояние системы:\n📡 IP: \$EXT_IP\n💽 RAM: \${RAM_FREE}M/\${RAM_TOTAL}M\n📦 Диск: \$DISK_FREE\n🔥 CPU: \$CPU_LOAD\n🕒 Аптайм: \$UPTIME"
    else
        MESSAGE="❌ \$HOSTNAME\nНе удалось перезапустить FRPC"
    fi
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
fi
EOF

    chmod +x "$WATCHDOG_SCRIPT"

    # status reporter
    echo -e "${GREEN}Создание status скрипта...${NC}"
    cat <<EOF > "$STATUS_SCRIPT"
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
HOSTNAME=$(uname -n)

EXT_IP=\$(wget -qO- https://api.ipify.org)
RAM_FREE=\$(awk '/MemFree/ {printf "%.0f", \$2/1024}' /proc/meminfo)
RAM_TOTAL=\$(awk '/MemTotal/ {printf "%.0f", \$2/1024}' /proc/meminfo)
DISK_FREE=\$(df -h / | awk 'NR==2 {print \$4}')
CPU_LOAD=\$(awk '{print \$1}' /proc/loadavg)
UPTIME_SEC=\$(awk '{print int(\$1)}' /proc/uptime)
DAYS=\$((UPTIME_SEC / 86400))
HOURS=\$(( (UPTIME_SEC % 86400) / 3600 ))
MINS=\$(( (UPTIME_SEC % 3600) / 60))
UPTIME="\${DAYS}д \${HOURS}ч \${MINS}м"

MSG="📊 FRPC статус: \$HOSTNAME
📡 Внешний IP: \$EXT_IP
💽 RAM: \${RAM_FREE}M/\${RAM_TOTAL}M
📦 Диск: \$DISK_FREE
🔥 CPU: \$CPU_LOAD
🕒 Аптайм: \$UPTIME"

wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
EOF

    chmod +x "$STATUS_SCRIPT"

    # Cron
    echo -e "${GREEN}Настройка cron...${NC}"
    sed -i "\|$WATCHDOG_SCRIPT|d" "$CRON_FILE"
    sed -i "\|$STATUS_SCRIPT|d" "$CRON_FILE"
    echo "*/1 * * * * $WATCHDOG_SCRIPT" >> "$CRON_FILE"
    echo "0 * * * * $STATUS_SCRIPT" >> "$CRON_FILE"
    /etc/init.d/cron restart

    # Уведомление об установке
    EXT_IP=$(wget -qO- https://api.ipify.org)
    RAM_FREE=$(awk '/MemFree/ {printf "%.0f", $2/1024}' /proc/meminfo)
    RAM_TOTAL=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
    UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
    DAYS=$((UPTIME_SEC / 86400))
    HOURS=$(( (UPTIME_SEC % 86400) / 3600 ))
    MINS=$(( (UPTIME_SEC % 3600) / 60))
    UPTIME="${DAYS}д ${HOURS}ч ${MINS}м"

    MESSAGE="✅ FRPC установлен на $HOSTNAME
🔹 Luci: $luci_name → :$luci_port
🔹 SSH:  $ssh_name → :$ssh_port

📡 Внешний IP: $EXT_IP
📦 Диск: $DISK_FREE
💽 RAM: ${RAM_FREE}M/${RAM_TOTAL}M
🔥 CPU: $CPU_LOAD
🕒 Аптайм: $UPTIME"

    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

    echo -e "${GREEN}Установка завершена.${NC}"
}

remove_frpc() {
    echo -e "${RED}Удаляю все компоненты frpc...${NC}"
    rm -rf "$FRP_DIR"
    rm -f "$INIT_SCRIPT"
    rm -f "$WATCHDOG_SCRIPT"
    rm -f "$STATUS_SCRIPT"
    sed -i "\|frpc_watchdog.sh|d" "$CRON_FILE"
    sed -i "\|frpc_status.sh|d" "$CRON_FILE"
    /etc/init.d/cron restart

    MESSAGE="🗑️ FRPC и все связанные скрипты удалены с устройства $HOSTNAME"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

    echo -e "${GREEN}Удаление завершено.${NC}"
}

ask_action
