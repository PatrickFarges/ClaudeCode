#!/usr/bin/env python3
"""Générateur de structures de château pour ClaudeCraft — Phase 4 Âge Médiéval.

Génère 4 structures JSON :
  1. Rempart (segment de mur avec créneaux) — 3×7×12
  2. Tour de défense (tour carrée avec créneaux) — 7×12×7
  3. Donjon (keep central 2 étages) — 15×16×15
  4. Caserne (bâtiment entraînement) — 11×8×9

v1.0.0 — 2026-03-01
"""

import json
import os


def _encode_rle(blocks_flat, palette):
    """Encode une liste de blocs en RLE numérique [palette_idx, count, ...]."""
    rle = []
    i = 0
    while i < len(blocks_flat):
        val = blocks_flat[i]
        count = 1
        while i + count < len(blocks_flat) and blocks_flat[i + count] == val:
            count += 1
        rle.append(val)    # palette index
        rle.append(count)  # count
        i += count
    return rle


def _save_structure(name, W, H, D, palette, blocks, output_dir):
    """Sauvegarde une structure en JSON ClaudeCraft (layer-first: y-major)."""
    # Flatten: index = y * (W * D) + z * W + x
    flat = []
    for y in range(H):
        for z in range(D):
            for x in range(W):
                flat.append(blocks[y][z][x])

    rle = _encode_rle(flat, palette)

    structure = {
        "size": [W, H, D],
        "palette": palette,
        "blocks_rle": rle,
    }

    filepath = os.path.join(output_dir, f"{name}.json")
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(structure, f, indent=2)

    total = W * H * D
    non_air = sum(1 for b in flat if b != 0)
    print(f"  {name}.json — {W}x{H}x{D} ({non_air}/{total} blocs)")
    return filepath


# ============================================================
# PALETTE COMMUNE CHÂTEAU
# ============================================================
CASTLE_PALETTE = [
    "AIR",            # 0
    "COBBLESTONE",    # 1 - murs principaux
    "STONE",          # 2 - fondation / structure
    "PLANKS",         # 3 - plancher / toit
    "SPRUCE_PLANKS",  # 4 - charpente sombre
    "SPRUCE_LOG",     # 5 - piliers / poutres
    "TORCH",          # 6 - éclairage
    "SMOOTH_STONE",   # 7 - sol intérieur
    "IRON_TABLE",     # 8 - workstation caserne (placeholder)
    "GLASS",          # 9 - meurtrières / fenêtres
    "DARK_OAK_PLANKS",  # 10 - porte / déco
    "BRICK",          # 11 - déco murs
]


def generate_rempart():
    """Segment de rempart : mur avec créneaux et chemin de ronde.
    Dimensions: 3×7×12 (largeur × hauteur × profondeur)"""
    W, H, D = 3, 7, 12
    blocks = [[[0]*W for _ in range(D)] for _ in range(H)]

    def put(x, y, z, bid):
        if 0 <= x < W and 0 <= y < H and 0 <= z < D:
            blocks[y][z][x] = bid

    # Mur plein (y=0 à y=4, toute la profondeur)
    for y in range(5):
        for z in range(D):
            for x in range(W):
                put(x, y, z, 1)  # cobblestone

    # Chemin de ronde (y=4, x=1 centre = plancher)
    for z in range(D):
        put(1, 4, z, 3)  # planks

    # Créneaux (y=5, alternés tous les 2 blocs sur les bords)
    for z in range(D):
        if z % 3 == 0:
            put(0, 5, z, 1)  # créneau extérieur
            put(2, 5, z, 1)  # créneau intérieur

    # Meurtrières (y=2, une tous les 3 blocs)
    for z in range(1, D, 3):
        put(1, 2, z, 9)  # glass = meurtrière

    return W, H, D, blocks


