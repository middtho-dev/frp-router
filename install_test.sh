#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Параметры
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
LOG_FILE="/root/frpc_watchdog.log"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

echo -e "${GREEN}Проверка наличия curl и wget...${NC}"
opkg update
opkg install curl wget -qq

mkdir -p $FRP_DIR && cd $FRP_DIR

echo -e "${GREEN}Удаление старого frpc, если существует...${NC}"
rm -f "$FRP_DIR/frpc"

echo -e "${GREEN}Скачивание frpc...${NC}"
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "frpc" || {
    echo -e "${RED}Ошибка загрузки frpc.${NC}"; exit 1;
}
chmod +x frpc

# Получение параметров от пользователя
echo -e "${GREEN}Введите имя устройства (например: SVetrov):${NC}"
read device_name
echo -e "${GREEN}Введите номер устройства (двузначный, например: 11):${NC}"
read device_number

# Проверка корректности номера
if ! [[ "$device_number" =~ ^[0-9]{2}$ ]]; then
  echo -e "${RED}Номер устройства должен быть двузначным числом (например: 01, 12, 45).${NC}"
  exit 1
fi

luci_name="${device_name}_Luci"
ssh_name="${device_name}_SSH"
luci_port="80${device_number}"
ssh_port="22${device_number}"

echo -e "${GREEN}Сформированы параметры:${NC}"
echo -e "  Luci: $luci_name → порт $luci_port"
echo -e "  SSH:  $ssh_name → порт $ssh_port"

# Создание конфигурации
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

# Watchdog скрипт
cat <<EOF > $WATCHDOG_SCRIPT
#!/bin/sh

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    MSG="⚠️ \$DATE_NOW - FRPC не работает на \$(uname -n)! Перезапускаю..."
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
         -d "chat_id=\$CHAT_ID" --data-urlencode "text=\$MSG"
    /etc/init.d/frpc restart
    sleep 3
    if pgrep -f "\$FRPC_BIN" > /dev/null; then
        MSG="✅ \$DATE_NOW - FRPC успешно перезапущен."
    else
        MSG="❌ \$DATE_NOW - FRPC не удалось запустить."
    fi
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
         -d "chat_id=\$CHAT_ID" --data-urlencode "text=\$MSG"
fi
EOF

chmod +x $WATCHDOG_SCRIPT

# Настройка cron
if ! grep -q "$WATCHDOG_SCRIPT" /etc/crontabs/root; then
    echo "*/1 * * * * $WATCHDOG_SCRIPT" >> /etc/crontabs/root
    /etc/init.d/cron enable
    /etc/init.d/cron restart
    echo -e "${GREEN}Cron успешно настроен на каждую минуту.${NC}"
else
    echo -e "${RED}Cron уже содержит задачу для watchdog.${NC}"
fi

# Уведомление о первом запуске
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode "text=✅ FRPC установлен и запущен на $(uname -n) ($device_name, №$device_number)"

echo -e "${GREEN}Установка и настройка завершены.${NC}"
