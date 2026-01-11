#!/bin/sh

# ========= CONFIG =========
FRP_DIR="/root/frp"
FRPS_HOST="router.kv9.ru"
FRPS_PORT="7000"

API_HOST="router.kv9.ru"
API_PORT="26001"
INSTALL_TOKEN="super-secret-token"

# ========= UI =========
SP='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
i=0

spin() {
    while kill -0 "$1" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r %s %s" "${SP:$i:1}" "$2"
        sleep 0.1
    done
    printf "\r ✔ %s\n" "$2"
}

fail() {
    printf "\r ✖ %s\n" "$1"
    exit 1
}

# ========= ARGS =========
DEVICE="$1"
[ -z "$DEVICE" ] && fail "использование: install.sh <device>"

# ========= DEPS =========
(opkg update >/dev/null && opkg install curl wget jq >/dev/null) &
spin $! "зависимости"

# ========= PORTS =========
API_URL="http://${API_HOST}:${API_PORT}/allocate?token=${INSTALL_TOKEN}&device=${DEVICE}"
PORTS="$(curl -fs "$API_URL")" || fail "API недоступен"

LUCi_PORT="${PORTS%%:*}"
SSH_PORT="${PORTS##*:}"

[ -z "$LUCi_PORT" ] && fail "нет Luci порта"
[ -z "$SSH_PORT" ] && fail "нет SSH порта"

printf " ✔ порты: %s / %s\n" "$LUCi_PORT" "$SSH_PORT"

# ========= FRPC =========
mkdir -p "$FRP_DIR" || fail "mkdir"
cd "$FRP_DIR" || fail "cd"

(wget -q https://github.com/middtho-dev/frp-router/raw/main/frpc -O frpc) &
spin $! "загрузка frpc"

chmod +x frpc || fail "chmod"

# ========= CONFIG =========
cat > frpc.toml <<EOF
serverAddr = "$FRPS_HOST"
serverPort = $FRPS_PORT

[[proxies]]
name = "${DEVICE}_Luci"
type = "tcp"
localPort = 80
remotePort = $LUCi_PORT

[[proxies]]
name = "${DEVICE}_SSH"
type = "tcp"
localPort = 22
remotePort = $SSH_PORT
EOF

printf " ✔ конфиг\n"

# ========= INIT =========
cat > /etc/init.d/frpc <<'EOF'
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command /root/frp/frpc -c /root/frp/frpc.toml
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/frpc
/etc/init.d/frpc enable >/dev/null
/etc/init.d/frpc start  >/dev/null || fail "frpc start"

printf " ✔ frpc запущен\n"

# ========= SYSTEM =========
uci set system.@system[0].hostname="$DEVICE"
uci commit system
/etc/init.d/system reload >/dev/null

# ========= DONE =========
echo
echo " 🎉 ГОТОВО"
echo " ─────────────────────"
echo " Luci: http://${FRPS_HOST}:${LUCi_PORT}"
echo " SSH : ssh root@${FRPS_HOST} -p ${SSH_PORT}"
echo " ─────────────────────"
