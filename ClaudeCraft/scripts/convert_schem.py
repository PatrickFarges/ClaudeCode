#!/usr/bin/env python3
"""
Convertisseur .schem (Sponge Schematic) → JSON structure pour ClaudeCraft.

Usage :
    python convert_schem.py fichier.schem [--output structure.json] [--info]

Le flag --info affiche les dimensions et la palette sans convertir.

Format de sortie : JSON compatible avec StructureManager de ClaudeCraft.
Ordre des blocs : layer-first (y-major) → index = y * (sx * sz) + z * sx + x
"""

import gzip
import io
import json
import math
import struct
import sys
import os

# ============================================================
# MAPPING Minecraft → ClaudeCraft BlockType
# ============================================================
# Blocs Minecraft mappés vers les types disponibles dans ClaudeCraft.
# Les blocs inconnus sont mappés vers le type le plus proche ou KEEP.

MC_TO_CLAUDECRAFT = {
    # Air et vide
    "minecraft:air": "AIR",
    "minecraft:cave_air": "AIR",
    "minecraft:void_air": "AIR",

    # Pierre et derives
    "minecraft:stone": "STONE",
    "minecraft:stone_bricks": "STONE",
    "minecraft:stone_brick_stairs": "STONE",
    "minecraft:stone_brick_slab": "STONE",
    "minecraft:stone_brick_wall": "STONE",
    "minecraft:mossy_stone_bricks": "MOSSY_COBBLESTONE",
    "minecraft:cracked_stone_bricks": "STONE",
    "minecraft:chiseled_stone_bricks": "STONE",
    "minecraft:cobblestone": "COBBLESTONE",
    "minecraft:cobblestone_stairs": "COBBLESTONE",
    "minecraft:cobblestone_slab": "COBBLESTONE",
    "minecraft:cobblestone_wall": "COBBLESTONE",
    "minecraft:mossy_cobblestone": "MOSSY_COBBLESTONE",
    "minecraft:mossy_cobblestone_stairs": "MOSSY_COBBLESTONE",
    "minecraft:mossy_cobblestone_slab": "MOSSY_COBBLESTONE",
    "minecraft:mossy_cobblestone_wall": "MOSSY_COBBLESTONE",
    "minecraft:smooth_stone": "SMOOTH_STONE",
    "minecraft:smooth_stone_slab": "SMOOTH_STONE",
    "minecraft:infested_stone": "STONE",
    "minecraft:infested_stone_bricks": "STONE",
    "minecraft:andesite": "ANDESITE",
    "minecraft:polished_andesite": "ANDESITE",
    "minecraft:diorite": "DIORITE",
    "minecraft:polished_diorite": "DIORITE",
    "minecraft:granite": "GRANITE",
    "minecraft:polished_granite": "GRANITE",
    "minecraft:deepslate": "DEEPSLATE",
    "minecraft:cobbled_deepslate": "DEEPSLATE",
    "minecraft:polished_deepslate": "DEEPSLATE",
    "minecraft:deepslate_bricks": "DEEPSLATE",
    "minecraft:deepslate_tiles": "DEEPSLATE",
    "minecraft:tuff": "STONE",
    "minecraft:calcite": "STONE",
    "minecraft:bedrock": "STONE",

    # Terre et herbe
    "minecraft:dirt": "DIRT",
    "minecraft:coarse_dirt": "DIRT",
    "minecraft:rooted_dirt": "DIRT",
    "minecraft:dirt_path": "DIRT",
    "minecraft:farmland": "DIRT",
    "minecraft:mud": "DIRT",
    "minecraft:soul_soil": "DIRT",
    "minecraft:grass_block": "GRASS",
    "minecraft:podzol": "PODZOL",
    "minecraft:mycelium": "DARK_GRASS",
    "minecraft:moss_block": "MOSS_BLOCK",

    # Sable et grès
    "minecraft:sand": "SAND",
    "minecraft:red_sand": "SAND",
    "minecraft:sandstone": "SANDSTONE",
    "minecraft:sandstone_stairs": "SANDSTONE",
    "minecraft:sandstone_slab": "SANDSTONE",
    "minecraft:sandstone_wall": "SANDSTONE",
    "minecraft:smooth_sandstone": "SANDSTONE",
    "minecraft:smooth_sandstone_stairs": "SANDSTONE",
    "minecraft:smooth_sandstone_slab": "SANDSTONE",
    "minecraft:chiseled_sandstone": "SANDSTONE",
    "minecraft:cut_sandstone": "SANDSTONE",
    "minecraft:cut_sandstone_slab": "SANDSTONE",
    "minecraft:red_sandstone": "SANDSTONE",

    # Gravier
    "minecraft:gravel": "GRAVEL",

    # Bois (troncs)
    "minecraft:oak_log": "WOOD",
    "minecraft:spruce_log": "SPRUCE_LOG",
    "minecraft:birch_log": "BIRCH_LOG",
    "minecraft:jungle_log": "JUNGLE_LOG",
    "minecraft:acacia_log": "ACACIA_LOG",
    "minecraft:dark_oak_log": "DARK_OAK_LOG",
    "minecraft:mangrove_log": "JUNGLE_LOG",
    "minecraft:cherry_log": "CHERRY_LOG",
    "minecraft:stripped_oak_log": "WOOD",
    "minecraft:stripped_spruce_log": "SPRUCE_LOG",
    "minecraft:stripped_birch_log": "BIRCH_LOG",
    "minecraft:stripped_jungle_log": "JUNGLE_LOG",
    "minecraft:stripped_acacia_log": "ACACIA_LOG",
    "minecraft:stripped_dark_oak_log": "DARK_OAK_LOG",
    "minecraft:stripped_mangrove_log": "JUNGLE_LOG",
    "minecraft:stripped_cherry_log": "CHERRY_LOG",
    "minecraft:oak_wood": "WOOD",
    "minecraft:spruce_wood": "SPRUCE_LOG",
    "minecraft:birch_wood": "BIRCH_LOG",
    "minecraft:jungle_wood": "JUNGLE_LOG",
    "minecraft:acacia_wood": "ACACIA_LOG",
    "minecraft:dark_oak_wood": "DARK_OAK_LOG",

    # Planches
    "minecraft:oak_planks": "PLANKS",
    "minecraft:spruce_planks": "SPRUCE_PLANKS",
    "minecraft:birch_planks": "BIRCH_PLANKS",
    "minecraft:jungle_planks": "JUNGLE_PLANKS",
    "minecraft:acacia_planks": "ACACIA_PLANKS",
    "minecraft:dark_oak_planks": "DARK_OAK_PLANKS",
    "minecraft:mangrove_planks": "JUNGLE_PLANKS",
    "minecraft:cherry_planks": "CHERRY_PLANKS",
    "minecraft:crimson_planks": "PLANKS",
    "minecraft:warped_planks": "PLANKS",
    "minecraft:bamboo_planks": "PLANKS",
    # Escaliers et dalles en bois
    "minecraft:oak_stairs": "PLANKS",
    "minecraft:spruce_stairs": "SPRUCE_PLANKS",
    "minecraft:birch_stairs": "BIRCH_PLANKS",
    "minecraft:jungle_stairs": "JUNGLE_PLANKS",
    "minecraft:acacia_stairs": "ACACIA_PLANKS",
    "minecraft:dark_oak_stairs": "DARK_OAK_PLANKS",
    "minecraft:oak_slab": "PLANKS",
    "minecraft:spruce_slab": "SPRUCE_PLANKS",
    "minecraft:birch_slab": "BIRCH_PLANKS",
    "minecraft:jungle_slab": "JUNGLE_PLANKS",
    "minecraft:acacia_slab": "ACACIA_PLANKS",
    "minecraft:dark_oak_slab": "DARK_OAK_PLANKS",
    # Portes, trappes, barrieres
    "minecraft:oak_door": "PLANKS",
    "minecraft:spruce_door": "SPRUCE_PLANKS",
    "minecraft:birch_door": "BIRCH_PLANKS",
    "minecraft:jungle_door": "JUNGLE_PLANKS",
    "minecraft:acacia_door": "ACACIA_PLANKS",
    "minecraft:dark_oak_door": "DARK_OAK_PLANKS",
    "minecraft:oak_trapdoor": "PLANKS",
    "minecraft:spruce_trapdoor": "SPRUCE_PLANKS",
    "minecraft:birch_trapdoor": "BIRCH_PLANKS",
    "minecraft:jungle_trapdoor": "JUNGLE_PLANKS",
    "minecraft:acacia_trapdoor": "ACACIA_PLANKS",
    "minecraft:dark_oak_trapdoor": "DARK_OAK_PLANKS",
    "minecraft:oak_fence": "PLANKS",
    "minecraft:spruce_fence": "SPRUCE_PLANKS",
    "minecraft:birch_fence": "BIRCH_PLANKS",
    "minecraft:jungle_fence": "JUNGLE_PLANKS",
    "minecraft:acacia_fence": "ACACIA_PLANKS",
    "minecraft:dark_oak_fence": "DARK_OAK_PLANKS",
    "minecraft:oak_fence_gate": "PLANKS",
    "minecraft:spruce_fence_gate": "PLANKS",
    "minecraft:birch_fence_gate": "PLANKS",
    "minecraft:oak_sign": "PLANKS",
    "minecraft:spruce_sign": "PLANKS",
    "minecraft:birch_sign": "PLANKS",
    "minecraft:oak_wall_sign": "PLANKS",
    "minecraft:spruce_wall_sign": "PLANKS",
    "minecraft:birch_wall_sign": "PLANKS",

    # Feuilles
    "minecraft:oak_leaves": "LEAVES",
    "minecraft:spruce_leaves": "SPRUCE_LEAVES",
    "minecraft:birch_leaves": "BIRCH_LEAVES",
    "minecraft:jungle_leaves": "JUNGLE_LEAVES",
    "minecraft:acacia_leaves": "ACACIA_LEAVES",
    "minecraft:dark_oak_leaves": "DARK_OAK_LEAVES",
    "minecraft:azalea_leaves": "LEAVES",
    "minecraft:flowering_azalea_leaves": "LEAVES",
    "minecraft:mangrove_leaves": "JUNGLE_LEAVES",
    "minecraft:cherry_leaves": "CHERRY_LEAVES",

    # Briques
    "minecraft:bricks": "BRICK",
    "minecraft:brick_stairs": "BRICK",
    "minecraft:brick_slab": "BRICK",
    "minecraft:brick_wall": "BRICK",
    "minecraft:nether_bricks": "BRICK",
    "minecraft:red_nether_bricks": "BRICK",

    # Neige et glace
    "minecraft:snow": "SNOW",
    "minecraft:snow_block": "SNOW",
    "minecraft:powder_snow": "SNOW",
    "minecraft:ice": "ICE",
    "minecraft:packed_ice": "PACKED_ICE",
    "minecraft:blue_ice": "PACKED_ICE",
    "minecraft:packed_ice": "SNOW",
    "minecraft:blue_ice": "SNOW",

    # Eau
    "minecraft:water": "WATER",

    # Minerais
    "minecraft:coal_ore": "COAL_ORE",
    "minecraft:deepslate_coal_ore": "COAL_ORE",
    "minecraft:iron_ore": "IRON_ORE",
    "minecraft:deepslate_iron_ore": "IRON_ORE",
    "minecraft:gold_ore": "GOLD_ORE",
    "minecraft:deepslate_gold_ore": "GOLD_ORE",

    # Blocs métalliques
    "minecraft:iron_block": "IRON_INGOT",
    "minecraft:gold_block": "GOLD_INGOT",

    # Cactus
    "minecraft:cactus": "CACTUS",

    # Crafting
    "minecraft:crafting_table": "CRAFTING_TABLE",
    "minecraft:furnace": "FURNACE",
    "minecraft:blast_furnace": "FURNACE",
    "minecraft:smoker": "FURNACE",

    # Verre → AIR (transparent, pas de bloc verre dans ClaudeCraft)
    "minecraft:glass": "GLASS",
    "minecraft:glass_pane": "GLASS",
    "minecraft:white_stained_glass": "AIR",
    "minecraft:white_stained_glass_pane": "AIR",

    # Laine et terre cuite colorée → PLANKS (approximation)
    "minecraft:white_wool": "SNOW",
    "minecraft:white_concrete": "SNOW",
    "minecraft:white_terracotta": "SANDSTONE",
    "minecraft:brown_terracotta": "DIRT",
    "minecraft:orange_terracotta": "SANDSTONE",
    "minecraft:terracotta": "SANDSTONE",
    "minecraft:red_terracotta": "BRICK",

    # Blocs divers → mapping approximatif
    "minecraft:coal_block": "COAL_BLOCK",
    "minecraft:diamond_ore": "DIAMOND_ORE",
    "minecraft:deepslate_diamond_ore": "DIAMOND_ORE",
    "minecraft:diamond_block": "DIAMOND_BLOCK",
    "minecraft:copper_ore": "COPPER_ORE",
    "minecraft:deepslate_copper_ore": "COPPER_ORE",
    "minecraft:copper_block": "COPPER_BLOCK",
    "minecraft:decorated_pot": "BRICK",
    "minecraft:barrel": "BARREL",
    "minecraft:bookshelf": "BOOKSHELF",
    "minecraft:chest": "PLANKS",
    "minecraft:hay_block": "HAY_BLOCK",
    "minecraft:clay": "CLAY",
    "minecraft:lantern": "AIR",
    "minecraft:soul_lantern": "AIR",
    "minecraft:torch": "AIR",
    "minecraft:wall_torch": "AIR",
    "minecraft:campfire": "AIR",
    "minecraft:soul_campfire": "AIR",
    "minecraft:ladder": "AIR",
    "minecraft:vine": "AIR",
    "minecraft:flower_pot": "AIR",
    "minecraft:potted_oak_sapling": "AIR",
    "minecraft:lever": "AIR",
    "minecraft:tripwire": "AIR",
    "minecraft:tripwire_hook": "AIR",
    "minecraft:string": "AIR",
    "minecraft:iron_bars": "AIR",
    "minecraft:chain": "AIR",
    "minecraft:bell": "AIR",

    # Végétation → AIR (pas de rendu dans ClaudeCraft)
    "minecraft:grass": "AIR",
    "minecraft:short_grass": "AIR",
    "minecraft:tall_grass": "AIR",
    "minecraft:fern": "AIR",
    "minecraft:large_fern": "AIR",
    "minecraft:dead_bush": "AIR",
    "minecraft:dandelion": "AIR",
    "minecraft:poppy": "AIR",
    "minecraft:blue_orchid": "AIR",
    "minecraft:allium": "AIR",
    "minecraft:azure_bluet": "AIR",
    "minecraft:red_tulip": "AIR",
    "minecraft:oxeye_daisy": "AIR",
    "minecraft:cornflower": "AIR",
    "minecraft:lily_of_the_valley": "AIR",
    "minecraft:sunflower": "AIR",
    "minecraft:lilac": "AIR",
    "minecraft:rose_bush": "AIR",
    "minecraft:peony": "AIR",
    "minecraft:sugar_cane": "AIR",
    "minecraft:bamboo": "AIR",
    "minecraft:sweet_berry_bush": "AIR",
    "minecraft:oak_sapling": "AIR",
    "minecraft:spruce_sapling": "AIR",
    "minecraft:birch_sapling": "AIR",
    "minecraft:lily_pad": "AIR",
    "minecraft:seagrass": "AIR",
    "minecraft:tall_seagrass": "AIR",
    "minecraft:kelp": "AIR",
    "minecraft:kelp_plant": "AIR",
    "minecraft:moss_carpet": "AIR",
    "minecraft:hanging_roots": "AIR",
    "minecraft:spore_blossom": "AIR",
    "minecraft:glow_lichen": "AIR",

    # Redstone → AIR
    "minecraft:redstone_wire": "AIR",
    "minecraft:redstone_torch": "AIR",
    "minecraft:redstone_wall_torch": "AIR",
    "minecraft:repeater": "AIR",
    "minecraft:comparator": "AIR",

    # Tapis → AIR
    "minecraft:white_carpet": "AIR",
    "minecraft:orange_carpet": "AIR",
    "minecraft:brown_carpet": "AIR",
    "minecraft:green_carpet": "AIR",
    "minecraft:red_carpet": "AIR",
    "minecraft:light_gray_carpet": "AIR",
    "minecraft:gray_carpet": "AIR",

    # Bannières → AIR
    "minecraft:white_banner": "AIR",
    "minecraft:white_wall_banner": "AIR",

    # Têtes de mobs → AIR
    "minecraft:skeleton_skull": "AIR",
    "minecraft:skeleton_wall_skull": "AIR",
    "minecraft:player_head": "AIR",
    "minecraft:player_wall_head": "AIR",

    # Boutons et plaques de pression → AIR
    "minecraft:oak_button": "AIR",
    "minecraft:stone_button": "AIR",
    "minecraft:oak_pressure_plate": "AIR",
    "minecraft:stone_pressure_plate": "AIR",

    # Portails → AIR
    "minecraft:end_portal_frame": "STONE",
    "minecraft:nether_portal": "AIR",
}


