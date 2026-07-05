"""ClaudeCAD — outil de dessin architectural filaire 2D/3D type « ARC+ like ».

APP_VERSION : ci-dessous. À incrémenter à CHAQUE modification + tenir le changelog.

Changelog
---------
0.1.2 (2026-07-05) — Format .cca durci :
    * Identifiant magique `"magic": "ClaudeCAD"` en toute première clé du fichier
      (avant la version) : permet de reconnaître un fichier ClaudeCAD à coup sûr.
      À l'ouverture, un fichier sans ce marqueur est refusé avec un message clair
      (les .cca 0.1.x sans magic restent acceptés — rétrocompatibilité).
    * Section `settings` : les réglages de travail (unité, couleurs fond/aide/trait,
      épaisseur, police, calque courant) sont sauvegardés dans le fichier et
      restaurés à l'ouverture — plus besoin de reconfigurer. Le canvas lit désormais
      ses couleurs depuis ces réglages (les constantes de canvas.py servent de défauts).
    * Caméra : champ `projection` ("ortho" pour l'instant) sérialisé — prêt pour le
      futur mode perspective sans casser le format.

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

APP_VERSION = "0.1.2"
__version__ = APP_VERSION

# Extension des fichiers de travail ClaudeCAD.
FILE_EXTENSION = "cca"
FILE_FILTER = "Fichiers ClaudeCAD (*.cca)"

# Identifiant magique : toute première valeur d'un fichier .cca. Sert à reconnaître
# un fichier ClaudeCAD sans ambiguïté (l'extension .cca est aussi utilisée par
# quelques logiciels legacy — Clickteam Fusion, cc:Mail…).
FILE_MAGIC = "ClaudeCAD"
