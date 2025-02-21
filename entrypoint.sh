#!/bin/sh

echo "Настройка AppArmor..."

# Блокируем опасные утилиты через AppArmor
for cmd in socat nc ncat netcat bash sh perl php awk lua telnet openssl wget curl; do
    echo "deny network inet stream," > "/etc/apparmor.d/usr.bin.$cmd"
    apparmor_parser -r "/etc/apparmor.d/usr.bin.$cmd"
done

echo "AppArmor настроен."

echo "Настройка iptables..."

# ЧАСТИЧНОЕ ОГРАНИЧЕНИЕ СЕТЕВОГО ДОСТУПА (разрешены только нужные соединения)
iptables -A OUTPUT -p tcp --dport 80 -m owner --uid-owner root -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m owner --uid-owner root -j ACCEPT
iptables -A OUTPUT -p tcp --dport 8080 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j DROP
iptables -A OUTPUT -p tcp -j DROP

echo "iptables настроен."

# Запускаем приложение
echo "Запуск Hikka..."
exec python -m hikka
