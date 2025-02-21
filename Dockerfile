# Стадия сборки
FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Установка базовых пакетов
RUN apt-get update && \
    apt-get install -y --no-install-recommends git python3-dev gcc build-essential && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Копируем код в контейнер
COPY . /Hikka

# Создаём виртуальное окружение
RUN python -m venv /Hikka/venv

# Обновляем pip
RUN /Hikka/venv/bin/python -m pip install --upgrade pip

# Устанавливаем зависимости проекта
RUN /Hikka/venv/bin/pip install --no-warn-script-location --no-cache-dir -r /Hikka/requirements.txt

# Финальная стадия
FROM python:3.10-slim

# Установка необходимых пакетов
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 \
    libavcodec-dev libavutil-dev libavformat-dev \
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf gcc python3-dev nftables && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* && \
    apt-get clean

# Установка Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* && \
    apt-get clean

# Настройки окружения
ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH"

# Копируем файлы из builder-стадии
COPY --from=builder /Hikka /Hikka

# Копируем скрипт
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Копируем конфиг для nftables
COPY nftables.conf /etc/nftables.conf

# Указываем рабочую директорию
WORKDIR /Hikka

# Открываем порт
EXPOSE 8080

# Запускаем скрипт и приложение
ENTRYPOINT ["/bin/sh", "-c", "/entrypoint.sh && exec python -m hikka"]
