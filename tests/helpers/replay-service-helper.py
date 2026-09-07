#!/usr/bin/env python3
"""Keep a deterministic replay stream alive for the QML service smoke test."""

from __future__ import annotations

import json
from pathlib import Path
import sys


fixture = Path(__file__).parents[1] / "tests" / "fixtures" / "two-switch-pro.ndjson"
for line in fixture.read_text(encoding="utf-8").splitlines():
    print(line, flush=True)
print(json.dumps({"type": "error", "code": "mapping_failed", "message": "Controller mapping needs attention."}), flush=True)

for line in sys.stdin:
    try:
        command = json.loads(line)
    except json.JSONDecodeError:
        continue
    if command.get("command") == "shutdown":
        break
