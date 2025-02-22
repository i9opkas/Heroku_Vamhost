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
# Стадия сборки
FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Установка базовых пакетов и зависимостей для сборки
RUN apt-get update && \
    apt-get install -y --no-install-recommends git python3-dev gcc build-essential curl libcairo2 \
    ffmpeg libmagic1 libavcodec-dev libavutil-dev libavformat-dev libswscale-dev libavdevice-dev neofetch \
    wkhtmltopdf && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Копируем код в контейнер
COPY . /Hikka

# Создаём виртуальное окружение
RUN python -m venv /Hikka/venv

# Обновляем pip и устанавливаем зависимости
RUN /Hikka/venv/bin/python -m pip install --upgrade pip && \
    /Hikka/venv/bin/pip install --no-warn-script-location --no-cache-dir -r /Hikka/requirements.txt

# Финальная стадия
FROM python:3.10-slim

# Установка необходимых пакетов
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl libcairo2 ffmpeg libmagic1 \
    libavcodec-dev libavutil-dev libavformat-dev \
    libswscale-dev libavdevice-dev neofetch wkhtmltopdf gcc python3-dev nodejs && \
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

# Указываем рабочую директорию
WORKDIR /Hikka

# Открываем порт
EXPOSE 8080

# Запускаем скрипт и приложение
ENTRYPOINT ["/bin/sh", "-c", "/entrypoint.sh && exec python -m hikka"]
