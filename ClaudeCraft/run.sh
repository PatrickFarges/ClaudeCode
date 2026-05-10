#!/usr/bin/env bash
# Lance ClaudeCraft dans Godot 4.6.2 Linux.
#
# Usage :
#   ./run.sh             → ouvre l'éditeur Godot sur le projet
#   ./run.sh play        → lance directement la scène principale (équivalent F5)
#   ./run.sh tools       → active le venv outils Python (PyQt6, OpenGL, etc.)
#   ./run.sh viewer      → lance scripts/character_viewer.py dans le venv
#   ./run.sh gallery     → lance scripts/mob_gallery.py dans le venv
#   ./run.sh struct      → lance scripts/structure_viewer.py dans le venv
set -euo pipefail
cd "$(dirname "$0")"

GODOT=/mnt/Raid4Tb/Program/Godot/Godot_v4.6.2-stable_linux.x86_64
PROJ_PATH="$(pwd)"

ensure_venv() {
    if [ ! -d .venv ]; then
        echo "[run.sh] venv outils absent, création + install..."
        python3 -m venv .venv
        .venv/bin/pip install --upgrade pip
        .venv/bin/pip install PyQt6 PyOpenGL PyOpenGL_accelerate numpy Pillow
    fi
}

case "${1:-editor}" in
    editor) exec "$GODOT" --editor --path "$PROJ_PATH" ;;
    play)   exec "$GODOT" --path "$PROJ_PATH" ;;
    tools)
        ensure_venv
        echo "[run.sh] venv prêt — active-le avec :  source .venv/bin/activate"
        ;;
    viewer)
        ensure_venv
        exec .venv/bin/python scripts/character_viewer.py "${@:2}"
        ;;
    gallery)
        ensure_venv
        exec .venv/bin/python scripts/mob_gallery.py "${@:2}"
        ;;
    struct)
        ensure_venv
        exec .venv/bin/python scripts/structure_viewer.py "${@:2}"
        ;;
    *)
        echo "Usage : $0 [editor|play|tools|viewer|gallery|struct]" >&2
        exit 1
        ;;
esac
