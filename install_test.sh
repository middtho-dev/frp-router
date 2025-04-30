#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# Проверка curl и wget
echo -e "${GREEN}Проверяю, установлены ли curl и wget...${NC}"
opkg update
command -v curl &> /dev/null || opkg install curl
command -v wget &> /dev/null || opkg install wget

# Проверка jq
command -v jq &> /dev/null || opkg install jq

# Загрузка frpc
mkdir -p $FRP_DIR
cd $FRP_DIR
[ -f frpc ] && rm -f frpc
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o frpc
chmod +x frpc

# Ввод параметров
echo -e "${GREEN}Введите имя для прокси Luci:${NC}"
read luci_name
echo -e "${GREEN}Введите порт для прокси Luci:${NC}"
read luci_port
echo -e "${GREEN}Введите имя для прокси SSH:${NC}"
read ssh_name
echo -e "${GREEN}Введите порт для прокси SSH:${NC}"
read ssh_port

# Создание frpc.toml
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

# Создание init.d скрипта
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

# Telegram уведомление
WAN_IP=$(ip -4 addr show dev eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || curl -s https://api.ipify.org)
DEVICE_NAME=$(uname -n)

MESSAGE="✅ *FRPC установлен и запущен!*
🪧 *Устройство:* \`$DEVICE_NAME\`
☁️ *WAN:* \`$WAN_IP\`

🔌 *Прокси Luci:* \`$luci_name\` — порт \`$luci_port\`
🔐 *Прокси SSH:* \`$ssh_name\` — порт \`$ssh_port\`"

wget -qO- --post-data="chat_id=$CHAT_ID&text=$(echo -e "$MESSAGE")&parse_mode=Markdown" \
  "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

# Установка watchdog
cat <<'EOF' > /root/frpc_watchdog.sh
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
FRPC_BIN="/root/frp/frpc"
LOG_FILE="/root/frpc_watchdog.log"
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')
WAN_IP=$(ip -4 addr show dev eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || curl -s https://api.ipify.org)

if ! pgrep -f "$FRPC_BIN" > /dev/null; then
    MSG="⚠️ $DATE_NOW - FRPC не работает! WAN: $WAN_IP. Перезапускаю..."
    echo "$MSG" >> "$LOG_FILE"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MSG" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    /etc/init.d/frpc restart
else
    echo "$DATE_NOW - FRPC работает. WAN: $WAN_IP" >> "$LOG_FILE"
fi
EOF

chmod +x /root/frpc_watchdog.sh

# Добавляем в cron
crontab -l | grep -q frpc_watchdog.sh || (crontab -l; echo "*/5 * * * * /root/frpc_watchdog.sh") | crontab -

# Telegram-бот
cat <<'EOF' > /root/frpc_bot.sh
#!/bin/bash

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
while true; do
  UPDATES=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates")
  LAST=$(echo "$UPDATES" | jq -r '.result[-1]')
  TEXT=$(echo "$LAST" | jq -r '.message.text')
  ID=$(echo "$LAST" | jq -r '.message.message_id')

  if [[ "$TEXT" == "/status" ]]; then
    WAN=$(ip -4 addr show dev eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || curl -s https://api.ipify.org)
    HOST=$(uname -n)
    MSG="📡 Устройство: \`$HOST\`\n🌐 WAN: \`$WAN\`"
    curl -s "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
         -d chat_id="$CHAT_ID" -d text="$MSG" -d parse_mode="Markdown"
  fi

  sleep 10
done
EOF

chmod +x /root/frpc_bot.sh

# Добавляем бот в автозагрузку
grep -q frpc_bot.sh /etc/rc.local || sed -i '$i nohup bash /root/frpc_bot.sh &' /etc/rc.local

echo -e "${GREEN}Готово! FRPC установлен, настроен и Telegram уведомления включены.${NC}"