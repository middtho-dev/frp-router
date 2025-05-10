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
    # Извлекаем MAC-адреса и их аренды, сортируем
    awk '{print $2}' /tmp/dhcp.leases | sort
}

# Получаем информацию о DHCP-клиенте по MAC-адресу
get_ip_hostname() {
    MAC="$1"
    grep -i "$MAC" /tmp/dhcp.leases | awk '{printf "%s|%s|%s", $3, $4, $1}'  # Возвращаем IP, имя устройства и время аренды
}

CLIENT_LIST="/tmp/dhcp_monitor_clients"
touch "$CLIENT_LIST"

# Функция для очистки истёкших клиентов (если их нет в /tmp/dhcp.leases)
clean_expired_clients() {
    # Выбираем только тех клиентов, которых нет в текущем списке
    for mac in $(cat "$CLIENT_LIST"); do
        if ! grep -q "$mac" /tmp/dhcp.leases; then
            # Если клиента нет в /tmp/dhcp.leases, это значит, что аренда истекла
            send_msg "❌ *Отключился от $DEVICE_NAME*
🔗 MAC: \`$mac\`
⏰ Время последней аренды истекло"
            # Удаляем его из списка клиентов
            sed -i "/$mac/d" "$CLIENT_LIST"
        fi
    done
}

while true; do
    CURRENT_LIST="/tmp/dhcp_monitor_current"
    get_current_clients > "$CURRENT_LIST"

    # Проверяем и очищаем истёкшие аренды
    clean_expired_clients

    # Обработка новых подключений
    for mac in $(comm -13 "$CLIENT_LIST" "$CURRENT_LIST"); do
        info=$(get_ip_hostname "$mac")
        ip=$(echo "$info" | cut -d'|' -f1)
        name=$(echo "$info" | cut -d'|' -f2)
        timestamp=$(echo "$info" | cut -d'|' -f3)  # Время аренды

        [ -z "$ip" ] && ip="Неизвестен"
        [ -z "$name" ] && name="Неизвестно"

        send_msg "✅ *Подключился к $DEVICE_NAME*
📱 Имя: *$name*
🌐 IP: \`$ip\`
🔗 MAC: \`$mac\`
⏰ Время подключения: $timestamp"

        # Добавляем нового клиента в список отслеживаемых
        echo "$mac" >> "$CLIENT_LIST"
    done

    # Обработка отключений (клиенты, которых нет в списке текущих)
    for mac in $(comm -23 "$CLIENT_LIST" "$CURRENT_LIST"); do
        info=$(get_ip_hostname "$mac")
        ip=$(echo "$info" | cut -d'|' -f1)
        name=$(echo "$info" | cut -d'|' -f2)
        timestamp=$(echo "$info" | cut -d'|' -f3)  # Время аренды

        [ -z "$ip" ] && ip="Неизвестен"
        [ -z "$name" ] && name="Неизвестно"

        send_msg "❌ *Отключился от $DEVICE_NAME*
💻 Имя: *$name*
🌐 IP: \`$ip\`
🔗 MAC: \`$mac\`
⏰ Время последней аренды: $timestamp"

        # Удаляем клиента из отслеживаемого списка
        sed -i "/$mac/d" "$CLIENT_LIST"
    done

    mv "$CURRENT_LIST" "$CLIENT_LIST"
    sleep 2
done
