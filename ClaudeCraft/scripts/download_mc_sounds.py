#!/usr/bin/env python3
"""
download_mc_sounds.py v1.0.0
Télécharge tous les sons Minecraft depuis minecraft-sounds.vercel.app

Usage:
    python download_mc_sounds.py
    python download_mc_sounds.py --category block entity
    python download_mc_sounds.py --output path/to/dir
"""

import json
import os
import sys
import time
import argparse
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_URL = "https://minecraft-sounds.vercel.app"
API_URL = f"{BASE_URL}/api/sounds"
CAT_URL = f"{BASE_URL}/api/categories"
DEFAULT_OUTPUT = Path(r"D:\Program\ClaudeCode\ClaudeCraft\assets\Audio\Minecraft")
PAGE_SIZE = 50
MAX_WORKERS = 8


def fetch_json(url):
    req = Request(url, headers={"User-Agent": "ClaudeCraft-SoundDownloader/1.0"})
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_categories():
    data = fetch_json(CAT_URL)
    if isinstance(data, list):
        return data
    return data.get("categories", data.get("data", []))


def fetch_all_sounds(categories=None):
    """Fetch all sound entries from the API, paginated."""
    all_sounds = []
    cats = categories or [None]

    for cat in cats:
        offset = 0
        cat_label = cat or "all"
        while True:
            url = f"{API_URL}?limit={PAGE_SIZE}&offset={offset}"
            if cat:
                url += f"&category={cat}"
            try:
                data = fetch_json(url)
            except Exception as e:
                print(f"  ERREUR API offset={offset} cat={cat_label}: {e}")
                break

            if isinstance(data, dict):
                sounds = data.get("sounds", [])
                pagination = data.get("pagination", {})
                has_more = pagination.get("hasMore", False)
            elif isinstance(data, list):
                sounds = data
                has_more = len(sounds) == PAGE_SIZE
            else:
                break

            if not sounds:
                break

            all_sounds.extend(sounds)
            print(f"    {cat_label}: {len(all_sounds)} entrées (offset={offset})...", end="\r")
            offset += PAGE_SIZE

            if not has_more:
                break

        if cat:
            print(f"    {cat_label}: {sum(1 for s in all_sounds if s.get('category') == cat)} entrées")

    print()
    return all_sounds


def extract_file_paths(sounds):
    """Extract unique file paths from sound entries."""
    paths = set()
    for sound in sounds:
        # Primary: "file" field is a list of paths like "/sounds/dig/grass1.ogg"
        files = sound.get("file", [])
        if isinstance(files, list):
            for f in files:
                if isinstance(f, str) and f:
                    paths.add(f)
        elif isinstance(files, str) and files:
            paths.add(files)
    return sorted(paths)


def download_file(path, output_dir):
    """Download a single sound file. Returns (path, success, size, status)."""
    # API returns paths like "/sounds/dig/grass1.ogg"
    # Files are served as .mp3 at the same URL with .mp3 extension
    mp3_path = path.replace(".ogg", ".mp3")
    if not mp3_path.endswith(".mp3"):
        mp3_path += ".mp3"

    # URL uses the path directly (already starts with /sounds/)
    url_path = mp3_path.lstrip("/")
    url = f"{BASE_URL}/{url_path}"

    # Local file path — strip leading /sounds/ for cleaner directory structure
    local_rel = mp3_path.lstrip("/")
    if local_rel.startswith("sounds/"):
        local_rel = local_rel[len("sounds/"):]
    local_path = output_dir / local_rel
    if local_path.exists():
        return (path, True, local_path.stat().st_size, "skip")

    local_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        req = Request(url, headers={"User-Agent": "ClaudeCraft-SoundDownloader/1.0"})
        with urlopen(req, timeout=30) as resp:
            data = resp.read()
            if len(data) < 100:
                return (path, False, 0, "too_small")
            with open(local_path, "wb") as f:
                f.write(data)
            return (path, True, len(data), "ok")
    except HTTPError as e:
        return (path, False, 0, f"HTTP {e.code}")
    except Exception as e:
        return (path, False, 0, str(e))


def main():
    parser = argparse.ArgumentParser(description="Télécharge les sons Minecraft")
    parser.add_argument("--output", "-o", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--category", "-c", nargs="*", help="Filtrer par catégorie")
    parser.add_argument("--list-categories", action="store_true")
    parser.add_argument("--workers", "-w", type=int, default=MAX_WORKERS)
    args = parser.parse_args()

    print("=== Minecraft Sound Downloader pour ClaudeCraft ===\n")

    # List categories
    print("Récupération des catégories...")
    try:
        categories = fetch_categories()
        print(f"  {len(categories)} catégories : {', '.join(str(c) for c in categories)}")
    except Exception as e:
        print(f"  Impossible de récupérer les catégories: {e}")
        categories = None

    if args.list_categories:
        return

    # Fetch all sounds
    filter_cats = args.category
    if filter_cats:
        print(f"\nFiltrage : {', '.join(filter_cats)}")

    print("\nRécupération de l'index des sons...")
    sounds = fetch_all_sounds(filter_cats)
    print(f"  {len(sounds)} entrées récupérées")

    # Extract unique file paths
    file_paths = extract_file_paths(sounds)
    print(f"  {len(file_paths)} fichiers uniques à télécharger")

    if not file_paths:
        print("Aucun fichier trouvé !")
        return

    # Download
    output_dir = args.output
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"\nTéléchargement vers : {output_dir}")
    print(f"  Workers parallèles : {args.workers}\n")

    ok_count = 0
    skip_count = 0
    fail_count = 0
    total_bytes = 0
    errors = []

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(download_file, p, output_dir): p for p in file_paths}
        done = 0
        total = len(futures)

        for future in as_completed(futures):
            done += 1
            path, success, size, status = future.result()

            if success:
                if status == "skip":
                    skip_count += 1
                else:
                    ok_count += 1
                total_bytes += size
            else:
                fail_count += 1
                errors.append((path, status))

            if done % 100 == 0 or done == total:
                pct = done * 100 // total
                print(f"  [{pct:3d}%] {done}/{total} — "
                      f"{ok_count} OK, {skip_count} skip, {fail_count} fail "
                      f"({total_bytes / 1024 / 1024:.1f} MB)")

    print(f"\n{'='*60}")
    print(f"  TERMINÉ !")
    print(f"  {ok_count} téléchargés + {skip_count} déjà présents = {ok_count + skip_count} fichiers")
    print(f"  {fail_count} erreurs")
    print(f"  {total_bytes / 1024 / 1024:.1f} MB total")
    print(f"  Dossier : {output_dir}")
    print(f"{'='*60}")

    if errors and len(errors) <= 20:
        print("\nErreurs :")
        for path, status in errors:
            print(f"  {path} — {status}")


if __name__ == "__main__":
    main()
