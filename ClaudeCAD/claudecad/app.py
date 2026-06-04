"""Amorçage de l'application Qt ClaudeCAD."""
from __future__ import annotations

import sys

from PySide6.QtWidgets import QApplication

from . import APP_VERSION
from .main_window import MainWindow


def run() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName("ClaudeCAD")
    app.setApplicationVersion(APP_VERSION)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
