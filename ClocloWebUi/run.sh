#!/usr/bin/env bash
# Lance ClocloWebUi dans son venv local.
# Note : server.py utilise pywinpty (Windows-only) — à porter vers ptyprocess
# avant que ce script puisse réellement démarrer le serveur sous Linux.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
    echo "[run.sh] venv absent, création + install des dépendances..."
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install aiohttp ptyprocess
fi

exec .venv/bin/python server.py "$@"
