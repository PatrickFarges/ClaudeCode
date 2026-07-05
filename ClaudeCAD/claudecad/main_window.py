"""Fenêtre principale de ClaudeCAD : canvas plein cadre + barre inférieure.

Barre inférieure :
    - à gauche : ligne de commande (saisie manuelle des commandes — branchée mais
      sans commande implémentée pour l'instant, c'est la prochaine étape) ;
    - à droite : affichage des coordonnées XYZ de la souris sur le canvas.
"""
from __future__ import annotations

import os

from PySide6.QtCore import Qt
from PySide6.QtGui import QAction, QFont, QKeySequence
from PySide6.QtWidgets import (
    QFileDialog, QHBoxLayout, QLabel, QLineEdit, QMainWindow, QMessageBox,
    QVBoxLayout, QWidget,
)

from . import APP_VERSION, FILE_EXTENSION, FILE_FILTER
from .canvas import CadCanvas
from .document import Document


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.document = Document.new_document()

        # --- canvas ---
        self.canvas = CadCanvas(self.document, self)
        self.canvas.coords_changed.connect(self._on_coords)

        # --- barre inférieure ---
        self.cmd_input = QLineEdit()
        self.cmd_input.setPlaceholderText("Commande…")
        self.cmd_input.returnPressed.connect(self._on_command)

        self.coord_label = QLabel()
        self.coord_label.setFont(QFont("monospace"))
        self.coord_label.setMinimumWidth(280)
        self.coord_label.setAlignment(Qt.AlignVCenter | Qt.AlignRight)
        self._set_coords(0.0, 0.0, 0.0)

        bottom = QWidget()
        bl = QHBoxLayout(bottom)
        bl.setContentsMargins(6, 3, 6, 3)
        bl.addWidget(self.cmd_input, 1)
        bl.addWidget(self.coord_label, 0)

        central = QWidget()
        layout = QVBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self.canvas, 1)
        layout.addWidget(bottom, 0)
        self.setCentralWidget(central)

        self._build_menu()
        self.resize(1280, 800)
        self._update_title()
        self.cmd_input.setFocus()

    # ----------------------------------------------------------------- menu
    def _build_menu(self) -> None:
        m = self.menuBar().addMenu("&Fichier")
        for text, seq, slot in (
            ("&Nouveau", QKeySequence.New, self.new_document),
            ("&Ouvrir…", QKeySequence.Open, self.open_document),
            ("&Enregistrer", QKeySequence.Save, self.save_document),
            ("Enregistrer &sous…", QKeySequence.SaveAs, self.save_document_as),
        ):
            act = QAction(text, self)
            act.setShortcut(seq)
            act.triggered.connect(slot)
            m.addAction(act)
        m.addSeparator()
        quit_act = QAction("&Quitter", self)
        quit_act.setShortcut(QKeySequence.Quit)
        quit_act.triggered.connect(self.close)
        m.addAction(quit_act)

    # ------------------------------------------------------------- coords / cmd
    def _on_coords(self, x: float, y: float, z: float) -> None:
        self._set_coords(x, y, z)

    def _set_coords(self, x: float, y: float, z: float) -> None:
        self.coord_label.setText(f"X {x:10.3f}   Y {y:10.3f}   Z {z:10.3f}")

    def _on_command(self) -> None:
        text = self.cmd_input.text().strip()
        self.cmd_input.clear()
        if not text:
            return
        # Point d'entrée des futures commandes (tracé de lignes, arcs, etc.).
        # Pour la base 0.1, on ne fait qu'accuser réception dans le titre.
        self._update_title(status=f"commande « {text} » — non implémentée")

    # ------------------------------------------------------------- fichiers
    def new_document(self) -> None:
        self.document = Document.new_document()
        self.canvas.set_document(self.document)
        self.cmd_input.setFocus()
        self._update_title()

    def open_document(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Ouvrir un projet", "", FILE_FILTER)
        if not path:
            return
        try:
            self.document = Document.load(path)
        except ValueError as exc:
            QMessageBox.warning(self, "Ouverture impossible", str(exc))
            return
        self.canvas.set_document(self.document)
        self._update_title()

    def save_document(self) -> bool:
        if not self.document.filepath:
            return self.save_document_as()
        self.document.save(self.document.filepath)
        self._update_title()
        return True

    def save_document_as(self) -> bool:
        path, _ = QFileDialog.getSaveFileName(self, "Enregistrer le projet", "", FILE_FILTER)
        if not path:
            return False
        if not path.lower().endswith("." + FILE_EXTENSION):
            path += "." + FILE_EXTENSION
        self.document.save(path)
        self._update_title()
        return True

    # ------------------------------------------------------------- divers
    def _update_title(self, status: str | None = None) -> None:
        name = os.path.basename(self.document.filepath) if self.document.filepath else "Sans titre"
        title = f"ClaudeCAD {APP_VERSION} — {name}"
        if status:
            title += f"   [{status}]"
        self.setWindowTitle(title)

    def closeEvent(self, event):
        # « Dernières coordonnées de la fenêtre de zoom » : on persiste l'état caméra
        # à la fermeture pour rouvrir le projet exactement au même endroit.
        if self.document.filepath:
            self.document.save(self.document.filepath)
        event.accept()
