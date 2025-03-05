#!/bin/bash
set -e

# Список запрещённых утилит
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Пути
DATA_DIR="/data"  # Используем ~/data, что на Render обычно означает /data

# Проверка и установка зависимостей для работы с PostgreSQL
if ! python -c "import psycopg2" >/dev/null 2>&1; then
    echo "Установка psycopg2-binary..."
    pip install psycopg2-binary
fi

# Проверка наличия DATABASE_URL
if [ -z "$DATABASE_URL" ]; then
    echo "Ошибка: Переменная окружения DATABASE_URL не задана. Убедитесь, что база данных настроена на Render."
    exit 1
fi

# Создание директории, если её нет
mkdir -p "$DATA_DIR"

# Инициализация базы данных
init_db() {
    python - <<EOF
import psycopg2
from psycopg2 import Error

try:
    conn = psycopg2.connect("$DATABASE_URL")
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cell_data (
            id SERIAL PRIMARY KEY,
            filename VARCHAR(255) UNIQUE,
            content TEXT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    conn.commit()
    print("База данных инициализирована!")
except Error as e:
    print(f"Ошибка инициализации базы данных: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Загрузка данных из ~/data в базу данных при запуске
load_data_to_db() {
    python - <<EOF
import psycopg2
import os

data_dir = "$DATA_DIR"
db_url = "$DATABASE_URL"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    for filename in os.listdir(data_dir):
        filepath = os.path.join(data_dir, filename)
        if os.path.isfile(filepath):
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            cursor.execute("""
                INSERT INTO cell_data (filename, content)
                VALUES (%s, %s)
                ON CONFLICT (filename)
                DO UPDATE SET content = EXCLUDED.content, timestamp = CURRENT_TIMESTAMP;
            """, (filename, content))
    conn.commit()
    print("Данные из ~/data загружены в базу!")
except Exception as e:
    print(f"Ошибка загрузки данных: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Сохранение данных в базу перед завершением
save_data_to_db() {
    python - <<EOF
import psycopg2
import os

data_dir = "$DATA_DIR"
db_url = "$DATABASE_URL"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    for filename in os.listdir(data_dir):
        filepath = os.path.join(data_dir, filename)
        if os.path.isfile(filepath):
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            cursor.execute("""
                INSERT INTO cell_data (filename, content)
                VALUES (%s, %s)
                ON CONFLICT (filename)
                DO UPDATE SET content = EXCLUDED.content, timestamp = CURRENT_TIMESTAMP;
            """, (filename, content))
    conn.commit()
    print("Данные сохранены в базу перед завершением!")
except Exception as e:
    print(f"Ошибка сохранения данных: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Генерация внешнего трафика
keep_alive() {
    urls=(
        "https://api.github.com/repos/hikariatama/Hikka/commits?per_page=10"
        "https://httpbin.org/stream/20"
        "https://httpbin.org/get"
    )
    while true; do
        for url in "${urls[@]}"; do
            curl -s "$url" -o /dev/null &
        done
        sleep 5
    done
}
keep_alive &

# Мониторинг запрещённых утилит
monitor_forbidden() {
    while true; do
        for cmd in $FORBIDDEN_UTILS; do
            if command -v "$cmd" >/dev/null 2>&1; then
                apt-get purge -y "$cmd" 2>/dev/null || true
            fi
        done
        sleep 10
    done
}
monitor_forbidden &

# Инициализация и загрузка данных
init_db
load_data_to_db

# Обработка завершения процесса
trap 'save_data_to_db; exit 0' SIGTERM SIGINT

# Запуск приложения
exec python -m hikka