def generate_tour_defense():
    """Tour de défense carrée avec créneaux et torches.
    Dimensions: 7×12×7"""
    W, H, D = 7, 12, 7
    blocks = [[[0]*W for _ in range(D)] for _ in range(H)]

    def put(x, y, z, bid):
        if 0 <= x < W and 0 <= y < H and 0 <= z < D:
            blocks[y][z][x] = bid

    def fill(x0, y0, z0, x1, y1, z1, bid):
        for y in range(y0, y1+1):
            for z in range(z0, z1+1):
                for x in range(x0, x1+1):
                    put(x, y, z, bid)

    # Fondation pleine (y=0)
    fill(0, 0, 0, 6, 0, 6, 2)  # stone

    # Murs extérieurs (y=1 à y=8)
    for y in range(1, 9):
        for z in range(D):
            for x in range(W):
                if x == 0 or x == 6 or z == 0 or z == 6:
                    put(x, y, z, 1)  # cobblestone

    # Intérieur vide
    for y in range(1, 9):
        fill(1, y, 1, 5, y, 5, 0)

    # Planchers (y=0 intérieur = smooth_stone, y=4 = planks, y=8 = planks)
    fill(1, 0, 1, 5, 0, 5, 7)  # sol
    fill(1, 4, 1, 5, 4, 5, 3)  # étage 1
    fill(1, 8, 1, 5, 8, 5, 3)  # toit / plateforme

    # Créneaux (y=9)
    for x in range(W):
        for z in range(D):
            if x == 0 or x == 6 or z == 0 or z == 6:
                if (x + z) % 2 == 0:
                    put(x, 9, z, 1)

    # Piliers coins (y=1 à y=9)
    for y in range(1, 10):
        put(0, y, 0, 5)  # spruce_log
        put(6, y, 0, 5)
        put(0, y, 6, 5)
        put(6, y, 6, 5)

    # Torches intérieures (y=3 et y=7)
    for ty in [3, 7]:
        put(1, ty, 1, 6)
        put(5, ty, 1, 6)
        put(1, ty, 5, 6)
        put(5, ty, 5, 6)

    # Porte (z=0, centre)
    put(3, 1, 0, 0)  # AIR
    put(3, 2, 0, 0)  # AIR

    # Meurtrières
    for z in [2, 4]:
        put(0, 5, z, 9)
        put(6, 5, z, 9)
    for x in [2, 4]:
        put(x, 5, 0, 9)
        put(x, 5, 6, 9)

    return W, H, D, blocks


def generate_donjon():
    """Donjon / Keep central : bâtiment principal du château.
    Dimensions: 15×16×15"""
    W, H, D = 15, 16, 15
    blocks = [[[0]*W for _ in range(D)] for _ in range(H)]

    def put(x, y, z, bid):
        if 0 <= x < W and 0 <= y < H and 0 <= z < D:
            blocks[y][z][x] = bid

    def fill(x0, y0, z0, x1, y1, z1, bid):
        for y in range(y0, y1+1):
            for z in range(z0, z1+1):
                for x in range(x0, x1+1):
                    put(x, y, z, bid)

    def fill_walls(x0, y0, z0, x1, y1, z1, bid):
        for y in range(y0, y1+1):
            for z in range(z0, z1+1):
                for x in range(x0, x1+1):
                    if x == x0 or x == x1 or z == z0 or z == z1:
                        put(x, y, z, bid)

    # Fondation (y=0)
    fill(0, 0, 0, 14, 0, 14, 2)  # stone plein

    # Murs RDC (y=1-5)
    fill_walls(0, 1, 0, 14, 5, 14, 1)

    # Sol RDC
    fill(1, 0, 1, 13, 0, 13, 7)  # smooth_stone

    # Plancher 1er étage (y=5)
    fill(1, 5, 1, 13, 5, 13, 3)  # planks

    # Murs 1er étage (y=6-10)
    fill_walls(0, 6, 0, 14, 10, 14, 1)

    # Plancher 2e étage / toit (y=10)
    fill(1, 10, 1, 13, 10, 13, 3)

    # Tourelles aux 4 coins (y=10-14)
    for cx, cz in [(0, 0), (12, 0), (0, 12), (12, 12)]:
        for y in range(10, 14):
            for dx in range(3):
                for dz in range(3):
                    put(cx + dx, y, cz + dz, 1)
        # Intérieur tourelle vide
        for y in range(11, 14):
            put(cx + 1, y, cz + 1, 0)
        # Créneaux tourelle
        put(cx, 14, cz, 1)
        put(cx + 2, 14, cz, 1)
        put(cx, 14, cz + 2, 1)
        put(cx + 2, 14, cz + 2, 1)

    # Créneaux toiture (y=11, murs)
    for x in range(W):
        for z in range(D):
            if x == 0 or x == 14 or z == 0 or z == 14:
                if (x + z) % 2 == 0:
                    put(x, 11, z, 1)

    # Piliers intérieurs (soutien plancher)
    for cx, cz in [(4, 4), (10, 4), (4, 10), (10, 10)]:
        for y in range(1, 10):
            put(cx, y, cz, 5)  # spruce_log

    # Porte principale (z=0, centre)
    for dx in range(6, 9):
        put(dx, 1, 0, 0)  # AIR
        put(dx, 2, 0, 0)
        put(dx, 3, 0, 0)
    # Arche porte
    put(6, 4, 0, 2)  # stone
    for dx in range(6, 9):
        put(dx, 4, 0, 2)

    # Fenêtres (y=3 et y=8)
    for wy in [3, 8]:
        for wz in [4, 7, 10]:
            put(0, wy, wz, 9)   # verre côté gauche
            put(14, wy, wz, 9)  # verre côté droit
        for wx in [4, 7, 10]:
            put(wx, wy, 14, 9)  # verre fond

    # Torches
    for ty in [2, 7]:
        for tx, tz in [(2, 2), (12, 2), (2, 12), (12, 12), (7, 7)]:
            put(tx, ty, tz, 6)

    # Trône / table de commandement au fond RDC
    put(7, 1, 12, 8)  # iron_table = workstation stratégie

    return W, H, D, blocks


