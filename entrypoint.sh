#!/bin/bash
set -e

# Список запрещенных утилит
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Пути
HOME_DIR="$HOME"
DATA_DIR="$HOME_DIR/data"
HEROKU_DIR="$HOME_DIR/heroku"
HEROKU_CONFIG=""

# Переменные для Telegram
BOT_TOKEN=""
CHAT_ID=""

# Функция отправки сообщения в Telegram
send_telegram() {
    if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d chat_id="$CHAT_ID" \
            -d text="$1" >/dev/null
    fi
}

# Проверка и удаление запрещенных утилит
echo "Перевіряємо та видаляємо небажані утиліти..."
for cmd in $FORBIDDEN_UTILS; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "detect: $cmd. Видаляємо..."
        apt-get purge -y "$cmd" || echo "Не вдалося видалити $cmd"
    fi
done

# Мониторинг запрещенных утилит в фоне
( while true; do
    for cmd in $FORBIDDEN_UTILS; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "detect: $cmd. Видаляємо..."
            apt-get purge -y "$cmd"
        fi
    done
    sleep 10
done ) &

# Генерация внешнего трафика (все три ссылки одновременно)
keep_alive() {
    urls=(
        "https://api.github.com/repos/hikariatama/Hikka/commits?per_page=10"  # ~10-20 КБ
        "https://httpbin.org/stream/20"                                       # ~10 КБ
        "https://httpbin.org/get"                                             # ~0.5-1 КБ, эхо-сервер
    )
    while true; do
        for url in "${urls[@]}"; do
            curl -s "$url" -o /dev/null &
        done
        sleep 5  # Каждые 5 секунд
    done
}
keep_alive &

# Функции управления Heroku
start_heroku() {
    if [ ! -d "$HEROKU_DIR" ]; then
        install_heroku
    fi
    cd "$HEROKU_DIR"  # Необходимо для запуска
    nohup python3 -m heroku &
    HEROKU_PID=$!
    if ps -p "$HEROKU_PID" > /dev/null; then
        echo "$HEROKU_PID" > "$DATA_DIR/heroku.pid"
        send_telegram "Heroku запущена (PID: $HEROKU_PID)"
    else
        send_telegram "Ошибка: Heroku не запустилась"
    fi
}

stop_heroku() {
    if [ -f "$DATA_DIR/heroku.pid" ]; then
        HEROKU_PID=$(cat "$DATA_DIR/heroku.pid")
        kill -TERM "$HEROKU_PID" 2>/dev/null && rm "$DATA_DIR/heroku.pid"
        pkill -P "$HEROKU_PID" 2>/dev/null
        send_telegram "Heroku отключена"
    else
        send_telegram "Heroku не запущена"
    fi
}

remove_heroku() {
    stop_heroku
    if [ -d "$HEROKU_DIR" ]; then
        rm -rf "$HEROKU_DIR"
        send_telegram "Heroku удалена (~/data сохранена)"
    fi
}

install_heroku() {
    cd "$HOME_DIR"  # Необходимо для клонирования в ~
    git clone https://github.com/i9opkas/Heroku_Vamhost "$HEROKU_DIR"
    cd "$HEROKU_DIR"  # Необходимо для установки зависимостей
    pip3 install -r requirements.txt || echo "Не удалось установить зависимости"
    send_telegram "Heroku установлена. Используйте .start для запуска."
}

reinstall_heroku() {
    cd "$HOME_DIR"  # Необходимо для удаления и установки
    remove_heroku
    install_heroku
    start_heroku
}

# Мониторинг Heroku
monitor_heroku() {
    while true; do
        if [ -f "$DATA_DIR/heroku.pid" ]; then
            HEROKU_PID=$(cat "$DATA_DIR/heroku.pid")
            if ! ps -p "$HEROKU_PID" > /dev/null; then
                send_telegram "Heroku упала! Переключаюсь на резервное управление."
                rm "$DATA_DIR/heroku.pid"
            fi
        fi
        sleep 10
    done
}
monitor_heroku &

# Ожидание конфигурации и сессии
wait_for_config() {
    while ! ls "$DATA_DIR"/hikka-*.session >/dev/null 2>&1 || ! ls "$DATA_DIR"/config-*.json >/dev/null 2>&1; do
        echo "Ожидаю создания сессии и конфигурации..."
        sleep 10
    done

    SESSION_FILE=$(ls "$DATA_DIR"/hikka-*.session | head -n 1)
    CHAT_ID=$(basename "$SESSION_FILE" | sed 's/hikka-\([0-9]*\).session/\1/')
    HEROKU_CONFIG="$DATA_DIR/config-$CHAT_ID.json"
    if [ ! -f "$HEROKU_CONFIG" ]; then
        echo "Конфигурация $HEROKU_CONFIG не найдена"
        exit 1
    fi
    BOT_TOKEN=$(jq -r '.["hikka.inline"]["bot_token"] // empty' "$HEROKU_CONFIG")
    if [ -z "$BOT_TOKEN" ]; then
        echo "BOT_TOKEN не найден в $HEROKU_CONFIG"
        exit 1
    fi
}

# Основной цикл
cd "$HOME_DIR"  # Необходим для стартовой точки
echo "Скрипт запущен"
send_telegram "Скрипт запущен и готов к работе (ожидаю конфигурацию)"
wait_for_config
send_telegram "Конфигурация найдена, скрипт полностью активен"

while true; do
    read -p "Введите команду (.start, .stop, .remove, .reinstall, .status): " cmd
    case "$cmd" in
        ".start") start_heroku ;;
        ".stop") stop_heroku ;;
        ".remove") remove_heroku ;;
        ".reinstall") reinstall_heroku ;;
        ".status")
            if [ -f "$DATA_DIR/heroku.pid" ] && ps -p "$(cat "$DATA_DIR/heroku.pid")" > /dev/null; then
                send_telegram "Heroku работает"
            else
                send_telegram "Heroku остановлена"
            fi
            ;;
        *) echo "Неверная команда" ;;
    esac
done
