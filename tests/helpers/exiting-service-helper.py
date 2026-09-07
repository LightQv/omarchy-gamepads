#!/usr/bin/env python3
"""Emit a complete replay stream and exit for lifecycle testing."""

from pathlib import Path


fixture = Path(__file__).parents[1] / "tests" / "fixtures" / "two-switch-pro.ndjson"
print(fixture.read_text(encoding="utf-8"), end="", flush=True)
