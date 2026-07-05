"""Caméra orthographique 3D de ClaudeCAD (modèle géométrique en float64).

Convention de vue :
    - vue XY par défaut (azimuth = 0, elevation = 0) : X vers la droite, Y vers le
      haut, Z vers l'observateur.
    - plan de travail courant : z = 0 (où sont projetées les coordonnées souris).

La caméra ne stocke AUCUN pixel : elle mémorise un point monde (`center`) affiché au
centre du viewport, une échelle (px/unité), et deux angles. Ainsi la vue se restaure
« exactement » quelle que soit la taille de la fenêtre à la réouverture du fichier.

APP_VERSION-tracking : la sérialisation de cette classe constitue l'« état caméra »
écrit dans l'en-tête des fichiers .cca.
"""
from __future__ import annotations

import math

import numpy as np

DEFAULT_SCALE = 40.0   # pixels par unité monde au démarrage d'un nouveau projet
MARGIN_PX = 20.0       # décalage de l'origine depuis le coin bas-gauche (nouveau projet)


def _rot_x(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def _rot_y(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


class Camera:
    """Projection orthographique paramétrée par center / scale / azimuth / elevation."""

    def __init__(self) -> None:
        self.center = np.zeros(3, dtype=np.float64)  # point monde au centre du viewport
        self.scale = DEFAULT_SCALE                   # pixels par unité monde (zoom)
        self.azimuth = 0.0                           # degrés (rotation autour de Y monde)
        self.elevation = 0.0                         # degrés (bascule autour de X caméra)
        self.projection = "ortho"                    # "ortho" ; "perspective" à venir

    # ------------------------------------------------------------------ bases
    def _basis(self) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Retourne (right u, up v, forward f) en repère monde.

        À azimuth = elevation = 0 : u = X, v = Y, f = Z (vue XY frontale)."""
        r = _rot_y(math.radians(self.azimuth)) @ _rot_x(math.radians(self.elevation))
        u = r @ np.array([1.0, 0.0, 0.0])
        v = r @ np.array([0.0, 1.0, 0.0])
        f = r @ np.array([0.0, 0.0, 1.0])
        return u, v, f

    # ---------------------------------------------------------- projections
    def world_to_screen(self, p, w: float, h: float) -> tuple[float, float]:
        u, v, _ = self._basis()
        rel = np.asarray(p, dtype=np.float64) - self.center
        sx = w * 0.5 + self.scale * float(rel @ u)
        sy = h * 0.5 - self.scale * float(rel @ v)
        return sx, sy

    def screen_to_world(self, sx: float, sy: float, w: float, h: float) -> np.ndarray:
        """Point monde sous le pixel (sx, sy), projeté sur le plan de travail z = 0."""
        u, v, f = self._basis()
        cam_x = (sx - w * 0.5) / self.scale
        cam_y = -(sy - h * 0.5) / self.scale
        # Droite de visée orthographique : P(t) = center + cam_x*u + cam_y*v + t*f
        base = self.center + cam_x * u + cam_y * v
        if abs(f[2]) > 1e-9:                       # intersection avec le plan z = 0
            t = -base[2] / f[2]
            return base + t * f
        return base                                # vue rasante : on reste sur le plan caméra

    # --------------------------------------------------------- manipulations
    def pan_pixels(self, dpx: float, dpy: float, w: float, h: float) -> None:
        """Déplace la vue de (dpx, dpy) pixels (le point monde suit le curseur)."""
        u, v, _ = self._basis()
        self.center += (-dpx / self.scale) * u + (dpy / self.scale) * v

    def zoom_at(self, sx: float, sy: float, factor: float, w: float, h: float) -> None:
        """Zoom (factor > 1) / dézoom (factor < 1) en gardant fixe le point sous le curseur."""
        before = self.screen_to_world(sx, sy, w, h)
        self.scale = max(1e-6, self.scale * factor)
        after = self.screen_to_world(sx, sy, w, h)
        self.center += before - after

    def frame_new_document(self, w: float, h: float) -> None:
        """Cadrage d'un nouveau projet : origine 0,0,0 en bas à gauche (à MARGIN_PX du coin)."""
        self.scale = DEFAULT_SCALE
        self.azimuth = 0.0
        self.elevation = 0.0
        self.center = np.array(
            [(w * 0.5 - MARGIN_PX) / self.scale,
             (h * 0.5 - MARGIN_PX) / self.scale,
             0.0],
            dtype=np.float64,
        )

    # ---------------------------------------------------------- (dé)sérialisation
    def to_dict(self) -> dict:
        return {
            "projection": self.projection,
            "center": [float(c) for c in self.center],
            "scale": float(self.scale),
            "azimuth": float(self.azimuth),
            "elevation": float(self.elevation),
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Camera":
        cam = cls()
        cam.projection = d.get("projection", "ortho")
        cam.center = np.array(d.get("center", [0.0, 0.0, 0.0]), dtype=np.float64)
        cam.scale = float(d.get("scale", DEFAULT_SCALE))
        cam.azimuth = float(d.get("azimuth", 0.0))
        cam.elevation = float(d.get("elevation", 0.0))
        return cam