# ============================================================
# PARSEUR NBT MINIMAL
# ============================================================

TAG_END = 0
TAG_BYTE = 1
TAG_SHORT = 2
TAG_INT = 3
TAG_LONG = 4
TAG_FLOAT = 5
TAG_DOUBLE = 6
TAG_BYTE_ARRAY = 7
TAG_STRING = 8
TAG_LIST = 9
TAG_COMPOUND = 10
TAG_INT_ARRAY = 11
TAG_LONG_ARRAY = 12


class NBTReader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def read(self, n: int) -> bytes:
        result = self.data[self.pos:self.pos + n]
        self.pos += n
        return result

    def read_byte(self) -> int:
        val = self.data[self.pos]
        self.pos += 1
        return val

    def read_signed_byte(self) -> int:
        val = struct.unpack_from('>b', self.data, self.pos)[0]
        self.pos += 1
        return val

    def read_short(self) -> int:
        val = struct.unpack_from('>h', self.data, self.pos)[0]
        self.pos += 2
        return val

    def read_int(self) -> int:
        val = struct.unpack_from('>i', self.data, self.pos)[0]
        self.pos += 4
        return val

    def read_long(self) -> int:
        val = struct.unpack_from('>q', self.data, self.pos)[0]
        self.pos += 8
        return val

    def read_float(self) -> float:
        val = struct.unpack_from('>f', self.data, self.pos)[0]
        self.pos += 4
        return val

    def read_double(self) -> float:
        val = struct.unpack_from('>d', self.data, self.pos)[0]
        self.pos += 8
        return val

    def read_string(self) -> str:
        length = self.read_short()
        if length < 0:
            length = 0
        s = self.data[self.pos:self.pos + length].decode('utf-8', errors='replace')
        self.pos += length
        return s

    def read_tag_payload(self, tag_type: int):
        if tag_type == TAG_END:
            return None
        elif tag_type == TAG_BYTE:
            return self.read_signed_byte()
        elif tag_type == TAG_SHORT:
            return self.read_short()
        elif tag_type == TAG_INT:
            return self.read_int()
        elif tag_type == TAG_LONG:
            return self.read_long()
        elif tag_type == TAG_FLOAT:
            return self.read_float()
        elif tag_type == TAG_DOUBLE:
            return self.read_double()
        elif tag_type == TAG_BYTE_ARRAY:
            length = self.read_int()
            return self.read(length)
        elif tag_type == TAG_STRING:
            return self.read_string()
        elif tag_type == TAG_LIST:
            list_type = self.read_byte()
            length = self.read_int()
            return [self.read_tag_payload(list_type) for _ in range(length)]
        elif tag_type == TAG_COMPOUND:
            result = {}
            while True:
                child_type = self.read_byte()
                if child_type == TAG_END:
                    break
                child_name = self.read_string()
                child_value = self.read_tag_payload(child_type)
                # En cas de doublon de clé, préserver le byte_array (prioritaire)
                if child_name in result:
                    existing = result[child_name]
                    if isinstance(existing, (bytes, bytearray)):
                        # Garder le byte_array, stocker l'autre sous un nom alternatif
                        result[child_name + "_alt"] = child_value
                        continue
                result[child_name] = child_value
            return result
        elif tag_type == TAG_INT_ARRAY:
            length = self.read_int()
            return [self.read_int() for _ in range(length)]
        elif tag_type == TAG_LONG_ARRAY:
            length = self.read_int()
            return [self.read_long() for _ in range(length)]
        else:
            raise ValueError(f"Type NBT inconnu : {tag_type} à position {self.pos}")

    def read_root(self) -> dict:
        tag_type = self.read_byte()
        if tag_type != TAG_COMPOUND:
            raise ValueError(f"Le tag racine devrait être un Compound (10), trouvé {tag_type}")
        _root_name = self.read_string()
        return self.read_tag_payload(TAG_COMPOUND)


