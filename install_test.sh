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
CRON_FILE="/etc/crontabs/root"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

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
LOG_FILE="/root/frpc_watchdog.log"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MESSAGE="⚠️ \$DATE_NOW - FRPC не работает, перезапускаю..."
    echo "\$MESSAGE" >> "\$LOG_FILE"
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
    /etc/init.d/frpc restart
    sleep 5
    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MESSAGE="✅ \$DATE_NOW - FRPC перезапущен."
    else
        MESSAGE="❌ \$DATE_NOW - FRPC не удалось перезапустить."
    fi
    echo "\$MESSAGE" >> "\$LOG_FILE"
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
else
    echo "\$DATE_NOW - FRPC работает." >> "\$LOG_FILE"
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"

# Cron настройка
echo -e "${GREEN}Настройка cron каждые 1 минуту...${NC}"
if ! grep -q "$WATCHDOG_SCRIPT" "$CRON_FILE"; then
    echo "*/1 * * * * $WATCHDOG_SCRIPT" >> "$CRON_FILE"
    /etc/init.d/cron restart
fi

# Telegram уведомление о завершении установки
HOSTNAME=$(uname -n)
MESSAGE="✅ FRPC установлен на $HOSTNAME\n
🔹 Luci: $luci_name → :$luci_port\n
🔹 SSH:  $ssh_name → :$ssh_port"

wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

echo -e "${GREEN}Установка завершена.${NC}"
