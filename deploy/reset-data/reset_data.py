"""Deletes every shipment and its proof-of-delivery files, and optionally seeds five demo shipments (ADR-0036).

The GCP counterpart of the platform's reset (platform ADR-0034): the same tables, the same order, the same five
demo shipments, and the same output lines. It runs in the cluster as a Job from the release's own image
(deploy/reset-data/job.yaml), because the database is private and the cluster is the one place that reaches it.

In this order, so that a failure leaves the database and the files agreeing as far as possible:
  1. the database, in one transaction, as the application role;
  2. the objects under proof-of-delivery/ in the proof-of-delivery bucket.

Deleted: sla_alerts, pod_documents, tracking_events, shipments, in foreign-key order.
Kept: carriers (reference data) and the schema.

The seeded shipments have fixed tracking numbers so that they can be looked up by hand:
  MF0000000001 Created, MF0000000002 Picked up, MF0000000003 In transit,
  MF0000000004 Out for delivery, MF0000000005 Delivered

Output is lines of numbers and these synthetic tracking numbers:
  RESET_DATA deleted shipments=<n> tracking_events=<n> pod_documents=<n> sla_alerts=<n>
  RESET_DATA now shipments=<n> carriers=<n>
  SEEDED MF0000000001 MF0000000002 ...
  RESET_DATA objects_removed=<n>

Environment: RESET_CONFIRM (must be delete-all-shipments), RESET_SEED (yes or no), and RESET_BUCKET. In the
cluster, SHIPTRACK_CLOUD, SHIPTRACK_GCP_PROJECT, and SHIPTRACK_DB_SECRET_NAME select the application's
credentials. For tests, RESET_DATABASE_URL connects directly and an empty RESET_BUCKET skips the bucket.
"""

from __future__ import annotations

import os
import sys

import psycopg

CONFIRMATION = "delete-all-shipments"
PREFIX = "proof-of-delivery/"
DEMO = ("MF0000000001", "MF0000000002", "MF0000000003", "MF0000000004", "MF0000000005")
TABLES = ("sla_alerts", "pod_documents", "tracking_events", "shipments")

# One statement: the shipments, then each one's events, which hang off the rows just inserted. The carrier is
# ACME when it exists, otherwise the first one. A number that is already taken is left alone. The same
# statement as the platform's db/reset-data.sql.
SEED_SQL = """
WITH seed (idx, tracking_number, origin, destination, steps) AS (
  VALUES
    (0, 'MF0000000001', 'Rotterdam', 'Hamburg', 0),
    (1, 'MF0000000002', 'Leeds',     'Cardiff', 1),
    (2, 'MF0000000003', 'Lyon',      'Gdansk',  2),
    (3, 'MF0000000004', 'Bilbao',    'Antwerp', 3),
    (4, 'MF0000000005', 'Hamburg',   'Leeds',   4)
),
carrier AS (
  SELECT id FROM shiptrack.carriers ORDER BY (code = 'ACME') DESC, id LIMIT 1
),
inserted AS (
  INSERT INTO shiptrack.shipments (
    tracking_number, carrier_id, origin, destination, status,
    promised_delivery_at, estimated_delivery_at, delivered_at, last_event_at,
    created_at, updated_at
  )
  SELECT
    s.tracking_number, carrier.id, s.origin, s.destination,
    (ARRAY['CREATED', 'PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED'])[s.steps + 1],
    now() + interval '2 days',
    CASE WHEN s.steps > 0 THEN now() + interval '2 days' - interval '3 hours' END,
    CASE WHEN s.steps = 4 THEN made.at + s.steps * interval '3 hours' END,
    CASE WHEN s.steps > 0 THEN made.at + s.steps * interval '3 hours' END,
    made.at,
    COALESCE(made.at + s.steps * interval '3 hours', made.at)
  FROM seed s
  CROSS JOIN carrier
  CROSS JOIN LATERAL (SELECT now() - (30 - s.idx) * interval '1 hour' AS at) made
  ON CONFLICT (tracking_number) DO NOTHING
  RETURNING id, tracking_number, created_at
)
INSERT INTO shiptrack.tracking_events (
  shipment_id, event_type, location, occurred_at, idempotency_key, applied
)
SELECT
  i.id,
  (ARRAY['PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED'])[g.n],
  (ARRAY['Origin depot', 'Sorting hub', 'Local depot', 'Destination'])[g.n],
  i.created_at + g.n * interval '3 hours',
  'seed-' || i.tracking_number || '-'
    || (ARRAY['PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED'])[g.n],
  true
FROM inserted i
JOIN seed s ON s.tracking_number = i.tracking_number
CROSS JOIN LATERAL generate_series(1, s.steps) AS g (n)
ON CONFLICT (idempotency_key) DO NOTHING
"""


