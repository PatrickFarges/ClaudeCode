"""Smoke test Qt (mode offscreen) : la fenêtre se construit, peint, et le .cca tourne.

Lancement : QT_QPA_PLATFORM=offscreen .venv/bin/python tests/smoke.py
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from claudecad import APP_VERSION
from claudecad.document import Document
from claudecad.main_window import MainWindow


def main():
    app = QApplication(sys.argv)
    win = MainWindow()
    win.resize(1280, 800)
    win.show()
    app.processEvents()

    canvas = win.canvas
    assert canvas.width() > 1 and canvas.height() > 1, "canvas non dimensionné"
    assert not canvas.document.needs_default_framing, "cadrage initial non appliqué"

    # Force un paintEvent (lève si le rendu casse).
    pm = canvas.grab()
    assert not pm.isNull(), "grab() canvas vide"

    # Coordonnées sous le centre du canvas (doit être ~ centre monde de la caméra).
    cam = canvas.document.camera
    wpt = cam.screen_to_world(canvas.width() / 2, canvas.height() / 2,
                              canvas.width(), canvas.height())
    print(f"  centre canvas -> monde {tuple(round(float(c), 3) for c in wpt)}")

    # Aller-retour fichier .cca.
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "essai.cca")
        cam.zoom_at(300, 300, 1.3, canvas.width(), canvas.height())
        win.document.save(path)
        with open(path, encoding="utf-8") as fh:
            head = fh.read(60)
        assert "claudecad_version" in head, f"version absente de l'en-tête: {head!r}"
        reloaded = Document.load(path)
        import numpy as np
        assert np.allclose(reloaded.camera.center, win.document.camera.center)
        assert len(reloaded.help_lines) == 2, "axes X/Y attendus"
        print(f"  .cca v{reloaded.created_version} relu, {len(reloaded.help_lines)} lignes d'aide")

    print(f"\nsmoke OK — ClaudeCAD {APP_VERSION}")


if __name__ == "__main__":
    main()
