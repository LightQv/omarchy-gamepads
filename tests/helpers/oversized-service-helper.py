#!/usr/bin/env python3
"""Emit an unterminated oversized frame for the QML service smoke test."""

from __future__ import annotations

import sys
import time


sys.stdout.write("x" * 70_000)
sys.stdout.flush()
time.sleep(5)