def parse_nbt(data: bytes) -> dict:
    reader = NBTReader(data)
    return reader.read_root()


# ============================================================
# DÉCODAGE VARINT (Sponge Schematic BlockData)
# ============================================================

def decode_varints(data: bytes, expected_count: int) -> list:
    """Décode un tableau d'entiers encodés en varint."""
    result = []
    i = 0
    while i < len(data) and len(result) < expected_count:
        value = 0
        shift = 0
        while True:
            b = data[i]
            i += 1
            value |= (b & 0x7F) << shift
            shift += 7
            if (b & 0x80) == 0:
                break
        result.append(value)
    return result


# ============================================================
# DÉCODAGE BIT-PACKED LONGARRAY (Litematica)
# ============================================================

def unpack_litematic_blocks(long_array: list, palette_size: int, volume: int) -> list:
    """Décode un LongArray bit-packed du format Litematica.

    Le format Litematica stocke les indices de blocs en compact bit-packing :
    - bits_per_block = max(2, ceil(log2(palette_size)))
    - Les valeurs peuvent chevaucher deux longs (format compact, pas paddé)
    - Les longs NBT sont signés 64 bits → conversion en non-signé nécessaire
    """
    if palette_size <= 1:
        return [0] * volume

    bits = max(2, math.ceil(math.log2(palette_size)))
    mask = (1 << bits) - 1

    # Convertir les longs signés en non-signés
    unsigned = [(v + (1 << 64)) if v < 0 else v for v in long_array]

    result = []
    for i in range(volume):
        bit_start = i * bits
        long_idx = bit_start // 64
        bit_offset = bit_start % 64

        if long_idx >= len(unsigned):
            result.append(0)
            continue

        if bit_offset + bits <= 64:
            # L'entrée tient dans un seul long
            value = (unsigned[long_idx] >> bit_offset) & mask
        else:
            # L'entrée chevauche deux longs
            bits_first = 64 - bit_offset
            value = (unsigned[long_idx] >> bit_offset) & ((1 << bits_first) - 1)
            if long_idx + 1 < len(unsigned):
                bits_rem = bits - bits_first
                value |= (unsigned[long_idx + 1] & ((1 << bits_rem) - 1)) << bits_first

        result.append(value)

    return result


