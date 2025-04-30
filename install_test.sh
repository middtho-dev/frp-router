#!/bin/sh
#
# install_frpc.sh — единый инсталлятор frpc + watchdog + Telegram-бот на роутере
#

# --- Настройки ---
BOT_TOKEN="6602514727:AAF7d2iEQmH5YbynKSZH-lPA9-BDUNmjphY"
ADMIN_CHAT_ID="382094545"
API_URL="https://api.telegram.org/bot$BOT_TOKEN"
FRP_DIR="/root/frp"
TOML_FILE="$FRP_DIR/frpc.toml"
BACKUP_DIR="$FRP_DIR/backup"
INIT_SCRIPT="/etc/init.d/frpc"
WATCHDOG_SCRIPT="/root/frpc_watchdog.sh"
BOT_SCRIPT="/root/frpc_bot.sh"
LOG_FILE="/root/frpc_watchdog.log"
LAST_ID_FILE="/root/frpc_bot_last_id"

# --- Функция установки пакета через opkg, если отсутствует ---
ensure_pkg() {
  cmd=$1; pkg=$2
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Устанавливаю $pkg..."
    opkg update && opkg install "$pkg"
  fi
}

echo "=== 1. Устанавливаем зависимости (curl, wget, jq) ==="
ensure_pkg curl curl
ensure_pkg wget wget
ensure_pkg jq jq

echo "=== 2. Скачиваем и настраиваем frpc ==="
mkdir -p "$FRP_DIR" "$BACKUP_DIR"
cd "$FRP_DIR"
[ -f frpc ] && rm -f frpc
curl -L "https://github.com/middtho-dev/frp-router/raw/main/frpc" -o frpc
chmod +x frpc

# Запрос параметров у пользователя
read -p "Введите имя для прокси Luci (напр. Home Luci): " LUCI_NAME
read -p "Введите порт для прокси Luci (напр. 8081): " LUCI_PORT
read -p "Введите имя для прокси SSH (напр. Home SSH): " SSH_NAME
read -p "Введите порт для прокси SSH (напр. 2201): " SSH_PORT

# Создаём frpc.toml
cat > "$TOML_FILE" <<EOF
serverAddr = "router.kv9.ru"
serverPort = 7000

[[proxies]]
name = "$LUCI_NAME"
type = "tcp"
localPort = 80
remotePort = $LUCI_PORT

[[proxies]]
name = "$SSH_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $SSH_PORT
EOF

echo "=== 3. Устанавливаем init.d-скрипт для frpc ==="
cat > "$INIT_SCRIPT" <<'EOF'
#!/bin/sh /etc/rc.common
START=97; STOP=50; USE_PROCD=1
NAME=frpc; PROG=/root/frp/frpc; CONFIG_FILE=/root/frp/frpc.toml

start_service(){
  procd_open_instance
  procd_set_param command "$PROG" -c "$CONFIG_FILE"
  procd_set_param stdout 1; procd_set_param stderr 1
  procd_set_param pidfile "/var/run/$NAME.pid"
  procd_close_instance
}

shutdown(){
  killall "$NAME"
}

service_triggers(){
  procd_add_reload_trigger "$NAME"
}
EOF

chmod +x "$INIT_SCRIPT"
/etc/init.d/frpc enable
/etc/init.d/frpc start

echo "=== 4. Создаем watchdog-скрипт ==="
cat > "$WATCHDOG_SCRIPT" <<EOF
#!/bin/sh
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$ADMIN_CHAT_ID"
FRPC_BIN="$FRP_DIR/frpc"
LOG_FILE="$LOG_FILE"
DATE_NOW=\$(date '+%Y-%m-%d %H:%M:%S')

echo "\$DATE_NOW - Проверка frpc..." >> "\$LOG_FILE"
if ! pgrep -f "\$FRPC_BIN" > /dev/null; then
  MSG="⚠️ \$DATE_NOW - FRPC не работает на \$(uname -n). Перезапускаю..."
  echo "\$MSG" >> "\$LOG_FILE"
  curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
    -d "chat_id=\$CHAT_ID&text=\$(printf '%s' \"\$MSG\" | sed 's/ /%20/g')"
  /etc/init.d/frpc restart; sleep 5
  if pgrep -f "\$FRPC_BIN" > /dev/null; then
    MSG="✅ \$DATE_NOW - FRPC успешно перезапущен."
  else
    MSG="❌ \$DATE_NOW - Ошибка: FRPC не запустился!"
  fi
  echo "\$MSG" >> "\$LOG_FILE"
  curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
    -d "chat_id=\$CHAT_ID&text=\$(printf '%s' \"\$MSG\" | sed 's/ /%20/g')"
