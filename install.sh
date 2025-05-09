#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Переменные
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
WIFI_MONITOR_SCRIPT="/root/wifi_monitor.sh"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# Имя хоста и WAN IP
HOSTNAME=$(uname -n)
WAN_IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
WAN_IP=$(ip -4 addr show "$WAN_IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)

# Проверка необходимых пакетов
echo -e "${GREEN}Проверяю наличие необходимых пакетов...${NC}"
for pkg in curl wget hostapd-utils jq; do
    if ! command -v $pkg &> /dev/null; then
        echo -e "${RED}$pkg не найден, устанавливаю...${NC}"
        opkg update && opkg install $pkg
    fi
done

# Подготовка каталога и скачивание frpc
echo -e "${GREEN}Загружаю frpc...${NC}"
mkdir -p $FRP_DIR
cd $FRP_DIR

rm -f frpc
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o frpc
chmod +x frpc

# Настройка frpc.toml
echo -e "${GREEN}Настройка frpc.toml...${NC}"
read -p "Имя прокси Luci: " luci_name
read -p "Порт Luci: " luci_port
read -p "Имя прокси SSH: " ssh_name
read -p "Порт SSH: " ssh_port

cat <<EOF > frpc.toml
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

# Создание /etc/init.d/frpc
echo -e "${GREEN}Создаю init-скрипт...${NC}"
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

chmod +x $INIT_SCRIPT
/etc/init.d/frpc enable
/etc/init.d/frpc start

# Watchdog
echo -e "${GREEN}Создаю watchdog...${NC}"
cat <<EOF > $WATCHDOG_SCRIPT
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
LOG="/root/frpc_watchdog.log"
DATE=\$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=\$(uname -n)
WAN_IFACE=\$(ip route get 8.8.8.8 | awk '{print \$5; exit}')
WAN_IP=\$(ip -4 addr show \$WAN_IFACE | awk '/inet / {print \$2}' | cut -d/ -f1)

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MSG="⚠️ \$DATE
FRPC не работает на \$HOSTNAME (\$WAN_IP)
Перезапускаю..."
    echo "\$MSG" >> \$LOG
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"

    /etc/init.d/frpc restart
    sleep 5

    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MSG="✅ \$DATE
FRPC перезапущен на \$HOSTNAME (\$WAN_IP)"
    else
        MSG="❌ \$DATE
Не удалось запустить FRPC на \$HOSTNAME (\$WAN_IP)"
    fi
    echo "\$MSG" >> \$LOG
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
fi
EOF

chmod +x $WATCHDOG_SCRIPT

# Cron для watchdog
if ! crontab -l 2>/dev/null | grep -q "$WATCHDOG_SCRIPT"; then
    (crontab -l 2>/dev/null; echo "* * * * * $WATCHDOG_SCRIPT") | crontab -
fi

# Wi-Fi мониторинг
echo -e "${GREEN}Настройка мониторинга Wi-Fi подключений...${NC}"
cat <<'EOF' > $WIFI_MONITOR_SCRIPT
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
HOSTNAME=$(uname -n)
WAN_IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
WAN_IP=$(ip -4 addr show $WAN_IFACE | awk '/inet / {print $2}' | cut -d/ -f1)

IFACE=$1
EVENT=$2
MAC=$3

case "$EVENT" in
    "AP-STA-CONNECTED") STATUS="🔌 Подключение";;
    "AP-STA-DISCONNECTED") STATUS="❌ Отключение";;
    *) exit 0;;
esac

NAME=$(grep -i "$MAC" /tmp/dhcp.leases | awk '{print $4}' | head -n 1)
IP=$(grep -i "$MAC" /tmp/dhcp.leases | awk '{print $3}' | head -n 1)

MSG="$STATUS к Wi-Fi
📍 Устройство на $HOSTNAME ($WAN_IP)
👤 Имя: ${NAME:-Неизвестно}
🌐 IP: ${IP:-Неизвестно}
🆔 MAC: $MAC"

wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
EOF

chmod +x $WIFI_MONITOR_SCRIPT

# Привязка через hostapd_cli
for iface in $(iw dev | awk '$1=="Interface"{print $2}'); do
    hostapd_cli -i $iface -a $WIFI_MONITOR_SCRIPT &
done

# Уведомление об установке
MSG="✅ Установка завершена на $HOSTNAME ($WAN_IP)

🔹 Luci: $luci_name → :$luci_port
🔹 SSH: $ssh_name → :$ssh_port"

wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

echo -e "${GREEN}Готово!${NC}"
