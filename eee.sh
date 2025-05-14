#!/bin/sh

BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=Markdown \
        --data-urlencode "text=$1"
}

get_status() {
    uptime_info=$(uptime | awk -F'up ' '{print $2}' | cut -d',' -f1)

    # Получаем load average и количество ядер
    load=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1)
    cores=$(grep -c ^processor /proc/cpuinfo)
    if [ "$cores" -gt 0 ]; then
        cpu_load=$(awk -v l="$load" -v c="$cores" 'BEGIN { printf "%.0f%%", (l/c)*100 }')
    else
        cpu_load="n/a"
    fi

    # RAM
    ram_free=$(free | awk '/Mem:/ {printf "%.0f", $4/1024}')
    ram_total=$(free | awk '/Mem:/ {printf "%.0f", $2/1024}')

    # Диск
    disk_free=$(df -h / | awk 'NR==2 {print $4}')
    disk_total=$(df -h / | awk 'NR==2 {print $2}')

    # Внешний IP
    ext_ip=$(wget -qO- http://api.ipify.org)

    echo "📊 *Состояние системы:*

📡 *Внешний IP*: $ext_ip
💽 *RAM*: ${ram_free}Mb / ${ram_total}Mb
📦 *Диск*: ${disk_free} / ${disk_total}
🕒 *Uptime*: $uptime_info
🔥 *CPU*: $cpu_load"
}

sync_time() {
    sleep 10
    while true; do
        if ping -c 1 -W 3 0.openwrt.pool.ntp.org > /dev/null; then
            ntpd -q -n \
                -p 0.openwrt.pool.ntp.org \
                -p 1.openwrt.pool.ntp.org \
                -p 2.openwrt.pool.ntp.org \
                -p 3.openwrt.pool.ntp.org
            send_telegram "⏰ Время успешно синхронизировано на *$(uname -n)*"
            break
        else
            send_telegram "⚠️ Не удалось синхронизировать время на *$(uname -n)*. Повтор через 10 секунд."
            sleep 10
        fi
    done
}

if [ "$1" = "check" ]; then
    if ! pidof frpc > /dev/null; then
        send_telegram "⚠️ *$DATE_NOW*

FRPC на *$(uname -n)* не работает. 
Перезапуск..."
        /etc/init.d/frpc restart
        sleep 5
        if pidof frpc > /dev/null; then
            send_telegram "✅ *FRPC* на *$(uname -n)* успешно запущен.

$(get_status)"
        else
            send_telegram "❌ Не удалось запустить FRPC на *$(uname -n)*!"
        fi
    fi
    sync_time
elif [ "$1" = "info" ]; then
    HOSTNAME=$(uname -n)
    send_telegram "📊 Состояние системы на *$HOSTNAME*

$(get_status)"
fi