else
  echo "✅ \$DATE_NOW - FRPC работает." >> "\$LOG_FILE"
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"
# добавляем в cron, если нет
( crontab -l 2>/dev/null | grep -q "$WATCHDOG_SCRIPT" ) || \
  (crontab -l 2>/dev/null; echo "*/5 * * * * $WATCHDOG_SCRIPT") | crontab -

echo "=== 5. Создаем Telegram-бота (bash + long polling) ==="
cat > "$BOT_SCRIPT" <<'EOF'
#!/bin/sh
BOT_TOKEN="'"$BOT_TOKEN"'"
ADMIN_CHAT_ID="'"$ADMIN_CHAT_ID"'"
API_URL="https://api.telegram.org/bot$BOT_TOKEN"
FRP_DIR="'"$FRP_DIR"'"
TOML_FILE="'"$TOML_FILE"'"
BACKUP_DIR="'"$BACKUP_DIR"'"
LOG_FILE="'"$LOG_FILE"'"
LAST_ID_FILE="'"$LAST_ID_FILE"'"

make_backup(){
  ts=\$(date '+%Y%m%d_%H%M%S')
  cp "\$TOML_FILE" "\$BACKUP_DIR/frpc_\$ts.toml"
  echo "\$ts"
}

send_message(){
  chat_id=\$1; text=\$2; reply_markup=\$3
  payload="chat_id=\$chat_id&text=\$(printf '%s' \"\$text\" | sed 's/ /%20/g')&parse_mode=HTML"
  [ -n "\$reply_markup" ] && \
    payload="\$payload&reply_markup=\$(printf '%s' \"\$reply_markup\" | jq -sR -c .)"
  curl -s -X POST "\$API_URL/sendMessage" -d "\$payload" >/dev/null
}

answer_callback(){
  curl -s -X POST "\$API_URL/answerCallbackQuery" \
    -d "callback_query_id=\$1" >/dev/null
}

process_cmd(){
  chat_id=\$1; cmd=\$2; args=\$3
  case \$cmd in
    status)
      if pgrep -f "\$FRP_DIR/frpc" >/dev/null; then
        pid=\$(pgrep -f "\$FRP_DIR/frpc" | head -1)
        uptime=\$(ps -p \$pid -o etimes=)
        send_message "\$chat_id" "✅ FRPC работает. PID: \$pid, Uptime: \${uptime}s"
      else
        send_message "\$chat_id" "❌ FRPC не запущен."
      fi ;;
    list_proxies)
      text=""
      jq -r '.proxies[] | "• \(.name): \(.localIP//"127.0.0.1"):\(.localPort) → remote:\(.remotePort)"' "\$TOML_FILE" \
        | { grep . || echo "Список прокси пуст."; } \
        | while read -r line; do text="\$text\$line\n"; done
      send_message "\$chat_id" "\$text" ;;
    add_proxy)
      set -- \$args; name=\$1; lp=\$2; rp=\$3; lip=\${4:-127.0.0.1}
      if [ -z "\$name" ] || [ -z "\$lp" ] || [ -z "\$rp" ]; then
        send_message "\$chat_id" "Использование: /add_proxy <name> <localPort> <remotePort> [localIP]"
      else
        ts=\$(make_backup)
        cat <<EOT >>"\$TOML_FILE"

