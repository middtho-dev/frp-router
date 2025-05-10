#!/bin/sh

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

echo "${GREEN}Выберите действие:${NC}"
echo "1 - Установить FRPC"
echo "2 - Удалить FRPC"
printf "Ваш выбор (1/2): "
read choice

if [ "$choice" = "2" ]; then
    echo "${RED}Удаление...${NC}"
    rm -rf "$FRP_DIR" "$INIT_SCRIPT" "$WATCHDOG_SCRIPT" "$STATUS_SCRIPT"
    sed -i '\|frpc_watchdog.sh|d' "$CRON_FILE"
    sed -i '\|frpc_status.sh|d' "$CRON_FILE"
    /etc/init.d/cron restart
    /etc/init.d/frpc stop 2>/dev/null
    /etc/init.d/frpc disable 2>/dev/null
    wget -qO- --post-data="chat_id=$CHAT_ID&text=🗑️ frpc и все связанные скрипты удалены с $HOSTNAME" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    echo "${GREEN}Удаление завершено.${NC}"
    exit 0
fi

echo "${GREEN}Установка curl и wget...${NC}"
opkg update
opkg install curl wget

echo "${GREEN}Создание каталога и загрузка frpc...${NC}"
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit

rm -f "$FRP_DIR/frpc"
wget -qO frpc "https://github.com/$GITHUB_REPO/raw/main/frpc"
chmod +x frpc
echo "${GREEN}frpc скачан.${NC}"

echo "${GREEN}Введите параметры прокси:${NC}"
printf "Имя прокси Luci: " ; read luci_name
printf "Удалённый порт Luci: " ; read luci_port
printf "Имя прокси SSH: " ; read ssh_name
printf "Удалённый порт SSH: " ; read ssh_port

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

echo "${GREEN}Создание init.d службы...${NC}"
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

echo "${GREEN}Создание watchdog скрипта...${NC}"
cat <<EOF > "$WATCHDOG_SCRIPT"
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
HOSTNAME="$(uname -n)"

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MSG="⚠️ FRPC не работает на \$HOSTNAME, пытаюсь перезапустить..."
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
    /etc/init.d/frpc restart
    sleep 3
    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        CPU=\$(top -bn1 | grep -m1 CPU | awk '{print \$8}')
        RAM=\$(free | grep Mem | awk '{printf("%.1fMB", \$4/1024)}')
        DISK=\$(df -h / | awk 'NR==2 {print \$4}')
        UPTIME=\$(uptime | sed 's/.*up \([^,]*\),.*/\1/')
        IP=\$(wget -qO- ifconfig.me)
        MSG="✅ FRPC успешно перезапущен на \$HOSTNAME\n🕒 Uptime: \$UPTIME\n🌐 IP: \$IP\n💽 RAM: \$RAM\n📦 Диск: \$DISK\n🔥 CPU: \$CPU%"
        wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
    else
        MSG="❌ FRPC не удалось перезапустить на \$HOSTNAME"
        wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
    fi
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"

echo "${GREEN}Создание скрипта отправки статуса...${NC}"
cat <<EOF > "$STATUS_SCRIPT"
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
HOSTNAME="$(uname -n)"
IP=\$(wget -qO- ifconfig.me)
DISK=\$(df -h / | awk 'NR==2 {print \$4}')
RAM=\$(free | grep Mem | awk '{printf("%.1fMB", \$4/1024)}')
CPU=\$(top -bn1 | grep -m1 CPU | awk '{print \$8}')
UPTIME=\$(uptime | sed 's/.*up \([^,]*\),.*/\1/')

MSG="📡 FRPC статус на \$HOSTNAME\n🕒 Uptime: \$UPTIME\n🌐 IP: \$IP\n💽 RAM: \$RAM\n📦 Диск: \$DISK\n🔥 CPU: \$CPU%"
wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
EOF

chmod +x "$STATUS_SCRIPT"

echo "${GREEN}Настройка cron...${NC}"
sed -i '\|frpc_watchdog.sh|d' "$CRON_FILE"
sed -i '\|frpc_status.sh|d' "$CRON_FILE"
echo "*/1 * * * * $WATCHDOG_SCRIPT" >> "$CRON_FILE"
echo "0 * * * * $STATUS_SCRIPT" >> "$CRON_FILE"
/etc/init.d/cron restart

echo "${GREEN}Отправка Telegram уведомления...${NC}"
IP=$(wget -qO- ifconfig.me)
DISK=$(df -h / | awk 'NR==2 {print $4}')
RAM=$(free | grep Mem | awk '{printf("%.1fMB", $4/1024)}')
MSG="✅ FRPC установлен на $HOSTNAME\n🔹 Luci: $luci_name → :$luci_port\n🔹 SSH: $ssh_name → :$ssh_port\n\n📡 Внешний IP: $IP\n📦 Диск: $DISK\n💽 RAM: $RAM"
wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

echo "${GREEN}Установка завершена.${NC}"
