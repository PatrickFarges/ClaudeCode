"""
fetch_images.py — Télécharge des images pour chaque jeu/application
détecté par ClaudeLauncher, via l'API SteamGridDB.

Organise les images dans ClaudeLauncher/images/<nom_programme>/
et crée un manifest.json pour tracer les sources.

Usage : python fetch_images.py
"""

import os
import sys
import json
import time
import hashlib
import re
import requests
from pathlib import Path
from PIL import Image
from io import BytesIO

# ─── Configuration ───────────────────────────────────────────────
STEAMGRIDDB_API = "https://www.steamgriddb.com/api/v2"
API_KEY = "f2941c496e64e7d8fbaafc8096107d09"
HEADERS = {"Authorization": f"Bearer {API_KEY}"}

IMAGES_DIR = Path(__file__).parent / "images"
MANIFEST_PATH = IMAGES_DIR / "manifest.json"

MIN_SIZE = 512       # pixels minimum sur le côté le plus court
MAX_SIZE = 1920      # pixels maximum sur le côté le plus long
MIN_IMAGES = 2
MAX_IMAGES = 5

# Délai entre requêtes API pour ne pas spam
API_DELAY = 0.4  # secondes

# ─── Programmes à chercher ───────────────────────────────────────
# Clé = nom affiché dans le launcher (nom du dossier ou nom registre)
# Valeur = dict avec :
#   "search"   : terme de recherche SteamGridDB
#   "category" : "game" ou "app"
#   "real_name": nom réel du jeu/app (pour info)

PROGRAMS = {
    # === JEUX ===
    "Baldur's Gate 3": {
        "search": "Baldur's Gate 3",
        "category": "game",
        "real_name": "Baldur's Gate 3",
    },
    "Black Desert": {
        "search": "Black Desert Online",
        "category": "game",
        "real_name": "Black Desert Online",
    },
    "Grinn": {
        "search": "Skyrim Special Edition",
        "category": "game",
        "real_name": "Skyrim Special Edition (modlist Grinn)",
    },
    "Magnum": {
        "search": "Fallout 4",
        "category": "game",
        "real_name": "Fallout 4 (modlist Magnum Opus)",
    },
    "No Man's Sky": {
        "search": "No Man's Sky",
        "category": "game",
        "real_name": "No Man's Sky",
    },
    "SoulFrame": {
        "search": "Soulframe",
        "category": "game",
        "real_name": "Soulframe",
    },
    "Core Keeper": {
        "search": "Core Keeper",
        "category": "game",
        "real_name": "Core Keeper",
    },
    "Lost Ark": {
        "search": "Lost Ark",
        "category": "game",
        "real_name": "Lost Ark",
    },
    "Path of Exile": {
        "search": "Path of Exile",
        "category": "game",
        "real_name": "Path of Exile",
    },
    "Wild Terra 2": {
        "search": "Wild Terra 2",
        "category": "game",
        "real_name": "Wild Terra 2: New Lands",
    },

    # === APPLICATIONS ===
    "7-Zip": {
        "search": "7-Zip",
        "category": "app",
        "real_name": "7-Zip",
    },
    "Brave": {
        "search": "Brave Browser",
        "category": "app",
        "real_name": "Brave Browser",
    },
    "Discord": {
        "search": "Discord",
        "category": "app",
        "real_name": "Discord",
    },
    "Foxit PDF Editor": {
        "search": "Foxit PDF Editor",
        "category": "app",
        "real_name": "Foxit PDF Editor",
    },
    "Kodi": {
        "search": "Kodi",
        "category": "app",
        "real_name": "Kodi",
    },
    "Microsoft Edge": {
        "search": "Microsoft Edge",
        "category": "app",
        "real_name": "Microsoft Edge",
    },
    "Visual Studio Code": {
        "search": "Visual Studio Code",
        "category": "app",
        "real_name": "Visual Studio Code",
    },
    "OneCommander": {
        "search": "OneCommander",
        "category": "app",
        "real_name": "OneCommander",
    },
    "Playnite": {
        "search": "Playnite",
        "category": "app",
        "real_name": "Playnite",
    },
    "Visual Studio 2022": {
        "search": "Visual Studio",
        "category": "app",
        "real_name": "Visual Studio Community 2022",
    },
    "Vivaldi": {
        "search": "Vivaldi",
        "category": "app",
        "real_name": "Vivaldi Browser",
    },
    "Bitdefender": {
        "search": "Bitdefender",
        "category": "app",
        "real_name": "Bitdefender Antivirus",
    },
    "Samsung Magician": {
        "search": "Samsung Magician",
        "category": "app",
        "real_name": "Samsung Magician",
    },
    "Python": {
        "search": "Python",
        "category": "app",
        "real_name": "Python 3.12",
    },
    "Git": {
        "search": "Git",
        "category": "app",
        "real_name": "Git",
    },
    "PowerShell": {
        "search": "PowerShell",
        "category": "app",
        "real_name": "PowerShell 7",
    },
    "Godot Engine": {
        "search": "Godot Engine",
        "category": "app",
        "real_name": "Godot Engine 4.5",
    },
}


