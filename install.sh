#!/usr/bin/env bash
# Общий чат с Claude для команды на Маке (Apple Silicon / Intel).
# Ставит Docker (OrbStack) и Open WebUI с автозапуском, опционально публикует через Tailscale.
# Запуск: bash install.sh
set -euo pipefail

PORT="${PORT:-3000}"
NAME="open-webui"
IMAGE="ghcr.io/open-webui/open-webui:main-slim"
CONF_DIR="$HOME/.open-webui"
ENV_FILE="$CONF_DIR/env"

say() { printf "\n\033[1;32m▶ %s\033[0m\n" "$*"; }
die() { printf "\n\033[1;31m✖ %s\033[0m\n" "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Скрипт рассчитан на macOS."

# 1. Homebrew
if ! command -v brew >/dev/null 2>&1; then
  say "Устанавливаю Homebrew (попросит пароль от Мака)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
fi

# 2. Docker через OrbStack (лёгкий, нативный для M1)
if ! command -v docker >/dev/null 2>&1; then
  say "Устанавливаю OrbStack (Docker для Мака)"
  brew install --cask orbstack
fi
open -ga OrbStack || true
say "Жду, пока запустится Docker"
for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info >/dev/null 2>&1 || die "Docker не запустился. Откройте OrbStack вручную и запустите скрипт ещё раз."

# 3. Настройки и учётка администратора (спрашиваются один раз)
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
if [[ ! -f "$ENV_FILE" ]]; then
  say "Создаём администратора чата"
  read -r -p "Email администратора: " ADMIN_EMAIL
  read -r -s -p "Пароль администратора: " ADMIN_PASS; echo
  [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASS" ]] || die "Email и пароль обязательны."
  umask 077
  cat > "$ENV_FILE" <<EOF
WEBUI_ADMIN_EMAIL=$ADMIN_EMAIL
WEBUI_ADMIN_PASSWORD=$ADMIN_PASS
WEBUI_ADMIN_NAME=Admin
WEBUI_SECRET_KEY=$(openssl rand -base64 32)
ENABLE_SIGNUP=false
ENABLE_OLLAMA_API=false
DEFAULT_LOCALE=ru-RU
WEBUI_NAME=AI для команды
EOF
fi

# 4. Open WebUI с автозапуском
say "Запускаю Open WebUI"
docker pull "$IMAGE"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart always \
  -p "127.0.0.1:$PORT:8080" --env-file "$ENV_FILE" \
  -v open-webui:/app/backend/data "$IMAGE" >/dev/null

say "Жду готовности интерфейса"
for _ in $(seq 1 90); do curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break; sleep 2; done
curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 || die "Интерфейс не поднялся: docker logs $NAME"

# 5. Удалённый доступ через Tailscale (если приложение установлено и выполнен вход)
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
if [[ -x "$TS" ]] && "$TS" status >/dev/null 2>&1; then
  say "Публикую чат в вашей сети Tailscale"
  "$TS" serve --bg "$PORT" >/dev/null
  URL="$("$TS" serve status 2>/dev/null | grep -Eo 'https://[^ ]+' | head -1 || true)"
else
  URL=""
fi

# 6. Мак не должен засыпать, иначе чат недоступен
say "Отключаю сон Мака при питании от сети (попросит пароль)"
sudo pmset -c sleep 0 || true

say "Готово!"
echo "  На этом Маке:      http://localhost:$PORT"
[[ -n "$URL" ]] && echo "  Для сотрудников:   $URL" \
  || echo "  Для удалённого доступа установите Tailscale (tailscale.com/download), войдите и запустите скрипт ещё раз."
echo "  Дальше: войдите как администратор → Настройки администратора → Подключения → добавьте ключ API."
