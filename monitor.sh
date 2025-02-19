#!/bin/bash

# Логирование начала работы скрипта
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
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "Блокировка утилиты: $cmd"
            chmod -x "$(command -v "$cmd")" || echo "Не удалось заблокировать $cmd"
        fi
    done
}

# Функция для настройки iptables
setup_iptables() {
    echo "Настройка iptables..."

    iptables -A OUTPUT -p tcp --dport 80 -m owner --uid-owner root -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 443 -m owner --uid-owner root -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 8080 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 22 -j DROP
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp -j DROP
}

# Запуск процесса настройки
echo "Запуск настройки iptables..."
setup_iptables

# Функция для отслеживания установок запрещённых утилит
monitor_forbidden_utils() {
    while true; do
        # Проверяем установку утилит
        for cmd in $FORBIDDEN_UTILS; do
            # Если утилита установлена, удаляем её
            if command -v "$cmd" >/dev/null 2>&1; then
                echo "Обнаружена запрещённая утилита: $cmd. Удаляем..."
                remove_forbidden_utils
            fi
        done
        # Задержка перед следующим циклом
        sleep 5
    done
}

# Запускаем мониторинг в фоне
monitor_forbidden_utils &
