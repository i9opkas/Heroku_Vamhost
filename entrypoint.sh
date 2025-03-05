#!/bin/bash
set -e

# Список запрещённых утилит
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Пути
DATA_DIR="/data"
CONFIG_FILE="$DATA_DIR/config.json"  # Файл конфига (можно изменить формат/имя)

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

# Инициализация базы данных с таблицей состояния
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
            content BYTEA,  -- Для бинарных данных (сессия, конфиг)
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS instance_state (
            id SERIAL PRIMARY KEY,
            state VARCHAR(50),
            last_shutdown TIMESTAMP,
            last_startup TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    # Проверяем, существует ли запись о состоянии
    cursor.execute("SELECT COUNT(*) FROM instance_state;")
    if cursor.fetchone()[0] == 0:
        cursor.execute("INSERT INTO instance_state (state) VALUES ('created');")
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

# Проверка состояния инстанции (заснул или создан заново)
check_instance_state() {
    python - <<EOF
import psycopg2
import os

db_url = "$DATA_URL"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    cursor.execute("SELECT state, last_shutdown FROM instance_state ORDER BY id DESC LIMIT 1;")
    state, last_shutdown = cursor.fetchone()
    if state == 'created' and last_shutdown is None:
        print("Инстанция создана впервые.")
    elif state == 'sleeping' and last_shutdown is not None:
        print("Инстанция проснулась после сна.")
        cursor.execute("UPDATE instance_state SET state = 'awake', last_startup = CURRENT_TIMESTAMP WHERE id = (SELECT MAX(id) FROM instance_state);")
    else:
        print("Неизвестное состояние инстанции.")
    conn.commit()
except Exception as e:
    print(f"Ошибка проверки состояния: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Восстановление данных из базы в /data
restore_data_from_db() {
    python - <<EOF
import psycopg2
import os

data_dir = "$DATA_DIR"
db_url = "$DATABASE_URL"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    cursor.execute("SELECT filename, content FROM cell_data;")
    data = cursor.fetchall()
    if data:
        if not os.path.exists(data_dir):
            os.makedirs(data_dir)
        for filename, content in data:
            filepath = os.path.join(data_dir, filename)
            with open(filepath, 'wb') as f:
                f.write(content)
        print("Данные из базы восстановлены в /data!")
    else:
        print("В базе нет данных для восстановления, ждём создания файлов.")
except Exception as e:
    print(f"Ошибка восстановления данных: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Сохранение данных из /data в базу перед завершением
save_data_to_db() {
    python - <<EOF
import psycopg2
import os

data_dir = "$DATA_DIR"
db_url = "$DATABASE_URL"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    if os.path.exists(data_dir):
        for filename in os.listdir(data_dir):
            filepath = os.path.join(data_dir, filename)
            if os.path.isfile(filepath):
                with open(filepath, 'rb') as f:
                    content = f.read()
                cursor.execute("""
                    INSERT INTO cell_data (filename, content)
                    VALUES (%s, %s)
                    ON CONFLICT (filename)
                    DO UPDATE SET content = EXCLUDED.content, timestamp = CURRENT_TIMESTAMP;
                """, (filename, psycopg2.Binary(content)))
    # Обновляем состояние инстанции на "засыпание"
    cursor.execute("INSERT INTO instance_state (state, last_shutdown) VALUES ('sleeping', CURRENT_TIMESTAMP);")
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

# Инициализация, проверка состояния и восстановление данных
init_db
check_instance_state
restore_data_from_db

# Перехват SIGTERM от Render для сохранения данных перед "засыпанием"
trap 'save_data_to_db; exit 0' SIGTERM SIGINT

# Запуск приложения
exec python -m hikka
