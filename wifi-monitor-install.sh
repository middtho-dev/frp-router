#!/bin/sh

# WiFi Monitoring Install Script for OpenWRT
# GitHub: https://github.com/middtho-dev/frp-router/blob/main/wifi-monitor-install.sh

# Telegram Bot Configuration
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname)

# Install required packages
opkg update
opkg install hostapd-utils curl

# Create monitoring script
cat << 'EOF' > /usr/bin/wifi-monitor.sh
#!/bin/sh

# WiFi Monitoring Script
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname)

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}" \
        -d disable_notification="false" > /dev/null
}

# Send startup notification
send_telegram "🟢 WiFi Monitoring started on ${ROUTER_NAME}"

# Process hostapd events
hostapd_cli -i $(uci get wireless.@wifi-iface[0].device).$(uci get wireless.@wifi-iface[0].ifname) -a /usr/bin/hostapd-event.sh
EOF

# Create hostapd event handler
cat << 'EOF' > /usr/bin/hostapd-event.sh
#!/bin/sh

# Hostapd Event Handler
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
CHAT_ID="382094545"
ROUTER_NAME=$(uci get system.@system[0].hostname)

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}" \
        -d disable_notification="false" > /dev/null
}

case "$1" in
    AP-STA-CONNECTED)
        MAC="$2"
        IP=$(arp -n | grep "$MAC" | awk '{print $1}')
        HOST=$(grep "$MAC" /tmp/dhcp.leases | awk '{print $4}')
        [ -z "$HOST" ] && HOST="Unknown"
        send_telegram "🟢 Device connected to ${ROUTER_NAME}:
- Device: ${HOST}
- MAC: ${MAC}
- IP: ${IP}"
        ;;
    AP-STA-DISCONNECTED)
        MAC="$2"
        IP=$(arp -n | grep "$MAC" | awk '{print $1}')
        HOST=$(grep "$MAC" /tmp/dhcp.leases | awk '{print $4}')
        [ -z "$HOST" ] && HOST="Unknown"
        send_telegram "🔴 Device disconnected from ${ROUTER_NAME}:
- Device: ${HOST}
- MAC: ${MAC}
- IP: ${IP}"
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
    /usr/bin/wifi-monitor.sh &
}

stop() {
    killall wifi-monitor.sh
    killall hostapd-event.sh
}
EOF

# Make init script executable and enable it
chmod +x /etc/init.d/wifi-monitor
/etc/init.d/wifi-monitor enable
/etc/init.d/wifi-monitor start

echo "WiFi monitoring installation complete!"
