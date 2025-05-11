# FRPC Автоустановщик для OpenWrt с Telegram-уведомлениями

Скрипт автоматической установки и удаления FRPC (Fast Reverse Proxy Client) на OpenWrt с дополнительной функциональностью:

* мониторинг состояния
* уведомления в Telegram
* проброс Luci и SSH
* автоматический перезапуск при сбое

---

## Возможности

✅ Установка `frpc` в одну команду

📡 Автоматическое пробрасывание Luci и SSH по внешнему адресу через frps

🔁 Автозапуск frpc при старте системы

💬 Уведомления в Telegram:

* при установке и удалении
* при сбоях и перезапусках frpc
* ежечасная сводка о состоянии системы

⚙️ Настройка hostname и timezone

🕵️ Автоматический cron-мониторинг (каждую минуту)

🧹 Удаление всех компонентов по выбору

---

## Требования

* OpenWrt 21.02+
* curl, wget, bash, cron

---

## Установка

```bash
wget -O - sh <(wget -O - https://raw.githubusercontent.com/middtho-dev/frp-router/main/frpc-install.sh)
```

Скрипт запросит:

1. Имя устройства (используется как hostname и в названии прокси)
2. Номер устройства (добавляется к портам: `80XX` для Luci, `22XX` для SSH)

Пример:

* Имя: `Home`
* Номер: `21`

Прокси:

* Luci: `router.kv9.ru:8021`
* SSH: `router.kv9.ru:2221`

---

## Что делает скрипт

### 📂 Создаёт директорию `/root/frp`

### 📥 Загружает бинарный `frpc`

Из GitHub-репозитория: `https://github.com/middtho-dev/frp-router/raw/main/frpc`

### 🛠️ Генерирует `frpc.toml`

```toml
serverAddr = "router.kv9.ru"
serverPort = 7000

[[proxies]]
name = "Home_Luci"
type = "tcp"
localPort = 80
remotePort = 8021

[[proxies]]
name = "Home_SSH"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 2221
```

### 🚀 Создаёт init-скрипт `/etc/init.d/frpc`

* Использует `procd`
* Добавляется в автозагрузку
* Запускается сразу после установки

### 🧠 Настраивает hostname и часовой пояс

* hostname = имя устройства
* timezone = Europe/Moscow

### 🧪 Создаёт утилиту мониторинга `/root/frp/frpc_util.sh`

Скрипт с двумя режимами:

* `check` — проверяет, запущен ли frpc. Если нет — перезапускает и отправляет уведомление.
* `info` — отправляет системную сводку: IP, uptime, загрузка CPU, RAM, диск.

#### Пример уведомления:

```
📊 Состояние системы:
📡 Внешний IP: 93.184.216.34
💽 RAM: 42Mb / 124Mb
📦 Диск: 8.3M / 16M
🕒 Uptime: 2 days
🔥 CPU: 37%
```

### ⏲️ Добавляет задания в cron

* Каждую минуту: `check`
* Каждый час: `info`

### 🧹 Функция удаления

* Останавливает и отключает frpc
* Удаляет директории и скрипты
* Очищает crontab
* Отправляет Telegram-уведомление

---

## Переменные Telegram

* BOT\_TOKEN: задаётся в скрипте
* CHAT\_ID: ID получателя уведомлений

Если вы хотите адаптировать под свой бот — замените эти значения в:

* основном скрипте
* `frpc_util.sh`

---

## Исходный код

> [GitHub: middtho-dev/frp-router](https://github.com/middtho-dev/frp-router)

---

## Лицензия

MIT

---

## Контакты

Для вопросов и предложений: Telegram — [@middtho](https://t.me/middtho)
