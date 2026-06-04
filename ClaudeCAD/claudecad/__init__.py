"""ClaudeCAD — outil de dessin architectural filaire 2D/3D type « ARC+ like ».

APP_VERSION : ci-dessous. À incrémenter à CHAQUE modification + tenir le changelog.

Changelog
---------
0.1.1 (2026-06-04) — Pan :
    * Pan via [CTRL] + clic gauche (au lieu de [ALT], capté par le WM Cinnamon pour
      déplacer les fenêtres) — modifieur configurable (`PAN_MODIFIER` dans canvas.py).
    * Pan aussi au bouton du milieu (standard CAD, aucun conflit WM).

0.1 (2026-06-04) — Base ALPHA :
    * Fenêtre principale : canvas plein cadre + barre inférieure
      (ligne de commande à gauche + affichage des coordonnées XYZ de la souris à droite).
    * Caméra orthographique 3D (float64, NumPy), vue XY par défaut.
    * Zoom à la molette centré sur le curseur ; pan [ALT] + clic gauche.
    * Lignes d'aide « infinies » en pointillé gris clair (axes X et Y passant par 0,0,0).
    * Nouveau projet : origine 0,0,0 en bas à gauche (décalée de 20 px).
    * Format de fichier .cca (JSON, version en tête) : version + état caméra
      (restauration exacte de la vue) + lignes d'aide + entités.
"""

APP_VERSION = "0.1.1"
__version__ = APP_VERSION

# Extension des fichiers de travail ClaudeCAD.
FILE_EXTENSION = "cca"
FILE_FILTER = "Fichiers ClaudeCAD (*.cca)"
