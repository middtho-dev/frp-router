#!/bin/sh

echo "[*] Установка Wi-Fi Telegram Monitor..."

# Создаём папку
mkdir -p /etc/wifi-monitor

# Основной мониторинг-скрипт
cat << 'EOF' > /etc/wifi-monitor/wifi-monitor.sh
#!/bin/sh

TOKEN='6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY'
CHAT_ID='382094545'

send_msg() {
    TEXT="$1"
    curl -s -m 5 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${TEXT}" \
        -d "parse_mode=Markdown" \
        -d "disable_notification=false" >/dev/null
}

get_current_clients() {
    iwinfo | grep 'ESSID' >/dev/null 2>&1 || exit 1
    for iface in $(iw dev | grep Interface | awk '{print $2}'); do
        iw dev "$iface" station dump 2>/dev/null | grep '^Station' | awk '{print $2}'
    done
}

get_ip_hostname() {
    MAC="$1"
    grep -i "$MAC" /tmp/dhcp.leases | awk '{printf "%s|%s", $3, $2}'
}

CLIENT_LIST="/tmp/wifi_monitor_clients"
touch "$CLIENT_LIST"

while true; do
    CURRENT_LIST="/tmp/wifi_monitor_current"
    get_current_clients | sort > "$CURRENT_LIST"

    # Новые подключения
    for mac in $(comm -13 "$CLIENT_LIST" "$CURRENT_LIST"); do
        info=$(get_ip_hostname "$mac")
        ip=$(echo "$info" | cut -d'|' -f1)
        name=$(echo "$info" | cut -d'|' -f2)

        [ -z "$ip" ] && ip="Неизвестен"
        [ -z "$name" ] && name="Неизвестно"

        send_msg "✅ *Новое Wi-Fi подключение*
📱 Имя: *$name*
🌐 IP: \`$ip\`
🔗 MAC: \`$mac\`"
    done

    # Отключения
    for mac in $(comm -23 "$CLIENT_LIST" "$CURRENT_LIST"); do
        info=$(get_ip_hostname "$mac")
        ip=$(echo "$info" | cut -d'|' -f1)
        name=$(echo "$info" | cut -d'|' -f2)

        [ -z "$ip" ] && ip="Неизвестен"
        [ -z "$name" ] && name="Неизвестно"

        send_msg "❌ *Wi-Fi отключение*
💻 Имя: *$name*
🌐 IP: \`$ip\`
🔗 MAC: \`$mac\`"
    done

    mv "$CURRENT_LIST" "$CLIENT_LIST"
    sleep 10
done
EOF

chmod +x /etc/wifi-monitor/wifi-monitor.sh

# Init.d-скрипт
cat << 'EOF' > /etc/init.d/wifi-monitor
#!/bin/sh /etc/rc.common

START=95
STOP=10

start() {
    echo "[+] Запуск wifi-monitor"
    /etc/wifi-monitor/wifi-monitor.sh &
}

stop() {
    echo "[-] Остановка wifi-monitor"
    killall wifi-monitor.sh 2>/dev/null
}
EOF

chmod +x /etc/init.d/wifi-monitor
/etc/init.d/wifi-monitor enable
/etc/init.d/wifi-monitor start

# Cron-задача как резервный запуск
grep -q "wifi-monitor-check" /etc/crontabs/root || {
    echo "*/2 * * * * grep -q wifi-monitor.sh /proc/*/cmdline || /etc/init.d/wifi-monitor start # wifi-monitor-check" >> /etc/crontabs/root
    /etc/init.d/cron restart
}

echo "[✓] Установка завершена. Мониторинг Wi-Fi клиентов активен."
