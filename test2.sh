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
# COLORS
# =========================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# =========================
# HELPERS
# =========================

die() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

info() {
    echo -e "${GREEN}▶ $1${NC}"
}

# =========================
# REMOVE
# =========================

remove_all() {
    info "Удаление FRPC..."

    /etc/init.d/frpc stop 2>/dev/null
    /etc/init.d/frpc disable 2>/dev/null

    rm -f "$INIT_SCRIPT"
    rm -rf "$FRP_DIR"

    info "FRPC полностью удалён"
    exit 0
}

# =========================
# ARGUMENTS
# =========================

if [ "$1" = "remove" ]; then
    remove_all
fi

DEVICE_NAME="$1"

if [ -z "$DEVICE_NAME" ]; then
    echo "Использование:"
    echo "  install.sh <device_name>"
    echo "  install.sh remove"
    exit 1
fi

# =========================
# DEPENDENCIES
# =========================

info "Установка зависимостей..."
opkg update
opkg install curl wget jq || die "Не удалось установить зависимости"

# =========================
# REQUEST PORTS
# =========================

info "Запрос портов у сервера..."

API_URL="http://${API_HOST}:${API_PORT}/allocate?token=${INSTALL_TOKEN}&device=${DEVICE_NAME}"

RESPONSE="$(curl -fs "$API_URL")" || die "Не удалось подключиться к API"

LUCi_PORT="$(echo "$RESPONSE" | cut -d: -f1)"
SSH_PORT="$(echo "$RESPONSE" | cut -d: -f2)"

[ -z "$LUCi_PORT" ] && die "Luci порт не получен"
[ -z "$SSH_PORT" ] && die "SSH порт не получен"

info "Получены порты: Luci=$LUCi_PORT SSH=$SSH_PORT"

# =========================
# FRPC SETUP
# =========================

info "Установка FRPC..."

mkdir -p "$FRP_DIR" || die "Не удалось создать $FRP_DIR"
cd "$FRP_DIR" || die "Не удалось войти в $FRP_DIR"

curl -fsSL \
  https://github.com/middtho-dev/frp-router/raw/main/frpc \
  -o frpc || die "Не удалось скачать frpc"

chmod +x frpc

# =========================
# FRPC CONFIG
# =========================

info "Создание конфигурации FRPC..."

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

# =========================
# INIT SCRIPT
# =========================

info "Настройка автозапуска..."

cat > "$INIT_SCRIPT" <<'EOF'
#!/bin/sh /etc/rc.common

START=95
STOP=10
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
/etc/init.d/frpc enable
/etc/init.d/frpc restart

# =========================
# SYSTEM
# =========================

info "Настройка имени устройства..."

uci set system.@system[0].hostname="$DEVICE_NAME"
uci commit system
/etc/init.d/system reload

# =========================
# DONE
# =========================

EXT_IP="$(wget -qO- https://api.ipify.org)"

echo
info "УСТАНОВКА ЗАВЕРШЕНА"
echo "----------------------------------"
echo "Устройство : $DEVICE_NAME"
echo "Luci       : http://${FRPS_HOST}:${LUCi_PORT}"
echo "SSH        : ssh root@${FRPS_HOST} -p ${SSH_PORT}"
echo "Внешний IP : ${EXT_IP}"
echo "----------------------------------"