def sanitize_dirname(name: str) -> str:
    """Nettoie un nom pour en faire un nom de dossier valide."""
    return re.sub(r'[<>:"/\\|?*]', '_', name).strip('. ')


def resize_image(img: Image.Image) -> Image.Image:
    """
    Redimensionne en gardant le ratio :
    - Si le côté le plus court < MIN_SIZE, on agrandit
    - Si le côté le plus long > MAX_SIZE, on réduit
    """
    w, h = img.size
    short_side = min(w, h)
    long_side = max(w, h)

    # Si trop petit, agrandir pour que le côté court = MIN_SIZE
    if short_side < MIN_SIZE:
        scale = MIN_SIZE / short_side
        w = int(w * scale)
        h = int(h * scale)
        img = img.resize((w, h), Image.LANCZOS)

    # Si trop grand, réduire pour que le côté long = MAX_SIZE
    long_side = max(w, h)
    if long_side > MAX_SIZE:
        scale = MAX_SIZE / long_side
        w = int(w * scale)
        h = int(h * scale)
        img = img.resize((w, h), Image.LANCZOS)

    return img


def search_game(search_term: str) -> dict | None:
    """Recherche un jeu/app sur SteamGridDB. Retourne le premier résultat."""
    url = f"{STEAMGRIDDB_API}/search/autocomplete/{requests.utils.quote(search_term)}"
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        if resp.status_code == 200:
            data = resp.json()
            if data.get("success") and data.get("data"):
                return data["data"][0]
    except Exception as e:
        print(f"  [ERREUR] Recherche '{search_term}': {e}")
    return None


def get_images(game_id: int, img_type: str = "grids", **params) -> list:
    """Récupère les images d'un type donné pour un jeu."""
    url = f"{STEAMGRIDDB_API}/{img_type}/game/{game_id}"
    try:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
        if resp.status_code == 200:
            data = resp.json()
            if data.get("success"):
                return data.get("data", [])
    except Exception as e:
        print(f"  [ERREUR] Fetch {img_type} game {game_id}: {e}")
    return []


def download_image(url: str) -> Image.Image | None:
    """Télécharge une image depuis une URL et retourne un objet PIL."""
    try:
        resp = requests.get(url, timeout=30, stream=True)
        if resp.status_code == 200:
            return Image.open(BytesIO(resp.content))
    except Exception as e:
        print(f"    [ERREUR] Download {url[:80]}...: {e}")
    return None


