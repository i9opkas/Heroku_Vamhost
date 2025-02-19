#!/bin/sh

FORBIDDEN_UTILS="socat nc netcat bash sh perl php awk lua telnet wget curl"

while true; do
    for cmd in $FORBIDDEN_UTILS; do
        if command -v $cmd > /dev/null 2>&1; then
            chmod -x $(which $cmd)
            echo "Заблокирована утилита: $cmd"
        fi
    done
    sleep 5  
done
