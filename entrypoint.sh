#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

echo "Перевіряємо та видаляємо небажані утиліти..."
for cmd in $FORBIDDEN_UTILS; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "detect: $cmd. Видаляємо..."
        apt-get purge -y "$cmd" || echo "Не вдалося видалити $cmd"
    fi
done

echo "Моніторинг небажаних утиліт..."
( while true; do
    for cmd in $FORBIDDEN_UTILS; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "detect: $cmd. Видаляємо..."
            apt-get purge -y "$cmd"
        fi
    done
    sleep 10
done ) &

echo "starting Heroku..."
