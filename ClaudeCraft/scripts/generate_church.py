#!/usr/bin/env python3
"""Generateur de chapelle de village pour ClaudeCraft."""

import json
import os

def generate_church():
    """Genere une chapelle de village en pierre avec clocher.

    Dimensions: 13 x 18 x 21 (largeur x hauteur x profondeur)
    Style: chapelle medievale en pierre avec:
      - Nef rectangulaire 11x7 interieur
      - Toit en pente avec planches
      - Clocher carre 5x5 au-dessus de l'entree
      - Vitraux (verre) sur les cotes
      - Sol en dalles de pierre lisse
      - Autel en pierre au fond
    """

    # Dimensions totales
    W, H, D = 13, 18, 21

    # Palette ClaudeCraft
    palette = [
        "AIR",           # 0
        "COBBLESTONE",   # 1 - murs
        "STONE",         # 2 - fondation / autel
        "PLANKS",        # 3 - toit / charpente
        "SPRUCE_PLANKS", # 4 - toit sombre
        "GLASS",         # 5 - vitraux
        "SMOOTH_STONE",  # 6 - sol
        "SPRUCE_LOG",    # 7 - piliers / structure
        "BRICK",         # 8 - decoration murs
        "TORCH",         # 9 - torches
        "DARK_OAK_PLANKS", # 10 - porte / details
    ]

    # Grille 3D [y][z][x]
    blocks = [[[0]*W for _ in range(D)] for _ in range(H)]

    def put(x, y, z, block_id):
        if 0 <= x < W and 0 <= y < H and 0 <= z < D:
            blocks[y][z][x] = block_id

    def fill(x0, y0, z0, x1, y1, z1, block_id):
        for y in range(y0, y1+1):
            for z in range(z0, z1+1):
                for x in range(x0, x1+1):
                    put(x, y, z, block_id)

    def fill_hollow(x0, y0, z0, x1, y1, z1, block_id):
        """Remplit les murs exterieurs seulement."""
        for y in range(y0, y1+1):
            for z in range(z0, z1+1):
                for x in range(x0, x1+1):
                    if x == x0 or x == x1 or z == z0 or z == z1:
                        put(x, y, z, block_id)

    # =============================================
    # FONDATION (y=0)
    # =============================================
    # Dalle de fondation en pierre
    fill(0, 0, 0, 12, 0, 20, 2)  # STONE foundation

    # =============================================
    # SOL INTERIEUR (y=1)
    # =============================================
    fill(1, 1, 1, 11, 1, 19, 6)  # SMOOTH_STONE floor

    # =============================================
    # MURS (y=1 a y=7)
    # =============================================
    for y in range(1, 8):
        # Mur ouest (x=0)
        for z in range(0, 21):
            put(0, y, z, 1)
        # Mur est (x=12)
        for z in range(0, 21):
            put(12, y, z, 1)
        # Mur nord - fond (z=20)
        for x in range(0, 13):
            put(x, y, 20, 1)
        # Mur sud - entree (z=0)
        for x in range(0, 13):
            put(x, y, 0, 1)

    # Porte d'entree (z=0, x=5-7, y=1-4)
    for y in range(1, 5):
        for x in range(5, 8):
            put(x, y, 0, 0)  # AIR = ouverture
    # Cadre de porte en bois sombre
    put(5, 5, 0, 10)   # DARK_OAK linteau gauche
    put(6, 5, 0, 10)   # DARK_OAK linteau centre
    put(7, 5, 0, 10)   # DARK_OAK linteau droite

    # Piliers en bois aux coins interieurs
    for y in range(1, 8):
        put(1, y, 1, 7)    # SPRUCE_LOG coin SW
        put(11, y, 1, 7)   # SPRUCE_LOG coin SE
        put(1, y, 19, 7)   # SPRUCE_LOG coin NW
        put(11, y, 19, 7)  # SPRUCE_LOG coin NE

    # =============================================
    # VITRAUX (fenetres en verre)
    # =============================================
    # Mur ouest (x=0) — 3 fenetres
    for z_center in [5, 10, 15]:
        for y in range(3, 6):
            for dz in range(-1, 2):
                put(0, y, z_center + dz, 5)  # GLASS

    # Mur est (x=12) — 3 fenetres
    for z_center in [5, 10, 15]:
        for y in range(3, 6):
            for dz in range(-1, 2):
                put(12, y, z_center + dz, 5)  # GLASS

    # Grande rosace au fond (z=20)
    # Croix en verre
    for y in range(3, 7):
        put(6, y, 20, 5)
    for x in range(4, 9):
        put(x, 5, 20, 5)
    # Coins de la rosace
    put(5, 4, 20, 5)
    put(7, 4, 20, 5)
    put(5, 6, 20, 5)
    put(7, 6, 20, 5)

    # =============================================
    # FRISE DECORATIVE en briques (y=7, bande sous le toit)
    # =============================================
    for z in range(0, 21):
        put(0, 7, z, 8)   # BRICK ouest
        put(12, 7, z, 8)  # BRICK est
    for x in range(0, 13):
        put(x, 7, 0, 8)   # BRICK sud
        put(x, 7, 20, 8)  # BRICK nord

    # =============================================
    # TOIT EN PENTE (y=8 a y=12)
    # =============================================
    # Toit a deux pentes (est-ouest), pointe au centre (x=6)
    for dy in range(0, 6):
        y = 8 + dy
        x_left = dy          # cote gauche monte
        x_right = 12 - dy    # cote droit monte
        if x_left > x_right:
            break
        for z in range(0, 21):
            # Rang de toit gauche
            put(x_left, y, z, 4)      # SPRUCE_PLANKS
            # Rang de toit droit
            put(x_right, y, z, 4)     # SPRUCE_PLANKS
        # Remplir les pignons (murs triangulaires sud et nord)
        for x in range(x_left + 1, x_right):
            put(x, y, 0, 1)   # COBBLESTONE pignon sud
            put(x, y, 20, 1)  # COBBLESTONE pignon nord
    # Faitage (crete du toit)
    for z in range(0, 21):
        put(6, 13, z, 4)  # SPRUCE_PLANKS faitage

    # =============================================
    # CLOCHER (au-dessus de l'entree, z=0-4)
    # =============================================
    # Base du clocher : piliers aux coins (x=4,8 z=0,4)
    for y in range(8, 15):
        put(4, y, 0, 1)    # COBBLESTONE pilier SW
        put(8, y, 0, 1)    # COBBLESTONE pilier SE
        put(4, y, 4, 1)    # COBBLESTONE pilier NW
        put(8, y, 4, 1)    # COBBLESTONE pilier NE

    # Murs du clocher (y=8-14, ouvertures pour cloches y=11-13)
    for y in range(8, 15):
        # Murs pleins en bas (y=8-10), ouverts en haut (y=11-13)
        if y <= 10:
            for x in range(4, 9):
                put(x, y, 0, 1)
                put(x, y, 4, 1)
            for z in range(0, 5):
                put(4, y, z, 1)
                put(8, y, z, 1)
        else:
            # Ouvertures (arches) sur les 4 faces
            put(4, y, 0, 1); put(8, y, 0, 1)
            put(4, y, 4, 1); put(8, y, 4, 1)
            for z in range(0, 5):
                put(4, y, z, 1)
                put(8, y, z, 1)
            for x in range(4, 9):
                put(x, y, 0, 1)
                put(x, y, 4, 1)
            # Vider les ouvertures
            for x in range(5, 8):
                put(x, y, 0, 0)  # Face sud ouverte
                put(x, y, 4, 0)  # Face nord ouverte
            for z in range(1, 4):
                put(4, y, z, 0)  # Face ouest ouverte
                put(8, y, z, 0)  # Face est ouverte
            # Garder les piliers aux coins
            put(4, y, 0, 1); put(8, y, 0, 1)
            put(4, y, 4, 1); put(8, y, 4, 1)

    # Toit du clocher (pyramide y=15-17)
    for dy in range(0, 3):
        y = 15 + dy
        margin = dy
        for x in range(4 + margin, 9 - margin):
            for z in range(0 + margin, 5 - margin):
                put(x, y, z, 4)  # SPRUCE_PLANKS
    # Pointe du clocher
    put(6, 17, 2, 7)  # SPRUCE_LOG pointe

    # =============================================
    # AUTEL au fond (z=18-19)
    # =============================================
    # Table d'autel en pierre (2 blocs de haut)
    fill(4, 1, 18, 8, 1, 19, 2)  # STONE base
    fill(5, 2, 19, 7, 2, 19, 2)  # STONE dessus autel
    # Torches pres de l'autel
    put(4, 3, 19, 9)  # TORCH gauche
    put(8, 3, 19, 9)  # TORCH droite

    # =============================================
    # TORCHES le long de la nef
    # =============================================
    for z in [4, 9, 14]:
        put(1, 4, z, 9)   # TORCH mur ouest interieur
        put(11, 4, z, 9)  # TORCH mur est interieur

    # =============================================
    # BANCS (rangees de planches)
    # =============================================
    for z in range(4, 16, 2):
        # Rangee gauche
        fill(2, 1, z, 4, 1, z, 3)  # PLANKS banc gauche
        # Rangee droite
        fill(8, 1, z, 10, 1, z, 3) # PLANKS banc droite
    # Allee centrale libre (x=5-7)

    # =============================================
    # EXPORT
    # =============================================
    # Aplatir en 1D (y * W*D + z * W + x)
    flat = []
    for y in range(H):
        for z in range(D):
            for x in range(W):
                flat.append(blocks[y][z][x])

    # RLE encode
    rle = []
    i = 0
    while i < len(flat):
        val = flat[i]
        count = 1
        while i + count < len(flat) and flat[i + count] == val:
            count += 1
        rle.extend([val, count])
        i += count

    # Compter blocs non-air
    non_air = sum(1 for v in flat if v != 0)

    output = {
        "name": "chapelle_village",
        "size": [W, H, D],
        "palette": palette,
        "blocks_rle": rle
    }

    out_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                            "structures", "chapelle_village.json")
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, separators=(',', ':'))

    file_size = os.path.getsize(out_path)
    print(f"Chapelle generee: {W}x{H}x{D}")
    print(f"Blocs non-air: {non_air:,}")
    print(f"Palette: {len(palette)} types")
    print(f"Sauvegarde: {out_path} ({file_size:,} octets)")


if __name__ == "__main__":
    generate_church()
