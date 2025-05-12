#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(uname -n)

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$1"
}

get_status() {
    uptime_info=$(uptime | awk -F'up ' '{print $2}' | cut -d',' -f1)
    load=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1)
    cores=$(grep -c ^processor /proc/cpuinfo)
    cpu_load=$(awk -v l="$load" -v c="$cores" 'BEGIN { printf "%.0f%%", (c > 0 ? (l/c)*100 : 0) }')
    ram_free=$(free | awk '/Mem:/ {printf "%.0f", $4/1024}')
    ram_total=$(free | awk '/Mem:/ {printf "%.0f", $2/1024}')
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    disk_total=$(df -h / | awk 'NR==2 {print $2}')
    ext_ip=$(wget -qO- https://api.ipify.org)

    echo "📊 *Состояние системы на $HOSTNAME:*

📡 *Внешний IP*: $ext_ip
💽 *RAM*: ${ram_free}Mb / ${ram_total}Mb
📦 *Диск*: ${disk_free} / ${disk_total}
🕒 *Uptime*: $uptime_info
🔥 *CPU*: $cpu_load"
}

watch_auth_logins() {
    logread -f | while read -r line; do
        if echo "$line" | grep -q -iE "Accepted password for|dropbear.*Password auth succeeded"; then
            user=$(echo "$line" | grep -oE 'user \S+' | awk '{print $2}')
            ip=$(echo "$line" | grep -oE 'from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')
            send_telegram "✅ *SSH вход* на *$HOSTNAME* от \`$user\` с IP \`$ip\`"
        elif echo "$line" | grep -qi "luci"; then
            if echo "$line" | grep -qi "authentication failure"; then
                send_telegram "❌ *Ошибка входа в LuCI* на *$HOSTNAME*:\n\`$line\`"
            elif echo "$line" | grep -qi "Authenticated successfully"; then
                send_telegram "✅ *Вход в LuCI* на *$HOSTNAME*:\n\`$line\`"
            fi
        fi
    done
}

if [ "$1" = "check" ]; then
    if ! pidof frpc > /dev/null; then
        send_telegram "⚠️ *$DATE_NOW*

FRPC на *$HOSTNAME* не работает. 
Перезапуск..."
        /etc/init.d/frpc restart
        sleep 5
        if pidof frpc > /dev/null; then
            send_telegram "✅ *FRPC* на *$HOSTNAME* успешно запущен.

$(get_status)"
        else
            send_telegram "❌ Не удалось запустить FRPC на *$HOSTNAME*!"
        fi
    fi

    # Запуск мониторинга логинов
    if ! pgrep -f "logread -f" | grep -q .; then
        watch_auth_logins &
    fi

elif [ "$1" = "info" ]; then
    send_telegram "$(get_status)"
fi