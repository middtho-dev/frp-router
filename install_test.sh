#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Переменные
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# Установка зависимостей
echo -e "${GREEN}Проверка зависимостей...${NC}"
opkg update
opkg install curl wget bash coreutils-base64 coreutils-nohup

# Скачиваем frpc
mkdir -p $FRP_DIR
cd $FRP_DIR
rm -f frpc
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "frpc"
chmod +x frpc

# Ввод данных
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

# Init-скрипт
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
EOF

chmod +x $INIT_SCRIPT
/etc/init.d/frpc enable
/etc/init.d/frpc start

# Получение IP и имя хоста
EXTERNAL_IP=$(curl -s https://api.ipify.org)
HOSTNAME=$(uname -n)

# Уведомление о запуске
MESSAGE="✅ *FRPC установлен и запущен!*
🏷 Устройство: \`$HOSTNAME\`
☁️ WAN: \`$EXTERNAL_IP\`

📦 *Прокси настроены:*
• Luci: \`$luci_name\` → порт \`$luci_port\`
• SSH: \`$ssh_name\` → порт \`$ssh_port\`"

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$MESSAGE" \
  -d parse_mode="Markdown"

# watchdog скрипт
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
cat <<EOF > $WATCHDOG_SCRIPT
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
LOG="/root/frpc_watchdog.log"
EXTERNAL_IP=\$(curl -s https://api.ipify.org)
HOSTNAME=\$(uname -n)
DATE=\$(date '+%Y-%m-%d %H:%M:%S')

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    echo "\$DATE - FRPC не работает. Перезапуск..." >> "\$LOG"
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=⚠️ *FRPC упал. Перезапуск...*
🏷 \\\`\$HOSTNAME\\\`
☁️ WAN: \\\`\$EXTERNAL_IP\\\`&parse_mode=Markdown" \
    "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
    
    /etc/init.d/frpc restart

    sleep 3
    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MSG="✅ *FRPC перезапущен*
🏷 \\\`\$HOSTNAME\\\`
☁️ WAN: \\\`\$EXTERNAL_IP\\\`"
    else
        MSG="❌ *Не удалось перезапустить FRPC*
🏷 \\\`\$HOSTNAME\\\`"
    fi

    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MSG&parse_mode=Markdown" \
    "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
else
    echo "\$DATE - FRPC работает" >> "\$LOG"
fi
EOF

chmod +x $WATCHDOG_SCRIPT

# Cron для watchdog
crontab -l | grep -v frpc_watchdog.sh > /tmp/crontab_tmp
echo "*/5 * * * * $WATCHDOG_SCRIPT" >> /tmp/crontab_tmp
crontab /tmp/crontab_tmp
rm /tmp/crontab_tmp

# Команды Telegram-бота
BOT_HANDLER="/root/frpc_bot.sh"
cat <<EOF > $BOT_HANDLER
#!/bin/bash

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
OFFSET=0

while true; do
  UPDATES=\$(curl -s "https://api.telegram.org/bot\$BOT_TOKEN/getUpdates?offset=\$OFFSET")
  for row in \$(echo \$UPDATES | jq -c '.result[]'); do
    OFFSET=\$(echo \$row | jq '.update_id + 1')
    TEXT=\$(echo \$row | jq -r '.message.text')
    CID=\$(echo \$row | jq -r '.message.chat.id')

    EXTERNAL_IP=\$(curl -s https://api.ipify.org)
    HOSTNAME=\$(uname -n)

    case "\$TEXT" in
      "/status")
        if pgrep -f "frpc" > /dev/null; then
          MSG="✅ *FRPC работает*
🏷 \\\`\$HOSTNAME\\\`
☁️ WAN: \\\`\$EXTERNAL_IP\\\`"
        else
          MSG="❌ *FRPC остановлен*
🏷 \\\`\$HOSTNAME\\\`"
        fi
        ;;
      "/restart")
        /etc/init.d/frpc restart
        MSG="♻️ *FRPC перезапущен*"
        ;;
      "/ip")
        MSG="☁️ WAN IP: \\\`\$EXTERNAL_IP\\\`"
        ;;
      "/uptime")
        UPTIME=\$(uptime | sed 's/.*up \([^,]*\),.*/\1/')
        MSG="⏱ *Аптайм*: \\\`\$UPTIME\\\`"
        ;;
      *)
        MSG="Команды:
/status — статус FRPC
/restart — перезапуск FRPC
/ip — WAN IP
/uptime — аптайм"
        ;;
    esac

    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
      -d chat_id="\$CID" -d text="\$MSG" -d parse_mode="Markdown"
  done
  sleep 5
done
EOF

chmod +x $BOT_HANDLER
nohup bash $BOT_HANDLER >/dev/null 2>&1 &

echo -e "${GREEN}Установка завершена. FRPC работает, Telegram уведомления и команды активны.${NC}"