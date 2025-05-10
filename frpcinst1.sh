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

prompt_action() {
    echo -e "${GREEN}Выберите действие:${NC}"
    echo "1. Установить frpc"
    echo "2. Удалить frpc и все связанные скрипты"
    read -p "Введите 1 или 2: " choice
    case "$choice" in
        1) install_frpc ;;
        2) remove_frpc ;;
        *) echo "Неверный выбор."; exit 1 ;;
    esac
}

install_frpc() {
    echo -e "${GREEN}Проверяю curl и wget...${NC}"
    opkg update
    opkg install curl wget

    echo -e "${GREEN}Подготовка каталога и загрузка frpc...${NC}"
    mkdir -p "$FRP_DIR"
    cd "$FRP_DIR" || exit

    if [ -f "$FRP_DIR/frpc" ]; then
        echo -e "${RED}Удаляю старый frpc...${NC}"
        rm -f "$FRP_DIR/frpc"
    fi

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

    echo -e "${GREEN}Создание init.d скрипта...${NC}"
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
EOF

    chmod +x "$INIT_SCRIPT"
    /etc/init.d/frpc enable
    /etc/init.d/frpc start

    echo -e "${GREEN}Создание watchdog...${NC}"
    cat <<'EOF' > "$WATCHDOG_SCRIPT"
#!/bin/sh

FRPC_BIN="/root/frp/frpc"
BOT_TOKEN="'"$BOT_TOKEN"'"
CHAT_ID="'"$CHAT_ID"'"
HOSTNAME="$(uname -n)"

uptime_fmt() {
    UPTIME=$(awk '{print int($1)}' /proc/uptime)
    days=$((UPTIME / 86400))
    hours=$(( (UPTIME % 86400) / 3600 ))
    mins=$(( (UPTIME % 3600) / 60 ))
    echo "${days}д ${hours}ч ${mins}м"
}

get_stats() {
    MEM_FREE=$(awk '/MemFree/ {print int($2/1024)}' /proc/meminfo)
    MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    CPU_LOAD=$(awk '{printf "%.2f", $1}' /proc/loadavg)
    EXT_IP=$(wget -qO- https://api.ipify.org)
    echo "🕒 Аптайм: $(uptime_fmt)\n🌐 IP: $EXT_IP\n💽 RAM: ${MEM_FREE}M / ${MEM_TOTAL}M\n📦 Диск: $DISK_FREE\n🔥 CPU: ${CPU_LOAD}"
}

if ! pgrep -f "$FRPC_BIN" > /dev/null; then
    MSG="⚠️ $HOSTNAME: FRPC не работает, пытаюсь перезапустить..."
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    /etc/init.d/frpc restart
    sleep 5
    if pgrep -f "$FRPC_BIN" > /dev/null; then
        MSG="✅ $HOSTNAME: FRPC успешно перезапущен!\n$(get_stats)"
    else
        MSG="❌ $HOSTNAME: Не удалось перезапустить FRPC."
    fi
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
fi
EOF

    chmod +x "$WATCHDOG_SCRIPT"

    echo -e "${GREEN}Создание скрипта статуса...${NC}"
    cat <<'EOF' > "$STATUS_SCRIPT"
#!/bin/sh

BOT_TOKEN="'"$BOT_TOKEN"'"
CHAT_ID="'"$CHAT_ID"'"
HOSTNAME="$(uname -n)"

uptime_fmt() {
    UPTIME=$(awk '{print int($1)}' /proc/uptime)
    days=$((UPTIME / 86400))
    hours=$(( (UPTIME % 86400) / 3600 ))
    mins=$(( (UPTIME % 3600) / 60 ))
    echo "${days}д ${hours}ч ${mins}м"
}

MEM_FREE=$(awk '/MemFree/ {print int($2/1024)}' /proc/meminfo)
MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
CPU_LOAD=$(awk '{printf "%.2f", $1}' /proc/loadavg)
EXT_IP=$(wget -qO- https://api.ipify.org)

MSG="📊 FRPC статус на $HOSTNAME\n🕒 Аптайм: $(uptime_fmt)\n🌐 Внешний IP: $EXT_IP\n💽 RAM: ${MEM_FREE}M / ${MEM_TOTAL}M\n📦 Диск: $DISK_FREE\n🔥 CPU: $CPU_LOAD"

wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
EOF

    chmod +x "$STATUS_SCRIPT"

    echo -e "${GREEN}Настройка cron...${NC}"
    sed -i "\|$WATCHDOG_SCRIPT|d" "$CRON_FILE"
    sed -i "\|$STATUS_SCRIPT|d" "$CRON_FILE"
    echo "*/1 * * * * $WATCHDOG_SCRIPT" >> "$CRON_FILE"
    echo "0 * * * * $STATUS_SCRIPT" >> "$CRON_FILE"
    /etc/init.d/cron restart

    MSG="✅ FRPC установлен на $HOSTNAME\n🔹 Luci: $luci_name → :$luci_port\n🔹 SSH:  $ssh_name → :$ssh_port"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    echo -e "${GREEN}Установка завершена.${NC}"
}

remove_frpc() {
    echo -e "${RED}Удаление всех компонентов frpc...${NC}"
    rm -rf "$FRP_DIR"
    rm -f "$INIT_SCRIPT" "$WATCHDOG_SCRIPT" "$STATUS_SCRIPT"
    sed -i "\|$WATCHDOG_SCRIPT|d" "$CRON_FILE"
    sed -i "\|$STATUS_SCRIPT|d" "$CRON_FILE"
    /etc/init.d/cron restart

    MSG="🗑️ frpc и все связанные скрипты удалены с $HOSTNAME"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    echo -e "${GREEN}Удаление завершено.${NC}"
}

prompt_action
