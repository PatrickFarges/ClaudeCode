#!/usr/bin/env python3
"""
Extracteur de données Minecraft Java Edition → ClaudeCraft
Parse le client.jar extrait et génère des fichiers JSON exploitables par le jeu.

Usage:
    python scripts/minecraft_import.py

Entrée:  minecraft_data/client_jar/ (client.jar extrait)
Sortie:  minecraft_data/  (fichiers JSON consolidés)
"""

import os
import json
import sys
from collections import defaultdict
from pathlib import Path

# Chemins
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
MC_BASE = PROJECT_DIR / "minecraft_data" / "client_jar"
MC_ASSETS = MC_BASE / "assets" / "minecraft"
MC_DATA = MC_BASE / "data" / "minecraft"
OUTPUT_DIR = PROJECT_DIR / "minecraft_data"
# Pack de textures actif (doit correspondre a GameConfig.ACTIVE_PACK dans le jeu)
# ACTIVE_PACK = "Aurore Stone"
ACTIVE_PACK = "Faithful64x64"
TEXTURE_PACK = PROJECT_DIR / "TexturesPack" / ACTIVE_PACK / "assets" / "minecraft" / "textures"

# ============================================================
# TAGS — résoudre les références #minecraft:xxx dans les recettes
# ============================================================

