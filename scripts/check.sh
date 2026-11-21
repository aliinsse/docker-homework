#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

STEP="инициализация"
PROJECT="hw3_test_$$_$(date +%s)"
RESTORE_PROJECT="${PROJECT}_restore"
TEST_PORT="${TEST_PORT:-18080}"
BASE_URL="http://127.0.0.1:${TEST_PORT}"
TMP_DIR="$(mktemp -d)"
BACKUP_FILE="${TMP_DIR}/redis_backup.tar.gz"

cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "ОШИБКА на этапе: ${STEP} (код выхода: ${exit_code})" >&2
  fi
  echo "Очистка тестовых ресурсов..."
  APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" down -v --remove-orphans >/dev/null 2>&1 || true
  APP_PORT="$TEST_PORT" docker compose -p "$RESTORE_PROJECT" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

wait_ready() {
  local expected_code="$1"
  local timeout=30
  local elapsed=0
  local code="000"
  while [ $elapsed -lt $timeout ]; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "${BASE_URL}/readyz" || echo "000")
    if [ "$code" = "$expected_code" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "Таймаут ожидания /readyz == ${expected_code} (последний код: ${code})" >&2
  return 1
}

assert_count() {
  local json="$1"
  local expected="$2"
  if ! echo "$json" | grep -Eq "\"count\":[[:space:]]*${expected}\b"; then
    echo "Ожидался count=${expected}, получено: ${json}" >&2
    exit 1
  fi
}
STEP="1. Запуск тестового Compose-проекта"
echo "==> $STEP"
APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" up -d --build
wait_ready "200"
STEP="1.1. Проверка ограничений безопасности app (UID != 0, read-only)"
echo "==> $STEP"
APP_CID=$(APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" ps -q app)
APP_UID=$(docker exec "$APP_CID" id -u)
[ "$APP_UID" != "0" ] || { echo "Ожидался не-root UID, получен 0" >&2; exit 1; }
READ_ONLY=$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$APP_CID")
[ "$READ_ONLY" = "true" ] || { echo "Ожидался ReadonlyRootfs=true, получено $READ_ONLY" >&2; exit 1; }
STEP="2. Проверка начального счётчика 0 и N инкрементов"
echo "==> $STEP"
INIT_RESP=$(curl -fsS --max-time 5 "${BASE_URL}/")
echo "GET /: $INIT_RESP"
assert_count "$INIT_RESP" 0

N=5
for _ in $(seq 1 $N); do
  curl -fsS --max-time 5 -X POST "${BASE_URL}/increment" >/dev/null
done
AFTER_INC=$(curl -fsS --max-time 5 "${BASE_URL}/")
echo "GET / после $N инкрементов: $AFTER_INC"
assert_count "$AFTER_INC" "$N"
STEP="3. Пересоздание только контейнера app"
echo "==> $STEP"
APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" up -d --force-recreate --no-deps app
wait_ready "200"
AFTER_RECREATE=$(curl -fsS --max-time 5 "${BASE_URL}/")
echo "GET / после пересоздания app: $AFTER_RECREATE"
assert_count "$AFTER_RECREATE" "$N"
STEP="4. Проверка остановки и повторного запуска Redis"
echo "==> $STEP"
APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" stop redis

HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${BASE_URL}/healthz")
READY_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${BASE_URL}/readyz")
INC_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X POST "${BASE_URL}/increment")

[ "$HEALTH_CODE" = "200" ] || { echo "Ожидался 200 от /healthz, получен $HEALTH_CODE" >&2; exit 1; }
[ "$READY_CODE" = "503" ] || { echo "Ожидался 503 от /readyz, получен $READY_CODE" >&2; exit 1; }
[ "$INC_CODE" = "503" ] || { echo "Ожидался 503 от POST /increment, получен $INC_CODE" >&2; exit 1; }

APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" start redis
wait_ready "200"

AFTER_REDIS_BACK=$(curl -fsS --max-time 5 "${BASE_URL}/")
echo "GET / после возврата Redis: $AFTER_REDIS_BACK"
assert_count "$AFTER_REDIS_BACK" "$N"

N_PLUS_1=$((N + 1))
AFTER_NEXT_POST=$(curl -fsS --max-time 5 -X POST "${BASE_URL}/increment")
echo "POST /increment после возврата Redis: $AFTER_NEXT_POST"
assert_count "$AFTER_NEXT_POST" "$N_PLUS_1"
STEP="5. Создание согласованной резервной копии данных Redis"
echo "==> $STEP"
APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" stop app redis
docker run --rm \
  -v "${PROJECT}_redis_data:/data:ro" \
  -v "${TMP_DIR}:/backup" \
  alpine tar -czpf /backup/redis_backup.tar.gz -C /data .

[ -s "$BACKUP_FILE" ] || { echo "Файл резервной копии не создан или пуст" >&2; exit 1; }
STEP="6. Удаление исходного тестового проекта через down -v"
echo "==> $STEP"
APP_PORT="$TEST_PORT" docker compose -p "$PROJECT" down -v
STEP="7. Проверка восстановления данных из резервной копии"
echo "==> $STEP"
docker volume create \
  --label "com.docker.compose.project=${RESTORE_PROJECT}" \
  --label "com.docker.compose.volume=redis_data" \
  "${RESTORE_PROJECT}_redis_data" >/dev/null

docker run --rm \
  -v "${RESTORE_PROJECT}_redis_data:/data" \
  -v "${TMP_DIR}:/backup:ro" \
  alpine tar -xzpf /backup/redis_backup.tar.gz -C /data

APP_PORT="$TEST_PORT" docker compose -p "$RESTORE_PROJECT" up -d
wait_ready "200"

RESTORED_RESP=$(curl -fsS --max-time 5 "${BASE_URL}/")
echo "GET / после восстановления из бэкапа: $RESTORED_RESP"
assert_count "$RESTORED_RESP" "$N_PLUS_1"

echo "ВСЕ ПРОВЕРКИ УСПЕШНО ПРОЙДЕНЫ!"
