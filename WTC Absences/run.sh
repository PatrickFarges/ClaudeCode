#!/usr/bin/env bash
# Lance le générateur du Wagetype Catalog Absences (Phase 1 : rebranding visuel)
set -e
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
    echo "[run.sh] Création du virtualenv .venv/..."
    python3 -m venv .venv
    .venv/bin/pip install --quiet --upgrade pip
    .venv/bin/pip install --quiet openpyxl xlrd==2.0.1 pillow pdfplumber
fi
exec .venv/bin/python generate_wtc_absences.py "$@"