# ============================================================
# ENCODAGE RLE
# ============================================================

def encode_rle(data: list) -> list:
    """Encode une liste en RLE : [valeur, count, valeur, count, ...]"""
    if not data:
        return []
    rle = []
    current = data[0]
    count = 1
    for val in data[1:]:
        if val == current:
            count += 1
        else:
            rle.extend([current, count])
            current = val
            count = 1
    rle.extend([current, count])
    return rle


# ============================================================
# CONVERSION .schem → JSON
# ============================================================

# ============================================================
# MAPPING INTELLIGENT PAR PATTERN (fallback pour blocs non listés)
# ============================================================

# Suffixes qui indiquent une variante du bloc de base (escalier, dalle, mur, etc.)
_VARIANT_SUFFIXES = [
    "_stairs", "_slab", "_wall", "_fence", "_fence_gate",
    "_door", "_trapdoor", "_sign", "_wall_sign", "_hanging_sign",
    "_wall_hanging_sign", "_button", "_pressure_plate",
]

# Patterns de noms → mapping ClaudeCraft
_PATTERN_RULES = [
    # Transparents / décoratifs → AIR
    (lambda n: "glass" in n, "AIR"),
    (lambda n: "glass_pane" in n, "AIR"),
    (lambda n: "carpet" in n, "AIR"),
    (lambda n: "banner" in n, "AIR"),
    (lambda n: "wall_banner" in n, "AIR"),
    (lambda n: "candle" in n, "AIR"),
    (lambda n: "torch" in n, "AIR"),
    (lambda n: "lantern" in n, "AIR"),
    (lambda n: "flower" in n, "AIR"),
    (lambda n: "tulip" in n, "AIR"),
    (lambda n: "orchid" in n, "AIR"),
    (lambda n: "daisy" in n, "AIR"),
    (lambda n: "bush" in n, "AIR"),
    (lambda n: "sapling" in n, "AIR"),
    (lambda n: "mushroom" in n and "block" not in n, "AIR"),
    (lambda n: "potted_" in n, "AIR"),
    (lambda n: "coral" in n and "block" not in n, "AIR"),
    (lambda n: n.endswith("_stem"), "AIR"),
    (lambda n: "attached_" in n, "AIR"),
    (lambda n: "vine" in n, "AIR"),
    (lambda n: "lichen" in n, "AIR"),
    (lambda n: "roots" in n, "AIR"),
    (lambda n: "spore" in n, "AIR"),
    (lambda n: "pickle" in n, "AIR"),
    (lambda n: "frogspawn" in n, "AIR"),
    (lambda n: "rail" in n, "AIR"),
    (lambda n: "lever" == n, "AIR"),
    (lambda n: "tripwire" in n, "AIR"),
    (lambda n: "string" == n, "AIR"),
    (lambda n: "chain" == n, "AIR"),
    (lambda n: "iron_bars" == n, "AIR"),
    (lambda n: "scaffolding" in n, "AIR"),
    (lambda n: "sign" in n, "AIR"),
    (lambda n: "head" in n or "skull" in n, "AIR"),
    (lambda n: "item_frame" in n, "AIR"),
    (lambda n: "painting" in n, "AIR"),
    (lambda n: "armor_stand" in n, "AIR"),
    (lambda n: "redstone" in n, "AIR"),
    (lambda n: "repeater" in n, "AIR"),
    (lambda n: "comparator" in n, "AIR"),
    (lambda n: "piston" in n, "AIR"),
    (lambda n: "hopper" in n, "AIR"),
    (lambda n: "dropper" in n, "AIR"),
    (lambda n: "dispenser" in n, "AIR"),
    (lambda n: "observer" in n, "AIR"),
    (lambda n: "daylight" in n, "AIR"),
    (lambda n: "target" in n, "AIR"),
    (lambda n: "bell" == n, "AIR"),
    (lambda n: "cake" in n, "AIR"),
    (lambda n: "brewing" in n, "AIR"),
    (lambda n: "anvil" in n, "AIR"),
    (lambda n: "grindstone" in n, "AIR"),
    (lambda n: "loom" in n, "AIR"),
    (lambda n: "composter" in n, "AIR"),
    (lambda n: "lectern" in n, "AIR"),
    (lambda n: "cauldron" in n, "AIR"),
    (lambda n: "enchanting" in n, "AIR"),
    (lambda n: "end_rod" in n, "AIR"),
    (lambda n: "lightning_rod" in n, "AIR"),
    (lambda n: "button" in n, "AIR"),
    (lambda n: "pressure_plate" in n, "AIR"),
    (lambda n: "shulker_box" in n, "AIR"),
    (lambda n: "bed" in n and "rock" not in n, "AIR"),
    (lambda n: "spawner" in n, "AIR"),
    (lambda n: "command_block" in n, "AIR"),
    (lambda n: "structure_block" in n, "AIR"),
    (lambda n: "barrier" in n, "AIR"),
    (lambda n: "light" == n, "AIR"),
    (lambda n: "jigsaw" in n, "AIR"),
    (lambda n: "structure_void" in n, "AIR"),

    # Cultures → AIR
    (lambda n: "wheat" in n, "AIR"),
    (lambda n: "carrots" in n, "AIR"),
    (lambda n: "potatoes" in n, "AIR"),
    (lambda n: "beetroots" in n, "AIR"),
    (lambda n: "melon" in n and "block" not in n, "AIR"),
    (lambda n: "pumpkin" in n and n != "pumpkin", "AIR"),
    (lambda n: "cocoa" in n, "AIR"),
    (lambda n: "nether_wart" in n and "block" not in n, "AIR"),
    (lambda n: "sugar_cane" in n, "AIR"),
    (lambda n: "bamboo" in n and "planks" not in n and "block" not in n, "AIR"),
    (lambda n: "kelp" in n, "AIR"),
    (lambda n: "seagrass" in n, "AIR"),
    (lambda n: "grass" == n or "short_grass" == n or "tall_grass" == n, "AIR"),
    (lambda n: "fern" == n or "large_fern" == n, "AIR"),

    # Eau et lave
    (lambda n: "water" in n, "WATER"),
    (lambda n: "lava" in n, "AIR"),

    # Feuilles
    (lambda n: "leaves" in n, "LEAVES"),

    # Bois (troncs)
    (lambda n: "_log" in n or "_wood" in n, "WOOD"),
    (lambda n: "stripped_" in n and ("log" in n or "wood" in n or "stem" in n or "hyphae" in n), "WOOD"),
    (lambda n: "mushroom_stem" in n, "WOOD"),

    # Planches et dérivés bois
    (lambda n: "_planks" in n, "PLANKS"),
    (lambda n: "_fence" in n and "nether" not in n and "iron" not in n, "PLANKS"),
    (lambda n: "_door" in n and "iron" not in n, "PLANKS"),
    (lambda n: "_trapdoor" in n and "iron" not in n, "PLANKS"),
    (lambda n: "barrel" == n, "PLANKS"),
    (lambda n: "bookshelf" in n, "PLANKS"),
    (lambda n: "chest" in n, "PLANKS"),
    (lambda n: "crafting_table" in n, "PLANKS"),
    (lambda n: "cartography_table" in n, "PLANKS"),
    (lambda n: "fletching_table" in n, "PLANKS"),
    (lambda n: "smithing_table" in n, "PLANKS"),
    (lambda n: "stonecutter" in n, "PLANKS"),

    # Briques
    (lambda n: "brick" in n, "BRICK"),

    # Pierre et variantes
    (lambda n: "stone" in n, "STONE"),
    (lambda n: "andesite" in n, "STONE"),
    (lambda n: "diorite" in n, "STONE"),
    (lambda n: "granite" in n, "STONE"),
    (lambda n: "cobblestone" in n, "STONE"),
    (lambda n: "deepslate" in n, "STONE"),
    (lambda n: "tuff" in n, "STONE"),
    (lambda n: "calcite" in n, "STONE"),
    (lambda n: "basalt" in n, "STONE"),
    (lambda n: "blackstone" in n, "STONE"),
    (lambda n: "prismarine" in n, "STONE"),
    (lambda n: "purpur" in n, "STONE"),
    (lambda n: "end_stone" in n, "STONE"),
    (lambda n: "obsidian" in n, "STONE"),
    (lambda n: "quartz" in n, "STONE"),

    # Sable et grès
    (lambda n: "sandstone" in n, "SANDSTONE"),
    (lambda n: "sand" in n and "stone" not in n, "SAND"),

    # Terre/herbe
    (lambda n: "dirt" in n or "mud" in n, "DIRT"),
    (lambda n: "grass_block" in n, "GRASS"),
    (lambda n: "podzol" in n or "mycelium" in n or "moss_block" in n, "DARK_GRASS"),
    (lambda n: "farmland" in n, "DIRT"),

    # Gravier
    (lambda n: "gravel" in n, "GRAVEL"),
    (lambda n: "clay" == n, "GRAVEL"),

    # Neige
    (lambda n: "snow" in n or "ice" in n, "SNOW"),

    # Laine colorée → approximation par couleur
    (lambda n: "wool" in n, "SNOW"),
    (lambda n: "concrete" in n and "powder" not in n, "STONE"),
    (lambda n: "concrete_powder" in n, "SAND"),
    (lambda n: "terracotta" in n, "SANDSTONE"),

    # Blocs lumineux → AIR ou STONE
    (lambda n: "froglight" in n, "SAND"),
    (lambda n: "glowstone" in n, "SAND"),
    (lambda n: "shroomlight" in n, "SAND"),
    (lambda n: "sea_lantern" in n, "SAND"),

    # Nether blocks
    (lambda n: "nether_wart_block" in n, "BRICK"),
    (lambda n: "netherrack" in n, "STONE"),
    (lambda n: "soul_sand" in n, "SAND"),
    (lambda n: "magma_block" in n, "STONE"),
    (lambda n: "crimson" in n or "warped" in n, "PLANKS"),

    # Divers solides
    (lambda n: "beehive" in n or "bee_nest" in n, "PLANKS"),
    (lambda n: "honey" in n, "SAND"),
    (lambda n: "petrified_oak_slab" in n, "PLANKS"),
    (lambda n: "pumpkin" == n, "SAND"),
    (lambda n: "melon_block" in n or "melon" == n, "GRASS"),
    (lambda n: "hay_block" in n, "SAND"),
    (lambda n: "mushroom_block" in n, "DIRT"),
    (lambda n: "sponge" in n, "SAND"),
    (lambda n: "honeycomb_block" in n, "SAND"),
    (lambda n: "copper" in n, "STONE"),
    (lambda n: "amethyst" in n, "STONE"),
    (lambda n: "iron" in n, "STONE"),
]


