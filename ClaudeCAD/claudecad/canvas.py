"""Canvas de dessin ClaudeCAD (QWidget + QPainter).

Rendu filaire pur (lignes/arcs) : QPainter suffit largement et reste léger — pas de
moteur 3D. La projection 3D→2D est faite par la caméra (NumPy float64) ; QPainter ne
trace que des segments 2D. Les lignes d'aide sont des pointillés gris clair étirés d'un
bord à l'autre du canvas (« infinies »).

Interactions :
    - molette : zoom / dézoom centré sur le curseur ;
    - [CTRL] + clic gauche maintenu : déplacement (pan) de l'espace de travail (façon ARC+) ;
    - bouton du milieu maintenu : pan également (standard CAD).

Note : on évite [ALT] car le gestionnaire de fenêtres Cinnamon capte Alt+glisser pour
déplacer les fenêtres — l'événement n'atteindrait jamais le canvas. CTRL et SHIFT passent.
"""
from __future__ import annotations

from PySide6.QtCore import Qt, Signal, QPointF
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QWidget

# --- couleurs / styles ---
BG_COLOR = QColor(255, 255, 255)          # fond clair (lignes finales en noir)
HELP_COLOR = QColor(180, 180, 180)        # gris clair des lignes d'aide
FINAL_COLOR = QColor(0, 0, 0)             # noir des lignes finales (à venir)

# Sens du zoom : molette vers l'avant (angleDelta > 0) => zoom avant.
# Mettre WHEEL_INVERT = True pour inverser si le sens ne te convient pas.
ZOOM_STEP = 1.2
WHEEL_INVERT = False

# Modifieur clavier pour le pan au clic gauche (façon ARC+).
# CTRL ou SHIFT : tous deux ignorés par le gestionnaire de fenêtres Cinnamon.
# NE PAS mettre Qt.AltModifier : Cinnamon capte Alt+glisser pour déplacer les fenêtres.
PAN_MODIFIER = Qt.ControlModifier   # passe à Qt.ShiftModifier pour utiliser SHIFT


def clip_infinite_line(px: float, py: float, dx: float, dy: float,
                       w: float, h: float):
    """Découpe la droite (point (px,py), direction (dx,dy)) au rectangle [0,w]x[0,h].

    Retourne les deux points extrêmes (QPointF, QPointF) ou None si hors cadre.
    Robuste à toute orientation (horizontale, verticale, oblique)."""
    pts = []
    # Intersections avec les 4 bords ; on garde celles qui tombent dans le rectangle.
    if abs(dx) > 1e-12:
        for x in (0.0, w):
            t = (x - px) / dx
            y = py + t * dy
            if -1e-6 <= y <= h + 1e-6:
                pts.append((x, y))
    if abs(dy) > 1e-12:
        for y in (0.0, h):
            t = (y - py) / dy
            x = px + t * dx
            if -1e-6 <= x <= w + 1e-6:
                pts.append((x, y))
    if len(pts) < 2:
        return None
    # Deux points les plus éloignés (gère les doublons de coin).
    best = None
    best_d = -1.0
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            d = (pts[i][0] - pts[j][0]) ** 2 + (pts[i][1] - pts[j][1]) ** 2
            if d > best_d:
                best_d = d
                best = (pts[i], pts[j])
    if best is None or best_d < 1e-9:
        return None
    (ax, ay), (bx, by) = best
    return QPointF(ax, ay), QPointF(bx, by)


