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

    wget -qO- --post-data="chat_id=$CHAT_ID&text=🗑️ frpc и все связанные скрипты удалены&parse_mode=Markdown" \
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

    echo -e "${GREEN}Удаление завершено.${NC}"
    exit 0
}

# Меню выбора
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

# ---------------------------
# Дальше идёт установка (как раньше, без изменений)
# ---------------------------

# Установка curl и wget
echo -e "${GREEN}Проверяю curl и wget...${NC}"
opkg update
opkg install curl wget

# Загрузка frpc
echo -e "${GREEN}Подготовка каталога и загрузка frpc...${NC}"
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit

if [ -f "$FRP_DIR/frpc" ]; then
    echo -e "${RED}Удаляю старый frpc...${NC}"
    rm -f "$FRP_DIR/frpc"
fi

curl -L "https://github.com/middtho-dev/frp-router/raw/main/frpc" -o "frpc"
chmod +x frpc
echo -e "${GREEN}frpc скачан.${NC}"

# Получение параметров
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
cat <<'EOF' > "$WATCHDOG_SCRIPT"
#!/bin/sh
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
FRPC_BIN="/root/frp/frpc"
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')

get_status() {
    uptime_info=$(uptime | cut -d',' -f1)
    cpu_load=$(top -bn1 | grep "load average" | awk '{print $12 $13 $14}')
    ram_free=$(free -m | awk '/Mem:/ {print $4}')
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    ext_ip=$(wget -qO- https://api.ipify.org)
    echo "*Состояние системы:*
🕒 $uptime_info
🌐 IP: $ext_ip
💽 RAM: ${ram_free}M
📦 Диск: $disk_free
🔥 CPU: $cpu_load"
}

notify() {
    local text="$1"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$text&parse_mode=Markdown" \
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
}

if ! pgrep -f "$FRPC_BIN" > /dev/null; then
    notify "⚠️ *$DATE_NOW*  
FRPC не работает, пытаюсь перезапустить..."
    /etc/init.d/frpc restart
    sleep 5
    if pgrep -f "$FRPC_BIN" > /dev/null; then
        notify "✅ FRPC успешно перезапущен!\n$(get_status)"
    else
        notify "❌ Не удалось перезапустить FRPC!"
    fi
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"

# info script
echo -e "${GREEN}Создание скрипта состояния...${NC}"
cat <<'EOF' > "$INFO_SCRIPT"
#!/bin/sh
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

get_info() {
    HOSTNAME=$(uname -n)
    uptime_info=$(uptime | cut -d',' -f1)
    cpu_load=$(top -bn1 | grep "load average" | awk '{print $12 $13 $14}')
    ram_free=$(free -m | awk '/Mem:/ {print $4}')
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    ext_ip=$(wget -qO- https://api.ipify.org)

    echo "*FRPC статус на* \`$HOSTNAME\`
🕒 $uptime_info
🌐 Внешний IP: $ext_ip
💽 RAM: ${ram_free}M
📦 Диск: $disk_free
🔥 CPU: $cpu_load"
}

MESSAGE=$(get_info)
wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE&parse_mode=Markdown" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
EOF

chmod +x "$INFO_SCRIPT"

# Cron
echo -e "${GREEN}Настройка cron...${NC}"
grep -q "$WATCHDOG_SCRIPT" "$CRON_FILE" || echo "*/1 * * * * $WATCHDOG_SCRIPT" >> "$CRON_FILE"
grep -q "$INFO_SCRIPT" "$CRON_FILE" || echo "0 * * * * $INFO_SCRIPT" >> "$CRON_FILE"
/etc/init.d/cron restart

# Telegram сообщение об установке
HOSTNAME=$(uname -n)
UPTIME=$(uptime | cut -d',' -f1)
EXT_IP=$(wget -qO- https://api.ipify.org)
DISK=$(df -h / | awk 'NR==2 {print $4}')
RAM=$(free -m | awk '/Mem:/ {print $4}')

MESSAGE="✅ *FRPC установлен на* \`$HOSTNAME\`
🔹 *Luci*: \`$luci_name\` → :$luci_port
🔹 *SSH*:  \`$ssh_name\` → :$ssh_port

📡 *Внешний IP*: $EXT_IP
📦 *Диск*: $DISK
💽 *RAM*: ${RAM}M
🕒 $UPTIME"

wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE&parse_mode=Markdown" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

echo -e "${GREEN}Установка завершена.${NC}"
