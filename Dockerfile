FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Установка базовых пакетов
RUN apt-get update && \
    apt-get install -y --no-install-recommends git python3-dev gcc && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Копируем код
COPY . /Hikka

# Создаем виртуальное окружение
RUN python -m venv /Hikka/venv

# Обновляем pip
RUN /Hikka/venv/bin/python -m pip install --upgrade pip

# Устанавливаем зависимости проекта
RUN /Hikka/venv/bin/pip install --no-warn-script-location --no-cache-dir -r /Hikka/requirements.txt

# Вторая стадия
FROM python:3.10-slim

# Установка необходимых пакетов
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 \
    libavcodec-dev libavutil-dev libavformat-dev \
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf \
    gcc python3-dev iptables && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Устанавливаем Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Блокировка исполнения нежелательных утилит
RUN chmod -x /usr/bin/socat && \
    chmod -x /usr/bin/nc && \
    chmod -x /usr/bin/netcat && \
    chmod -x /usr/bin/bash && \
    chmod -x /usr/bin/sh && \
    chmod -x /usr/bin/perl && \
    chmod -x /usr/bin/php && \
    chmod -x /usr/bin/awk && \
    chmod -x /usr/bin/lua && \
    chmod -x /usr/bin/telnet && \
    chmod -x /usr/bin/wget && \
    chmod -x /usr/bin/curl

# ЧАСТИЧНОЕ ОГРАНИЧЕНИЕ СЕТЕВОГО ДОСТУПА (разрешены только нужные соединения)
RUN iptables -A OUTPUT -p tcp --dport 80 -m owner --uid-owner root -j ACCEPT && \
    iptables -A OUTPUT -p tcp --dport 443 -m owner --uid-owner root -j ACCEPT && \
    iptables -A OUTPUT -p tcp --dport 8080 -j ACCEPT && \
    iptables -A OUTPUT -p tcp --dport 22 -j DROP && \
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT && \
    iptables -A OUTPUT -p tcp -j DROP

# Устанавливаем окружение Docker
ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH"

# Копируем файлы из builder-стадии
COPY --from=builder /Hikka /Hikka

WORKDIR /Hikka

EXPOSE 8080

ENTRYPOINT ["python", "-m", "hikka"]