def smart_map_block(mc_name: str) -> str:
    """Résout un nom de bloc Minecraft vers ClaudeCraft, d'abord par dict, puis par patterns."""
    # 1. Lookup direct dans le dictionnaire
    result = MC_TO_CLAUDECRAFT.get(mc_name)
    if result is not None:
        return result

    # 2. Enlever le préfixe "minecraft:"
    short = mc_name.replace("minecraft:", "")

    # 3. Tester les patterns
    for test, mapping in _PATTERN_RULES:
        if test(short):
            return mapping

    # 4. Fallback → STONE (bloc solide inconnu)
    return None


def strip_block_states(block_name: str) -> str:
    """Enlève les block states : 'minecraft:oak_stairs[facing=north,half=bottom]' → 'minecraft:oak_stairs'"""
    bracket = block_name.find('[')
    if bracket != -1:
        return block_name[:bracket]
    return block_name


def convert_schem(schem_path: str, output_path: str = None, info_only: bool = False):
    # Lire et décompresser
    with open(schem_path, 'rb') as f:
        raw = f.read()

    if raw[:2] == b'\x1f\x8b':
        data = gzip.decompress(raw)
    else:
        data = raw

    nbt = parse_nbt(data)

    # Sponge Schematic v2/v3 : peut être wrappé dans "Schematic"
    root = nbt.get("Schematic", nbt)

    version = root.get("Version", 0)
    width = root.get("Width", 0)    # X
    height = root.get("Height", 0)   # Y
    length = root.get("Length", 0)    # Z

    print(f"Fichier    : {os.path.basename(schem_path)}")
    print(f"Version    : Sponge Schematic v{version}")
    print(f"Dimensions : {width} x {height} x {length} (X x Y x Z)")
    print(f"Total blocs: {width * height * length:,}")

    # Récupérer la palette et les données de blocs
    # v3 : root.Blocks.Palette + root.Blocks.Data
    # v2 : root.Palette + root.BlockData
    blocks_compound = root.get("Blocks", {})
    if blocks_compound and isinstance(blocks_compound, dict):
        # v3 path
        palette_data = blocks_compound.get("Palette", {})
        block_data_raw = blocks_compound.get("Data", b"")
        if not palette_data:
            # Fallback : palette au niveau racine
            palette_data = root.get("Palette", {})
    else:
        # v2 path
        palette_data = root.get("Palette", {})
        block_data_raw = root.get("BlockData", b"")

    if not palette_data:
        print("ERREUR : Palette introuvable dans le fichier.")
        return

    # Palette : {nom_bloc: id} → inverser en {id: nom_bloc}
    id_to_name = {}
    for name, idx in palette_data.items():
        id_to_name[idx] = name

    print(f"Palette    : {len(id_to_name)} types de blocs")

    if info_only:
        print("\n--- Palette complete ---")
        unmapped = []
        for idx in sorted(id_to_name.keys()):
            mc_name = strip_block_states(id_to_name[idx])
            cc_name = smart_map_block(mc_name)
            if cc_name is None:
                cc_name = "STONE"
                unmapped.append(mc_name)
                marker = "  <-- NON MAPPE"
            else:
                marker = ""
            print(f"  [{idx:3d}] {id_to_name[idx]:50s} -> {cc_name}{marker}")

        if unmapped:
            unique_unmapped = sorted(set(unmapped))
            print(f"\n/!\\ {len(unique_unmapped)} bloc(s) non mappe(s) (seront convertis en STONE) :")
            for n in sorted(unique_unmapped):
                print(f"  {n}")
        else:
            print("\nTous les blocs sont mappes !")
        return

    # Vérifier le type de block_data_raw
    if not isinstance(block_data_raw, (bytes, bytearray)):
        print(f"DEBUG: block_data_raw est de type {type(block_data_raw).__name__}")
        if isinstance(block_data_raw, dict):
            print(f"DEBUG: clés = {list(block_data_raw.keys())[:10]}")
        # Si c'est un dict, c'est peut-être un TAG_Byte_Array mal parsé
        # ou les données sont ailleurs
        # Chercher dans toutes les clés connues
        for search_key in ["Data", "BlockData", "data", "blockData"]:
            for search_root in [root, blocks_compound]:
                if isinstance(search_root, dict) and search_key in search_root:
                    candidate = search_root[search_key]
                    if isinstance(candidate, (bytes, bytearray)):
                        block_data_raw = candidate
                        print(f"DEBUG: trouvé données dans {search_key}, {len(candidate)} octets")
                        break
            if isinstance(block_data_raw, (bytes, bytearray)):
                break

    if not isinstance(block_data_raw, (bytes, bytearray)):
        print("ERREUR : impossible de trouver les données de blocs (BlockData/Data)")
        print(f"Clés disponibles au root : {list(root.keys())}")
        if isinstance(blocks_compound, dict):
            print(f"Clés dans Blocks : {list(blocks_compound.keys())}")
        return

    # Décoder les blocs
    total_blocks = width * height * length
    block_ids = decode_varints(block_data_raw, total_blocks)

    if len(block_ids) != total_blocks:
        print(f"ATTENTION : {len(block_ids)} blocs décodés, attendu {total_blocks}")

    # Mapper les blocs Minecraft → ClaudeCraft
    # Construire la palette de sortie
    cc_palette_set = set()
    cc_palette_set.add("AIR")

    mc_id_to_cc = {}
    unmapped_blocks = {}
    for mc_id, mc_name in id_to_name.items():
        stripped = strip_block_states(mc_name)
        cc_name = smart_map_block(stripped)
        if cc_name is None:
            cc_name = "STONE"
            unmapped_blocks[stripped] = unmapped_blocks.get(stripped, 0)
        mc_id_to_cc[mc_id] = cc_name
        cc_palette_set.add(cc_name)

    # Palette de sortie ordonnée (AIR en premier)
    cc_palette = ["AIR"] + sorted(cc_palette_set - {"AIR"})
    cc_name_to_idx = {name: idx for idx, name in enumerate(cc_palette)}

    # Convertir les blocs dans l'ordre layer-first (y * width * length + z * width + x)
    # Le format .schem stocke en : index = (y * length + z) * width + x
    # Notre format : index = y * (width * length) + z * width + x
    # → C'est le même ordre !
    converted = []
    for block_id in block_ids:
        cc_name = mc_id_to_cc.get(block_id, "STONE")
        converted.append(cc_name_to_idx[cc_name])

    # Compter les blocs non-air pour les stats
    non_air = sum(1 for b in converted if b != 0)
    air_pct = (1 - non_air / len(converted)) * 100 if converted else 0

    # Encoder en RLE
    rle = encode_rle(converted)

    print(f"Blocs pleins: {non_air:,} ({100 - air_pct:.1f}%), air: {air_pct:.1f}%")
    print(f"RLE         : {len(rle)} valeurs ({len(rle) // 2} runs)")

    if unmapped_blocks:
        print(f"\n/!\\ {len(unmapped_blocks)} type(s) de blocs non mappe(s) -> STONE :")
        for name in sorted(unmapped_blocks.keys()):
            print(f"  {name}")

    # Générer le JSON
    structure_name = os.path.splitext(os.path.basename(schem_path))[0]
    structure_name = structure_name.lower().replace(" ", "_").replace("-", "_")

    output = {
        "name": structure_name,
        "size": [width, height, length],
        "palette": cc_palette,
        "blocks_rle": rle
    }

    if output_path is None:
        output_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "structures")
        os.makedirs(output_dir, exist_ok=True)
        output_path = os.path.join(output_dir, structure_name + ".json")

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, separators=(',', ':'))

    file_size = os.path.getsize(output_path)
    print(f"\n-> Sauvegarde : {output_path}")
    print(f"  Taille     : {file_size:,} octets ({file_size / 1024:.1f} Ko)")


