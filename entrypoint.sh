#!/bin/bash
set -e

# Список запрещенных утилит
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Пути
HOME_DIR="$HOME"
DATA_DIR="$HOME_DIR/data"
HEROKU_DIR="$HOME_DIR/Heroku_Vamhost"
HEROKU_CONFIG=""

# Переменные для Telegram
BOT_TOKEN=""
CHAT_ID=""
KOYEB_URL=""

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

# Генерация внешнего трафика (три ссылки одновременно)
keep_alive() {
    urls=(
        "https://api.github.com/repos/hikariatama/Hikka/commits?per_page=10"  # ~10-20 КБ
        "https://httpbin.org/stream/20"                                       # ~10 КБ
        "https://httpbin.org/get"                                             # ~0.5-1 КБ
    )
    while true; do
        for url in "${urls[@]}"; do
            curl -s "$url" -o /dev/null &
        done
        if [ -n "$KOYEB_URL" ]; then
            curl -s "https://httpbin.org/redirect-to?url=$KOYEB_URL" -o /dev/null &
        fi
        sleep 5  # Каждые 5 секунд
    done
}
keep_alive &

# Функции управления Hikka
start_hikka() {
    if [ ! -d "$HEROKU_DIR" ]; then
        install_hikka
    fi
    if [ ! -f "$DATA_DIR/hikka.pid" ] || ! ps -p "$(cat "$DATA_DIR/hikka.pid")" > /dev/null; then
        cd "$HEROKU_DIR"  # Необходимо для запуска
        nohup python3 -m hikka &  # Без --port, используем 8080, как уже работает
        HIKKA_PID=$!
        if ps -p "$HIKKA_PID" > /dev/null; then
            echo "$HIKKA_PID" > "$DATA_DIR/hikka.pid"
            send_telegram "Hikka запущена (PID: $HIKKA_PID, порт 8080)"
        else
            send_telegram "Ошибка: Hikka не запустилась"
        fi
    else
        send_telegram "Hikka уже запущена Koyeb"
    fi
}

stop_hikka() {
    if [ -f "$DATA_DIR/hikka.pid" ]; then
        HIKKA_PID=$(cat "$DATA_DIR/hikka.pid")
        kill -TERM "$HIKKA_PID" 2>/dev/null && rm "$DATA_DIR/hikka.pid"
        pkill -P "$HIKKA_PID" 2>/dev/null
        send_telegram "Hikka отключена"
    else
        send_telegram "Hikka не запущена"
    fi
}

remove_hikka() {
    stop_hikka
    if [ -d "$HEROKU_DIR" ]; then
        rm -rf "$HEROKU_DIR"
        send_telegram "Hikka удалена (~/data сохранена)"
    fi
}

install_hikka() {
    cd "$HOME_DIR"  # Необходимо для клонирования в ~
    git clone https://github.com/i9opkas/Heroku_Vamhost "$HEROKU_DIR"
    cd "$HEROKU_DIR"  # Необходимо для установки зависимостей
    pip3 install -r requirements.txt || echo "Не удалось установить зависимости"
    send_telegram "Hikka установлена. Используйте .start для запуска, если не запущена Koyeb."
}

reinstall_hikka() {
    cd "$HOME_DIR"  # Необходимо для удаления и установки
    remove_hikka
    install_hikka
    start_hikka
}

# Мониторинг Hikka
monitor_hikka() {
    while true; do
        if [ -
