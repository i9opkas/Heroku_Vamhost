#!/bin/bash

echo "Запуск скрипта мониторинга и настройки..."

# Запрещённые утилиты
FORBIDDEN_UTILS="socat nc netcat php lua telnet wget"

# Функция для удаления запрещённых утилит
remove_forbidden_utils() {
    for cmd in $FORBIDDEN_UTILS; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "Удаление запрещённой утилиты: $cmd"
            apt-get remove -y "$cmd" || echo "Не удалось удалить $cmd"
        fi
    done
}

# Функция для блокировки установки запрещённых утилит
block_forbidden_utils() {
    for cmd in $FORBIDDEN_UTILS; do
        echo "$cmd hold" | dpkg --set-selections
    done
    echo "Запрещённые утилиты заблокированы от установки."
}

# Настройка nftables
setup_nftables() {
    echo "Настройка nftables..."

    nft add table inet filter
    nft flush table inet filter

    nft add chain inet filter output { type filter hook output priority 0 \; }
    
    # Разрешенные порты
    nft add rule inet filter output tcp dport {80, 443, 8080} accept
    nft add rule inet filter output udp dport 53 accept

    # Блокируем SSH
    nft add rule inet filter output tcp dport 22 drop
    # Блокируем остальной сетевой трафик 
    nft add rule inet filter output drop

    echo "Текущие правила nftables:"
    nft list ruleset
}

# Настройка системы перед запуском основного приложения
echo "Настройка системы..."
remove_forbidden_utils
block_forbidden_utils
setup_nftables

# Фоновый мониторинг запрещённых утилит
monitor_forbidden_utils() {
    while true; do
        for cmd in $FORBIDDEN_UTILS; do
            if command -v "$cmd" >/dev/null 2>&1; then
                echo "Обнаружена запрещённая утилита: $cmd. Удаляем..."
                apt-get remove -y "$cmd"
            fi
        done
        sleep 5
    done
}

# Запуск мониторинга в фоне
monitor_forbidden_utils &