def reset_database(connection: psycopg.Connection, seed: bool) -> list[str]:
    """Runs the deletes and the seed in one transaction and returns the output lines."""
    with connection.transaction():
        deleted = {table: connection.execute(f"DELETE FROM shiptrack.{table}").rowcount for table in TABLES}
        lines = [
            (
                f"RESET_DATA deleted shipments={deleted['shipments']}"
                f" tracking_events={deleted['tracking_events']}"
                f" pod_documents={deleted['pod_documents']} sla_alerts={deleted['sla_alerts']}"
            )
        ]
        if seed:
            if connection.execute("SELECT 1 FROM shiptrack.carriers LIMIT 1").fetchone() is None:
                raise RuntimeError("there is no carrier to seed shipments with")
            connection.execute(SEED_SQL)
        row = connection.execute(
            "SELECT (SELECT count(*) FROM shiptrack.shipments), (SELECT count(*) FROM shiptrack.carriers)"
        ).fetchone()
        assert row is not None
        lines.append(f"RESET_DATA now shipments={row[0]} carriers={row[1]}")
        if seed:
            seeded = [
                found
                for (found,) in connection.execute(
                    "SELECT tracking_number FROM shiptrack.shipments WHERE tracking_number = ANY(%s)"
                    " ORDER BY tracking_number",
                    (list(DEMO),),
                )
            ]
            if seeded:
                lines.append("SEEDED " + " ".join(seeded))
    return lines


def remove_documents(bucket_name: str) -> int:
    """Deletes every object under the proof-of-delivery prefix; nothing in the database points at them any more."""
    import google.cloud.storage  # noqa: PLC0415 - only the cluster run needs it

    client = google.cloud.storage.Client(project=os.environ["SHIPTRACK_GCP_PROJECT"])
    removed = 0
    for blob in client.list_blobs(bucket_name, prefix=PREFIX):
        blob.delete()
        removed += 1
    return removed


def connect() -> psycopg.Connection:
    url = os.environ.get("RESET_DATABASE_URL")
    if url:
        return psycopg.connect(url, autocommit=True, connect_timeout=10)
    from shiptrack.cloud import build_secret_cache  # noqa: PLC0415 - from the release's image
    from shiptrack.config import load_settings  # noqa: PLC0415

    settings = load_settings()
    creds = build_secret_cache(settings).get(settings.require_db_secret())
    return psycopg.connect(
        host=creds.host,
        port=creds.port,
        dbname=creds.dbname,
        user=creds.username,
        password=creds.password,
        sslmode=settings.db_sslmode,
        connect_timeout=10,
        autocommit=True,
    )


def main() -> int:
    if os.environ.get("RESET_CONFIRM") != CONFIRMATION:
        print(f"refused: RESET_CONFIRM must be {CONFIRMATION}", file=sys.stderr)
        return 1
    seed = os.environ.get("RESET_SEED")
    if seed not in ("yes", "no"):
        print("RESET_SEED must be yes or no", file=sys.stderr)
        return 1
    bucket = os.environ.get("RESET_BUCKET", "")
    if not bucket and not os.environ.get("RESET_DATABASE_URL"):
        print("RESET_BUCKET is required", file=sys.stderr)
        return 1

    with connect() as connection:
        lines = reset_database(connection, seed == "yes")
    for line in lines:
        print(line, flush=True)
    if bucket:
        print(f"RESET_DATA objects_removed={remove_documents(bucket)}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
