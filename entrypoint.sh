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
        filepath = os.path.join(data_dir, filename
