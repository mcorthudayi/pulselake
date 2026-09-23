#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p logs

API_URL="http://localhost:5080"
PORTAL_URL="http://127.0.0.1:5173"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

wait_for() {
  local url="$1" name="$2" log="$3"
  for attempt in $(seq 1 90); do
    if curl -s -o /dev/null "$url"; then
      echo "   $name is up"
      return 0
    fi
    sleep 2
  done
  echo "$name did not start. Last lines of $log:" >&2
  tail -n 30 "$log" >&2
  exit 1
}

step "Checking environment"
if ! docker info > /dev/null 2>&1; then
  echo "   Starting Docker Desktop..."
  open -a Docker
  until docker info > /dev/null 2>&1; do sleep 2; done
fi

if [ ! -f .env ]; then
  cp .env.example .env
  sed -i.bak "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env
  sed -i.bak "s/^API_DB_PASSWORD=.*/API_DB_PASSWORD=$(openssl rand -hex 24)/" .env
  rm -f .env.bak
  echo "   Created .env with generated passwords"
fi

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
set +u
source .venv/bin/activate
set -u
if ! python -c "import psycopg" 2> /dev/null || ! command -v dbt > /dev/null 2>&1; then
  echo "   Installing Python dependencies..."
  pip install -q -r ingestion/requirements.txt -r transform/requirements.txt
fi

if [ ! -d portal/node_modules ]; then
  echo "   Installing portal dependencies..."
  (cd portal && npm install --silent)
fi
echo "   Environment ready"

step "Running data pipeline (log: logs/pipeline.log)"
if ./scripts/pipeline.sh > logs/pipeline.log 2>&1; then
  tail -n 13 logs/pipeline.log
else
  tail -n 40 logs/pipeline.log >&2
  exit 1
fi

step "Starting API (log: logs/api.log)"
if curl -sf "$API_URL/health" > /dev/null; then
  echo "   API already running"
else
  dotnet user-jwts create --project api/PulseLake.Api --name bootstrap --role auditor --output token > /dev/null
  nohup ./scripts/api.sh > logs/api.log 2>&1 < /dev/null &
  wait_for "$API_URL/health" "API" logs/api.log
fi

step "Starting portal (log: logs/portal.log)"
if curl -s -o /dev/null "$PORTAL_URL"; then
  echo "   Portal already running"
else
  (cd portal && nohup npm run dev > ../logs/portal.log 2>&1 < /dev/null &)
  wait_for "$PORTAL_URL" "Portal" logs/portal.log
fi

if [ "${SKIP_SMOKE:-0}" != "1" ]; then
  step "Running smoke tests (log: logs/smoke.log)"
  if ./scripts/smoke_test.sh > logs/smoke.log 2>&1; then
    tail -n 1 logs/smoke.log
  else
    cat logs/smoke.log >&2
    exit 1
  fi
fi

step "Opening portal"
./scripts/login.sh clinician

printf '\n\033[1;32mPulseLake is running\033[0m\n'
printf '  Portal   %s\n' "$PORTAL_URL"
printf '  API      %s\n' "$API_URL"
printf '  Logs     logs/\n\n'
printf 'Switch role:  ./scripts/login.sh analyst | auditor | clinician\n'
printf 'Stop:         ./scripts/down.sh   (add --all to stop PostgreSQL too)\n'
printf 'Started in %ss\n' "$SECONDS"
