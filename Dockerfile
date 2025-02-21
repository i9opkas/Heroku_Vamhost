# Стадія збірки (builder)
FROM python:3.10-slim AS builder

# Встановлюємо необхідні пакети для збірки
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential && \
    rm -rf /var/lib/apt/lists/*

# Копіюємо код бота
WORKDIR /Hikka
COPY . /Hikka

# Створюємо віртуальне оточення та встановлюємо залежності
RUN python -m venv /Hikka/venv && \
    /Hikka/venv/bin/python -m pip install --upgrade pip && \
    /Hikka/venv/bin/pip install --no-cache-dir -r /Hikka/requirements.txt

# Стадія фінального образу
FROM python:3.10-slim

# Встановлюємо необхідні пакети
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libcairo2 git ffmpeg libmagic1 iptables && \
    rm -rf /var/lib/apt/lists/*

# Копіюємо файли з builder-стадії
COPY --from=builder /Hikka /Hikka

# Виставляємо робочу директорію
WORKDIR /Hikka

# Робимо entrypoint.sh виконуваним
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Відкриваємо необхідний порт
EXPOSE 8080

# Запускаємо контейнер
CMD ["/entrypoint.sh"]
