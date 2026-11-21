# ДЗ по Docker

## Запуск

### Один контейнер (4 балла)

```bash

docker build -t counter-app .

docker run -d --name counter-single -p 8080:8000 -e GREETING="Привет из Docker!" counter-app

```

### Docker Compose (6-10 баллов)

Перед запуском скопировать `.env.example` в `.env` (там задаются `APP_PORT` - внешний порт на хосте и `GREETING` - строка приветствия):

```bash

cp .env.example .env

docker compose up -d --build

```

Остановка:

```bash

docker compose down     # остановить контейнеры, volume с данными сохраняется

docker compose down -v  # удалить контейнеры вместе с volume

```

Автопроверка для 10 баллов:

```bash

./scripts/check.sh

```

## Отчет

### 4 балла

```text

$ docker logs counter-single

2026-11-21 16:24:58,172 listening port=8000 storage=sqlite

2026-11-21 16:25:11,811 http 172.17.0.1 "GET / HTTP/1.1" 200 -

2026-11-21 16:25:21,945 http 172.17.0.1 "POST /increment HTTP/1.1" 200 -

2026-11-21 16:25:28,071 http 172.17.0.1 "POST /increment HTTP/1.1" 200 -

2026-11-21 16:25:34,048 http 172.17.0.1 "GET / HTTP/1.1" 200 -

```

### 6 баллов

```text

$ curl -fsS -X POST http://127.0.0.1:8080/increment

{"greeting": "Привет из Docker Compose!", "count": 2, "hostname": "3a40cca65e28", "storage": "sqlite"}

$ docker compose down

$ docker compose up -d

$ curl -fsS http://127.0.0.1:8080/

{"greeting": "Привет из Docker Compose!", "count": 2, "hostname": "bf46603eeb87", "storage": "sqlite"}

```

### 8 баллов

```text

$ curl -fsS -X POST http://127.0.0.1:8080/increment

{"greeting": "Привет из Docker Compose!", "count": 3, "hostname": "458d576d12fd", "storage": "redis"}

$ docker compose down && docker compose up -d

$ curl -fsS http://127.0.0.1:8080/

{"greeting": "Привет из Docker Compose!", "count": 3, "hostname": "d08cb2642e73", "storage": "redis"}

$ docker compose stop redis

$ curl -i -s http://127.0.0.1:8080/healthz

HTTP/1.0 200 OK

{"status": "alive"}

$ curl -i -s http://127.0.0.1:8080/readyz

HTTP/1.0 503 Service Unavailable

{"error": "storage_unavailable"}

$ curl -i -s -X POST http://127.0.0.1:8080/increment

HTTP/1.0 503 Service Unavailable

{"error": "storage_unavailable"}

$ docker compose start redis

$ curl -fsS http://127.0.0.1:8080/

{"greeting": "Привет из Docker Compose!", "count": 3, "hostname": "d08cb2642e73", "storage": "redis"}

$ curl -fsS -X POST http://127.0.0.1:8080/increment

{"greeting": "Привет из Docker Compose!", "count": 4, "hostname": "d08cb2642e73", "storage": "redis"}

```

### 10 баллов

```text

$ ./scripts/check.sh

==> 1. Запуск тестового Compose-проекта

==> 1.1. Проверка ограничений безопасности app (UID != 0, read-only)

==> 2. Проверка начального счётчика 0 и N инкрементов

GET /: {"greeting": "Привет из Docker Compose!", "count": 0, "hostname": "9b9584015792", "storage": "redis"}

GET / после 5 инкрементов: {"greeting": "Привет из Docker Compose!", "count": 5, "hostname": "9b9584015792", "storage": "redis"}

==> 3. Пересоздание только контейнера app

GET / после пересоздания app: {"greeting": "Привет из Docker Compose!", "count": 5, "hostname": "b4e4f5d5ab3e", "storage": "redis"}

==> 4. Проверка остановки и повторного запуска Redis

GET / после возврата Redis: {"greeting": "Привет из Docker Compose!", "count": 5, "hostname": "b4e4f5d5ab3e", "storage": "redis"}

POST /increment после возврата Redis: {"greeting": "Привет из Docker Compose!", "count": 6, "hostname": "b4e4f5d5ab3e", "storage": "redis"}

==> 5. Создание согласованной резервной копии данных Redis

==> 6. Удаление исходного тестового проекта через down -v

==> 7. Проверка восстановления данных из резервной копии

GET / после восстановления из бэкапа: {"greeting": "Привет из Docker Compose!", "count": 6, "hostname": "bf332c38bd06", "storage": "redis"}

ВСЕ ПРОВЕРКИ УСПЕШНО ПРОЙДЕНЫ!

Очистка тестовых ресурсов...

$ ./scripts/check.sh

==> 1. Запуск тестового Compose-проекта

==> 1.1. Проверка ограничений безопасности app (UID != 0, read-only)

==> 2. Проверка начального счётчика 0 и N инкрементов

GET /: {"greeting": "Привет из Docker Compose!", "count": 0, "hostname": "7779d65354ae", "storage": "redis"}

GET / после 5 инкрементов: {"greeting": "Привет из Docker Compose!", "count": 5, "hostname": "7779d65354ae", "storage": "redis"}

==> 3. Пересоздание только контейнера app

GET / после пересоздания app: {"greeting": "Привет из Docker Compose!", "count": 5, "hostname": "dc1105473240", "storage": "redis"}

==> 4. Проверка остановки и повторного запуска Redis

GET / после возврата Redis: {"greeting": "Привет из Docker Compose!", "count": 5, "hostname": "dc1105473240", "storage": "redis"}

POST /increment после возврата Redis: {"greeting": "Привет из Docker Compose!", "count": 6, "hostname": "dc1105473240", "storage": "redis"}

==> 5. Создание согласованной резервной копии данных Redis

==> 6. Удаление исходного тестового проекта через down -v

==> 7. Проверка восстановления данных из резервной копии

GET / после восстановления из бэкапа: {"greeting": "Привет из Docker Compose!", "count": 6, "hostname": "73d893afd569", "storage": "redis"}

ВСЕ ПРОВЕРКИ УСПЕШНО ПРОЙДЕНЫ!

Очистка тестовых ресурсов...

```

