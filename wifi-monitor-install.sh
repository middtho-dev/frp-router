#!/bin/sh

# Конфигурация
BOT_TOKEN='6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY'
ADMIN_CHAT_ID='382094545'
HOSTNAME="$(uci get system.@system[0].hostname)"

send_telegram() {
    local MSG="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${ADMIN_CHAT_ID}" \
        -d "text=${MSG}" \
        -d "disable_notification=true" \
        -d "parse_mode=Markdown"
}

echo "📦 Обновление пакетов и установка зависимостей..."
opkg update
opkg install iw curl arp-scan

echo "📝 Создание скрипта мониторинга..."
cat << 'EOF' > /usr/bin/wifi-monitor.sh
#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
HOSTNAME="$(uci get system.@system[0].hostname)"

send_msg() {
    local MSG="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${MSG}" \
        -d "disable_notification=true" \
        -d "parse_mode=Markdown"
}

get_connected_clients() {
    iwinfo | grep 'ESSID' | awk -F': ' '{print $2}' | while read SSID; do
        for iface in $(iw dev | awk '/Interface/ {print $2}'); do
            iw dev "$iface" station dump 2>/dev/null | grep Station | awk '{print $2}'
        done
    done
}

# Словарь MAC->IP
declare_clients() {
    arp-scan --interface=br-lan --localnet 2>/dev/null | awk '/^[0-9]/ {print $1 "|" $2}' > /tmp/mac_list.txt
}

# Начальное состояние
declare_clients
get_connected_clients > /tmp/clients_old.txt

while true; do
    sleep 5
    get_connected_clients > /tmp/clients_new.txt
    declare_clients

    join=$(grep -Fxv -f /tmp/clients_old.txt /tmp/clients_new.txt)
    leave=$(grep -Fxv -f /tmp/clients_new.txt /tmp/clients_old.txt)

    for mac in $join; do
        ip=$(grep -i "$mac" /tmp/mac_list.txt | cut -d"|" -f1)
        name=$(grep -i "$mac" /tmp/mac_list.txt | cut -d"|" -f2)
        send_msg "✅ *[$HOSTNAME]* Новое подключение:\n📡 *MAC:* \`$mac\`\n🌐 *IP:* \`$ip\`\n🏷️ *Устройство:* $name"
    done

    for mac in $leave; do
        send_msg "❌ *[$HOSTNAME]* Отключение клиента:\n📡 *MAC:* \`$mac\`"
    done

    mv /tmp/clients_new.txt /tmp/clients_old.txt
done
EOF

chmod +x /usr/bin/wifi-monitor.sh

echo "🧩 Создание init-скрипта..."
cat << 'EOF' > /etc/init.d/wifi_monitor
#!/bin/sh /etc/rc.common
# WiFi Monitor init

START=99

start() {
    echo "▶️ Запуск wifi-мониторинга..."
    /usr/bin/wifi-monitor.sh &
}

stop() {
    echo "⏹️ Остановка wifi-мониторинга..."
    pkill -f wifi-monitor.sh
}
EOF

chmod +x /etc/init.d/wifi_monitor
/etc/init.d/wifi_monitor enable
/etc/init.d/wifi_monitor start

send_telegram "⚙️ *[$HOSTNAME]* WiFi-мониторинг установлен и запущен 🎉📡"
echo "✅ Готово. Мониторинг активен."
