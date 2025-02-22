#!/bin/sh

echo "-----------------------------------------"

# Функция анализа сетевых соединений
analyze_connections() {
    clear
    echo "Обновление данных... $(date)"
    echo "-----------------------------------------"

    netstat -tunp | awk 'NR>2 {print $1, $4, $5, $7}' | while read proto local_addr remote_addr pid_info; do
        local_ip=$(echo $local_addr | cut -d: -f1)
        local_port=$(echo $local_addr | awk -F: '{print $NF}')
        remote_ip=$(echo $remote_addr | cut -d: -f1)
        remote_port=$(echo $remote_addr | awk -F: '{print $NF}')

        # Если PID присутствует
        if [[ $pid_info =~ ([0-9]+)/([^ ]+) ]]; then
            pid=${BASH_REMATCH[1]}
            process=${BASH_REMATCH[2]}
        else
            pid="N/A"
            process="Unknown"
        fi

        echo "Процесс: $process (PID: $pid) -> Локальный: $local_ip:$local_port -> Внешний: $remote_ip:$remote_port ($proto)"
    done
}

# Следим за изменениями в /proc/net/tcp и /proc/net/udp
while true; do
    analyze_connections
    sleep 2  # Интервал обновления (можно уменьшить)
done
