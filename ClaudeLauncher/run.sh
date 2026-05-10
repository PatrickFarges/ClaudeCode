#!/usr/bin/env bash
# Lance ClaudeLauncher (version courante v7) dans son venv local.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
    echo "[run.sh] venv absent, création + install des dépendances..."
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install -r requirements.txt
fi

exec .venv/bin/python claudelauncher_v7.0.py "$@"
