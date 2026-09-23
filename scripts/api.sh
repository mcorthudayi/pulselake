#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set -a
source "$ROOT_DIR/.env"
set +a

export ConnectionStrings__PulseLake="Host=${POSTGRES_HOST};Port=${POSTGRES_PORT};Database=${POSTGRES_DB};Username=pulselake_api;Password=${API_DB_PASSWORD}"
exec dotnet run --project "$ROOT_DIR/api/PulseLake.Api" --launch-profile http
