#!/usr/bin/env bash
# Lance l'application ClaudeCAD (point d'entrée : main.py), quel que soit le nombre
# de fichiers .py présents dans le projet.
#   - crée le virtualenv .venv/ et installe les dépendances au 1er lancement ;
#   - lance ensuite .venv/bin/python main.py.
set -e
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
    echo "[run.sh] Création du virtualenv .venv/..."
    python3 -m venv .venv
    .venv/bin/pip install --quiet --upgrade pip
    .venv/bin/pip install --quiet -r requirements.txt
fi

# PySide6 (Qt) est installé dans le venv. Si l'import échoue, le venv est incomplet.
if ! .venv/bin/python -c "import PySide6" 2>/dev/null; then
    echo "[run.sh] PySide6 manquant — (ré)installation des dépendances..."
    .venv/bin/pip install --quiet -r requirements.txt
fi

# Sous Linux, Qt 6 a besoin de la lib système libxcb-cursor pour son plugin "xcb".
# Si au lancement tu vois « Could not load the Qt platform plugin xcb », installe-la :
#     sudo apt install libxcb-cursor0
exec .venv/bin/python main.py
