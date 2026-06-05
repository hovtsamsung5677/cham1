# Nginx Reverse Proxy Configuration

## Endpoints

После запуска все запросы идут через nginx на порт 80:

| Endpoint         | Описание                   | Прокси к            |
| ---------------- | -------------------------- | ------------------- |
| `/segment`       | Сегментация изображения    | segment-server:8001 |
| `/segment-proxy` | Прокси-эндпоинт            | segment-server:8001 |
| `/health`        | Проверка здоровья          | segment-server:8001 |
| `/`              | Gradio интерфейс MobileSAM | mobilesam:7860      |

## Запуск

```bash
# Запуск всех сервисов
docker-compose up -d

# Проверка
curl http://localhost/health
curl http://localhost/segment  # POST запрос с изображением
```

## SSL/HTTPS (опционально)

Для продакшена разместите сертификаты в `nginx/ssl/`:

- `server.crt` - сертификат
- `server.key` - приватный ключ

Затем раскомментируйте блок SSL в `nginx.conf`.

## Полезные настройки

- `client_max_body_size 50M` - максимальный размер загружаемого изображения
- `proxy_read_timeout 120s` - увеличенный таймаут для сегментации
- Gzip сжатие включено для ускорения передачи данных
