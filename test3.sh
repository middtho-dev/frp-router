#!/bin/sh

# =========================
# CONFIG
# =========================

FRP_DIR="/root/frp"
FRPC_BIN="$FRP_DIR/frpc"
FRPC_CONF="$FRP_DIR/frpc.toml"
INIT_SCRIPT="/etc/init.d/frpc"

FRPS_HOST="router.kv9.ru"
FRPS_PORT="7000"

API_HOST="router.kv9.ru"
API_PORT="26001"
INSTALL_TOKEN="AAHgOtBGZ-kuObcBm3VhYM_bfyExCZlDauo"

# =========================
# COLORS / UI
# =========================

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

step() {
    echo -e "${BLUE}▶ $1${NC}"
}

ok() {
    echo -e "${GREEN}✔ $1${NC}"
}

fail() {
    echo -e "${RED}✖ $1${NC}"
    exit 1
}

# =========================
# REMOVE
# =========================

if [ "$1" = "remove" ]; then
    step "Удаление FRPC"
    [ -x "$INIT_SCRIPT" ] && /etc/init.d/frpc stop 2>/dev/null
    [ -x "$INIT_SCRIPT" ] && /etc/init.d/frpc disable 2>/dev/null
    rm -rf "$FRP_DIR" "$INIT_SCRIPT"
    ok "FRPC удалён"
    exit 0
fi

DEVICE_NAME="$1"
[ -z "$DEVICE_NAME" ] && fail "Укажи имя устройства: install.sh <name>"

# =========================
# DEPENDENCIES
# =========================

step "Установка зависимостей"
opkg update >/dev/null
opkg install curl wget jq >/dev/null || fail "Не удалось установить зависимости"
ok "Зависимости готовы"

# =========================
# REQUEST PORTS
# =========================

step "Запрос портов у сервера"

API_URL="http://${API_HOST}:${API_PORT}/allocate?token=${INSTALL_TOKEN}&device=${DEVICE_NAME}"

RESPONSE="$(curl -fs "$API_URL")" || fail "API недоступен"

LUCi_PORT="$(echo "$RESPONSE" | cut -d: -f1)"
SSH_PORT="$(echo "$RESPONSE" | cut -d: -f2)"

[ -z "$LUCi_PORT" ] && fail "Luci порт не получен"
[ -z "$SSH_PORT" ] && fail "SSH порт не получен"

ok "Порты получены: Luci=$LUCi_PORT SSH=$SSH_PORT"

# =========================
# DOWNLOAD FRPC
# =========================

step "Загрузка FRPC"

mkdir -p "$FRP_DIR" || fail "Не удалось создать $FRP_DIR"
cd "$FRP_DIR" || fail "Не удалось перейти в $FRP_DIR"

wget --show-progress -q \
  https://github.com/middtho-dev/frp-router/raw/main/frpc \
  -O frpc || fail "Ошибка загрузки FRPC"

chmod +x frpc
ok "FRPC загружен"

# =========================
# CONFIG
# =========================

step "Создание конфигурации"

cat > "$FRPC_CONF" <<EOF
serverAddr = "${FRPS_HOST}"
serverPort = ${FRPS_PORT}

[[proxies]]
name = "${DEVICE_NAME}_Luci"
type = "tcp"
localPort = 80
remotePort = ${LUCi_PORT}

[[proxies]]
name = "${DEVICE_NAME}_SSH"
type = "tcp"
localPort = 22
remotePort = ${SSH_PORT}
EOF

ok "Конфигурация создана"

# =========================
# INIT SCRIPT
# =========================

step "Настройка автозапуска"

cat > "$INIT_SCRIPT" <<'EOF'
#!/bin/sh /etc/rc.common

START=95
USE_PROCD=1

PROG="/root/frp/frpc"
CONF="/root/frp/frpc.toml"

start_service() {
    procd_open_instance
    procd_set_param command "$PROG" -c "$CONF"
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x "$INIT_SCRIPT"

# enable + start (БЕЗ restart!)
/etc/init.d/frpc enable || fail "Не удалось включить автозапуск"
/etc/init.d/frpc start || fail "Не удалось запустить FRPC"

ok "FRPC запущен и добавлен в автозапуск"

# =========================
# SYSTEM
# =========================

step "Настройка имени устройства"

uci set system.@system[0].hostname="$DEVICE_NAME"
uci commit system
/etc/init.d/system reload

ok "Имя устройства обновлено"

# =========================
# DONE
# =========================

EXT_IP="$(wget -qO- https://api.ipify.org)"

echo
echo -e "${GREEN}🎉 УСТАНОВКА ЗАВЕРШЕНА${NC}"
echo "----------------------------------"
echo "Устройство : $DEVICE_NAME"
echo "Luci       : http://${FRPS_HOST}:${LUCi_PORT}"
echo "SSH        : ssh root@${FRPS_HOST} -p ${SSH_PORT}"
echo "Внешний IP : ${EXT_IP}"
echo "----------------------------------"
