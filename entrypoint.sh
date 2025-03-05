#!/bin/bash
set -e

# Список запрещённых утилит
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Пути
HOME_DIR="/Hikka"
DATA_DIR="$HOME_DIR/data"

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

# Healthcheck-сервер на порту 10000
start_healthcheck() {
    cat << 'EOF' > "$HOME_DIR/healthcheck.py"
from aiohttp import web
import asyncio

async def healthcheck_handler(request):
    return web.Response(text="OK", status=200)

async def main():
    app = web.Application()
    app.router.add_get('/', healthcheck_handler)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', 10000)
    await site.start()
    while True:
        await asyncio.sleep(3600)
EOF
    nohup python "$HOME_DIR/healthcheck.py" &
    echo $! > "$DATA_DIR/healthcheck.pid"
}

# Основной запуск
cd "$HOME_DIR"
mkdir -p "$DATA_DIR"
start_healthcheck

# Запуск Hikka на порту 10001 в основном потоке
exec python -m hikka --port 10001