class CadCanvas(QWidget):
    """Surface de dessin principale."""

    # Coordonnées monde sous le curseur (x, y, z) — pour l'affichage en barre basse.
    coords_changed = Signal(float, float, float)

    def __init__(self, document, parent=None) -> None:
        super().__init__(parent)
        self.document = document
        self.setMouseTracking(True)               # suivi souris même sans bouton
        self.setFocusPolicy(Qt.StrongFocus)
        self.setAutoFillBackground(False)
        self._panning = False
        self._pan_button = None
        self._last_pos = None

    def set_document(self, document) -> None:
        self.document = document
        if document.needs_default_framing and self.width() > 1 and self.height() > 1:
            document.camera.frame_new_document(self.width(), self.height())
            document.needs_default_framing = False
        self.update()

    # ------------------------------------------------------------- événements
    def resizeEvent(self, event):
        doc = self.document
        if doc.needs_default_framing and self.width() > 1 and self.height() > 1:
            doc.camera.frame_new_document(self.width(), self.height())
            doc.needs_default_framing = False
        super().resizeEvent(event)

    def wheelEvent(self, event):
        delta = event.angleDelta().y()
        if delta == 0:
            return
        zoom_in = (delta > 0) != WHEEL_INVERT
        factor = ZOOM_STEP if zoom_in else 1.0 / ZOOM_STEP
        pos = event.position()
        self.document.camera.zoom_at(pos.x(), pos.y(), factor,
                                     self.width(), self.height())
        self._emit_coords(pos.x(), pos.y())
        self.update()

    def mousePressEvent(self, event):
        btn = event.button()
        mod_ok = bool(event.modifiers() & PAN_MODIFIER)
        # Pan : <modifieur>+clic gauche (façon ARC+) OU bouton du milieu (standard CAD).
        if btn == Qt.MiddleButton or (btn == Qt.LeftButton and mod_ok):
            self._panning = True
            self._pan_button = btn
            self._last_pos = event.position()
            self.setCursor(Qt.ClosedHandCursor)

    def mouseMoveEvent(self, event):
        pos = event.position()
        if self._panning:
            # En mode modifieur+gauche, relâcher le modifieur arrête le pan ;
            # au bouton du milieu, le pan continue tant que le bouton est tenu.
            if self._pan_button == Qt.LeftButton and not (event.modifiers() & PAN_MODIFIER):
                self._stop_pan()
            else:
                d = pos - self._last_pos
                self.document.camera.pan_pixels(d.x(), d.y(),
                                                self.width(), self.height())
                self._last_pos = pos
                self.update()
        self._emit_coords(pos.x(), pos.y())

    def mouseReleaseEvent(self, event):
        if self._panning and event.button() == self._pan_button:
            self._stop_pan()

    def _stop_pan(self):
        self._panning = False
        self._pan_button = None
        self._last_pos = None
        self.unsetCursor()

    def _emit_coords(self, sx: float, sy: float):
        w = self.document.camera.screen_to_world(sx, sy, self.width(), self.height())
        self.coords_changed.emit(float(w[0]), float(w[1]), float(w[2]))

    # ------------------------------------------------------------- rendu
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing, True)
        painter.fillRect(self.rect(), BG_COLOR)

        cam = self.document.camera
        w, h = float(self.width()), float(self.height())

        # --- lignes d'aide (pointillé gris clair, infinies) ---
        help_pen = QPen(HELP_COLOR)
        help_pen.setWidthF(1.0)
        help_pen.setCosmetic(True)
        help_pen.setStyle(Qt.DashLine)
        painter.setPen(help_pen)
        for hl in self.document.help_lines:
            p0x, p0y = cam.world_to_screen(hl.point, w, h)
            p1x, p1y = cam.world_to_screen(hl.point + hl.direction, w, h)
            dx, dy = p1x - p0x, p1y - p0y
            if abs(dx) < 1e-9 and abs(dy) < 1e-9:
                continue   # direction dégénérée à l'écran (axe vu de face)
            seg = clip_infinite_line(p0x, p0y, dx, dy, w, h)
            if seg is not None:
                painter.drawLine(seg[0], seg[1])

        # --- entités finales (lignes/arcs noirs) : à venir ---
        # final_pen = QPen(FINAL_COLOR); final_pen.setCosmetic(True)
        # painter.setPen(final_pen)
        # ... (rendu des self.document.entities)

        painter.end()
