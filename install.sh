#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Параметры
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_FRPC="/etc/init.d/frpc"
INIT_WIFI="/etc/init.d/wifi_monitor"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
WIFI_MONITOR_SCRIPT="/root/wifi_monitor.sh"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# Хост и IP
HOSTNAME=$(uname -n)
WAN_IFACE=$(ip route get 8.8.8.8 | awk '{print $5}')
WAN_IP=$(ip -4 addr show $WAN_IFACE | awk '/inet / {print $2}' | cut -d/ -f1)

# Пакеты
echo -e "${GREEN}Проверяю пакеты...${NC}"
for pkg in curl wget hostapd-utils jq; do
    if ! command -v $pkg &>/dev/null; then
        echo -e "${RED}Устанавливаю $pkg...${NC}"
        opkg update && opkg install $pkg
    fi
done

# Каталог frp
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit

# frpc
echo -e "${GREEN}Загружаю frpc...${NC}"
rm -f frpc
if curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o frpc; then
    chmod +x frpc
else
    echo -e "${RED}Ошибка загрузки frpc.${NC}"
    exit 1
fi

# Настройка frpc.toml
echo -e "${GREEN}Настраиваю frpc.toml...${NC}"
read -p "Имя прокси Luci (например: Home_Luci): " luci_name
read -p "Удалённый порт Luci: " luci_port
read -p "Имя прокси SSH: " ssh_name
read -p "Удалённый порт SSH: " ssh_port

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

# frpc init
echo -e "${GREEN}Создаю init.d для frpc...${NC}"
cat <<EOF > "$INIT_FRPC"
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

chmod +x "$INIT_FRPC"
/etc/init.d/frpc enable
/etc/init.d/frpc start

# watchdog
echo -e "${GREEN}Создаю watchdog...${NC}"
cat <<EOF > "$WATCHDOG_SCRIPT"
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
HOSTNAME=\$(uname -n)
WAN_IFACE=\$(ip route get 8.8.8.8 | awk '{print \$5}')
WAN_IP=\$(ip -4 addr show \$WAN_IFACE | awk '/inet / {print \$2}' | cut -d/ -f1)
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MESSAGE="⚠️ \$DATE_NOW FRPC не работает на \$HOSTNAME (\$WAN_IP). Перезапускаю..."
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
    /etc/init.d/frpc restart
    sleep 5

    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MESSAGE="✅ \$DATE_NOW FRPC перезапущен на \$HOSTNAME (\$WAN_IP)"
    else
        MESSAGE="❌ \$DATE_NOW FRPC не запущен на \$HOSTNAME (\$WAN_IP)!"
    fi

    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"

# Cron
echo -e "${GREEN}Настраиваю cron...${NC}"
crontab -l 2>/dev/null | grep -v "$WATCHDOG_SCRIPT" | { cat; echo "* * * * * $WATCHDOG_SCRIPT"; } | crontab -

# Wi-Fi мониторинг скрипт
echo -e "${GREEN}Создаю скрипт Wi-Fi мониторинга...${NC}"
cat <<'EOF' > "$WIFI_MONITOR_SCRIPT"
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
HOSTNAME=$(uname -n)
WAN_IFACE=$(ip route get 8.8.8.8 | awk '{print $5}')
WAN_IP=$(ip -4 addr show $WAN_IFACE | awk '/inet / {print $2}' | cut -d/ -f1)

IFACE=$1
EVENT=$2
MAC=$3

if [ "$EVENT" = "AP-STA-CONNECTED" ]; then
    STATUS="Подключение к Wi-Fi"
    ICON="🔌"
elif [ "$EVENT" = "AP-STA-DISCONNECTED" ]; then
    STATUS="Отключение от Wi-Fi"
    ICON="❌"
else
    exit 0
fi

IP=$(arp -n | awk -v mac="$MAC" 'tolower($3)==tolower(mac) {print $1}')
NAME=$(grep -i "$MAC" /tmp/dhcp.leases | awk '{print $4}')
MESSAGE="$ICON $STATUS. Устройство на $HOSTNAME ($WAN_IP). Имя: ${NAME:-*}. IP: ${IP:-*}. MAC: $MAC"
wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
EOF

chmod +x "$WIFI_MONITOR_SCRIPT"

# Wi-Fi init скрипт
echo -e "${GREEN}Создаю init.d для Wi-Fi мониторинга...${NC}"
cat <<EOF > "$INIT_WIFI"
#!/bin/sh /etc/rc.common

START=98
STOP=20

start() {
    echo "Запуск Wi-Fi мониторинга"
    for iface in \$(iw dev | awk '\$1=="Interface"{print \$2}'); do
        hostapd_cli -i \$iface -a $WIFI_MONITOR_SCRIPT &
    done

    HOSTNAME=\$(uname -n)
    WAN_IFACE=\$(ip route get 8.8.8.8 | awk '{print \$5}')
    WAN_IP=\$(ip -4 addr show \$WAN_IFACE | awk '/inet / {print \$2}' | cut -d/ -f1)
    MESSAGE="📡 Wi-Fi мониторинг запущен на \$HOSTNAME (\$WAN_IP)"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
}

stop() {
    pkill -f hostapd_cli
}
EOF

chmod +x "$INIT_WIFI"
/etc/init.d/wifi_monitor enable
/etc/init.d/wifi_monitor restart

# Уведомление об установке
MESSAGE="✅ FRPC установлен на $HOSTNAME ($WAN_IP). Luci: $luci_name → :$luci_port. SSH: $ssh_name → :$ssh_port"
wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

echo -e "${GREEN}Установка завершена.${NC}"
