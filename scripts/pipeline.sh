#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

POPULATION="${POPULATION:-100}"
SEED="${SEED:-42}"
FORCE_GENERATE="${FORCE_GENERATE:-0}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

if [ ! -f .env ]; then
  echo "Missing .env. Run: cp .env.example .env and set strong passwords." >&2
  exit 1
fi

set -a
source .env
set +a

for name in POSTGRES_PASSWORD API_DB_PASSWORD; do
  if [ "${!name}" = "change_me" ]; then
    echo "$name is still 'change_me' in .env. Set a strong value first." >&2
    exit 1
  fi
done

if ! python -c "import psycopg" 2>/dev/null || ! command -v dbt >/dev/null 2>&1; then
  echo "Python dependencies missing. Run: source .venv/bin/activate" >&2
  exit 1
fi

step "Starting PostgreSQL"
docker compose up -d --wait

step "Applying database migrations"
for file in db/init/*.sql; do
  echo "   $file"
  docker exec -i -e PGOPTIONS='-c client_min_messages=warning' pulselake-postgres \
    psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 < "$file"
done

if [ "$FORCE_GENERATE" = "1" ] || [ -z "$(ls -A data/synthea/fhir 2>/dev/null)" ]; then
  step "Generating $POPULATION synthetic patients"
  ./scripts/generate_synthea.sh "$POPULATION" "$SEED"
else
  step "Synthetic data found, skipping generation (FORCE_GENERATE=1 to regenerate)"
fi

step "Loading FHIR bundles into the raw layer"
python ingestion/load_fhir.py

step "Building dbt models and running data quality tests"
./scripts/dbt.sh build

step "Configuring least-privilege API role"
./scripts/setup_api_role.sh > /dev/null

step "Summary"
docker exec pulselake-postgres psql -P pager=off -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
SELECT 'raw resources' AS layer, count(*) FROM raw.fhir_resources
UNION ALL SELECT 'patients', count(*) FROM marts.dim_patients
UNION ALL SELECT 'encounters', count(*) FROM marts.fct_encounters
UNION ALL SELECT 'conditions', count(*) FROM marts.fct_conditions
UNION ALL SELECT 'observations', count(*) FROM marts.fct_observations
UNION ALL SELECT 'de-identified patients', count(*) FROM deid.deid_patients;"

printf '\nPipeline finished in %ss\n' "$SECONDS"
