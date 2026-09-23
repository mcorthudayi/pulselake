#!/usr/bin/env bash
set -euo pipefail

POPULATION="${1:-100}"
SEED="${2:-42}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/tools"
OUT_DIR="$ROOT_DIR/data/synthea"
JAR="$TOOLS_DIR/synthea-with-dependencies.jar"
JAR_URL="https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar"

mkdir -p "$TOOLS_DIR" "$OUT_DIR"

if [ ! -f "$JAR" ]; then
  echo ">> Downloading Synthea..."
  curl -L --fail -o "$JAR" "$JAR_URL"
fi

echo ">> Cleaning previous output..."
rm -rf "$OUT_DIR/fhir"

echo ">> Generating $POPULATION patients (seed=$SEED)..."
docker run --rm \
  -v "$TOOLS_DIR:/tools:ro" \
  -v "$OUT_DIR:/output" \
  -w /tmp \
  eclipse-temurin:17-jre \
  java -jar /tools/synthea-with-dependencies.jar \
    -p "$POPULATION" \
    -s "$SEED" \
    --exporter.baseDirectory /output/ \
    --exporter.fhir.export true

echo ">> Done. Bundles written to $OUT_DIR/fhir"
ls "$OUT_DIR/fhir" | wc -l | xargs echo ">> File count:"