# ============================================================
# CONVERSION .litematic → JSON
# ============================================================

def convert_litematic(litematic_path: str, output_path: str = None, info_only: bool = False):
    """Convertit un fichier .litematic (Litematica) en JSON ClaudeCraft."""
    with open(litematic_path, 'rb') as f:
        raw = f.read()

    if raw[:2] == b'\x1f\x8b':
        data = gzip.decompress(raw)
    else:
        data = raw

    nbt = parse_nbt(data)

    version = nbt.get("Version", 0)
    mc_version = nbt.get("MinecraftDataVersion", 0)
    metadata = nbt.get("Metadata", {})
    regions = nbt.get("Regions", {})

    lit_name = metadata.get("Name", "unknown")
    author = metadata.get("Author", "unknown")
    enc_size = metadata.get("EnclosingSize", {})
    total_blocks = metadata.get("TotalBlocks", 0)
    total_volume = metadata.get("TotalVolume", 0)

    print(f"Fichier          : {os.path.basename(litematic_path)}")
    print(f"Format           : Litematica v{version} (MC data v{mc_version})")
    print(f"Nom              : {lit_name}")
    print(f"Auteur           : {author}")
    print(f"Taille englobante: {enc_size.get('x', '?')} x {enc_size.get('y', '?')} x {enc_size.get('z', '?')}")
    print(f"Blocs solides    : {total_blocks:,}")
    print(f"Volume total     : {total_volume:,}")
    print(f"Régions          : {len(regions)}")

    # Collecter tous les blocs avec coordonnées globales
    all_blocks = []  # [(x, y, z, cc_name), ...]
    unmapped_all = {}

    for region_name, region in regions.items():
        pos = region.get("Position", {})
        size = region.get("Size", {})

        px, py, pz = pos.get("x", 0), pos.get("y", 0), pos.get("z", 0)
        sx, sy, sz = size.get("x", 0), size.get("y", 0), size.get("z", 0)

        # Gérer les dimensions négatives
        if sx < 0:
            px += sx + 1
            sx = -sx
        if sy < 0:
            py += sy + 1
            sy = -sy
        if sz < 0:
            pz += sz + 1
            sz = -sz

        palette_list = region.get("BlockStatePalette", [])
        block_states = region.get("BlockStates", [])

        print(f"\n  Région '{region_name}' :")
        print(f"    Position  : ({px}, {py}, {pz})")
        print(f"    Taille    : {sx} x {sy} x {sz}")
        print(f"    Palette   : {len(palette_list)} types")

        if not palette_list or not block_states:
            print(f"    (vide)")
            continue

        # Construire la palette de noms Minecraft
        palette_names = []
        for entry in palette_list:
            if isinstance(entry, dict):
                block_name = entry.get("Name", "minecraft:air")
            else:
                block_name = str(entry)
            palette_names.append(block_name)

        volume = sx * sy * sz
        block_ids = unpack_litematic_blocks(block_states, len(palette_names), volume)

        if info_only:
            counts = {}
            for bid in block_ids:
                if 0 <= bid < len(palette_names):
                    bname = palette_names[bid]
                else:
                    bname = f"[invalid:{bid}]"
                counts[bname] = counts.get(bname, 0) + 1

            print(f"    Blocs :")
            for bname, count in sorted(counts.items(), key=lambda kv: -kv[1])[:30]:
                stripped = strip_block_states(bname)
                cc = smart_map_block(stripped)
                marker = "" if cc else "  <-- NON MAPPE"
                if not cc:
                    cc = "STONE"
                print(f"      {bname:50s} x{count:>7,} -> {cc}{marker}")
            continue

        # Mapper vers coordonnées globales
        for i, bid in enumerate(block_ids):
            if 0 <= bid < len(palette_names):
                mc_name = palette_names[bid]
            else:
                mc_name = "minecraft:air"

            stripped = strip_block_states(mc_name)
            cc_name = smart_map_block(stripped)
            if cc_name is None:
                cc_name = "STONE"
                unmapped_all[stripped] = unmapped_all.get(stripped, 0) + 1

            if cc_name == "AIR":
                continue

            # Ordre litematica : y * sx * sz + z * sx + x
            y = i // (sx * sz)
            remainder = i % (sx * sz)
            z = remainder // sx
            x = remainder % sx

            all_blocks.append((px + x, py + y, pz + z, cc_name))

    if info_only:
        return

    if not all_blocks:
        print("ERREUR : aucun bloc non-air trouvé dans le fichier.")
        return

    # Normaliser l'origine (le coin min des blocs occupés = 0,0,0)
    min_x = min(b[0] for b in all_blocks)
    min_y = min(b[1] for b in all_blocks)
    min_z = min(b[2] for b in all_blocks)
    max_x = max(b[0] for b in all_blocks)
    max_y = max(b[1] for b in all_blocks)
    max_z = max(b[2] for b in all_blocks)

    width = max_x - min_x + 1
    height = max_y - min_y + 1
    length = max_z - min_z + 1

    print(f"\nBounding box normalisée : {width} x {height} x {length}")
    print(f"Offset appliqué        : ({-min_x}, {-min_y}, {-min_z})")
    print(f"Blocs non-air          : {len(all_blocks):,}")

    # Construire palette et tableau 3D
    cc_palette_set = {"AIR"}
    for _, _, _, cc_name in all_blocks:
        cc_palette_set.add(cc_name)

    cc_palette = ["AIR"] + sorted(cc_palette_set - {"AIR"})
    cc_name_to_idx = {name: idx for idx, name in enumerate(cc_palette)}

    # Initialiser tout en AIR
    total = width * height * length
    blocks = [0] * total

    for wx, wy, wz, cc_name in all_blocks:
        x = wx - min_x
        y = wy - min_y
        z = wz - min_z
        idx = y * (width * length) + z * width + x
        blocks[idx] = cc_name_to_idx[cc_name]

    # Stats et RLE
    non_air = sum(1 for b in blocks if b != 0)
    air_pct = (1 - non_air / total) * 100 if total else 0
    rle = encode_rle(blocks)

    print(f"Blocs pleins: {non_air:,} ({100 - air_pct:.1f}%), air: {air_pct:.1f}%")
    print(f"RLE         : {len(rle)} valeurs ({len(rle) // 2} runs)")

    if unmapped_all:
        print(f"\n/!\\ {len(unmapped_all)} type(s) de blocs non mappé(s) -> STONE :")
        for name in sorted(unmapped_all.keys()):
            print(f"  {name}")

    # Générer le JSON
    structure_name = os.path.splitext(os.path.basename(litematic_path))[0]
    structure_name = structure_name.lower().replace(" ", "_").replace("-", "_")

    output = {
        "name": structure_name,
        "size": [width, height, length],
        "palette": cc_palette,
        "blocks_rle": rle
    }

    if output_path is None:
        output_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "structures")
        os.makedirs(output_dir, exist_ok=True)
        output_path = os.path.join(output_dir, structure_name + ".json")

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, separators=(',', ':'))

    file_size = os.path.getsize(output_path)
    print(f"\n-> Sauvegarde : {output_path}")
    print(f"   Taille     : {file_size:,} octets ({file_size / 1024:.1f} Ko)")


