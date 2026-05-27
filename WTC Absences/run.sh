#!/usr/bin/env bash
# Lance l'interface graphique HRO du Wagetype Catalog Absence.
# Le générateur en ligne de commande reste disponible :
#   .venv/bin/python generate_wtc_absences.py --client ABV
set -e
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
    echo "[run.sh] Création du virtualenv .venv/..."
    python3 -m venv .venv
    .venv/bin/pip install --quiet --upgrade pip
    .venv/bin/pip install --quiet -r requirements.txt
fi
# Tkinter = paquet système sous Linux (livré avec Python sous Windows)
if ! .venv/bin/python -c "import tkinter" 2>/dev/null; then
    echo "[run.sh] Tkinter (interface graphique) manquant."
    echo "         Installez-le une fois puis relancez :"
    echo "             sudo apt install python3-tk"
    exit 1
fi
exec .venv/bin/python wtc_absences_gui.py
