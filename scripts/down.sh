#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

stop_port() {
  local port="$1" name="$2" pids
  pids=$(lsof -ti "tcp:$port" -sTCP:LISTEN || true)
  if [ -n "$pids" ]; then
    kill $pids
    echo "Stopped $name"
  else
    echo "$name was not running"
  fi
}

stop_port 5080 "API"
stop_port 5173 "Portal"

if [ "${1:-}" = "--all" ]; then
  docker compose stop
  echo "Stopped PostgreSQL"
fi
