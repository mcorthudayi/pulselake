#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLE="${1:-clinician}"

case "$ROLE" in
  clinician) NAME="dr.grey" ;;
  analyst) NAME="ana.lyst" ;;
  auditor) NAME="au.ditor" ;;
  *) echo "Usage: $0 [clinician|analyst|auditor]" >&2; exit 1 ;;
esac

TOKEN=$(dotnet user-jwts create --project "$ROOT_DIR/api/PulseLake.Api" --name "$NAME" --role "$ROLE" --output token)
URL="http://127.0.0.1:5173/#token=$TOKEN"

if command -v open > /dev/null 2>&1; then
  open "$URL"
  echo "Opened portal as $NAME ($ROLE)"
else
  echo "Open this URL in your browser: $URL"
fi
