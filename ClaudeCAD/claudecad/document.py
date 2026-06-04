"""Modèle de document ClaudeCAD + lecture/écriture du format .cca.

Le format .cca est un JSON dont l'en-tête commence par la version de l'application
ayant créé le fichier (`claudecad_version`), suivi de l'état caméra (pour rouvrir la
vue à l'identique), des lignes d'aide, puis des entités du dessin.

Pour la base ALPHA 0.1 : pas encore d'entités (lignes/arcs finaux) — la liste existe
mais reste vide ; seules les lignes d'aide (axes X et Y) sont présentes par défaut.
"""
from __future__ import annotations

import json

import numpy as np

from . import APP_VERSION
from .camera import Camera


class HelpLine:
    """Ligne d'aide « infinie » : pointillé gris clair, support d'accrochage.

    Définie par un point et une direction dans l'espace monde (3D). Le rendu calcule
    sa projection écran et l'étire d'un bord à l'autre du canvas, quel que soit le zoom.
    """

    def __init__(self, point, direction) -> None:
        self.point = np.asarray(point, dtype=np.float64)
        self.direction = np.asarray(direction, dtype=np.float64)

    def to_dict(self) -> dict:
        return {
            "point": [float(c) for c in self.point],
            "direction": [float(c) for c in self.direction],
        }

    @classmethod
    def from_dict(cls, d: dict) -> "HelpLine":
        return cls(d["point"], d["direction"])


class Document:
    """État complet d'un dessin : caméra + lignes d'aide + entités finales."""

    def __init__(self) -> None:
        self.camera = Camera()
        self.help_lines: list[HelpLine] = []
        self.entities: list = []          # lignes/arcs finaux — à venir
        self.filepath: str | None = None
        self.created_version = APP_VERSION
        # Drapeau interne : un nouveau projet doit être cadré (origine en bas à gauche)
        # dès que la taille du canvas est connue.
        self.needs_default_framing = False

    # --------------------------------------------------------------- fabriques
    @classmethod
    def new_document(cls) -> "Document":
        """Nouveau projet : vue XY, axes X et Y comme lignes d'aide passant par 0,0,0."""
        doc = cls()
        doc.help_lines = [
            HelpLine([0.0, 0.0, 0.0], [1.0, 0.0, 0.0]),   # axe X (horizontale)
            HelpLine([0.0, 0.0, 0.0], [0.0, 1.0, 0.0]),   # axe Y (verticale)
        ]
        doc.needs_default_framing = True
        return doc

    # ------------------------------------------------------- (dé)sérialisation
    def to_dict(self) -> dict:
        # Ordre des clés volontaire : la version ouvre l'en-tête.
        return {
            "claudecad_version": APP_VERSION,
            "camera": self.camera.to_dict(),
            "help_lines": [h.to_dict() for h in self.help_lines],
            "entities": list(self.entities),
        }

    def save(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(self.to_dict(), fh, ensure_ascii=False, indent=2)
        self.filepath = path

    @classmethod
    def load(cls, path: str) -> "Document":
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        doc = cls()
        doc.created_version = data.get("claudecad_version", "?")
        doc.camera = Camera.from_dict(data.get("camera", {}))
        doc.help_lines = [HelpLine.from_dict(h) for h in data.get("help_lines", [])]
        doc.entities = list(data.get("entities", []))
        doc.filepath = path
        doc.needs_default_framing = False   # la caméra restaurée fait foi
        return doc
