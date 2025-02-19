FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Установка базовых пакетов для сборки
RUN apt-get update && \
    apt-get install -y --no-install-recommends git python3-dev gcc && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Копируем код в контейнер
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
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf gcc python3-dev iptables nftables && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* && \
    apt-get clean

# Установка Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* && \
    apt-get clean

# Установка окружения
ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH"

# Копируем файлы из builder-стадии
COPY --from=builder /Hikka /Hikka

# Копируем скрипт для мониторинга
COPY --chmod=755 monitor.sh /monitor.sh

# Устанавливаем рабочую директорию
WORKDIR /Hikka

# Запускаем скрипт мониторинга и основную программу
ENTRYPOINT ["/bin/sh", "-c", "/monitor.sh && python -m hikka"]
