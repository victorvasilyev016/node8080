#!/usr/bin/env bash
set -euo pipefail
cd /app

log() {
  echo "[entrypoint] $*"
}

# 1) .env
if [ -f ".env" ]; then
  export $(grep -v '^\s*#' .env | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | xargs -d '\n')
fi

# 2) PORT от Timeweb
if [ -n "${PORT:-}" ]; then
  export SERVICE_PORT="$PORT"
fi

# 3) Base64 → файл
decode_b64() {
  local var="$1"
  local out="$2"
  local data="${!var:-}"
  if [ -z "$data" ]; then
    log "ERROR: переменная $var пуста!"
    exit 1
  fi
  echo "$data" | base64 -d > "$out" 2>/dev/null || {
    log "ERROR: не удалось декодировать $var"
    head -c 50 <<< "$data"
    exit 1
  }
  chmod 600 "$out"
  log "Created $out (size: $(stat -c%s "$out") bytes)"
}

decode_b64 CLIENT_PEM_B64 "$SSL_CLIENT_CERT_FILE"
decode_b64 SERVER_KEY_B64 "$SSL_KEY_FILE"
decode_b64 SERVER_CERT_B64 "$SSL_CERT_FILE"

# 4) Проверяем файлы
for f in "$SSL_CLIENT_CERT_FILE" "$SSL_KEY_FILE" "$SSL_CERT_FILE"; do
  if [ ! -s "$f" ]; then
    log "ERROR: файл $f не создан или пуст!"
    ls -l /app
    exit 1
  fi
done

# 5) Запуск
log "All certs present, starting MarzNode..."
exec python3 /app/marznode.py
