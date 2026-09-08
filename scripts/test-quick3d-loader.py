#!/usr/bin/env python3

"""Verify that the Quick 3D scene either loads or fails at its import boundary."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QSG_RHI_BACKEND", "software")

from PySide6.QtCore import QUrl  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect", choices=("ready", "error"), required=True)
    args = parser.parse_args()

    app = QGuiApplication([])
    engine = QQmlEngine()
    scene = Path(__file__).resolve().parents[1] / "profiles/switch-pro/SwitchProScene.qml"
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(scene)))
    status = component.status()

    if args.expect == "error":
        errors = "\n".join(error.toString() for error in component.errors())
        if status == QQmlComponent.Error and "QtQuick3D" in errors and "not installed" in errors:
            print("Quick 3D missing-module boundary passed.")
            return 0
        print(f"Expected a missing QtQuick3D module error, got status {status}.")
        print(errors)
        return 1

    if status != QQmlComponent.Ready:
        for error in component.errors():
            print(error.toString())
        return 1
    instance = component.create()
    if instance is None:
        for error in component.errors():
            print(error.toString())
        return 1
    instance.deleteLater()
    app.processEvents()
    print("Quick 3D component load passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
