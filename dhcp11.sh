#!/bin/sh

echo "[*] Что вы хотите сделать?"
echo "[1] Установить DHCP Telegram Monitor"
echo "[2] Удалить DHCP Telegram Monitor"
echo -n "Введите номер: "
read choice

if [ "$choice" -eq 2 ]; then
    echo "[*] Удаление DHCP Telegram Monitor..."

    # Остановка сервисов
    /etc/init.d/dhcp-monitor stop

    # Удаление автозапуска
    /etc/init.d/dhcp-monitor disable

    # Удаление файлов скрипта
    rm -f /etc/init.d/dhcp-monitor
    rm -f /etc/dhcp-monitor/dhcp-monitor.sh

    # Удаление конфигурации
    rm -f /tmp/dhcp_monitor_clients
    rm -f /tmp/dhcp_monitor_current

    # Удаление cron-задачи
    sed -i '/dhcp-monitor-check/d' /etc/crontabs/root
    /etc/init.d/cron restart

    echo "[✓] Удаление завершено."
    exit 0
fi

if [ "$choice" -eq 1 ]; then
    echo "[*] Установка DHCP Telegram Monitor..."

    # Проверка и установка coreutils-comm (если отсутствует)
    if ! command -v comm >/dev/null 2>&1; then
        echo "[*] Обновление opkg и установка зависимостей..."
        opkg update
        opkg install coreutils-comm || {
            echo "[X] Не удалось установить coreutils-comm. Установите вручную."
            exit 1
        }
    fi

    # Создаём директорию
    mkdir -p /etc/dhcp-monitor

    # Основной скрипт
    cat << 'EOF' > /etc/dhcp-monitor/dhcp-monitor.sh
#!/bin/sh

TOKEN='6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY'
CHAT_ID='382094545'

DEVICE_NAME=$(uci get system.@system[0].hostname)  # Получаем имя устройства через uci

send_msg() {
    TEXT="$1"
    curl -s -m 5 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${TEXT}" \
        -d "parse_mode=Markdown" \
        -d "disable_notification=false" >/dev/null
}

# Получаем текущие DHCP клиенты
get_current_clients() {
    awk '{print $2}' /tmp/dhcp.leases | sort
}

# Получаем информацию о DHCP-клиенте по MAC-адресу
get_ip_hostname() {
    MAC="$1"
    grep -i "$MAC" /tmp/dhcp.leases | awk '{printf "%s|%s|%s", $3, $4, $1}'  # Возвращаем IP, имя устройства и время аренды
}

# Преобразование времени аренды в формат часы:минуты:секунды
convert_time() {
    SECONDS="$1"
    HOURS=$((SECONDS / 3600))
    MINUTES=$(( (SECONDS % 3600) / 60 ))
    SECONDS=$((SECONDS % 60))
    printf "%02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS
}

CLIENT_LIST="/tmp/dhcp_monitor_clients"
touch "$CLIENT_LIST"

# Использование обычного ассоциативного массива для хранения данных
client_info=""

while true; do
    CURRENT_LIST="/tmp/dhcp_monitor_current"
    get_current_clients > "$CURRENT_LIST"

    # Обработка новых подключений
    for mac in $(comm -13 "$CLIENT_LIST" "$CURRENT_LIST"); do
        info=$(get_ip_hostname "$mac")
        ip=$(echo "$info" | cut -d'|' -f1)
        name=$(echo "$info" | cut -d'|' -f2)
        timestamp=$(echo "$info" | cut -d'|' -f3)  # Время аренды в секундах

        [ -z "$ip" ] && ip="Неизвестен"
        [ -z "$name" ] && name="Неизвестно"

        # Конвертация времени аренды в формат часы:минуты:секунды
        formatted_time=$(convert_time "$timestamp")

        # Сохранение информации о подключении для последующего использования при отключении
        client_info="$client_info$mac|$name|$ip|$formatted_time"$'\n'

        send_msg "✅ *Подключился к $DEVICE_NAME*
📱 Имя: *$name*
🌐 IP: \`$ip\`
🔗 MAC: \`$mac\`
⏰ Время подключения: $formatted_time"
    done

    # Обработка отключений
    for mac in $(comm -23 "$CLIENT_LIST" "$CURRENT_LIST"); do
        # Используем сохраненную информацию о клиенте для отключившихся устройств
        line=$(echo "$client_info" | grep "^$mac|")
        if [ -n "$line" ]; then
            name=$(echo "$line" | cut -d'|' -f2)
            ip=$(echo "$line" | cut -d'|' -f3)
            # При отключении не показываем время последней аренды
            send_msg "❌ *Отключился от $DEVICE_NAME*
💻 Имя: *$name*
🌐 IP: \`$ip\`
🔗 MAC: \`$mac\`"
            client_info=$(echo "$client_info" | grep -v "^$mac|")  # Убираем информацию о клиенте
        fi
    done

    mv "$CURRENT_LIST" "$CLIENT_LIST"
    sleep 2
done
EOF

    chmod +x /etc/dhcp-monitor/dhcp-monitor.sh

    # Init.d
    cat << 'EOF' > /etc/init.d/dhcp-monitor
#!/bin/sh /etc/rc.common

START=95
STOP=10

start() {
    echo "[+] Запуск dhcp-monitor"
    /etc/dhcp-monitor/dhcp-monitor.sh & 
}

stop() {
    echo "[-] Остановка dhcp-monitor"
    killall dhcp-monitor.sh 2>/dev/null
}
EOF

    chmod +x /etc/init.d/dhcp-monitor
    /etc/init.d/dhcp-monitor enable
    /etc/init.d/dhcp-monitor start

    # Подготовка crontab
    mkdir -p /etc/crontabs
    touch /etc/crontabs/root

    # Cron-задача для надёжного автозапуска
    grep -q "dhcp-monitor-check" /etc/crontabs/root || {
        echo "*/2 * * * * grep -q dhcp-monitor.sh /proc/*/cmdline || /etc/init.d/dhcp-monitor start # dhcp-monitor-check" >> /etc/crontabs/root
        /etc/init.d/cron restart
    }

    echo "[✓] Установка завершена. Мониторинг DHCP клиентов активен."
    exit 0
fi

echo "[X] Неверный выбор. Пожалуйста, выберите 1 или 2."
exit 1
