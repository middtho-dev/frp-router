#!/bin/sh

# WiFi Monitoring Install Script for OpenWRT
# GitHub: https://github.com/middtho-dev/frp-router/blob/main/wifi-monitor-install.sh

# Telegram Bot Configuration
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname || echo "OpenWRT")

# Install required packages
opkg update
opkg install hostapd-utils curl jq

# Create monitoring script
cat << 'EOF' > /usr/bin/wifi-monitor.sh
#!/bin/sh

# WiFi Monitoring Script
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname || echo "OpenWRT")

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}" \
        -d disable_notification="false" > /dev/null
}

# Find the correct WiFi interface
find_wifi_interface() {
    for iface in $(uci show wireless | grep -o 'wifi-iface\[[0-9]*\]' | sort -u); do
        mode=$(uci get wireless.${iface}.mode)
        if [ "$mode" = "ap" ]; then
            device=$(uci get wireless.${iface}.device)
            ifname=$(uci get wireless.${iface}.ifname)
            echo "${device}.${ifname}"
            return 0
        fi
    done
    return 1
}

# Send startup notification
send_telegram "🟢 WiFi Monitoring started on ${ROUTER_NAME}"

# Get WiFi interface
WIFI_IFACE=$(find_wifi_interface)

if [ -z "$WIFI_IFACE" ]; then
    send_telegram "❌ Error: No WiFi AP interface found on ${ROUTER_NAME}"
    exit 1
fi

# Process hostapd events
while true; do
    hostapd_cli -i "$WIFI_IFACE" -a /usr/bin/hostapd-event.sh
    sleep 5
done
EOF

# Create hostapd event handler
cat << 'EOF' > /usr/bin/hostapd-event.sh
#!/bin/sh

# Hostapd Event Handler
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname || echo "OpenWRT")

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
    
    # Try to get manufacturer from MAC
    local oui=$(echo "$mac" | tr -d ':' | cut -c1-6 | tr '[:upper:]' '[:lower:]')
    local vendor=$(curl -s "https://api.macvendors.com/$oui" 2>/dev/null || echo "Unknown vendor")
    
    echo "$ip,$host,$vendor"
}

case "$1" in
    AP-STA-CONNECTED)
        MAC="$2"
        IFS=, read -r ip host vendor <<< "$(get_client_info "$MAC")"
        send_telegram "🟢 Device connected to ${ROUTER_NAME}:
- Device: ${host}
- MAC: ${MAC}
- IP: ${ip}
- Vendor: ${vendor}"
        ;;
    AP-STA-DISCONNECTED)
        MAC="$2"
        IFS=, read -r ip host vendor <<< "$(get_client_info "$MAC")"
        send_telegram "🔴 Device disconnected from ${ROUTER_NAME}:
- Device: ${host}
- MAC: ${MAC}
- IP: ${ip}
- Vendor: ${vendor}"
        ;;
esac
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
