#!/usr/bin/env python3
"""Workflow policy checks that actionlint does not make (ADR-0025, design §10).

Every job in every workflow names an `environment:`, so the owner's approval gates it, and every
third-party action is pinned to a full 40-character commit SHA.

Usage: check-workflows.py [workflow-dir]   (default: .github/workflows)
Needs PyYAML.
"""
import re
import sys
from pathlib import Path

import yaml

PINNED = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


def check(path: Path) -> list[str]:
    problems = []
    workflow = yaml.safe_load(path.read_text())
    jobs = workflow.get("jobs") or {}
    for name, job in jobs.items():
        if not job.get("environment"):
            problems.append(f"{path}: job '{name}' names no environment")
        uses = [job["uses"]] if "uses" in job else []
        uses += [step["uses"] for step in job.get("steps") or [] if "uses" in step]
        for ref in uses:
            if ref.startswith("./"):
                continue
            if not PINNED.match(ref):
                problems.append(f"{path}: job '{name}' uses '{ref}', not pinned to a full commit SHA")
    return problems


def main() -> int:
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else ".github/workflows")
    files = sorted([*directory.glob("*.yml"), *directory.glob("*.yaml")])
    if not files:
        print(f"no workflows found in {directory}", file=sys.stderr)
        return 1
    problems = [problem for path in files for problem in check(path)]
    for problem in problems:
        print(f"::error::{problem}")
    print(f"checked {len(files)} workflow(s): {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
