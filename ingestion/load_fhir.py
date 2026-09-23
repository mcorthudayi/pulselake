from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import time
import uuid
from pathlib import Path

import psycopg
from dotenv import load_dotenv

log = logging.getLogger("pulselake.ingestion")

CREATE_STAGE_SQL = """
CREATE TEMP TABLE stage_resources (
    resource_type TEXT,
    resource_id   TEXT,
    resource      JSONB,
    content_hash  TEXT
) ON COMMIT DELETE ROWS
"""

COPY_SQL = "COPY stage_resources (resource_type, resource_id, resource, content_hash) FROM STDIN"

UPSERT_SQL = """
WITH upserted AS (
    INSERT INTO raw.fhir_resources
        (resource_type, resource_id, resource, content_hash, source_file, run_id)
    SELECT DISTINCT ON (resource_type, resource_id)
        resource_type, resource_id, resource, content_hash,
        %(source_file)s::text, %(run_id)s::uuid
    FROM stage_resources
    ORDER BY resource_type, resource_id
    ON CONFLICT (resource_type, resource_id) DO UPDATE
    SET resource       = EXCLUDED.resource,
        content_hash   = EXCLUDED.content_hash,
        source_file    = EXCLUDED.source_file,
        run_id         = EXCLUDED.run_id,
        last_loaded_at = now()
    WHERE raw.fhir_resources.content_hash IS DISTINCT FROM EXCLUDED.content_hash
    RETURNING (xmax = 0) AS inserted
)
SELECT
    count(*) FILTER (WHERE inserted)     AS inserted,
    count(*) FILTER (WHERE NOT inserted) AS updated
FROM upserted
"""

FINISH_RUN_SQL = """
UPDATE raw.ingestion_runs
SET finished_at         = now(),
    status              = %(status)s,
    files_failed        = %(files_failed)s,
    resources_inserted  = %(inserted)s,
    resources_updated   = %(updated)s,
    resources_unchanged = %(unchanged)s
WHERE run_id = %(run_id)s
"""


def connection_kwargs() -> dict[str, str]:
    return {
        "host": os.getenv("POSTGRES_HOST", "localhost"),
        "port": os.getenv("POSTGRES_PORT", "5433"),
        "dbname": os.getenv("POSTGRES_DB", "pulselake"),
        "user": os.getenv("POSTGRES_USER", "pulselake"),
        "password": os.environ["POSTGRES_PASSWORD"],
    }


def discover_files(input_dir: Path) -> list[Path]:
    files = sorted(input_dir.glob("*.json"))
    reference_prefixes = ("hospitalInformation", "practitionerInformation")
    reference = [f for f in files if f.name.startswith(reference_prefixes)]
    patients = [f for f in files if not f.name.startswith(reference_prefixes)]
    return reference + patients


def extract_resources(path: Path) -> tuple[list[tuple[str, str, str, str]], int]:
    with path.open("r", encoding="utf-8") as f:
        bundle = json.load(f)

    if bundle.get("resourceType") != "Bundle":
        raise ValueError(f"{path.name} is not a FHIR Bundle")

    rows: list[tuple[str, str, str, str]] = []
    skipped = 0
    for entry in bundle.get("entry", []):
        resource = entry.get("resource") or {}
        resource_type = resource.get("resourceType")
        resource_id = resource.get("id")
        if not resource_type or not resource_id:
            skipped += 1
            continue
        canonical = json.dumps(resource, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        rows.append((resource_type, resource_id, canonical, digest))
    return rows, skipped


def main() -> int:
    parser = argparse.ArgumentParser(description="Load Synthea FHIR bundles into raw.fhir_resources")
    parser.add_argument("--input-dir", type=Path, default=Path("data/synthea/fhir"))
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    load_dotenv()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if not os.getenv("POSTGRES_PASSWORD"):
        log.error("POSTGRES_PASSWORD is not set. Copy .env.example to .env and set a password.")
        return 1

    if not args.input_dir.is_dir():
        log.error("Input directory not found: %s (run scripts/generate_synthea.sh first)", args.input_dir)
        return 1

    files = discover_files(args.input_dir)
    if args.limit:
        files = files[: args.limit]
    if not files:
        log.error("No .json files found in %s", args.input_dir)
        return 1

    run_id = uuid.uuid4()
    totals = {"inserted": 0, "updated": 0, "unchanged": 0, "skipped": 0}
    files_failed = 0
    started = time.perf_counter()

    with psycopg.connect(autocommit=True, **connection_kwargs()) as conn:
        conn.execute(
            "INSERT INTO raw.ingestion_runs (run_id, files_total) VALUES (%s, %s)",
            (run_id, len(files)),
        )
        conn.execute(CREATE_STAGE_SQL)
        log.info("Run %s started: %d files", run_id, len(files))

        for index, path in enumerate(files, start=1):
            try:
                rows, skipped = extract_resources(path)
                unique_keys = len({(r[0], r[1]) for r in rows})

                with conn.transaction(), conn.cursor() as cur:
                    with cur.copy(COPY_SQL) as copy:
                        for row in rows:
                            copy.write_row(row)
                    cur.execute(UPSERT_SQL, {"source_file": path.name, "run_id": run_id})
                    inserted, updated = cur.fetchone()

                unchanged = unique_keys - inserted - updated
                totals["inserted"] += inserted
                totals["updated"] += updated
                totals["unchanged"] += unchanged
                totals["skipped"] += skipped

                log.info(
                    "[%d/%d] %s: +%d new, ~%d updated, =%d unchanged",
                    index, len(files), path.name, inserted, updated, unchanged,
                )
            except Exception:
                files_failed += 1
                log.exception("[%d/%d] Failed to load %s", index, len(files), path.name)

        if files_failed == 0:
            status = "succeeded"
        elif files_failed == len(files):
            status = "failed"
        else:
            status = "partial"

        conn.execute(
            FINISH_RUN_SQL,
            {
                "status": status,
                "files_failed": files_failed,
                "inserted": totals["inserted"],
                "updated": totals["updated"],
                "unchanged": totals["unchanged"],
                "run_id": run_id,
            },
        )

    elapsed = time.perf_counter() - started
    log.info(
        "Run %s %s in %.1fs | inserted=%d updated=%d unchanged=%d skipped=%d failed_files=%d",
        run_id, status, elapsed,
        totals["inserted"], totals["updated"], totals["unchanged"], totals["skipped"], files_failed,
    )
    return 0 if status == "succeeded" else 1


if __name__ == "__main__":
    raise SystemExit(main())
