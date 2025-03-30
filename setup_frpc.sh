#!/bin/bash

# Параметры GitHub репозитория
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"

# Скачиваем файлы frpc и frpc.toml
mkdir -p $FRP_DIR
cd $FRP_DIR

echo "Скачиваю frpc и frpc.toml с GitHub..."
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "frpc"
curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc.toml" -o "frpc.toml"

# Проверка на успешную загрузку файлов
if [[ ! -f "frpc" || ! -f "frpc.toml" ]]; then
    echo "Ошибка при загрузке файлов с GitHub. Проверьте URL."
    exit 1
fi

# Создаем init.d скрипт
echo "Создаю init.d скрипт..."
cat <<EOF > $INIT_SCRIPT
#!/bin/sh /etc/rc.common

START=97
STOP=50
USE_PROCD=1

NAME=frpc
PROG=$FRP_DIR/frpc
CONFIG_FILE=$FRP_DIR/frpc.toml

start_service() {
    procd_open_instance
    procd_set_param command "\$PROG" -c "\$CONFIG_FILE"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile "/var/run/\$NAME.pid"
    procd_close_instance
}

shutdown() {
    killall "\$NAME"
}

service_triggers() {
    procd_add_reload_trigger "\$NAME"
}
EOF

# Устанавливаем права на файл
echo "Устанавливаю права на скрипт..."
chmod +x $INIT_SCRIPT

# Добавляем в автозагрузку
echo "Добавляю в автозагрузку..."
/etc/init.d/frpc enable

# Запускаем сервис
echo "Запускаю сервис..."
/etc/init.d/frpc start

echo "Готово!"