def process_program(name: str, info: dict, manifest: dict) -> int:
    """Traite un programme : recherche, télécharge et sauvegarde ses images."""
    search_term = info["search"]
    dir_name = sanitize_dirname(name)
    prog_dir = IMAGES_DIR / dir_name
    prog_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'='*60}")
    print(f"  {name} -> recherche '{search_term}'")
    print(f"  Categorie : {info['category']} | Reel : {info['real_name']}")

    # Vérifier images déjà présentes
    existing = list(prog_dir.glob("*.jpg")) + list(prog_dir.glob("*.png"))
    if len(existing) >= MIN_IMAGES:
        print(f"  -> {len(existing)} images deja presentes, on passe.")
        manifest[name] = manifest.get(name, {})
        manifest[name]["status"] = "already_done"
        manifest[name]["count"] = len(existing)
        return len(existing)

    # Recherche sur SteamGridDB
    game = search_game(search_term)
    time.sleep(API_DELAY)

    if not game:
        print(f"  -> NON TROUVE sur SteamGridDB")
        manifest[name] = {
            "search_term": search_term,
            "real_name": info["real_name"],
            "category": info["category"],
            "status": "not_found",
            "steamgriddb_id": None,
            "images": [],
        }
        return 0

    game_id = game["id"]
    game_name_sgdb = game.get("name", search_term)
    print(f"  -> Trouve : '{game_name_sgdb}' (ID: {game_id})")

    # Collecter les images de différents types
    all_images = []

    # 1. Heroes (grands banners horizontaux, très beaux)
    heroes = get_images(game_id, "heroes")
    time.sleep(API_DELAY)
    for h in heroes:
        if not h.get("nsfw") and not h.get("humor"):
            all_images.append({
                "url": h["url"],
                "type": "hero",
                "width": h.get("width", 0),
                "height": h.get("height", 0),
                "score": h.get("score", 0),
                "id": h["id"],
            })

    # 2. Grids (couvertures verticales, style Steam)
    grids = get_images(game_id, "grids")
    time.sleep(API_DELAY)
    for g in grids:
        if not g.get("nsfw") and not g.get("humor"):
            w = g.get("width", 0)
            h = g.get("height", 0)
            # Préférer les grandes grilles
            if w >= 300 and h >= 400:
                all_images.append({
                    "url": g["url"],
                    "type": "grid",
                    "width": w,
                    "height": h,
                    "score": g.get("score", 0),
                    "id": g["id"],
                })

    # 3. Logos (transparents, utiles)
    logos = get_images(game_id, "logos")
    time.sleep(API_DELAY)
    for l in logos:
        if not l.get("nsfw") and not l.get("humor"):
            all_images.append({
                "url": l["url"],
                "type": "logo",
                "width": l.get("width", 0),
                "height": l.get("height", 0),
                "score": l.get("score", 0),
                "id": l["id"],
            })

    # 4. Icons
    icons = get_images(game_id, "icons")
    time.sleep(API_DELAY)
    for ic in icons:
        if not ic.get("nsfw") and not ic.get("humor"):
            w = ic.get("width", 0)
            h = ic.get("height", 0)
            if w >= 256 and h >= 256:
                all_images.append({
                    "url": ic["url"],
                    "type": "icon",
                    "width": w,
                    "height": h,
                    "score": ic.get("score", 0),
                    "id": ic["id"],
                })

    if not all_images:
        print(f"  -> Aucune image disponible")
        manifest[name] = {
            "search_term": search_term,
            "real_name": info["real_name"],
            "category": info["category"],
            "status": "no_images",
            "steamgriddb_id": game_id,
            "steamgriddb_name": game_name_sgdb,
            "images": [],
        }
        return 0

    # Trier : priorité heroes > grids > logos > icons, puis par score
    type_priority = {"hero": 0, "grid": 1, "logo": 2, "icon": 3}
    all_images.sort(key=lambda x: (type_priority.get(x["type"], 9), -x["score"]))

    # Sélectionner les images (diversifier les types)
    selected = []
    types_seen = {}
    for img_info in all_images:
        t = img_info["type"]
        if types_seen.get(t, 0) >= 2 and len(selected) < MAX_IMAGES:
            continue
        selected.append(img_info)
        types_seen[t] = types_seen.get(t, 0) + 1
        if len(selected) >= MAX_IMAGES:
            break

    # Si pas assez, compléter sans restriction de type
    if len(selected) < MAX_IMAGES:
        for img_info in all_images:
            if img_info not in selected:
                selected.append(img_info)
                if len(selected) >= MAX_IMAGES:
                    break

    # Télécharger et sauvegarder
    saved_images = []
    for i, img_info in enumerate(selected):
        url = img_info["url"]
        img_type = img_info["type"]
        print(f"  [{i+1}/{len(selected)}] {img_type} ({img_info['width']}x{img_info['height']}) ...", end=" ")

        pil_img = download_image(url)
        if pil_img is None:
            print("ÉCHEC")
            continue

        # Convertir en RGB si nécessaire (pour sauver en JPEG)
        if pil_img.mode in ('RGBA', 'P', 'LA'):
            # Garder PNG pour les images avec transparence
            ext = "png"
            if pil_img.mode == 'P':
                pil_img = pil_img.convert('RGBA')
        else:
            ext = "jpg"
            if pil_img.mode != 'RGB':
                pil_img = pil_img.convert('RGB')

        # Redimensionner
        orig_size = pil_img.size
        pil_img = resize_image(pil_img)

        # Sauvegarder
        filename = f"{img_type}_{i+1}.{ext}"
        filepath = prog_dir / filename
        if ext == "jpg":
            pil_img.save(filepath, "JPEG", quality=92)
        else:
            pil_img.save(filepath, "PNG")

        file_size_kb = filepath.stat().st_size / 1024
        print(f"OK → {pil_img.size[0]}x{pil_img.size[1]} ({file_size_kb:.0f} KB)")

        saved_images.append({
            "filename": filename,
            "source_url": url,
            "type": img_type,
            "steamgriddb_image_id": img_info["id"],
            "original_size": f"{orig_size[0]}x{orig_size[1]}",
            "saved_size": f"{pil_img.size[0]}x{pil_img.size[1]}",
        })

        time.sleep(0.2)  # petit délai entre downloads

    manifest[name] = {
        "search_term": search_term,
        "real_name": info["real_name"],
        "category": info["category"],
        "status": "ok" if len(saved_images) >= MIN_IMAGES else "partial",
        "steamgriddb_id": game_id,
        "steamgriddb_name": game_name_sgdb,
        "images": saved_images,
    }

    print(f"  -> {len(saved_images)} images sauvegardees dans {prog_dir}")
    return len(saved_images)


