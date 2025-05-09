#!/bin/sh

BOT_TOKEN='6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY'
ADMIN_CHAT_ID='382094545'
SERVICE_NAME='wifi_monitor'
INIT_PATH="/etc/init.d/$SERVICE_NAME"

send_telegram() {
    local MSG="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${ADMIN_CHAT_ID}" \
        -d "text=${MSG}" \
        -d "disable_notification=true" \
        -d "parse_mode=Markdown"
}

install_packages() {
    opkg update
    opkg install iw arp-scan curl
}

create_monitor_script() {
    cat << 'EOF' > /usr/bin/wifi-monitor.sh
#!/bin/sh

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

send_telegram "📡 *[$HOSTNAME]* WiFi-мониторинг запущен ✅"

touch /tmp/known_clients

while true; do
    iw dev wlan0 station dump | grep '^Station' | awk '{print $2}' > /tmp/current_clients
    for MAC in $(cat /tmp/current_clients); do
        if ! grep -q "$MAC" /tmp/known_clients; then
            IP=$(ip neigh | grep "$MAC" | awk '{print $1}')
            NAME=$(grep "$MAC" /tmp/dhcp.leases 2>/dev/null | awk '{print $4}')
            [ -z "$NAME" ] && NAME="неизвестно"
            [ -z "$IP" ] && IP="нет IP"
            MSG="✅ *[$HOSTNAME]* Подключено новое устройство:\n\n🖥️ *Имя:* $NAME\n🌐 *IP:* $IP\n🔗 *MAC:* $MAC"
            send_telegram "$MSG"
            echo "$MAC" >> /tmp/known_clients
        fi
    done

    for MAC in $(cat /tmp/known_clients); do
        if ! grep -q "$MAC" /tmp/current_clients; then
            MSG="❌ *[$HOSTNAME]* Устройство отключено:\n\n🔗 *MAC:* $MAC"
            send_telegram "$MSG"
            sed -i "/$MAC/d" /tmp/known_clients
        fi
    done

    sleep 5
done
EOF

    chmod +x /usr/bin/wifi-monitor.sh
}

create_init_script() {
    cat << EOF > "$INIT_PATH"
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1
NAME=wifi_monitor

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/wifi-monitor.sh
    procd_set_param respawn
    procd_close_instance
}
EOF

    chmod +x "$INIT_PATH"
    /etc/init.d/$SERVICE_NAME enable
}

main() {
    install_packages
    create_monitor_script
    create_init_script
    /etc/init.d/$SERVICE_NAME start
    send_telegram "⚙️ *[$(uci get system.@system[0].hostname)]* Установлен и запущен WiFi-мониторинг 📶"
}

main
