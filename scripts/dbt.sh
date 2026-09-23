#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set -a
source "$ROOT_DIR/.env"
set +a

cd "$ROOT_DIR/transform"
exec dbt "$@" --profiles-dir "$ROOT_DIR/transform" --project-dir "$ROOT_DIR/transform"
