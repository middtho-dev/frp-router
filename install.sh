#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Настройки
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
WIFI_MONITOR_SCRIPT="/root/wifi_monitor.sh"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# Получение информации
HOSTNAME=$(uname -n)
WAN_IP=$(ip -4 addr show $(ip route get 8.8.8.8 | awk '{print $5}') | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Проверка и установка необходимых пакетов
echo -e "${GREEN}Проверяю и устанавливаю необходимые пакеты...${NC}"
REQUIRED_PKGS="curl wget hostapd-utils jq ip-full coreutils arp-scan bash grep awk cut"
for pkg in $REQUIRED_PKGS; do
    if ! opkg list-installed | grep -q "^$pkg"; then
        echo -e "${GREEN}Устанавливаю: $pkg${NC}"
        opkg update && opkg install "$pkg"
    fi
done

# Подготовка и загрузка frpc
mkdir -p $FRP_DIR && cd $FRP_DIR
rm -f "$FRP_DIR/frpc"
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o frpc
chmod +x frpc

# Настройка frpc.toml
read -p "Имя прокси Luci: " luci_name
read -p "Порт Luci: " luci_port
read -p "Имя прокси SSH: " ssh_name
read -p "Порт SSH: " ssh_port

cat <<EOF > $FRP_DIR/frpc.toml
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

# Init.d скрипт
cat <<EOF > $INIT_SCRIPT
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
    procd_close_instance
}
shutdown() {
    killall "\$NAME"
}
EOF
chmod +x $INIT_SCRIPT
/etc/init.d/frpc enable
/etc/init.d/frpc start

# Watchdog
cat <<EOF > $WATCHDOG_SCRIPT
#!/bin/sh
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
LOG_FILE="/root/frpc_watchdog.log"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=\$(uname -n)
WAN_IP=\$(ip -4 addr show \$(ip route get 8.8.8.8 | awk '{print \$5}') | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}')

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MESSAGE="⚠️ \$DATE_NOW\nFRPC не работает на \$HOSTNAME (\$WAN_IP). Перезапускаю..."
    echo "\$MESSAGE" >> "\$LOG_FILE"
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" -d "chat_id=\$CHAT_ID&text=\$MESSAGE"

    /etc/init.d/frpc restart
    sleep 5

    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MESSAGE="✅ \$DATE_NOW\nFRPC успешно перезапущен на \$HOSTNAME (\$WAN_IP)."
    else
        MESSAGE="❌ \$DATE_NOW\nОшибка запуска FRPC на \$HOSTNAME (\$WAN_IP)."
    fi
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" -d "chat_id=\$CHAT_ID&text=\$MESSAGE"
fi
EOF
chmod +x $WATCHDOG_SCRIPT
(crontab -l 2>/dev/null; echo "* * * * * $WATCHDOG_SCRIPT") | crontab -

# Wi-Fi мониторинг
cat <<'EOF' > $WIFI_MONITOR_SCRIPT
#!/bin/sh
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
HOSTNAME=$(uname -n)
WAN_IP=$(ip -4 addr show $(ip route get 8.8.8.8 | awk '{print $5}') | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
IFACE=$1
EVENT=$2
MAC=$3

if [ "$EVENT" = "AP-STA-CONNECTED" ]; then
    STATUS="подключилось"
elif [ "$EVENT" = "AP-STA-DISCONNECTED" ]; then
    STATUS="отключилось"
else
    exit 0
fi

IP=$(arp -n | grep "$MAC" | awk '{print $1}')
NAME=$(grep -i "$MAC" /tmp/dhcp.leases | awk '{print $4}')

TEXT="📶 Устройство $STATUS к Wi-Fi на $HOSTNAME ($WAN_IP)%0AИмя: ${NAME:-Неизвестно}%0AIP: ${IP:-Неизвестно}%0AMAC: $MAC"
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID&text=$TEXT"
EOF
chmod +x $WIFI_MONITOR_SCRIPT

# Автозапуск Wi-Fi мониторинга
echo -e "${GREEN}Настройка отслеживания Wi-Fi подключений...${NC}"
for iface in $(iw dev | awk '$1=="Interface"{print $2}'); do
    uci set wireless.@wifi-iface[0].ap_script="$WIFI_MONITOR_SCRIPT"
done
uci commit wireless
wifi reload

# Telegram уведомление об установке
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID&text=✅ FRPC установлен на $HOSTNAME ($WAN_IP)%0A🔹 Luci: $luci_name → :$luci_port%0A🔹 SSH: $ssh_name → :$ssh_port"

echo -e "${GREEN}Установка завершена.${NC}"
