#!/bin/sh

### Конфигурация
BOT_TOKEN='6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY'
CHAT_ID='382094545'
INSTALL_DIR="/etc/telegram-clock"
SCRIPT_NAME="clock.sh"
SERVICE_NAME="telegram-clock"
MSG_FILE="/tmp/telegram-clock-msgid.txt"

### Установка
mkdir -p "$INSTALL_DIR"

cat << 'EOF' > "$INSTALL_DIR/$SCRIPT_NAME"
#!/bin/sh

BOT_TOKEN='6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY'
CHAT_ID='382094545'
MSG_FILE="/tmp/telegram-clock-msgid.txt"

send_message() {
  local text="🕒 Текущее время: $(date '+%H:%M:%S')"
  local response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$text")
  echo "$response" | grep -o '"message_id":[0-9]*' | cut -d: -f2 > "$MSG_FILE"
}

pin_message() {
  local msg_id=$(cat "$MSG_FILE")
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/pinChatMessage" \
    -d chat_id="$CHAT_ID" \
    -d message_id="$msg_id" \
    -d disable_notification=true
}

update_message() {
  local msg_id=$(cat "$MSG_FILE")
  local new_text="🕒 Текущее время: $(date '+%H:%M:%S')"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" \
    -d chat_id="$CHAT_ID" \
    -d message_id="$msg_id" \
    -d text="$new_text"
}

send_message
sleep 2
pin_message

while true; do
  update_message
  sleep 10
done
EOF

chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

### Служба init.d
cat << EOF > "/etc/init.d/$SERVICE_NAME"
#!/bin/sh /etc/rc.common
# Telegram Clock Service
START=99

start() {
    echo "Starting $SERVICE_NAME"
    "$INSTALL_DIR/$SCRIPT_NAME" &
}

stop() {
    echo "Stopping $SERVICE_NAME"
    pkill -f "$SCRIPT_NAME"
}
EOF

chmod +x "/etc/init.d/$SERVICE_NAME"
"/etc/init.d/$SERVICE_NAME" enable
"/etc/init.d/$SERVICE_NAME" start

echo "✅ Telegram Clock установлен и запущен."
