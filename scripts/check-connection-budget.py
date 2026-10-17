#!/usr/bin/env python3
"""Fail when the rendered chart could open more database connections than the budget allows.

Reads the output of `helm template` and, for each workload that talks to the database, multiplies its
replicas by its connection pool (size plus overflow). A Deployment's replica count is in its spec, and a
CronJob or a Job runs once. The budget is that of a `db-f1-micro` instance (ADR-0018).

Usage: scripts/check-connection-budget.py RENDERED.yaml [--budget 21]
"""

from __future__ import annotations

import argparse
import sys

import yaml


def env(container: dict) -> dict[str, str]:
    return {e["name"]: str(e.get("value", "")) for e in container.get("env", [])}


def pod_spec(doc: dict) -> dict:
    spec = doc["spec"]
    if doc["kind"] == "CronJob":
        return spec["jobTemplate"]["spec"]["template"]["spec"]
    return spec["template"]["spec"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rendered")
    parser.add_argument("--budget", type=int, default=21)
    args = parser.parse_args()

    rows: list[tuple[str, int, int]] = []
    with open(args.rendered) as handle:
        for doc in yaml.safe_load_all(handle):
            if not doc or doc.get("kind") not in {"Deployment", "CronJob", "Job"}:
                continue
            settings = env(pod_spec(doc)["containers"][0])
            if "SHIPTRACK_DB_POOL_SIZE" not in settings:
                continue  # no database access, as worker-notify
            pool = int(settings["SHIPTRACK_DB_POOL_SIZE"]) + int(settings["SHIPTRACK_DB_MAX_OVERFLOW"])
            replicas = int(doc["spec"].get("replicas", 1)) if doc["kind"] == "Deployment" else 1
            rows.append((doc["metadata"]["name"], replicas, pool))

    if not rows:
        print("no workload with a database pool was found; is this the rendered chart?", file=sys.stderr)
        return 2
    total = 0
    for name, replicas, pool in rows:
        print(f"{name:<28} {replicas} x {pool} = {replicas * pool}")
        total += replicas * pool
    print(f"{'total':<28} {total} (budget {args.budget})")
    if total > args.budget:
        print(f"the pools allow {total} connections, over the budget of {args.budget}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
