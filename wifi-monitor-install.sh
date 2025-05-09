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
    MONITOR-STARTED)
        send_telegram "🟢 WiFi Monitoring started on ${ROUTER_NAME}"
        ;;
esac
EOF

# Create monitoring script
cat << 'EOF' > /usr/bin/wifi-monitor.sh
#!/bin/sh

# WiFi Monitoring Script
ROUTER_NAME=$(uci get system.@system[0].hostname 2>/dev/null || echo "OpenWRT")

# Find active WiFi interfaces
find_wifi_interfaces() {
    # Check for ujail-hosted hostapd instances
    for pid in $(pgrep hostapd); do
        if grep -q ujail /proc/$pid/cmdline 2>/dev/null; then
            # Extract interface name from process cmdline
            grep -oE '\-i [^ ]+' /proc/$pid/cmdline 2>/dev/null | awk '{print $2}' | sort -u
        fi
    done
    
    # Fallback to traditional method
    if [ -z "$INTERFACES" ]; then
        ls /var/run/hostapd/ 2>/dev/null | grep -v '^global$'
    fi
}

# Send startup notification
/usr/bin/hostapd-event.sh "MONITOR-STARTED" "$ROUTER_NAME"

# Monitor all interfaces
while true; do
    INTERFACES=$(find_wifi_interfaces)
    
    if [ -z "$INTERFACES" ]; then
        echo "No active WiFi interfaces found, waiting..."
        sleep 10
        continue
    fi

    for IFACE in $INTERFACES; do
        # Skip if already monitoring this interface
        if pgrep -f "hostapd_cli.*${IFACE}" >/dev/null; then
            continue
        fi
        
        echo "Starting monitoring for interface $IFACE"
        hostapd_cli -i "$IFACE" -a /usr/bin/hostapd-event.sh >/dev/null 2>&1 &
    done
    
    sleep 30
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
    killall hostapd_cli 2>/dev/null
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
echo "Please wait 1-2 minutes for the system to stabilize"
echo "Check status with: /etc/init.d/wifi-monitor status"
echo "View logs with: logread | grep wifi-monitor"
