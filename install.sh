#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Сброс цвета

# Параметры GitHub репозитория
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"

# Скачиваем файлы frpc и frpc.toml
mkdir -p $FRP_DIR
cd $FRP_DIR

echo -e "${GREEN}Скачиваю frpc и frpc.toml с GitHub...${NC}"
if curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "frpc" && curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc.toml" -o "frpc.toml"; then
    echo -e "${GREEN}Файлы успешно скачаны.${NC}"
else
    echo -e "${RED}Ошибка при загрузке файлов с GitHub. Проверьте URL.${NC}"
    exit 1
fi

# Даем права на frpc
echo -e "${GREEN}Даю права на frpc...${NC}"
if chmod +x $FRP_DIR/frpc; then
    echo -e "${GREEN}Права успешно установлены на frpc.${NC}"
else
    echo -e "${RED}Не удалось установить права на frpc.${NC}"
    exit 1
fi

# Создаем init.d скрипт
echo -e "${GREEN}Создаю init.d скрипт...${NC}"
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

# Устанавливаем права на init.d скрипт
echo -e "${GREEN}Устанавливаю права на init.d скрипт...${NC}"
if chmod +x $INIT_SCRIPT; then
    echo -e "${GREEN}Права успешно установлены на init.d скрипт.${NC}"
else
    echo -e "${RED}Не удалось установить права на init.d скрипт.${NC}"
    exit 1
fi

# Добавляем в автозагрузку
echo -e "${GREEN}Добавляю в автозагрузку...${NC}"
if /etc/init.d/frpc enable; then
    echo -e "${GREEN}Служба успешно добавлена в автозагрузку.${NC}"
else
    echo -e "${RED}Не удалось добавить службу в автозагрузку.${NC}"
    exit 1
fi

# Запускаем сервис
echo -e "${GREEN}Запускаю сервис...${NC}"
if /etc/init.d/frpc start; then
    echo -e "${GREEN}Сервис успешно запущен.${NC}"
else
    echo -e "${RED}Не удалось запустить сервис.${NC}"
    exit 1
fi

echo -e "${GREEN}Готово!${NC}"