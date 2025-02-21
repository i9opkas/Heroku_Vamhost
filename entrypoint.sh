#!/bin/bash

echo "Setting up AppArmor and iptables..."

# PARTIAL NETWORK ACCESS RESTRICTION (only necessary connections are allowed)
iptables -A OUTPUT -p tcp --dport 80 -m owner --uid-owner root -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m owner --uid-owner root -j ACCEPT
iptables -A OUTPUT -p tcp --dport 8080 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j DROP
iptables -A OUTPUT -p tcp -j DROP

echo "iptables configured."

echo "Starting monitoring and setup script..."

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

echo "Checking and removing forbidden utilities..."
for cmd in $FORBIDDEN_UTILS; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "Forbidden utility detected: $cmd. Removing..."
        apt-get purge -y "$cmd" || echo "Failed to remove $cmd"
    fi
done

echo "Monitoring forbidden utilities..."
while true; do
    for cmd in $FORBIDDEN_UTILS; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "Forbidden utility detected: $cmd. Removing..."
            apt-get purge -y "$cmd"
        fi
    done
    sleep 10
done &
echo "Запуск Heroku..."

exec firejail --net=eth0 python -m hikka --root
