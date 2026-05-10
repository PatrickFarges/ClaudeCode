#!/usr/bin/env bash
# Lance ComparePDF dans son venv local.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
    echo "[run.sh] venv absent, création + install des dépendances..."
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install pypdf openpyxl
fi

exec .venv/bin/python Compare_PDF_V4.py "$@"
