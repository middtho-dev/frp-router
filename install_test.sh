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

# Функция проверки порта
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}Ошибка: Некорректный порт. Введите число от 1 до 65535${NC}"
        exit 1
    fi
}

# Функция отправки в Telegram с экранированием
send_telegram() {
    local message=$(echo "$1" | sed 's/_/\\_/g; s/*/\\*/g; s/`/\\`/g; s/-/\\-/g')
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" >/dev/null
}

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
mkdir -p "$FRP_DIR"
cd "$FRP_DIR" || exit 1

echo -e "${GREEN}Проверяю, не занят ли файл frpc...${NC}"
if [ -f "$FRP_DIR/frpc" ]; then
    echo -e "${RED}Файл frpc уже существует, пытаюсь удалить...${NC}"
    rm -f "$FRP_DIR/frpc" || {
        echo -e "${RED}Не удалось удалить файл frpc. Прерываю выполнение.${NC}"
        exit 1
    }
    echo -e "${GREEN}Файл frpc успешно удалён.${NC}"
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
if chmod +x "$FRP_DIR/frpc"; then
    echo -e "${GREEN}Права успешно установлены на frpc.${NC}"
else
    echo -e "${RED}Не удалось установить права на frpc.${NC}"
    exit 1
fi

# Запрашиваем параметры для frpc.toml
echo -e "${GREEN}Введите имя для прокси Luci (например: Home Luci):${NC}"
read -r luci_name
echo -e "${GREEN}Введите порт для прокси Luci (например: 8081):${NC}"
read -r luci_port
validate_port "$luci_port"

echo -e "${GREEN}Введите имя для прокси SSH (например: Home SSH):${NC}"
read -r ssh_name
echo -e "${GREEN}Введите порт для прокси SSH (например: 2201):${NC}"
read -r ssh_port
validate_port "$ssh_port"

# Создаем frpc.toml
echo -e "${GREEN}Создаю файл frpc.toml...${NC}"
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

# Проверка на успешное создание frpc.toml
if [[ -f "$FRP_DIR/frpc.toml" ]]; then
    echo -e "${GREEN}Файл frpc.toml успешно создан.${NC}"
else
    echo -e "${RED}Не удалось создать файл frpc.toml.${NC}"
    exit 1
fi

# Создаем init.d скрипт
echo -e "${GREEN}Создаю init.d скрипт...${NC}"
cat <<EOF > "$INIT_SCRIPT"
#!/bin/sh /etc/rc.common

START=97
STOP=50
USE_PROCD=1

NAME=frpc
PROG="$FRP_DIR/frpc"
CONFIG_FILE="$FRP_DIR/frpc.toml"

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

# Устанавливаем права на init.d скрипт
echo -e "${GREEN}Устанавливаю права на init.d скрипт...${NC}"
if chmod +x "$INIT_SCRIPT"; then
    echo -e "${GREEN}Права успешно установлены на init.d скрипт.${NC}"
else
    echo -e "${RED}Не удалось установить права на init.d скрипт.${NC}"
    exit 1
fi

# Добавляем в автозагрузку
echo -e "${GREEN}Добавляю в автозагрузку...${NC}"
if /etc/init.d/frpc enable; then
    echo -e "${GREEN}Служба успешно добавлена в автозагрузку.${NC}"
else
    echo -e "${RED}Не удалось добавить службу в автозагрузку.${NC}"
    exit 1
fi

# Запускаем сервис
echo -e "${GREEN}Запускаю сервис...${NC}"
if /etc/init.d/frpc start; then
    echo -e "${GREEN}Сервис успешно запущен.${NC}"
    IP_ADDR=$(curl -s ifconfig.me)
    send_telegram "✅ FRPC успешно установлен на \$(uname -n) (${IP_ADDR})
- Luci: \`${luci_name}\` порт \`${luci_port}\`
- SSH: \`${ssh_name}\` порт \`${ssh_port}\`"
else
    echo -e "${RED}Не удалось запустить сервис.${NC}"
    exit 1
fi

# Скрипт мониторинга и перезапуска службы (watchdog)
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"

echo -e "${GREEN}Создаю скрипт для мониторинга и перезапуска frpc...${NC}"

cat <<EOF > "$WATCHDOG_SCRIPT"
#!/bin/sh

# Telegram Bot Token and Chat ID
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
LOG_FILE="/root/frpc_watchdog.log"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')
IP_ADDR=\$(curl -s ifconfig.me)

# Проверка процесса frpc
echo "\$DATE_NOW - Проверка frpc..." >> "\$LOG_FILE"

if ! pgrep -f "frpc.*toml" > /dev/null; then
    MESSAGE="⚠️ *\$(uname -n | sed 's/_/\\\\_/g') (\$IP_ADDR)*
FRPC не работает!
Время: \$DATE_NOW
Попытка перезапуска..."
    echo "\$MESSAGE" >> "\$LOG_FILE"

    RESPONSE=\$(curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
        -d chat_id="\$CHAT_ID" \
        -d text="\$MESSAGE" \
        -d parse_mode="Markdown")

    if [ -x "/etc/init.d/frpc" ]; then
        /etc/init.d/frpc restart
        sleep 5
        if pgrep -f "frpc.*toml" > /dev/null; then
            STATUS=\$(/etc/init.d/frpc status | grep 'is running')
            MESSAGE="✅ *\$(uname -n | sed 's/_/\\\\_/g') (\$IP_ADDR)*
FRPC успешно перезапущен!
Статус: \$STATUS"
        else
            MESSAGE="❌ *\$(uname -n | sed 's/_/\\\\_/g') (\$IP_ADDR)*
Ошибка перезапуска FRPC!
Проверьте систему!"
        fi
        echo "\$MESSAGE" >> "\$LOG_FILE"
        RESPONSE=\$(curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
            -d chat_id="\$CHAT_ID" \
            -d text="\$MESSAGE" \
            -d parse_mode="Markdown")
    fi
else
    echo "✅ \$DATE_NOW - FRPC работает." >> "\$LOG_FILE"
fi
EOF

# Даем права на watchdog скрипт
echo -e "${GREEN}Устанавливаю права на скрипт watchdog...${NC}"
if chmod +x "$WATCHDOG_SCRIPT"; then
    echo -e "${GREEN}Права успешно установлены на скрипт watchdog.${NC}"
else
    echo -e "${RED}Не удалось установить права на скрипт watchdog.${NC}"
    exit 1
fi

# Настроим cron для запуска watchdog каждые 5 минут
echo -e "${GREEN}Настраиваю cron для мониторинга...${NC}"
if ! crontab -l | grep -q "$WATCHDOG_SCRIPT"; then
    (crontab -l; echo "*/5 * * * * $WATCHDOG_SCRIPT") | crontab -
    echo -e "${GREEN}Cron для мониторинга успешно настроен.${NC}"
else
    echo -e "${RED}Cron для мониторинга уже настроен.${NC}"
fi

echo -e "${GREEN}Готово! Скрипт успешно установлен и настроен.${NC}"