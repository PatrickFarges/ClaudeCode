#!/usr/bin/env bash
# Lance le pipeline SAP_DSN dans son venv local.
#
# Usage :
#   ./run.sh                 → pipeline complet (scan source 1 + 2 + merge)
#   ./run.sh scan1           → uniquement scan_dsn_tickets.py (Julio)
#   ./run.sh scan2           → uniquement scan_dsn_tickets_clients.py (SAP Ticket)
#   ./run.sh merge           → uniquement merge_and_report.py
#   ./run.sh <script>.py     → lance un script arbitraire du projet
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
        $PY scan_dsn_tickets.py
        $PY scan_dsn_tickets_clients.py
        $PY merge_and_report.py
        ;;
    scan1) exec $PY scan_dsn_tickets.py ;;
    scan2) exec $PY scan_dsn_tickets_clients.py ;;
    merge) exec $PY merge_and_report.py ;;
    *)     exec $PY "$@" ;;
esac
