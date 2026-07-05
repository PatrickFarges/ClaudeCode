"""Modèle de document ClaudeCAD + lecture/écriture du format .cca.

Le format .cca est un JSON dont l'en-tête commence par l'identifiant magique
(`"magic": "ClaudeCAD"` — reconnaissance certaine du type de fichier), puis la version
de l'application ayant créé le fichier (`claudecad_version`), l'état caméra 3D complet
(pour rouvrir la vue à l'identique, y compris en iso/perspective), les réglages de
travail (`settings` : unité, couleurs, épaisseur, police, calque courant — pour ne rien
avoir à reconfigurer à l'ouverture), les lignes d'aide, puis les entités du dessin.

Pour la base ALPHA 0.1 : pas encore d'entités (lignes/arcs finaux) — la liste existe
mais reste vide ; seules les lignes d'aide (axes X et Y) sont présentes par défaut.
"""
from __future__ import annotations

import json

import numpy as np

from . import APP_VERSION, FILE_MAGIC
from .camera import Camera

# Réglages de travail par défaut, sauvegardés dans chaque .cca et restaurés à
# l'ouverture. À l'ouverture, les valeurs du fichier sont fusionnées PAR-DESSUS ces
# défauts : un fichier ancien (sans certaines clés) récupère les défauts pour les
# clés manquantes — le format peut donc grossir sans casser les anciens fichiers.
DEFAULT_SETTINGS = {
    "unit": "m",                        # unité d'affichage (le modèle reste sans unité)
    "background_color": "#ffffff",      # fond du canvas
    "help_line_color": "#b4b4b4",       # lignes d'aide (pointillé gris clair)
    "line_color": "#000000",            # trait final (noir plein)
    "line_width": 1.0,                  # épaisseur du trait final (px)
    "font_family": "monospace",         # police des textes/cotes (à venir)
    "font_size": 10,
    "current_layer": "0",               # calque courant (système de calques à venir)
}


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
        self.settings: dict = dict(DEFAULT_SETTINGS)
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
        # Ordre des clés volontaire : le magic ouvre le fichier, la version suit.
        return {
            "magic": FILE_MAGIC,
            "claudecad_version": APP_VERSION,
            "camera": self.camera.to_dict(),
            "settings": dict(self.settings),
            "help_lines": [h.to_dict() for h in self.help_lines],
            "entities": list(self.entities),
        }

    def save(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(self.to_dict(), fh, ensure_ascii=False, indent=2)
        self.filepath = path

    @classmethod
    def load(cls, path: str) -> "Document":
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise ValueError(
                f"« {path} » n'est pas un fichier ClaudeCAD (contenu illisible)."
            ) from exc
        # Reconnaissance : magic "ClaudeCAD" en tête. Les .cca 0.1.x d'avant le magic
        # n'avaient que claudecad_version — on les accepte (rétrocompatibilité).
        if not isinstance(data, dict) or (
            data.get("magic") != FILE_MAGIC and "claudecad_version" not in data
        ):
            raise ValueError(
                f"« {path} » n'est pas un fichier ClaudeCAD (identifiant absent)."
            )
        doc = cls()
        doc.created_version = data.get("claudecad_version", "?")
        doc.camera = Camera.from_dict(data.get("camera", {}))
        # Défauts + valeurs du fichier : les clés absentes gardent leur défaut.
        doc.settings = {**DEFAULT_SETTINGS, **data.get("settings", {})}
        doc.help_lines = [HelpLine.from_dict(h) for h in data.get("help_lines", [])]
        doc.entities = list(data.get("entities", []))
        doc.filepath = path
        doc.needs_default_framing = False   # la caméra restaurée fait foi
        return doc
