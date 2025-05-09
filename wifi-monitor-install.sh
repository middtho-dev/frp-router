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

# Create hostapd event handler
cat << 'EOF' > /usr/bin/hostapd-event.sh
#!/bin/sh

# Hostapd Event Handler
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname 2>/dev/null || echo "OpenWRT")

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}" \
        -d disable_notification="false" > /dev/null
}

get_client_info() {
    local mac="$1"
    # Try to get IP from ARP table
    local ip=$(ip neigh | grep -i "$mac" | awk '{print $1}')
    
    # Try to get hostname from DHCP leases
    local host=$(grep -i "$mac" /tmp/dhcp.leases | awk '{print $4}')
    [ -z "$host" ] && host="Unknown"
    
    echo "$ip,$host"
}

case "$1" in
    AP-STA-CONNECTED)
        MAC="$2"
        IFS=, read -r ip host <<< "$(get_client_info "$MAC")"
        send_telegram "🟢 Device connected to ${ROUTER_NAME}:
- Device: ${host}
- MAC: ${MAC}
- IP: ${ip}"
        ;;
    AP-STA-DISCONNECTED)
        MAC="$2"
        IFS=, read -r ip host <<< "$(get_client_info "$MAC")"
        send_telegram "🔴 Device disconnected from ${ROUTER_NAME}:
- Device: ${host}
- MAC: ${MAC}
- IP: ${ip}"
        ;;
esac
EOF

# Create monitoring script
cat << 'EOF' > /usr/bin/wifi-monitor.sh
#!/bin/sh

# WiFi Monitoring Script
ROUTER_NAME=$(uci get system.@system[0].hostname 2>/dev/null || echo "OpenWRT")

# Find the correct WiFi interface
find_wifi_interface() {
    for iface in $(ls /var/run/hostapd* 2>/dev/null); do
        echo "$iface" | sed 's|/var/run/hostapd/||'
        return 0
    done
    
    for iface in $(iw dev | awk '/Interface/ {print $2}'); do
        if iwconfig "$iface" 2>/dev/null | grep -q "Mode:Master"; then
            echo "$iface"
            return 0
        fi
    done
    
    return 1
}

WIFI_IFACE=$(find_wifi_interface)

if [ -z "$WIFI_IFACE" ]; then
    echo "ERROR: No WiFi AP interface found"
    exit 1
fi

# Send startup notification
/usr/bin/hostapd-event.sh "MONITOR-STARTED" "$ROUTER_NAME"

# Process hostapd events
while true; do
    if [ -e "/var/run/hostapd/$WIFI_IFACE" ]; then
        hostapd_cli -i "$WIFI_IFACE" -a /usr/bin/hostapd-event.sh
    elif [ -e "/var/run/hostapd" ]; then
        hostapd_cli -a /usr/bin/hostapd-event.sh
    else
        echo "Hostapd socket not found, waiting..."
    fi
    sleep 5
done
EOF

# Make scripts executable
chmod +x /usr/bin/wifi-monitor.sh
chmod +x /usr/bin/hostapd-event.sh

# Create init script
cat << 'EOF' > /etc/init.d/wifi-monitor
#!/bin/sh /etc/rc.common

START=99
STOP=01

start() {
    echo "Starting WiFi monitoring..."
    /usr/bin/wifi-monitor.sh >/dev/null 2>&1 &
}

stop() {
    echo "Stopping WiFi monitoring..."
    killall wifi-monitor.sh 2>/dev/null
    killall hostapd-event.sh 2>/dev/null
}

restart() {
    stop
    start
}
EOF

# Make init script executable and enable it
chmod +x /etc/init.d/wifi-monitor
/etc/init.d/wifi-monitor enable
/etc/init.d/wifi-monitor restart

echo "WiFi monitoring installation complete!"
echo "Please check if hostapd is running:"
echo "ps | grep hostapd"
echo ""
echo "If hostapd is not running, you may need to restart WiFi:"
echo "wifi down && wifi up"