# ============================================================
# MAIN
# ============================================================

def main():
    if len(sys.argv) < 2:
        print("Usage : python convert_schem.py fichier.schem|.litematic [--output structure.json] [--info]")
        print()
        print("Formats supportés : .schem, .schematic, .litematic")
        print()
        print("Options :")
        print("  --output FILE  Chemin du fichier JSON de sortie")
        print("  --info         Afficher les dimensions et la palette sans convertir")
        print()
        print("Exemples :")
        print('  python convert_schem.py "assets/Lobbys/Natural Lobby.schem" --info')
        print('  python convert_schem.py "ma_tour.schem"')
        print('  python convert_schem.py "guard_outpost.litematic"')
        sys.exit(1)

    input_path = None
    output_path = None
    info_only = False

    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == "--output" and i + 1 < len(sys.argv):
            output_path = sys.argv[i + 1]
            i += 2
        elif arg == "--info":
            info_only = True
            i += 1
        else:
            input_path = arg
            i += 1

    if not input_path:
        print("ERREUR : aucun fichier spécifié")
        sys.exit(1)

    if not os.path.exists(input_path):
        print(f"ERREUR : fichier introuvable : {input_path}")
        sys.exit(1)

    ext = os.path.splitext(input_path)[1].lower()
    if ext == ".litematic":
        convert_litematic(input_path, output_path, info_only)
    elif ext in (".schem", ".schematic"):
        convert_schem(input_path, output_path, info_only)
    else:
        print(f"ERREUR : format non supporté : {ext}")
        print("Formats supportés : .schem, .schematic, .litematic")
        sys.exit(1)


if __name__ == "__main__":
    main()
