# Стадія збірки
FROM python:3.10-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /Hikka
COPY . /Hikka

RUN python -m venv /Hikka/venv && \
    /Hikka/venv/bin/python -m pip install --upgrade pip && \
    /Hikka/venv/bin/pip install --no-cache-dir -r /Hikka/requirements.txt

# Фінальна стадія
FROM python:3.10-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 iptables && \
    rm -rf /var/lib/apt/lists/*

# Створюємо користувача `hikka`
RUN useradd -m -s /bin/bash hikka

# Налаштовуємо права доступу для Hikka
RUN mkdir -p /home/hikka/Hikka && chown -R hikka:hikka /home/hikka

# Копіюємо файли з builder-стадії в домашню директорію користувача `hikka`
COPY --from=builder /Hikka/ /home/hikka/

# Виставляємо робочу директорію
WORKDIR /home/hikka/Hikka

# Копіюємо та налаштовуємо entrypoint.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Відкриваємо порт
EXPOSE 8080

# Запускаємо контейнер від root, але потім переходимо на `hikka`
CMD ["/entrypoint.sh"]