def load_tags():
    """Charge tous les tags (items et blocks) pour résoudre les groupes."""
    tags = {}
    for tag_type in ["item", "block"]:
        tag_dir = MC_DATA / "tags" / tag_type
        if not tag_dir.is_dir():
            # Essayer le format plus récent
            tag_dir = MC_DATA / "tags" / (tag_type + "s") if tag_type == "block" else tag_dir
        if not tag_dir.is_dir():
            continue
        for tag_file in tag_dir.rglob("*.json"):
            rel = tag_file.relative_to(MC_DATA / "tags")
            tag_name = f"minecraft:{rel.as_posix().replace('.json', '')}"
            with open(tag_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            values = []
            for v in data.get("values", []):
                if isinstance(v, str):
                    values.append(v)
                elif isinstance(v, dict):
                    values.append(v.get("id", ""))
            tags[tag_name] = values
    return tags


def resolve_tag(tag_ref, tags, depth=0):
    """Résout un tag récursivement (les tags peuvent référencer d'autres tags)."""
    if depth > 10:
        return [tag_ref]
    if not tag_ref.startswith("#"):
        return [tag_ref]
    tag_name = tag_ref[1:]  # Enlever le #
    if tag_name not in tags:
        return [tag_ref]
    result = []
    for v in tags[tag_name]:
        if v.startswith("#"):
            result.extend(resolve_tag(v, tags, depth + 1))
        else:
            result.append(v)
    return result


# ============================================================
# BLOCKS — extraire tous les modèles de blocs
# ============================================================

def load_block_model(name, cache=None, depth=0):
    """Charge un modèle de bloc en résolvant les parents récursivement."""
    if cache is None:
        cache = {}
    if name in cache:
        return cache[name]
    if depth > 10:
        return {}

    # Normaliser le nom
    clean = name.replace("minecraft:", "").replace("block/", "")
    model_file = MC_ASSETS / "models" / "block" / f"{clean}.json"
    if not model_file.is_file():
        # Essayer avec le chemin complet
        model_file = MC_ASSETS / "models" / name.replace("minecraft:", "").replace("block/", "block/")
        if not isinstance(model_file, Path):
            model_file = Path(str(model_file) + ".json")
        if not model_file.is_file():
            return {}

    with open(model_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Résoudre le parent
    result = {}
    if "parent" in data:
        parent = data["parent"]
        parent_data = load_block_model(parent, cache, depth + 1)
        result.update(parent_data)

    # Fusionner les textures
    if "textures" in data:
        if "textures" not in result:
            result["textures"] = {}
        result["textures"].update(data["textures"])

    # Éléments (géométrie)
    if "elements" in data:
        result["elements"] = data["elements"]

    result["_parent"] = data.get("parent", "")

    cache[name] = result
    return result


def classify_block(parent):
    """Classifie un bloc selon son parent model."""
    p = parent.replace("minecraft:", "")
    if "cube_all" in p:
        return "cube_all"
    elif "cube_column" in p and "horizontal" not in p:
        return "cube_column"
    elif "cube_bottom_top" in p:
        return "cube_bottom_top"
    elif "orientable" in p:
        return "orientable"
    elif "cross" in p:
        return "cross"
    elif "slab" in p:
        return "slab"
    elif "stairs" in p:
        return "stairs"
    elif "fence" in p:
        return "fence"
    elif "wall" in p:
        return "wall"
    elif "door" in p:
        return "door"
    elif "trapdoor" in p:
        return "trapdoor"
    elif "carpet" in p:
        return "carpet"
    elif "button" in p:
        return "button"
    elif "pressure_plate" in p:
        return "pressure_plate"
    elif "rail" in p:
        return "rail"
    elif "torch" in p:
        return "torch"
    elif "leaves" in p:
        return "leaves"
    elif "crop" in p:
        return "crop"
    elif "flower_pot" in p:
        return "flower_pot"
    elif "template" in p:
        return "template"
    elif "cube" in p:
        return "cube"
    else:
        return "other"


def resolve_texture_ref(tex, textures):
    """Résout une référence de texture (#all → valeur réelle)."""
    if not tex:
        return ""
    seen = set()
    while tex.startswith("#") and tex not in seen:
        seen.add(tex)
        key = tex[1:]
        tex = textures.get(key, tex)
    return tex.replace("minecraft:", "").replace("block/", "")


def check_texture_exists(tex_name, category="block"):
    """Verifie si une texture existe dans le TexturesPack."""
    if not tex_name:
        return False
    tex_path = TEXTURE_PACK / category / f"{tex_name}.png"
    return tex_path.is_file()


def extract_blocks():
    """Extrait tous les modèles de blocs avec leurs textures et classification."""
    models_dir = MC_ASSETS / "models" / "block"
    if not models_dir.is_dir():
        print("ERREUR: Dossier models/block introuvable")
        return []

    blocks = []
    cache = {}
    stats = defaultdict(int)

    for f in sorted(models_dir.iterdir()):
        if not f.suffix == ".json":
            continue
        name = f.stem
        with open(f, "r", encoding="utf-8") as fh:
            raw = json.load(fh)

        parent = raw.get("parent", "")
        block_type = classify_block(parent)
        stats[block_type] += 1

        # Résoudre le modèle complet (avec parents)
        full_model = load_block_model(f"block/{name}", cache)
        textures = full_model.get("textures", {})

        # Résoudre les références de textures
        resolved_textures = {}
        for key, val in textures.items():
            if key == "particle":
                continue
            resolved = resolve_texture_ref(val, textures)
            if resolved and not resolved.startswith("#"):
                resolved_textures[key] = resolved

        # Vérifier disponibilité dans le TexturesPack
        tex_available = {}
        for key, tex in resolved_textures.items():
            tex_available[key] = check_texture_exists(tex)

        block = {
            "id": f"minecraft:{name}",
            "name": name,
            "type": block_type,
            "parent": parent,
            "textures": resolved_textures,
            "textures_available": tex_available,
            "has_all_textures": all(tex_available.values()) if tex_available else False,
        }
        blocks.append(block)

    print(f"\n=== Blocs extraits: {len(blocks)} ===")
    for bt, count in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"  {bt}: {count}")

    return blocks


# ============================================================
# BLOCKSTATES — mapping état → modèle
# ============================================================

def extract_blockstates():
    """Extrait tous les blockstates."""
    bs_dir = MC_ASSETS / "blockstates"
    if not bs_dir.is_dir():
        return []

    blockstates = []
    for f in sorted(bs_dir.iterdir()):
        if not f.suffix == ".json":
            continue
        with open(f, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        blockstates.append({
            "name": f.stem,
            "variants": data.get("variants"),
            "multipart": data.get("multipart"),
        })

    print(f"Blockstates extraits: {len(blockstates)}")
    return blockstates


# ============================================================
# ITEMS — extraire les modèles d'items
# ============================================================

def extract_items():
    """Extrait tous les modèles d'items avec leurs textures."""
    items_dir = MC_ASSETS / "models" / "item"
    if not items_dir.is_dir():
        return []

    items = []
    for f in sorted(items_dir.iterdir()):
        if not f.suffix == ".json":
            continue
        with open(f, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        parent = data.get("parent", "")
        textures = data.get("textures", {})

        # Déterminer le type d'item
        item_type = "block"
        if "item/generated" in parent or "item/handheld" in parent:
            item_type = "flat"  # Item plat (2D sprite)
        elif "item/handheld" in parent:
            item_type = "handheld"  # Outil/arme tenu en main

        # Résoudre textures
        resolved = {}
        for key, val in textures.items():
            clean = val.replace("minecraft:", "").replace("item/", "").replace("block/", "")
            resolved[key] = clean

        items.append({
            "id": f"minecraft:{f.stem}",
            "name": f.stem,
            "type": item_type,
            "parent": parent,
            "textures": resolved,
        })

    print(f"Items extraits: {len(items)}")
    return items


# ============================================================
# RECIPES — extraire toutes les recettes
# ============================================================

def extract_recipes(tags):
    """Extrait toutes les recettes, en résolvant les tags."""
    recipe_dir = MC_DATA / "recipe"
    if not recipe_dir.is_dir():
        print("ERREUR: Dossier recipe introuvable")
        return []

    recipes = []
    stats = defaultdict(int)

    for f in sorted(recipe_dir.rglob("*.json")):
        with open(f, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        rtype = data.get("type", "unknown")
        stats[rtype] += 1

        # Ne garder que les types utiles
        if rtype not in [
            "minecraft:crafting_shaped",
            "minecraft:crafting_shapeless",
            "minecraft:smelting",
            "minecraft:blasting",
            "minecraft:smoking",
            "minecraft:campfire_cooking",
            "minecraft:stonecutting",
        ]:
            continue

        recipe = {
            "id": f.stem,
            "type": rtype.replace("minecraft:", ""),
            "category": data.get("category", ""),
            "group": data.get("group", ""),
        }

        if rtype == "minecraft:crafting_shaped":
            recipe["pattern"] = data.get("pattern", [])

            # Résoudre les clés
            key = data.get("key", {})
            resolved_key = {}
            for k, v in key.items():
                if isinstance(v, str):
                    if v.startswith("#"):
                        resolved_key[k] = {
                            "tag": v[1:],
                            "items": resolve_tag(v, tags)
                        }
                    else:
                        resolved_key[k] = {"item": v}
                elif isinstance(v, dict):
                    resolved_key[k] = v
                elif isinstance(v, list):
                    resolved_key[k] = {"items": [
                        vi if isinstance(vi, str) else vi.get("item", "")
                        for vi in v
                    ]}
            recipe["key"] = resolved_key

        elif rtype == "minecraft:crafting_shapeless":
            ingredients = data.get("ingredients", [])
            resolved_ingredients = []
            for ing in ingredients:
                if isinstance(ing, str):
                    if ing.startswith("#"):
                        resolved_ingredients.append({
                            "tag": ing[1:],
                            "items": resolve_tag(ing, tags)
                        })
                    else:
                        resolved_ingredients.append({"item": ing})
                elif isinstance(ing, dict):
                    resolved_ingredients.append(ing)
                elif isinstance(ing, list):
                    resolved_ingredients.append({"items": [
                        ii if isinstance(ii, str) else ii.get("item", "")
                        for ii in ing
                    ]})
            recipe["ingredients"] = resolved_ingredients

        elif rtype in ["minecraft:smelting", "minecraft:blasting",
                        "minecraft:smoking", "minecraft:campfire_cooking"]:
            ing = data.get("ingredient", "")
            if isinstance(ing, str):
                if ing.startswith("#"):
                    recipe["ingredient"] = {
                        "tag": ing[1:],
                        "items": resolve_tag(ing, tags)
                    }
                else:
                    recipe["ingredient"] = {"item": ing}
            elif isinstance(ing, dict):
                recipe["ingredient"] = ing
            elif isinstance(ing, list):
                recipe["ingredient"] = {"items": [
                    ii if isinstance(ii, str) else ii.get("item", "")
                    for ii in ing
                ]}
            recipe["cookingtime"] = data.get("cookingtime", 200)
            recipe["experience"] = data.get("experience", 0)

        elif rtype == "minecraft:stonecutting":
            ing = data.get("ingredient", "")
            if isinstance(ing, str):
                recipe["ingredient"] = {"item": ing}
            elif isinstance(ing, dict):
                recipe["ingredient"] = ing
            recipe["count"] = data.get("count", 1)

        # Résultat
        result = data.get("result", {})
        if isinstance(result, str):
            recipe["result"] = {"item": result, "count": 1}
        elif isinstance(result, dict):
            recipe["result"] = {
                "item": result.get("id", result.get("item", "")),
                "count": result.get("count", 1),
            }

        recipes.append(recipe)

    print(f"\n=== Recettes extraites: {len(recipes)} ===")
    for rt, count in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"  {rt}: {count}")

    return recipes


# ============================================================
# TEXTURES — inventaire des textures disponibles
# ============================================================

def extract_texture_inventory():
    """Inventorie toutes les textures MC et leur disponibilité dans le TexturesPack."""
    categories = {
        "block": MC_ASSETS / "textures" / "block",
        "item": MC_ASSETS / "textures" / "item",
        "entity": MC_ASSETS / "textures" / "entity",
    }

    inventory = {}
    for cat, cat_dir in categories.items():
        if not cat_dir.is_dir():
            continue
        for f in sorted(cat_dir.rglob("*.png")):
            rel = f.relative_to(cat_dir)
            name = rel.as_posix().replace(".png", "")
            mc_path = f"textures/{cat}/{name}.png"

            # Verifier dans TexturesPack
            tp_available = False
            tp_path = TEXTURE_PACK / cat / f"{name}.png"
            tp_available = tp_path.is_file()

            inventory[f"{cat}/{name}"] = {
                "category": cat,
                "name": name,
                "mc_path": mc_path,
                "in_texturepack": tp_available,
                "mc_source": str(f),
            }

    block_textures = [v for v in inventory.values() if v["category"] == "block"]
    item_textures = [v for v in inventory.values() if v["category"] == "item"]
    available = sum(1 for v in block_textures if v["in_texturepack"])

    print(f"\n=== Textures ===")
    print(f"  Blocs MC: {len(block_textures)} ({available} dans TexturesPack)")
    print(f"  Items MC: {len(item_textures)}")
    print(f"  Total: {len(inventory)}")

    return inventory


# ============================================================
# BEDROCK ENTITY MODELS — modèles d'entités
# ============================================================

def extract_bedrock_entities():
    """Extrait les modèles d'entités depuis Bedrock Edition."""
    bedrock_models = Path(r"D:\Games\Minecraft - Bedrock Edition\data\resource_packs\vanilla\models\entity")
    if not bedrock_models.is_dir():
        print("Bedrock Edition models non trouvés, skip")
        return []

    entities = []
    for f in sorted(bedrock_models.iterdir()):
        if not f.suffix == ".json":
            continue
        try:
            with open(f, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except:
            continue

        # Extraire les infos de géométrie
        name = f.stem
        format_version = data.get("format_version", "")

        # Les modèles Bedrock ont des clés comme "geometry.cow" ou sont dans "minecraft:geometry"
        geometries = []
        if "minecraft:geometry" in data:
            for geo in data["minecraft:geometry"]:
                desc = geo.get("description", {})
                bones = geo.get("bones", [])
                geometries.append({
                    "identifier": desc.get("identifier", name),
                    "texture_width": desc.get("texture_width", 64),
                    "texture_height": desc.get("texture_height", 64),
                    "bone_count": len(bones),
                    "bones": [b.get("name", "") for b in bones],
                })
        else:
            # Ancien format
            for key, val in data.items():
                if key.startswith("geometry.") and isinstance(val, dict):
                    bones = val.get("bones", [])
                    geometries.append({
                        "identifier": key,
                        "texture_width": val.get("texturewidth", 64),
                        "texture_height": val.get("textureheight", 64),
                        "bone_count": len(bones),
                        "bones": [b.get("name", "") for b in bones],
                    })

        entities.append({
            "name": name,
            "format_version": format_version,
            "file": str(f),
            "geometries": geometries,
        })

    print(f"Entités Bedrock extraites: {len(entities)}")
    return entities


# ============================================================
# BEDROCK ANIMATIONS
# ============================================================

def extract_bedrock_animations():
    """Extrait les animations d'entités Bedrock."""
    bedrock_anims = Path(r"D:\Games\Minecraft - Bedrock Edition\data\resource_packs\vanilla\animations")
    if not bedrock_anims.is_dir():
        print("Bedrock animations non trouvées, skip")
        return []

    animations = []
    for f in sorted(bedrock_anims.iterdir()):
        if not f.suffix == ".json":
            continue
        try:
            with open(f, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except:
            continue

        anims = data.get("animations", {})
        anim_list = []
        for anim_name, anim_data in anims.items():
            anim_list.append({
                "name": anim_name,
                "loop": anim_data.get("loop", False),
                "length": anim_data.get("animation_length", 0),
            })

        animations.append({
            "entity": f.stem.replace(".animation", ""),
            "file": str(f),
            "animations": anim_list,
        })

    total_anims = sum(len(a["animations"]) for a in animations)
    print(f"Animations Bedrock: {len(animations)} fichiers, {total_anims} animations")
    return animations


# ============================================================
# MAIN
# ============================================================

def main():
    print("=" * 60)
    print("Extracteur Minecraft -> ClaudeCraft")
    print("=" * 60)

    if not MC_BASE.is_dir():
        print(f"ERREUR: {MC_BASE} introuvable")
        print("Extraire d'abord le client.jar")
        sys.exit(1)

    # Charger les tags
    print("\n--- Chargement des tags ---")
    tags = load_tags()
    print(f"Tags chargés: {len(tags)}")

    # Extraire tout
    print("\n--- Extraction des blocs ---")
    blocks = extract_blocks()

    print("\n--- Extraction des blockstates ---")
    blockstates = extract_blockstates()

    print("\n--- Extraction des items ---")
    items = extract_items()

    print("\n--- Extraction des recettes ---")
    recipes = extract_recipes(tags)

    print("\n--- Inventaire des textures ---")
    textures = extract_texture_inventory()

    print("\n--- Extraction entités Bedrock ---")
    entities = extract_bedrock_entities()

    print("\n--- Extraction animations Bedrock ---")
    animations = extract_bedrock_animations()

    # Sauvegarder
    print("\n--- Sauvegarde ---")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    outputs = {
        "minecraft_blocks.json": blocks,
        "minecraft_blockstates.json": blockstates,
        "minecraft_items.json": items,
        "minecraft_recipes.json": recipes,
        "minecraft_textures.json": textures,
        "minecraft_entities_bedrock.json": entities,
        "minecraft_animations_bedrock.json": animations,
        "minecraft_tags.json": tags,
    }

    for filename, data in outputs.items():
        path = OUTPUT_DIR / filename
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False, default=str)
        size = path.stat().st_size
        if isinstance(data, list):
            print(f"  {filename}: {len(data)} entrées ({size // 1024} KB)")
        else:
            print(f"  {filename}: {len(data)} clés ({size // 1024} KB)")

    # Résumé
    print("\n" + "=" * 60)
    print("RÉSUMÉ")
    print("=" * 60)

    block_types = defaultdict(int)
    blocks_with_tex = 0
    for b in blocks:
        block_types[b["type"]] += 1
        if b["has_all_textures"]:
            blocks_with_tex += 1

    print(f"\nBlocs: {len(blocks)} total, {blocks_with_tex} avec textures dispo")
    print(f"Items: {len(items)}")
    print(f"Recettes: {len(recipes)}")
    print(f"Blockstates: {len(blockstates)}")
    print(f"Textures: {len(textures)} ({sum(1 for v in textures.values() if v['in_texturepack'])} dans TexturesPack)")
    print(f"Entités Bedrock: {len(entities)}")
    print(f"Tags: {len(tags)}")
    print(f"\nTout sauvegardé dans: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
