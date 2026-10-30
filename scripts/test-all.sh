#!/usr/bin/env sh
# Roda todas as verificações do monorepo (Linux/macOS/Git Bash).
# Uso: scripts/test-all.sh [tokens] [api] [mobile] [web]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STEPS=${*:-"tokens api mobile web"}
FAILED=""

# Ambiente virtual: Scripts/ no Windows (Git Bash), bin/ nos demais.
VENV_BIN="$ROOT/services/api/.venv/bin"
[ -d "$VENV_BIN" ] || VENV_BIN="$ROOT/services/api/.venv/Scripts"

# DB_MODE do ambiente ou do .env: "docker" (padrão) sobe o db-test; "local" usa o PostgreSQL da máquina.
if [ -z "${DB_MODE:-}" ] && [ -f "$ROOT/.env" ]; then
  DB_MODE=$(sed -n 's/^[[:space:]]*DB_MODE[[:space:]]*=[[:space:]]*//p' "$ROOT/.env" | tail -n 1 | tr -d '\r')
fi
DB_MODE=${DB_MODE:-docker}

run() {
  name=$1; shift
  printf '\n=== %s ===\n' "$name"
  if (set -e; "$@"); then echo "OK: $name"; else echo "FALHOU: $name"; FAILED="$FAILED $name"; fi
}

step_tokens() { cd "$ROOT" && python scripts/generate_tokens.py --check; }
step_api() {
  cd "$ROOT/services/api" &&
    { [ "$DB_MODE" != docker ] || docker compose -f ../../docker-compose.yml up -d --wait db-test; } &&
    "$VENV_BIN/ruff" check . && "$VENV_BIN/ruff" format --check . &&
    "$VENV_BIN/python" -m pytest
}
step_mobile() {
  cd "$ROOT/apps/mobile" &&
    dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test
}
step_web() { cd "$ROOT/apps/web" && npm run typecheck && npm run lint && npm test; }

for s in $STEPS; do run "$s" "step_$s"; done

if [ -n "$FAILED" ]; then printf '\nFalhas:%s\n' "$FAILED"; exit 1; fi
printf '\nTodas as verificações passaram.\n'