def generate_caserne():
    """Caserne : bâtiment d'entraînement des soldats.
    Dimensions: 11×8×9"""
    W, H, D = 11, 8, 9
    blocks = [[[0]*W for _ in range(D)] for _ in range(H)]

    def put(x, y, z, bid):
        if 0 <= x < W and 0 <= y < H and 0 <= z < D:
            blocks[y][z][x] = bid

    def fill(x0, y0, z0, x1, y1, z1, bid):
        for y in range(y0, y1+1):
            for z in range(z0, z1+1):
                for x in range(x0, x1+1):
                    put(x, y, z, bid)

    def fill_walls(x0, y0, z0, x1, y1, z1, bid):
        for y in range(y0, y1+1):
            for z in range(z0, z1+1):
                for x in range(x0, x1+1):
                    if x == x0 or x == x1 or z == z0 or z == z1:
                        put(x, y, z, bid)

    # Fondation
    fill(0, 0, 0, 10, 0, 8, 2)
    fill(1, 0, 1, 9, 0, 7, 7)  # sol intérieur smooth_stone

    # Murs (y=1-4)
    fill_walls(0, 1, 0, 10, 4, 8, 1)

    # Intérieur vide
    for y in range(1, 5):
        fill(1, y, 1, 9, y, 7, 0)

    # Toit en pente (planches)
    for z in range(D):
        for x in range(W):
            # Pente simple : centre plus haut
            dist_center = abs(x - 5)
            roof_y = 7 - dist_center
            if 5 <= roof_y <= 7:
                put(x, roof_y, z, 4)  # spruce_planks
    # Remplir les côtés du toit
    for z in [0, 8]:
        for y in range(5, 8):
            for x in range(W):
                dist_center = abs(x - 5)
                if y <= 7 - dist_center:
                    put(x, y, z, 1)

    # Porte (z=0, centre)
    put(5, 1, 0, 0)
    put(5, 2, 0, 0)

    # Fenêtres
    for wx in [3, 7]:
        put(wx, 2, 0, 9)
        put(wx, 2, 8, 9)
    put(0, 2, 4, 9)
    put(10, 2, 4, 9)

    # Torches intérieures
    put(2, 3, 2, 6)
    put(8, 3, 2, 6)
    put(2, 3, 6, 6)
    put(8, 3, 6, 6)

    # Piliers
    put(0, 1, 0, 5); put(0, 2, 0, 5); put(0, 3, 0, 5); put(0, 4, 0, 5)
    put(10, 1, 0, 5); put(10, 2, 0, 5); put(10, 3, 0, 5); put(10, 4, 0, 5)
    put(0, 1, 8, 5); put(0, 2, 8, 5); put(0, 3, 8, 5); put(0, 4, 8, 5)
    put(10, 1, 8, 5); put(10, 2, 8, 5); put(10, 3, 8, 5); put(10, 4, 8, 5)

    # Racks d'armes (barrels comme support)
    for z in [2, 4, 6]:
        put(1, 1, z, 8)  # iron_table placeholder

    return W, H, D, blocks


def main():
    output_dir = os.path.join(os.path.dirname(__file__), "..", "structures")
    os.makedirs(output_dir, exist_ok=True)

    print("Génération des structures de château Phase 4 :")

    structures = [
        ("rempart", generate_rempart),
        ("tour_defense", generate_tour_defense),
        ("donjon", generate_donjon),
        ("caserne", generate_caserne),
    ]

    for name, gen_func in structures:
        W, H, D, blocks = gen_func()
        _save_structure(name, W, H, D, CASTLE_PALETTE, blocks, output_dir)

    print(f"\n4 structures générées dans {output_dir}/")


if __name__ == "__main__":
    main()
