#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Путь к конфигу
CONFIG_FILE="/etc/frpc.conf"

# Если конфига нет — создаём с параметрами по умолчанию
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}Создаю файл конфигурации $CONFIG_FILE...${NC}"
    cat <<EOF > "$CONFIG_FILE"
FRP_DIR="/root/frp"
GITHUB_REPO="middtho-dev/frp-router"
SERVER_ADDR="router.kv9.ru"
SERVER_PORT=7000
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
EOF
fi

# Загружаем конфиг
source "$CONFIG_FILE"

# Проверка зависимостей
echo -e "${GREEN}Проверяю зависимости...${NC}"
for cmd in curl wget; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}$cmd не найден, устанавливаю...${NC}"
        opkg update && opkg install $cmd
    fi
done

# Директория и переход
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit 1

# Удаление старого бинарника
[ -f frpc ] && rm -f frpc

# Загрузка frpc
echo -e "${GREEN}Скачиваю frpc с GitHub...${NC}"
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o frpc || exit 1
chmod +x frpc

# Функция отправки сообщения
send_message() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" -d text="$1" > /dev/null
}

# Функция ожидания ответа
wait_for_reply() {
    local prompt="$1"
    local varname="$2"

    send_message "$prompt"
    echo -e "${GREEN}Ожидаю ответ через Telegram...${NC}"

    for i in {1..60}; do
        RESPONSE=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates" | \
            grep -oP '"text":"[^"]+"' | tail -1 | cut -d'"' -f4)

        if [[ "$RESPONSE" =~ ^[a-zA-Z0-9_\-]+[[:space:]]+[0-9]+$ ]]; then
            IFS=' ' read -r name port <<< "$RESPONSE"
            eval "$varname=\"$name\""
            eval "${varname}_PORT=\"$port\""
            break
        fi
        sleep 2
    done

    if [ -z "${!varname}" ]; then
        echo -e "${RED}Нет ответа от Telegram. Прерывание.${NC}"
        exit 1
    fi
}

# Получение параметров
wait_for_reply "Введите имя и порт Luci (пример: home_luci 8081)" LUCI_NAME
wait_for_reply "Введите имя и порт SSH (пример: home_ssh 2201)" SSH_NAME

# Создание frpc.toml
cat <<EOF > frpc.toml
serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT

[[proxies]]
name = "$LUCI_NAME"
type = "tcp"
localPort = 80
remotePort = $LUCI_NAME_PORT

[[proxies]]
name = "$SSH_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $SSH_NAME_PORT
EOF

# Скрипт запуска (init.d)
INIT_SCRIPT="/etc/init.d/frpc"
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
EOF

chmod +x "$INIT_SCRIPT"
/etc/init.d/frpc enable
/etc/init.d/frpc start

# watchdog
WATCHDOG_SCRIPT="$FRP_DIR/frpc_watchdog.sh"
cat <<EOF > "$WATCHDOG_SCRIPT"
#!/bin/sh
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')

if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
        -d chat_id="\$CHAT_ID" -d text="⚠️ \$DATE_NOW: frpc не работает, перезапускаю..."
    /etc/init.d/frpc restart
else
    echo "\$DATE_NOW: frpc OK" >> /tmp/frpc_watchdog.log
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"
(crontab -l 2>/dev/null; echo "*/5 * * * * $WATCHDOG_SCRIPT") | crontab -

echo -e "${GREEN}Установка завершена. frpc работает. Следующий запуск будет использовать сохранённые настройки.${NC}"