def main():
    # Forcer UTF-8 sur la console Windows
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

    print("=" * 60)
    print("  ClaudeLauncher -- Telechargement d'images")
    print(f"  Repertoire : {IMAGES_DIR}")
    print(f"  Programmes : {len(PROGRAMS)}")
    print("=" * 60)

    IMAGES_DIR.mkdir(parents=True, exist_ok=True)

    # Charger manifest existant
    manifest = {}
    if MANIFEST_PATH.exists():
        try:
            with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
                manifest = json.load(f)
        except:
            manifest = {}

    total_downloaded = 0
    total_errors = 0

    for name, info in PROGRAMS.items():
        try:
            count = process_program(name, info, manifest)
            total_downloaded += count
        except Exception as e:
            print(f"  [ERREUR FATALE] {name}: {e}")
            total_errors += 1
            manifest[name] = {
                "search_term": info["search"],
                "real_name": info["real_name"],
                "category": info["category"],
                "status": "error",
                "error": str(e),
                "images": [],
            }

        # Sauvegarder le manifest après chaque programme (en cas d'interruption)
        with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)

    # Resume final
    print("\n" + "=" * 60)
    print("  RESUME")
    print("=" * 60)

    ok_count = sum(1 for v in manifest.values() if v.get("status") == "ok")
    partial_count = sum(1 for v in manifest.values() if v.get("status") == "partial")
    not_found = sum(1 for v in manifest.values() if v.get("status") == "not_found")
    no_images = sum(1 for v in manifest.values() if v.get("status") == "no_images")
    errors = sum(1 for v in manifest.values() if v.get("status") == "error")

    print(f"  Complet (>={MIN_IMAGES} images) : {ok_count}")
    print(f"  Partiel (<{MIN_IMAGES} images)  : {partial_count}")
    print(f"  Non trouve sur SteamGridDB    : {not_found}")
    print(f"  Trouve mais sans images       : {no_images}")
    print(f"  Erreurs                       : {errors}")
    print(f"  Total images telechargees     : {total_downloaded}")
    print(f"\n  Manifest : {MANIFEST_PATH}")

    missing = [name for name, v in manifest.items()
               if v.get("status") in ("not_found", "no_images", "error", "partial")]
    if missing:
        print(f"\n  Programmes necessitant une action manuelle :")
        for m in missing:
            status = manifest[m].get("status", "?")
            print(f"    - {m} ({status})")

    print("\nTermine !")


if __name__ == "__main__":
    main()
