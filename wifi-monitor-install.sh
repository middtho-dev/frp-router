#!/bin/sh

# Задаем переменные
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
DEVICE_NAME=$(hostname)  # Имя устройства OpenWrt

# Устанавливаем необходимые пакеты
echo "Установка необходимых пакетов..."
opkg update
opkg install hostapd-utils curl

# Создаем скрипт мониторинга Wi-Fi
cat << 'EOF' > /usr/bin/wifi_monitor.sh
#!/bin/sh

# Получаем список подключенных клиентов
clients=$(hostapd_cli all_sta)

# Цикл для каждого клиента
echo "$clients" | while read client; do
    # Извлекаем MAC, IP и имя устройства
    mac=$(echo "$client" | grep -oP 'sta\=\K([0-9A-F]{2}(:[0-9A-F]{2}){5})')
    ip=$(echo "$client" | grep -oP 'ip\=\K([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)')
    device_name=$(echo "$client" | grep -oP 'name\=\K\w+')

    # Если найдены данные о клиенте
    if [ -n "$mac" ] && [ -n "$ip" ]; then
        # Отправка уведомления о подключении через Telegram
        message="Подключен новый клиент WiFi: \nИмя устройства: $device_name\nMAC-адрес: $mac\nIP-адрес: $ip\nИмя устройства OpenWrt: $DEVICE_NAME"
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id=$CHAT_ID -d text="$message"
    fi
done
EOF

# Делаем скрипт исполнимым
chmod +x /usr/bin/wifi_monitor.sh

# Добавляем скрипт в автозагрузку
echo "Добавляем скрипт в автозагрузку..."
cat << EOF > /etc/init.d/wifi_monitor
#!/bin/sh /etc/rc.common
# Скрипт для запуска Wi-Fi мониторинга

START=99
STOP=10

start() {
    echo "Запуск Wi-Fi мониторинга..."
    /usr/bin/wifi_monitor.sh &
}

stop() {
    echo "Остановка Wi-Fi мониторинга..."
    killall wifi_monitor.sh
}
EOF

# Делаем скрипт автозагрузки исполнимым
chmod +x /etc/init.d/wifi_monitor

# Включаем и запускаем скрипт
/etc/init.d/wifi_monitor enable
/etc/init.d/wifi_monitor start

echo "Wi-Fi мониторинг успешно установлен и запущен."
