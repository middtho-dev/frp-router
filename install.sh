#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Сброс цвета

# Параметры GitHub репозитория
GITHUB_REPO="middtho-dev/frp-router"
FRP_DIR="/root/frp"
INIT_SCRIPT="/etc/init.d/frpc"

# Скачиваем файл frpc
mkdir -p $FRP_DIR
cd $FRP_DIR

echo -e "${GREEN}Скачиваю frpc с GitHub...${NC}"
if curl -L "https://github.com/$GITHUB_REPO/raw/main/frpc" -o "frpc"; then
    echo -e "${GREEN}Файл frpc успешно скачан.${NC}"
else
    echo -e "${RED}Ошибка при загрузке файла frpc с GitHub.${NC}"
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

# Запрашиваем параметры для frpc.toml
echo -e "${GREEN}Введите имя для прокси Luci (например: Home Luci):${NC}"
read luci_name
echo -e "${GREEN}Введите порт для прокси Luci (например: 8081):${NC}"
read luci_port

echo -e "${GREEN}Введите имя для прокси SSH (например: Home SSH):${NC}"
read ssh_name
echo -e "${GREEN}Введите порт для прокси SSH (например: 2201):${NC}"
read ssh_port

# Создаем frpc.toml
echo -e "${GREEN}Создаю файл frpc.toml...${NC}"
cat <<EOF > $FRP_DIR/frpc.toml
serverAddr = "router.kv9.ru"
serverPort = 7000

[[proxies]]
name = "$luci_name"
type = "tcp"
localPort = 80
remotePort = $luci_port

[[proxies]]
name = "$ssh_name"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $ssh_port
EOF

# Проверка на успешное создание frpc.toml
if [[ -f $FRP_DIR/frpc.toml ]]; then
    echo -e "${GREEN}Файл frpc.toml успешно создан.${NC}"
else
    echo -e "${RED}Не удалось создать файл frpc.toml.${NC}"
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
