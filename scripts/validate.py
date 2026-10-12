#!/usr/bin/env python3
"""Validate every record under gpus/ and systems/ against its JSON Schema.

Usage: .venv/bin/python3 scripts/validate.py
Exits non-zero if any record fails schema validation or if a systems/*.json
gpu_model_ref does not resolve to an existing file in gpus/.
"""
import json
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parent.parent


def load(path):
    with open(path) as f:
        return json.load(f)


def main():
    gpu_schema = load(ROOT / "schema" / "gpu.schema.json")
    system_schema = load(ROOT / "schema" / "system.schema.json")

    ok = True

    gpu_files = sorted((ROOT / "gpus").glob("*.json"))
    for path in gpu_files:
        data = load(path)
        try:
            jsonschema.validate(data, gpu_schema)
            print(f"PASS  gpus/{path.name}")
        except jsonschema.exceptions.ValidationError as e:
            ok = False
            print(f"FAIL  gpus/{path.name}: {e.message} at {list(e.path)}")

    known_gpu_files = {p.name for p in gpu_files}

    for path in sorted((ROOT / "systems").glob("*.json")):
        data = load(path)
        try:
            jsonschema.validate(data, system_schema)
        except jsonschema.exceptions.ValidationError as e:
            ok = False
            print(f"FAIL  systems/{path.name}: {e.message} at {list(e.path)}")
            continue

        gpu_ref = data.get("gpu_model_ref")
        if gpu_ref not in known_gpu_files:
            ok = False
            print(
                f"FAIL  systems/{path.name}: gpu_model_ref {gpu_ref!r} "
                "does not resolve to a file in gpus/"
            )
            continue

        print(f"PASS  systems/{path.name}")

    if ok:
        print("\nAll records valid.")
    else:
        print("\nValidation failed.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
