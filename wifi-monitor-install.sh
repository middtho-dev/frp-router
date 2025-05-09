#!/bin/bash

# Цвета для оформления
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Параметры
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
WIFI_MONITOR_SCRIPT="/root/wifi_monitor.sh"
INIT_WIFI="/etc/init.d/wifi_monitor"
HOSTNAME=$(uname -n)
WAN_IFACE=$(ip route get 8.8.8.8 | awk '{print $5}')
WAN_IP=$(ip -4 addr show $WAN_IFACE | awk '/inet / {print $2}' | cut -d/ -f1)

# Уведомление о начале установки
echo -e "${GREEN}🚀 Установка Wi-Fi мониторинга...${NC}"

# Проверка на наличие необходимых пакетов
echo -e "${GREEN}🔽 Проверка пакетов...${NC}"
for pkg in curl hostapd-utils; do
    if ! command -v $pkg &>/dev/null; then
        echo -e "${RED}⚠️ Устанавливаю $pkg...${NC}"
        opkg update && opkg install $pkg
    fi
done

# Создание скрипта Wi-Fi мониторинга
echo -e "${GREEN}🛠 Создаю скрипт Wi-Fi мониторинга...${NC}"
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

# Создание init.d для Wi-Fi мониторинга
echo -e "${GREEN}🔧 Создаю init.d для Wi-Fi мониторинга...${NC}"
cat <<EOF > "$INIT_WIFI"
#!/bin/sh /etc/rc.common

START=98
STOP=20

start() {
    echo "📡 Запуск Wi-Fi мониторинга"
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
    HOSTNAME=\$(uname -n)
    WAN_IFACE=\$(ip route get 8.8.8.8 | awk '{print \$5}')
    WAN_IP=\$(ip -4 addr show \$WAN_IFACE | awk '/inet / {print \$2}' | cut -d/ -f1)
    MESSAGE="📡 Wi-Fi мониторинг остановлен на \$HOSTNAME (\$WAN_IP)"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=\$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
}
EOF

chmod +x "$INIT_WIFI"
/etc/init.d/wifi_monitor enable
/etc/init.d/wifi_monitor restart

# Уведомление об успешной установке
MESSAGE="✅ Wi-Fi мониторинг установлен и запущен на $HOSTNAME ($WAN_IP)"
wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

echo -e "${GREEN}🎉 Установка завершена.${NC}"
