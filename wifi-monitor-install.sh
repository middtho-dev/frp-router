#!/bin/sh

# WiFi Monitoring Install Script for OpenWRT
# GitHub: https://github.com/middtho-dev/frp-router/blob/main/wifi-monitor-install.sh

# Telegram Bot Configuration
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname 2>/dev/null || echo "OpenWRT")

# Install required packages
opkg update
opkg install hostapd-utils curl

# Create directories and files
mkdir -p /var/log/wifi-monitor
touch /var/log/wifi-monitor/debug.log
chmod 644 /var/log/wifi-monitor/debug.log

# Create hostapd event handler
cat << 'EOF' > /usr/bin/hostapd-event.sh
#!/bin/sh

# Hostapd Event Handler
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname 2>/dev/null || echo "OpenWRT")
LOG_FILE="/var/log/wifi-monitor/debug.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

send_telegram() {
    local message="$1"
    log "Sending Telegram: $message"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}" \
        -d disable_notification="false" >> $LOG_FILE 2>&1
}

get_client_info() {
    local mac="$1"
    
    # Get IP from ARP table
    local ip=$(ip neigh | grep -i "$mac" | awk '{print $1}')
    [ -z "$ip" ] && ip="N/A"
    
    # Get hostname from DHCP leases
    local host=$(grep -i "$mac" /tmp/dhcp.leases | awk '{print $4}')
    [ -z "$host" ] && host="Unknown"
    
    echo "$ip,$host"
}

case "$1" in
    AP-STA-CONNECTED)
        MAC="$2"
        log "CONNECTED EVENT: MAC=$MAC"
        IFS=, read -r ip host <<< "$(get_client_info "$MAC")"
        send_telegram "🟢 Device connected to ${ROUTER_NAME}:
- Device: ${host}
- MAC: ${MAC}
- IP: ${ip}"
        ;;
    AP-STA-DISCONNECTED)
        MAC="$2"
        log "DISCONNECTED EVENT: MAC=$MAC"
        IFS=, read -r ip host <<< "$(get_client_info "$MAC")"
        send_telegram "🔴 Device disconnected from ${ROUTER_NAME}:
- Device: ${host}
- MAC: ${MAC}
- IP: ${ip}"
        ;;
    MONITOR-STARTED)
        send_telegram "🟢 WiFi Monitoring started on ${ROUTER_NAME}"
        ;;
    *)
        log "UNKNOWN EVENT: $@"
        ;;
esac
EOF

# Create monitoring script
cat << 'EOF' > /usr/bin/wifi-monitor.sh
#!/bin/sh

# WiFi Monitoring Script
LOG_FILE="/var/log/wifi-monitor/debug.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

find_wifi_interfaces() {
    # Method 1: Check running hostapd processes
    interfaces=$(ps | grep hostapd | grep -oE '\-i [^ ]+' | awk '{print $2}' | sort -u)
    
    # Method 2: Check hostapd sockets
    [ -z "$interfaces" ] && interfaces=$(ls /var/run/hostapd/ 2>/dev/null | grep -v '^global$')
    
    # Method 3: Check network interfaces
    [ -z "$interfaces" ] && interfaces=$(iw dev | awk '/Interface/ {print $2}')
    
    echo "$interfaces"
}

log "Starting WiFi monitor script"

# Initial startup notification
/usr/bin/hostapd-event.sh "MONITOR-STARTED"

# Main monitoring loop
while true; do
    INTERFACES=$(find_wifi_interfaces)
    log "Found interfaces: $INTERFACES"
    
    if [ -z "$INTERFACES" ]; then
        log "No active WiFi interfaces found"
        sleep 10
        continue
    fi

    for IFACE in $INTERFACES; do
        if ! pgrep -f "hostapd_cli.*${IFACE}" >/dev/null; then
            log "Starting monitor for $IFACE"
            hostapd_cli -i "$IFACE" -a /usr/bin/hostapd-event.sh >> $LOG_FILE 2>&1 &
        fi
    done
    
    sleep 30
done
EOF

# Set permissions
chmod +x /usr/bin/wifi-monitor.sh
chmod +x /usr/bin/hostapd-event.sh

# Create init script
cat << 'EOF' > /etc/init.d/wifi-monitor
#!/bin/sh /etc/rc.common

START=99
STOP=01

start() {
    echo "Starting WiFi monitoring..."
    /usr/bin/wifi-monitor.sh >> /var/log/wifi-monitor/service.log 2>&1 &
}

stop() {
    echo "Stopping WiFi monitoring..."
    killall wifi-monitor.sh 2>/dev/null
    killall hostapd-event.sh 2>/dev/null
    killall hostapd_cli 2>/dev/null
}

restart() {
    stop
    start
}
EOF

# Enable and start service
chmod +x /etc/init.d/wifi-monitor
/etc/init.d/wifi-monitor enable
/etc/init.d/wifi-monitor restart

echo "Installation complete! Debug logs: tail -f /var/log/wifi-monitor/debug.log"
