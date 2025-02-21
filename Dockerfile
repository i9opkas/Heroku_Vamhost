# Стадія збірки
FROM python:3.10-slim AS builder

ENV PIP_NO_CACHE_DIR=1

# Установка базових пакунків для збірки
RUN apt-get update && \
    apt-get install -y --no-install-recommends git python3-dev gcc build-essential && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# Копіюємо код в контейнер
COPY . /Hikka

# Створюємо віртуальне середовище
RUN python -m venv /Hikka/venv

# Оновлюємо pip
RUN /Hikka/venv/bin/python -m pip install --upgrade pip

# Встановлюємо залежності проекту
RUN /Hikka/venv/bin/pip install --no-warn-script-location --no-cache-dir -r /Hikka/requirements.txt

# Фінальна стадія
FROM python:3.10-slim

# Установка необхідних пакунків
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

# Налаштування середовища
ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Hikka/venv/bin:$PATH"

# Копіюємо файли з builder-стадії
COPY --from=builder /Hikka /Hikka

# Копіюємо скрипт для моніторингу
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Встановлюємо робочу директорію
WORKDIR /Hikka

# Запускаємо cкрипт моніторингу i Heroku 
ENTRYPOINT ["/bin/sh", "-c", "/entrypoint.sh && python -m hikka"]