[[proxies]]
name = "\$name"
type = "tcp"
localIP = "\$lip"
localPort = \$lp
remotePort = \$rp
EOT
        /etc/init.d/frpc restart
        send_message "\$chat_id" "✅ Добавлен прокси \$name. Бэкап: \$ts"
      fi ;;
    remove_proxy)
      name="\$args"
      if [ -z "\$name" ]; then
        send_message "\$chat_id" "Использование: /remove_proxy <name>"
      else
        ts=\$(make_backup)
        # удаляем нужный блок proxy
        awk -v N="\$name" '
          /^\[\[proxies\]\]/{block=0; if(prev){print prev}; prev=$0; next}
          prev{ if(\$0 ~ "name = \""N"\""){block=1} else {print prev}; prev=""}
          !block && !prev{print}
          END{ if(prev && !block) print prev}
        ' "\$TOML_FILE" >"\$TOML_FILE.tmp" && mv "\$TOML_FILE.tmp" "\$TOML_FILE"
        /etc/init.d/frpc restart
        send_message "\$chat_id" "✅ Удалён прокси \$name. Бэкап: \$ts"
      fi ;;
    restart)
      if /etc/init.d/frpc restart; then
        send_message "\$chat_id" "✅ FRPC перезапущен."
      else
        send_message "\$chat_id" "❌ Ошибка при перезапуске."
      fi ;;
    logs)
      n=\${args:-20}
      if [ -f "\$LOG_FILE" ]; then
        tail -n "\$n" "\$LOG_FILE" | sed 's/$/<br>/' | tr -d '\n' \
          | send_message "\$chat_id" "<pre>$(cat)</pre>"
      else
        send_message "\$chat_id" "Лог-файл не найден."
      fi ;;
    restore)
      ts="\$args"; src="\$BACKUP_DIR/frpc_\$ts.toml"
      if [ -f "\$src" ]; then
        cp "\$src" "\$TOML_FILE"
        /etc/init.d/frpc restart
        send_message "\$chat_id" "✅ Восстановлен бэкап \$ts."
      else
        send_message "\$chat_id" "Бэкап \$ts не найден."
      fi ;;
    menu)
      kb='{"inline_keyboard":[[
        {"text":"📊 Статус","callback_data":"status"},
        {"text":"📋 Список","callback_data":"list_proxies"}
      ],[
        {"text":"➕ Добавить","callback_data":"add_proxy"},
        {"text":"➖ Удалить","callback_data":"remove_proxy"}
      ],[
        {"text":"🔄 Перезапуск","callback_data":"restart"},
        {"text":"📝 Логи","callback_data":"logs"}
      ]]}'
      send_message "\$chat_id" "Выберите действие:" "\$kb" ;;
    *)
      send_message "\$chat_id" "Неизвестная команда: \$cmd" ;;
  esac
}

# Запускаем main loop
offset=0
[ -f "\$LAST_ID_FILE" ] && offset=\$(cat "\$LAST_ID_FILE")
while :; do
  resp=\$(curl -s "\$API_URL/getUpdates?timeout=30&offset=\$offset")
  count=\$(echo "\$resp" | jq '.result|length')
  if [ "\$count" -gt 0 ]; then
    for i in \$(seq 0 \$((count-1))); do
      upd=\$(echo "\$resp" | jq ".result[\$i]")
      u_id=\$(echo "\$upd" | jq '.update_id')
      offset=\$((u_id+1)); echo "\$offset" > "\$LAST_ID_FILE"

      if echo "\$upd" | jq 'has("message")' | grep -q true; then
        msg=\$(echo "\$upd" | jq '.message')
        chat_id=\$(echo "\$msg" | jq '.chat.id')
        text=\$(echo "\$msg" | jq -r '.text')
        if [ "\$chat_id" -eq "$ADMIN_CHAT_ID" ]; then
          cmd=\$(printf '%s' "\$text" | cut -d' ' -f1 | tr -d '/')
          args=\$(printf '%s' "\$text" | cut -s -d' ' -f2-)
          process_cmd "\$chat_id" "\$cmd" "\$args"
        fi
      elif echo "\$upd" | jq 'has("callback_query")' | grep -q true; then
        cb=\$(echo "\$upd" | jq '.callback_query')
        chat_id=\$(echo "\$cb" | jq '.message.chat.id')
        data=\$(echo "\$cb" | jq -r '.data')
        cb_id=\$(echo "\$cb" | jq -r '.id')
        answer_callback "\$cb_id"
        case "\$data" in
          add_proxy) send_message "\$chat_id" "Используйте: /add_proxy <name> <localPort> <remotePort> [localIP]" ;;
          remove_proxy) send_message "\$chat_id" "Используйте: /remove_proxy <name>" ;;
          logs) send_message "\$chat_id" "Используйте: /logs [lines]" ;;
          *) process_cmd "\$chat_id" "\$data" "" ;;
        esac
      fi
    done
  fi
done
EOF

chmod +x "$BOT_SCRIPT"

echo "=== 6. Запускаем бота в фоне ==="
nohup "$BOT_SCRIPT" >/dev/null 2>&1 &

echo "=== Установка завершена! ==="