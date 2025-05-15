#!/bin/sh

BOT_TOKEN='6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY'
CHAT_ID='382094545'
MSG_FILE="/tmp/telegram-clock-msgid.txt"

HOST="router.kv9.ru"
PORTS="8001 8013 8016 8014 8011 8012"

check_tcp() {
  local port="$1"
  local start_time=$(date +%s%3N)
  nc -z -w 1 "$HOST" "$port" >/dev/null 2>&1
  local result=$?
  local end_time=$(date +%s%3N)
  local elapsed=$((end_time - start_time))
  if [ "$result" -eq 0 ]; then
    echo "✅ \`$HOST:$port\` — ${elapsed}мс"
  else
    echo "❌ \`$HOST:$port\` — нет ответа"
  fi
}

get_status_text() {
  local text="📡 *Состояние маршрутизаторов:*\n"
  for port in $PORTS; do
    status=$(check_tcp "$port")
    text="${text}${status}\n"
  done
  echo "$text"
}

send_message() {
  local text="$(get_status_text)"
  local response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$text" \
    -d parse_mode=Markdown)
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
  local new_text="$(get_status_text)"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" \
    -d chat_id="$CHAT_ID" \
    -d message_id="$msg_id" \
    -d text="$new_text" \
    -d parse_mode=Markdown
}

send_message
sleep 2
pin_message

while true; do
  update_message
  sleep 10
done
