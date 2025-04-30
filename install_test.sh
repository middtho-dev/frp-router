#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Сброс цвета

# Параметры GitHub репозитория
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# Проверяем наличие curl и wget
echo -e "${GREEN}Проверяю, установлены ли curl и wget...${NC}"
if ! command -v curl &> /dev/null; then
    echo -e "${RED}curl не найден, устанавливаю...${NC}"
    opkg update && opkg install curl
fi

if ! command -v wget &> /dev/null; then
    echo -e "${RED}wget не найден, устанавливаю...${NC}"
    opkg update && opkg install wget
fi

# Скачиваем файл frpc
mkdir -p $FRP_DIR
cd $FRP_DIR

echo -e "${GREEN}Проверяю, не занят ли файл frpc...${NC}"
if [ -f "$FRP_DIR/frpc" ]; then
    echo -e "${RED}Файл frpc уже существует, пытаюсь удалить...${NC}"
    rm -f "$FRP_DIR/frpc"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Файл frpc успешно удалён.${NC}"
    else
        echo -e "${RED}Не удалось удалить файл frpc. Прерываю выполнение.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Скачиваю frpc с GitHub...${NC}"
if curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "frpc"; then
    echo -e "${GREEN}Файл frpc успешно скачан.${NC}"
else
    echo -e "${RED}Ошибка при загрузке файла frpc с GitHub.${NC}"
    exit 1
fi

# Даем права на frpc
echo -e "${GREEN}Даю права на frpc...${NC}"
chmod +x $FRP_DIR/frpc

# Запрашиваем параметры для frpc.toml
echo -e "${GREEN}Введите имя для прокси Luci (например: Home Luci):${NC}"
read luci_name
echo -e "${GREEN}Введите порт для прокси Luci (например: 8081):${NC}"
read luci_port

echo -e "${GREEN}Введите имя для прокси SSH (например: Home SSH):${NC}"
read ssh_name
echo -e "${GREEN}Введите порт для прокси SSH (например: 2201):${NC}"
read ssh_port

# Создаем frpc.toml
echo -e "${GREEN}Создаю файл frpc.toml...${NC}"
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

# Создаем init.d скрипт
echo -e "${GREEN}Создаю init.d скрипт...${NC}"
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

# Получение IP
LOCAL_IP=$(ip -4 addr show br-lan 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
EXTERNAL_IP=$(curl -s https://api.ipify.org)
HOSTNAME=$(uname -n)

# Отправка уведомления о запуске
MESSAGE="✅ *FRPC установлен и запущен!*
🏷 Устройство: \`$HOSTNAME\`
🌐 IP: \`$LOCAL_IP\`
☁️ WAN: \`$EXTERNAL_IP\`"

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$MESSAGE" \
  -d parse_mode="Markdown"

# Скрипт мониторинга и перезапуска службы (watchdog)
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"

cat <<EOF > $WATCHDOG_SCRIPT
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
LOG_FILE="/root/frpc_watchdog.log"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')

LOCAL_IP=\$(ip -4 addr show br-lan 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -n 1)
EXTERNAL_IP=\$(curl -s https://api.ipify.org)
HOSTNAME=\$(uname -n)

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MESSAGE="⚠️ *FRPC не работает! Перезапускаю...*
🏷 Устройство: \\\`\$HOSTNAME\\\`
🌐 IP: \\\`\$LOCAL_IP\\\`
☁️ WAN: \\\`\$EXTERNAL_IP\\\`"
    echo "\$DATE_NOW - FRPC не работает. Перезапуск..." >> "\$LOG_FILE"
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE&parse_mode=Markdown" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"

    /etc/init.d/frpc restart
    sleep 5
    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MESSAGE="✅ *FRPC успешно перезапущен!*
🏷 Устройство: \\\`\$HOSTNAME\\\`
🌐 IP: \\\`\$LOCAL_IP\\\`
☁️ WAN: \\\`\$EXTERNAL_IP\\\`"
    else
        MESSAGE="❌ *Ошибка: FRPC не удалось запустить!*
🏷 Устройство: \\\`\$HOSTNAME\\\`"
    fi
    echo "\$DATE_NOW - \$MESSAGE" >> "\$LOG_FILE"
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE&parse_mode=Markdown" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
else
    MESSAGE="✅ *FRPC работает*
🏷 Устройство: \\\`\$HOSTNAME\\\`
🌐 IP: \\\`\$LOCAL_IP\\\`
☁️ WAN: \\\`\$EXTERNAL_IP\\\`"
    echo "\$DATE_NOW - FRPC OK" >> "\$LOG_FILE"
    wget -qO- --post-data="chat_id=\$CHAT_ID&text=\$MESSAGE&parse_mode=Markdown" "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage"
fi
EOF

chmod +x $WATCHDOG_SCRIPT

# Настраиваем cron
if ! crontab -l | grep -q "$WATCHDOG_SCRIPT"; then
    (crontab -l; echo "*/5 * * * * $WATCHDOG_SCRIPT") | crontab -
fi

echo -e "${GREEN}Готово! FRPC установлен, запущен, настроен watchdog и Telegram-оповещение.${NC}"