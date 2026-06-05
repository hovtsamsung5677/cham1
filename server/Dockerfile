# Многоэтапный Dockerfile для MobileSAM Segmentation Server
# ===========================================
# Этап 1: Сборка
# ===========================================
FROM python:3.12.7-slim AS builder

# Установка системных зависимостей
RUN apt-get update && apt-get install -y \
  git \
  && rm -rf /var/lib/apt/lists/*

# Рабочая директория
WORKDIR /build

# Установка setuptools с ограничением версии (для совместимости с torch)
RUN pip install --no-cache-dir "setuptools<82" wheel

# Кешируем слой с зависимостями
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ===========================================
# Этап 2: Финальный легковесный образ
# ===========================================
FROM python:3.12.7-slim AS runtime

# Установка только необходимых системных зависимостей
RUN apt-get update && apt-get install -y \
  libglib2.0-0 \
  libsm6 \
  libxext6 \
  libxrender1 \
  libgl1-mesa-glx \
  && rm -rf /var/lib/apt/lists/*

# Рабочая директория
WORKDIR /app

# Копируем зависимости из builder-этапа
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Копируем код сервера
COPY app.py .
COPY segment_utils.py .

# Создаем непривилегированного пользователя
RUN useradd --create-home --shell /bin/bash app && \
  chown -R app:app /app
USER app

# Экспортируем порт
EXPOSE 8001

# Запуск сервера
CMD ["python", "app.py"]
