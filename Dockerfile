# Стадия сборки (builder)
FROM python:3.10-slim AS builder

# Устанавливаем зависимости для сборки
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc && \
    rm -rf /var/lib/apt/lists/*

# Копируем код
COPY . /Hikka

# Создаём виртуальное окружение
RUN python -m venv /Hikka/venv
RUN /Hikka/venv/bin/python -m pip install --upgrade pip
RUN /Hikka/venv/bin/pip install --no-cache-dir -r /Hikka/requirements.txt

# Стадия финального образа
FROM python:3.10-slim

# Устанавливаем необходимые пакеты
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 \
    gcc python3-dev iptables apparmor-utils && \
    rm -rf /var/lib/apt/lists/*

# Копируем файлы из builder-стадии
COPY --from=builder /Hikka /Hikka

# Устанавливаем AppArmor и iptables во время старта контейнера
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /Hikka
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
