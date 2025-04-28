#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Сброс цвета

# Параметры GitHub репозитория
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"

# Создаем каталог
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit 1

# Удаляем старый frpc, если он есть
echo -e "${GREEN}Проверяю наличие старого frpc...${NC}"
if [ -f "$FRP_DIR/frpc" ]; then
    echo -e "${RED}Удаляю старый frpc...${NC}"
    rm -f "$FRP_DIR/frpc"
fi

# Скачиваем frpc
echo -e "${GREEN}Скачиваю frpc с GitHub...${NC}"
if ! curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "$FRP_DIR/frpc"; then
    echo -e "${RED}Ошибка загрузки frpc!${NC}"
    exit 1
fi

chmod +x "$FRP_DIR/frpc"

# Запрашиваем настройки
echo -e "${GREEN}Введите имя прокси Luci:${NC}"
read -r luci_name
echo -e "${GREEN}Введите порт для прокси Luci:${NC}"
read -r luci_port

echo -e "${GREEN}Введите имя прокси SSH:${NC}"
read -r ssh_name
echo -e "${GREEN}Введите порт для прокси SSH:${NC}"
read -r ssh_port

# Создаем frpc.toml
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

echo -e "${GREEN}Файл конфигурации frpc.toml создан.${NC}"

# Создаем init.d скрипт для OpenWrt
cat <<'EOF' > "$INIT_SCRIPT"
#!/bin/sh /etc/rc.common

START=97
STOP=10
USE_PROCD=1

FRPC_BIN="/root/frp/frpc"
FRPC_CFG="/root/frp/frpc.toml"

start_service() {
    procd_open_instance
    procd_set_param command "$FRPC_BIN" -c "$FRPC_CFG"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile "/var/run/frpc.pid"
    procd_close_instance
}

stop_service() {
    killall frpc
}
EOF

chmod +x "$INIT_SCRIPT"

# Добавляем в автозагрузку и запускаем
/etc/init.d/frpc enable
/etc/init.d/frpc restart

echo -e "${GREEN}Установка и настройка завершены.${NC}"

# Создаем watchdog скрипт
cat <<'EOF' > /root/frpc_watchdog.sh
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

FRPC_BIN="/root/frp/frpc"
INIT_SCRIPT="/etc/init.d/frpc"
LOG_FILE="/root/frpc_watchdog.log"
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')

# Проверка процесса frpc
if ! pgrep -f "$FRPC_BIN" > /dev/null; then
    MESSAGE="⚠️ $DATE_NOW - FRPC не работает на $(uname -n)! Перезапускаю..."
    echo "$MESSAGE" >> "$LOG_FILE"
    wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" restart

        sleep 5
        if pgrep -f "$FRPC_BIN" > /dev/null; then
            MESSAGE="✅ $DATE_NOW - FRPC успешно перезапущен."
        else
            MESSAGE="❌ $DATE_NOW - Ошибка: FRPC не запустился!"
        fi
        echo "$MESSAGE" >> "$LOG_FILE"
        wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    else
        MESSAGE="❌ $DATE_NOW - Init.d скрипт $INIT_SCRIPT не найден!"
        echo "$MESSAGE" >> "$LOG_FILE"
        wget -qO- --post-data="chat_id=$CHAT_ID&text=$MESSAGE" "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    fi
fi
EOF

chmod +x /root/frpc_watchdog.sh

# Добавляем watchdog в cron
echo "*/5 * * * * /root/frpc_watchdog.sh" >> /etc/crontabs/root
/etc/init.d/cron restart

echo -e "${GREEN}Watchdog для frpc настроен!${NC}"
