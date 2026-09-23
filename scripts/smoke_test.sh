#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="${API_URL:-http://localhost:5080}"
PROJECT="$ROOT_DIR/api/PulseLake.Api"

set -a
source "$ROOT_DIR/.env"
set +a

passed=0
failed=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32mPASS\033[0m  %-48s %s\n' "$name" "$actual"
    passed=$((passed + 1))
  else
    printf '  \033[31mFAIL\033[0m  %-48s expected %s, got %s\n' "$name" "$expected" "$actual"
    failed=$((failed + 1))
  fi
}

http() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
mint() { dotnet user-jwts create --project "$PROJECT" --name "$1" --role "$2" --output token; }
sql() { docker exec pulselake-postgres psql -At -U "$1" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$2"; }
blocked() { if sql "$1" "$2" > /dev/null 2>&1; then echo allowed; else echo blocked; fi; }

echo "Minting test tokens..."
CLINICIAN=$(mint smoke.clinician clinician)
ANALYST=$(mint smoke.analyst analyst)
AUDITOR=$(mint smoke.auditor auditor)
PATIENT_ID=$(sql "$POSTGRES_USER" "SELECT patient_id FROM marts.dim_patients ORDER BY patient_id LIMIT 1")

echo
echo "API contract"
check "health endpoint" 200 "$(http "$API/health")"
check "capability statement is public" 200 "$(http "$API/fhir/metadata")"
check "anonymous FHIR request is rejected" 401 "$(http "$API/fhir/Patient")"
check "clinician reads a Patient" 200 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/fhir/Patient/$PATIENT_ID")"
check "clinician searches patients by name" 200 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/fhir/Patient?name=a")"
check "clinician searches observations" 200 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/fhir/Observation?patient=$PATIENT_ID")"
check "unsupported resource type" 404 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/fhir/Account/abc")"
check "invalid resource id" 400 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/fhir/Patient/bad%20id")"
check "search without patient parameter" 400 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/fhir/Condition")"

echo
echo "Role-based access control"
check "analyst blocked from identified FHIR" 403 "$(http -H "Authorization: Bearer $ANALYST" "$API/fhir/Patient/$PATIENT_ID")"
check "analyst reads de-identified stats" 200 "$(http -H "Authorization: Bearer $ANALYST" "$API/deid/stats/top-conditions")"
check "analyst blocked from audit log" 403 "$(http -H "Authorization: Bearer $ANALYST" "$API/audit/access-log")"
check "clinician blocked from audit log" 403 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/audit/access-log")"
check "clinician blocked from de-identified data" 403 "$(http -H "Authorization: Bearer $CLINICIAN" "$API/deid/patients")"
check "auditor reads audit log" 200 "$(http -H "Authorization: Bearer $AUDITOR" "$API/audit/access-log")"
check "auditor blocked from identified FHIR" 403 "$(http -H "Authorization: Bearer $AUDITOR" "$API/fhir/Patient/$PATIENT_ID")"

echo
echo "Database guarantees"
sleep 1
AUDITED=$(sql "$POSTGRES_USER" "SELECT count(*) FROM audit.access_log WHERE user_name LIKE 'smoke.%' OR user_name IS NULL")
check "requests are written to the audit log" yes "$([ "$AUDITED" -ge 14 ] && echo yes || echo no)"
check "audit log rejects DELETE" blocked "$(blocked "$POSTGRES_USER" "DELETE FROM audit.access_log")"
check "audit log rejects UPDATE" blocked "$(blocked "$POSTGRES_USER" "UPDATE audit.access_log SET status_code = 200")"
check "audit log rejects TRUNCATE" blocked "$(blocked "$POSTGRES_USER" "TRUNCATE audit.access_log")"
check "API role cannot read marts" blocked "$(blocked pulselake_api "SELECT 1 FROM marts.dim_patients LIMIT 1")"
check "API role cannot read the salt" blocked "$(blocked pulselake_api "SELECT salt FROM security.deid_config")"
check "API role cannot modify FHIR data" blocked "$(blocked pulselake_api "DELETE FROM raw.fhir_resources WHERE false")"

total=$((passed + failed))
echo
if [ "$failed" -eq 0 ]; then
  printf '\033[32m%d/%d checks passed\033[0m\n' "$passed" "$total"
else
  printf '\033[31m%d of %d checks failed\033[0m\n' "$failed" "$total"
  exit 1
fi
