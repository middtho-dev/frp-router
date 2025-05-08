#!/bin/bash
#
# install.sh — установка frpc + watchdog + Telegram‑уведомления
# Обновлено: 2025‑05‑08

set -e

# === Цвета ===
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# === Параметры ===
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
CRON_FILE="/etc/cron.d/frpc_watchdog"
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"

# === Проверка утилит ===
echo -e "${GREEN}Проверяю curl и wget...${NC}"
for cmd in curl wget; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}$cmd не найден, устанавливаю...${NC}"
    opkg update && opkg install $cmd
  fi
done

# === Скачиваем frpc ===
echo -e "${GREEN}Подготовка каталога и загрузка frpc...${NC}"
mkdir -p "$FRP_DIR"
cd "$FRP_DIR"

if [ -f frpc ]; then
  echo -e "${RED}Удаляю старый frpc...${NC}"
  rm -f frpc
fi

curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o frpc \
  && echo -e "${GREEN}frpc скачан.${NC}" \
  || { echo -e "${RED}Ошибка загрузки frpc!${NC}"; exit 1; }

chmod +x frpc

# === Конфиг frpc.toml ===
echo -e "${GREEN}Настройка frpc.toml...${NC}"
read -p "Имя прокси Luci (например: Home_Luci): " luci_name
read -p "Удалённый порт Luci (например: 8081): " luci_port
read -p "Имя прокси SSH (например: Home_SSH): " ssh_name
read -p "Удалённый порт SSH (например: 2201): " ssh_port

cat > frpc.toml <<EOF
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

echo -e "${GREEN}frpc.toml создан.${NC}"

# === Init.d скрипт ===
echo -e "${GREEN}Создание /etc/init.d/frpc...${NC}"
cat > "$INIT_SCRIPT" <<'EOF'
#!/bin/sh /etc/rc.common
START=97
STOP=50
USE_PROCD=1

NAME=frpc
PROG=/root/frp/frpc
CONFIG_FILE=/root/frp/frpc.toml

start_service() {
    procd_open_instance
    procd_set_param command "$PROG" -c "$CONFIG_FILE"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile "/var/run/$NAME.pid"
    procd_close_instance
}

shutdown() {
    killall "$NAME"
}

service_triggers() {
    procd_add_reload_trigger "$NAME"
}
EOF

chmod +x "$INIT_SCRIPT"
/etc/init.d/frpc enable
/etc/init.d/frpc start

# === Watchdog‑скрипт ===
echo -e "${GREEN}Создание watchdog скрипта...${NC}"
cat > "$WATCHDOG_SCRIPT" <<EOF
#!/bin/sh
# frpc_watchdog.sh — проверяет и перезапускает frpc, шлёт Telegram‑уведомления

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRP_BIN="$FRP_DIR/frpc"
LOG_FILE="/root/frpc_watchdog.log"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')

echo "\$DATE_NOW Проверка frpc..." >> "\$LOG_FILE"

if ! pgrep -f "\$FRP_BIN" > /dev/null; then
    MSG="⚠️ \$DATE_NOW FRPC не работает на \$(uname -n)! Перезапускаю..."
    echo "\$MSG" >> "\$LOG_FILE"
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
        -d chat_id="\$CHAT_ID" \
        -d text="\$MSG"

    /etc/init.d/frpc restart && sleep 5

    if pgrep -f "\$FRP_BIN" > /dev/null; then
        MSG="✅ \$DATE_NOW FRPC успешно перезапущен."
    else
        MSG="❌ \$DATE_NOW Ошибка: FRPC не запустился!"
    fi
    echo "\$MSG" >> "\$LOG_FILE"
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
        -d chat_id="\$CHAT_ID" \
        -d text="\$MSG"
else
    MSG="✅ \$DATE_NOW FRPC работает."
    echo "\$MSG" >> "\$LOG_FILE"
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"

# === Системный cron (каждую минуту) ===
echo -e "${GREEN}Настройка cron каждые 1 минуту...${NC}"
cat > "$CRON_FILE" <<EOF
* * * * * root $WATCHDOG_SCRIPT >> /var/log/frpc_watchdog.log 2>&1
EOF
chmod 644 "$CRON_FILE"

echo -e "${GREEN}Установка и настройка завершены!${NC}"
