#!/usr/bin/env bash
# Lance ClocloWebUi dans son venv local.
# Crée le venv et installe les deps si absent.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
    echo "[run.sh] venv absent, création + install des dépendances..."
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install -r requirements.txt
fi

exec .venv/bin/python server.py "$@"
