#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
UTIL_SCRIPT="$FRP_DIR/frpc_util.sh"
CRON_FILE="/etc/crontabs/root"

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

DEVICE_NAME=""

# ===============================
# 📩 Telegram
# ===============================
send_telegram() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$text" >/dev/null
}

# ===============================
# 🗑 Удаление
# ===============================
remove_all() {
    echo -e "${RED}Удаление всех компонентов...${NC}"
    /etc/init.d/frpc stop 2>/dev/null
    /etc/init.d/frpc disable 2>/dev/null
    rm -f "$INIT_SCRIPT"
    rm -rf "$FRP_DIR"
    sed -i "\|$UTIL_SCRIPT check|d" "$CRON_FILE"
    sed -i "\|$UTIL_SCRIPT info|d" "$CRON_FILE"
    /etc/init.d/cron restart

    send_telegram "🗑️ FRPC и все скрипты удалены c *$(uname -n)*"
    echo -e "${GREEN}Удаление завершено.${NC}"
    exit 0
}

# ===============================
# 📋 Ввод
# ===============================
if [[ "$1" == --* ]]; then
    DEVICE_NAME="${1#--}"
fi

if [ -z "$DEVICE_NAME" ]; then
    echo -e "${GREEN}Выберите действие:${NC}
1 — Установить frpc
2 — Удалить frpc и все скрипты"
    read -p "Введите 1 или 2: " choice

    if [ "$choice" = "2" ]; then
        remove_all
    elif [ "$choice" != "1" ]; then
        echo -e "${RED}Неверный выбор.${NC}"
        exit 1
    fi

    read -p "Название устройства (например: Home): " DEVICE_NAME
fi

# ===============================
# 🔧 Зависимости
# ===============================
echo -e "${GREEN}Установка зависимостей...${NC}"
opkg update
opkg install curl wget jq

# ===============================
# 📡 Получение портов
# ===============================
echo -e "${GREEN}Запрос портов у сервера...${NC}"

ALLOC_RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode "text=/allocate $DEVICE_NAME")

PORTS=$(echo "$ALLOC_RESPONSE" | jq -r '.result.text')

LUCi_PORT=$(echo "$PORTS" | cut -d: -f1)
SSH_PORT=$(echo "$PORTS" | cut -d: -f2)

if [[ -z "$LUCi_PORT" || -z "$SSH_PORT" || "$LUCi_PORT" == "null" ]]; then
    echo -e "${RED}Ошибка получения портов${NC}"
    echo "$ALLOC_RESPONSE"
    exit 1
fi

echo -e "${GREEN}Выданы порты:${NC} Luci=$LUCi_PORT SSH=$SSH_PORT"

# ===============================
# 📦 Установка FRPC
# ===============================
echo -e "${GREEN}Загрузка FRPC...${NC}"
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit 1

rm -f frpc
curl -L "https://github.com/middtho-dev/frp-router/raw/main/frpc" -o frpc
chmod +x frpc

# ===============================
# 🧾 frpc.toml
# ===============================
cat <<EOF > "$FRP_DIR/frpc.toml"
serverAddr = "router.kv9.ru"
serverPort = 7000

[[proxies]]
name = "${DEVICE_NAME}_Luci"
type = "tcp"
localPort = 80
remotePort = $LUCi_PORT

[[proxies]]
name = "${DEVICE_NAME}_SSH"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $SSH_PORT
EOF

# ===============================
# ⚙️ init.d сервис
# ===============================
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

# ===============================
# 🌍 hostname + TZ
# ===============================
echo -e "${GREEN}Настройка системы...${NC}"
uci set system.@system[0].hostname="$DEVICE_NAME"
uci set system.@system[0].timezone='MSK-3'
uci set system.@system[0].zonename='Europe/Moscow'
uci commit system
/etc/init.d/system reload

# ===============================
# 🔄 watchdog + info
# ===============================
cat <<'EOF' > "$UTIL_SCRIPT"
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

send() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$1" >/dev/null
}

if [ "$1" = "check" ]; then
    if ! pidof frpc >/dev/null; then
        send "⚠️ FRPC перезапущен на *$(uname -n)*"
        /etc/init.d/frpc restart
    fi
elif [ "$1" = "info" ]; then
    IP=$(wget -qO- https://api.ipify.org)
    send "📊 *$(uname -n)*\n\n📡 IP: $IP"
fi
EOF

chmod +x "$UTIL_SCRIPT"

# ===============================
# ⏱ cron
# ===============================
( crontab -l 2>/dev/null | grep -q "$UTIL_SCRIPT check" ) || \
( crontab -l 2>/dev/null; echo "*/1 * * * * $UTIL_SCRIPT check" ) | crontab -

/etc/init.d/cron restart

# ===============================
# 📣 Финал
# ===============================
EXT_IP=$(wget -qO- https://api.ipify.org)

send_telegram "✅ *FRPC установлен*

📟 *Устройство:* $DEVICE_NAME
🔹 *Luci:* http://router.kv9.ru:$LUCi_PORT
🔹 *SSH:* http://router.kv9.ru:$SSH_PORT
📡 *Внешний IP:* $EXT_IP"

echo -e "${GREEN}Установка завершена.${NC}"
