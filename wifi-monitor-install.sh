#!/bin/sh

# Переменные
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
DEVICE_NAME=$(uci get system.@system[0].hostname)

# Функция для отправки сообщений в Telegram
send_telegram_message() {
    local message=$1
    local api_url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local data="chat_id=${CHAT_ID}&text=${message}"
    curl -s -X POST $api_url -d $data
}

# Устанавливаем необходимые пакеты
echo "Установка необходимых пакетов для WiFi мониторинга..."
opkg update
opkg install hostapd-utils curl

# Создаём скрипт мониторинга
cat > /etc/init.d/wifi-monitor << EOF
#!/bin/sh /etc/rc.common
# Скрипт для мониторинга WiFi

START=99
STOP=10

start() {
    send_telegram_message "Мониторинг WiFi запущен на устройстве ${DEVICE_NAME}"
    while true; do
        # Слежение за подключениями через hostapd-cli
        hostapd_cli -i wlan0 all_sta | while read line; do
            if echo "$line" | grep -q "STA"; then
                MAC=$(echo "$line" | awk '{print $2}')
                IP=$(echo "$line" | awk '{print $3}')
                DEVICE=$(hostapd_cli -i wlan0 sta_info $MAC | grep 'device' | cut -d' ' -f2)
                MESSAGE="Устройство подключено:\nMAC: $MAC\nIP: $IP\nDevice: $DEVICE\nHost: ${DEVICE_NAME}"
                send_telegram_message "$MESSAGE"
            elif echo "$line" | grep -q "DISCONNECTED"; then
                MAC=$(echo "$line" | awk '{print $2}')
                MESSAGE="Устройство отключено:\nMAC: $MAC\nHost: ${DEVICE_NAME}"
                send_telegram_message "$MESSAGE"
            fi
        done
        sleep 5
    done
}

stop() {
    send_telegram_message "Мониторинг WiFi остановлен на устройстве ${DEVICE_NAME}"
    # Дополнительные действия при остановке мониторинга
}

EOF

# Делаем скрипт исполнимым
chmod +x /etc/init.d/wifi-monitor

# Добавляем в автозагрузку
/etc/init.d/wifi-monitor enable

# Запускаем мониторинг
/etc/init.d/wifi-monitor start

echo "WiFi мониторинг установлен и запущен с автозагрузкой."
