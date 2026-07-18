#!/usr/bin/env bash
# Lance le pipeline SAP_Onenote dans son venv local.
#
# Usage :
#   ./run.sh                  → pipeline complet (evidence + onenote + index)
#   ./run.sh evidence         → scan_evidence.py uniquement
#   ./run.sh onenote          → scan_onenote.py (lecture onenote_pages.csv si présent)
#   ./run.sh onenote-refresh  → scan_onenote.py --refresh (force re-dump OneNote)
#   ./run.sh index            → build_index.py uniquement
#   ./run.sh <script>.py      → lance un script arbitraire du projet
#
# Note Linux : le re-dump OneNote (dump_onenote.ps1) ne tourne pas sous Linux,
# il faut produire onenote_pages.csv depuis Windows et le copier dans ce dossier.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
    echo "[run.sh] venv absent, création + install des dépendances..."
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install openpyxl
fi

PY=.venv/bin/python

case "${1:-all}" in
    all)
        $PY scan_evidence.py
        $PY scan_onenote.py
        $PY build_index.py
        ;;
    evidence)        exec $PY scan_evidence.py ;;
    onenote)         exec $PY scan_onenote.py ;;
    onenote-refresh) exec $PY scan_onenote.py --refresh ;;
    index)           exec $PY build_index.py ;;
    *)               exec $PY "$@" ;;
esac
