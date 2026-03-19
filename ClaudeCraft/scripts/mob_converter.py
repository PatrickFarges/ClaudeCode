#!/usr/bin/env python3
"""
mob_converter.py v1.0.0
Convertisseur universel Minecraft Bedrock Edition Mobs -> GLB pour ClaudeCraft

Parse les fichiers .geo.json (modèles) et .animation.json (animations Molang)
de Bedrock Edition pour générer des fichiers GLB skinned + animés importables
dans Godot 4.6+.

Supporte les quadrupèdes (vache, cochon, mouton...), humanoïdes (zombie,
skeleton...), araignées (8 pattes), et tout mob Bedrock.

Usage:
    python mob_converter.py cow
    python mob_converter.py --list
    python mob_converter.py zombie --output path/to/output.glb

Changelog:
    v2.3.0 — Fix enderman tête trop basse (CUBE_OFFSET_OVERRIDES +14Y pour head,
             tête passe de y=24 à y=38 au sommet du corps)
    v2.2.0 — Fix wolf rotation (body/upperBody bind_pose_rotation 90°X manquant),
             fix sheep tex_size (64×64 au lieu de 64×32),
             fix TGA alpha binarisation (alpha>0 → 255, corrige faces invisibles
             sheep/enderman), BPR_OVERRIDES pour bones manquant de rotation
    v2.1.0 — Fix hiérarchie bones (wolf/chicken/bat/sheep sans parents dans Bedrock),
             normalisation Y (pieds à Y=0 pour tous les mobs),
             PARENT_OVERRIDES pour inférer la hiérarchie manquante
    v2.0.0 — 15 mobs (ajout zombie, skeleton, polar_bear, rabbit, fox, cat, bat,
             enderman), support TGA (via Pillow), fix geo keys v1.8/v1.0,
             catégories passive/neutral/hostile, animations humanoid
    v1.3.0 — Fix bottom face winding (indices inversés pour normale -Y correcte),
             corrige les faces noires sur les mobs avec bind_pose_rotation
    v1.0.0 — Création : parsing .geo.json, bind_pose_rotation, Molang -> keyframes
"""

APP_VERSION = "2.3.0"

import json
import struct
import math
import os
import sys
import shutil
import argparse
from pathlib import Path

try:
    from PIL import Image
    import io
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# ─── Configuration ────────────────────────────────────────────────────────────

BEDROCK_PATH = Path(r"D:\Games\Minecraft - Bedrock Edition\data\resource_packs\vanilla")
OUTPUT_DIR = Path(r"D:\Program\ClaudeCode\ClaudeCraft\assets\Mobs\Bedrock")
SCALE = 1.0 / 16.0   # 16 Bedrock units = 1 Godot unit (≈ 1 block)

# ─── Mob Registry ─────────────────────────────────────────────────────────────
# Maps mob name -> { geo, texture, animations, tex_size }

# Categories for in-game behavior
MOB_CATEGORY = {
    # Passive — flee when attacked
    "cow": "passive", "pig": "passive", "sheep": "passive",
    "chicken": "passive", "rabbit": "passive", "bat": "passive",
    "fox": "passive", "cat": "passive",
    # Neutral — attack only when provoked
    "wolf": "neutral", "polar_bear": "neutral", "enderman": "neutral",
    # Hostile — attack on sight (night only unless specified)
    "zombie": "hostile", "skeleton": "hostile", "creeper": "hostile",
    "spider": "hostile",
}

# Day spawning for specific mobs (overrides night-only default for hostiles)
MOB_DAY_SPAWN = {"polar_bear", "enderman"}

# Biome restrictions
MOB_BIOMES = {
    "polar_bear": ["mountain"],  # Cold/snowy biomes
    "fox": ["forest"],
    "rabbit": ["desert", "plains"],
    "bat": ["all"],  # Spawns underground
    "cat": ["plains", "forest"],
    "enderman": ["all"],
}

MOB_REGISTRY = {
    # ── Passive mobs ──
    "cow": {
        "geo": "models/entity/cow.geo.json",
        "geo_key": "geometry.cow",
        "texture": "textures/entity/cow/cow.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle", "eat"],
    },
    "pig": {
        "geo": "models/entity/pig.geo.json",
        "geo_key": "geometry.pig",
        "texture": "textures/entity/pig/pig.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    "sheep": {
        "geo": "models/entity/sheep.geo.json",
        "geo_key": "geometry.sheep.sheared",
        "texture": "textures/entity/sheep/sheep.tga",
        "tex_size": (64, 64),
        "custom_anims": ["walk", "idle", "eat"],
    },
    "chicken": {
        "geo": "models/entity/chicken.geo.json",
        "geo_key": "geometry.chicken",
        "texture": "textures/entity/chicken.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    "rabbit": {
        "geo": "models/entity/rabbit.geo.json",
        "geo_key": "geometry.rabbit",
        "texture": "textures/entity/rabbit/brown.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    "fox": {
        "geo": "models/entity/fox.geo.json",
        "geo_key": "geometry.fox",
        "texture": "textures/entity/fox/fox.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    "cat": {
        "geo": "models/entity/cat.geo.json",
        "geo_key": "geometry.cat",
        "texture": "textures/entity/cat/tabby.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    "bat": {
        "geo": "models/entity/bat.geo.json",
        "geo_key": "geometry.bat",
        "texture": "textures/entity/bat.png",
        "tex_size": (64, 64),
        "custom_anims": ["walk", "idle"],
    },
    # ── Neutral mobs ──
    "wolf": {
        "geo": "models/entity/wolf.geo.json",
        "geo_key": "geometry.wolf",
        "texture": "textures/entity/wolf/wolf.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    "polar_bear": {
        "geo": "models/entity/polar_bear.geo.json",
        "geo_key": "geometry.polarbear",
        "texture": "textures/entity/polarbear.png",
        "tex_size": (128, 64),
        "custom_anims": ["walk", "idle"],
    },
    "enderman": {
        "geo": "models/entity/enderman.geo.json",
        "geo_key": "geometry.enderman",
        "texture": "textures/entity/enderman/enderman.tga",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    # ── Hostile mobs ──
    "zombie": {
        "geo": "models/entity/zombie.geo.json",
        "geo_key": "geometry.zombie",
        "texture": "textures/entity/zombie/zombie.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle", "attack"],
    },
    "skeleton": {
        "geo": "models/entity/skeleton.geo.json",
        "geo_key": "geometry.skeleton",
        "texture": "textures/entity/skeleton/skeleton.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle", "attack"],
    },
    "creeper": {
        "geo": "models/entity/creeper.geo.json",
        "geo_key": "geometry.creeper",
        "texture": "textures/entity/creeper/creeper.png",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
    "spider": {
        "geo": "models/entity/spider.geo.json",
        "geo_key": "geometry.spider",
        "texture": "textures/entity/spider/spider.tga",
        "tex_size": (64, 32),
        "custom_anims": ["walk", "idle"],
    },
}

# ─── Parent Overrides ────────────────────────────────────────────────────────
# Bedrock geometry for some mobs has NO parent hierarchy (all bones are roots).
# We infer the correct hierarchy based on Minecraft anatomy.
PARENT_OVERRIDES = {
    "wolf": {
        "head": "body", "upperBody": "body",
        "leg0": "body", "leg1": "body", "leg2": "body", "leg3": "body",
        "tail": "body",
    },
    "chicken": {
        "head": "body",
        "leg0": "body", "leg1": "body",
        "wing0": "body", "wing1": "body",
    },
    "sheep": {
        "head": "body",
    },
    "bat": {
        "head": "body",
    },
}

# ─── Bind Pose Rotation Overrides ────────────────────────────────────────────
# Some Bedrock mobs are missing bind_pose_rotation in the geo file — the game
# applies these rotations in code at runtime.  We inject them here.
BPR_OVERRIDES = {
    "wolf": {
        "body": [90.0, 0.0, 0.0],
        "upperBody": [90.0, 0.0, 0.0],
    },
}

# ─── Cube Position Overrides ─────────────────────────────────────────────────
# Some Bedrock mobs have bones whose cube positions don't match the visual rest
# pose (the game repositions them via skeleton at runtime).
# We shift pivot + cube origins by the given offset [x, y, z] in Bedrock units.
CUBE_OFFSET_OVERRIDES = {
    "enderman": {
        # Head at y=24 overlaps body (y=26-38) — move to y=38 (top of body)
        "head": [0, 14, 0],
    },
}


# ─── Math Utilities ───────────────────────────────────────────────────────────

def euler_to_quat(x_deg, y_deg, z_deg):
    """Euler XYZ (degrees) -> quaternion [x, y, z, w], ZYX intrinsic order."""
    x = math.radians(x_deg)
    y = math.radians(y_deg)
    z = math.radians(z_deg)
    cx, sx = math.cos(x / 2), math.sin(x / 2)
    cy, sy = math.cos(y / 2), math.sin(y / 2)
    cz, sz = math.cos(z / 2), math.sin(z / 2)
    return [
        sx * cy * cz - cx * sy * sz,
        cx * sy * cz + sx * cy * sz,
        cx * cy * sz - sx * sy * cz,
        cx * cy * cz + sx * sy * sz,
    ]


def quat_identity():
    return [0.0, 0.0, 0.0, 1.0]


def quat_multiply(q1, q2):
    """Multiply two quaternions q1 * q2."""
    x1, y1, z1, w1 = q1
    x2, y2, z2, w2 = q2
    return [
        w1*x2 + x1*w2 + y1*z2 - z1*y2,
        w1*y2 - x1*z2 + y1*w2 + z1*x2,
        w1*z2 + x1*y2 - y1*x2 + z1*w2,
        w1*w2 - x1*x2 - y1*y2 - z1*z2,
    ]


def quat_conjugate(q):
    """Conjugate (inverse for unit quaternions)."""
    return [-q[0], -q[1], -q[2], q[3]]


def rotate_vec_by_quat(q, v):
    """Rotate vector v by quaternion q."""
    qv = [v[0], v[1], v[2], 0.0]
    qc = quat_conjugate(q)
    result = quat_multiply(quat_multiply(q, qv), qc)
    return [result[0], result[1], result[2]]


def mat4_from_rot_trans(q, t):
    """Build 4x4 column-major matrix from quaternion rotation + translation."""
    x, y, z, w = q
    m = [0.0] * 16
    m[0] = 1 - 2*(y*y + z*z)
    m[1] = 2*(x*y + z*w)
    m[2] = 2*(x*z - y*w)
    m[4] = 2*(x*y - z*w)
    m[5] = 1 - 2*(x*x + z*z)
    m[6] = 2*(y*z + x*w)
    m[8] = 2*(x*z + y*w)
    m[9] = 2*(y*z - x*w)
    m[10] = 1 - 2*(x*x + y*y)
    m[12] = t[0]
    m[13] = t[1]
    m[14] = t[2]
    m[15] = 1.0
    return m


def mat4_inverse_rigid(m):
    """Inverse of a rigid-body transform (rotation + translation), column-major."""
    # R^T
    inv = [0.0] * 16
    inv[0] = m[0]; inv[1] = m[4]; inv[2] = m[8]
    inv[4] = m[1]; inv[5] = m[5]; inv[6] = m[9]
    inv[8] = m[2]; inv[9] = m[6]; inv[10] = m[10]
    # -R^T * t
    tx, ty, tz = m[12], m[13], m[14]
    inv[12] = -(inv[0]*tx + inv[4]*ty + inv[8]*tz)
    inv[13] = -(inv[1]*tx + inv[5]*ty + inv[9]*tz)
    inv[14] = -(inv[2]*tx + inv[6]*ty + inv[10]*tz)
    inv[15] = 1.0
    return inv


# ─── Model Parsing ───────────────────────────────────────────────────────────

def parse_geo_json(mob_info, mob_name=None):
    """Parse a .geo.json or mobs.json file for a specific geometry key.

    Returns list of bone dicts with: name, parent, pivot, cubes, bind_pose_rotation, mirror.
    If mob_name is given, applies PARENT_OVERRIDES for mobs with missing hierarchy.
    """
    geo_path = BEDROCK_PATH / mob_info["geo"]
    with open(geo_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    geo_key = mob_info["geo_key"]
    tex_w, tex_h = mob_info["tex_size"]

    # Find the geometry data — try exact match, then prefix match
    geo_data = None
    for key in data:
        if key == geo_key or key.startswith(geo_key + ".") or key.startswith(geo_key + ":"):
            geo_data = data[key]
            break

    if geo_data is None:
        # Try under format_version 1.12+ structure
        if "minecraft:geometry" in data:
            for geo in data["minecraft:geometry"]:
                desc = geo.get("description", {})
                if desc.get("identifier", "").startswith(geo_key):
                    geo_data = geo
                    break

    if geo_data is None:
        raise RuntimeError(f"Geometry '{geo_key}' introuvable dans {geo_path}")

    # Handle parent geometry (inheritance)
    parent_key = None
    if ":" in geo_key:
        parent_key = geo_key.split(":")[0]

    # Check for inheritance in mobs.json
    parent_bones_map = {}
    if mob_info["geo"].endswith("mobs.json"):
        # Look for parent geometries
        for key in data:
            if key != geo_key and not key.startswith(geo_key):
                # Check if our geo inherits from this
                pass
        # For zombie/skeleton: they inherit from geometry.humanoid
        if "geometry.humanoid" in data and geo_key != "geometry.humanoid":
            for b in data["geometry.humanoid"].get("bones", []):
                parent_bones_map[b["name"]] = b

    # Get texture dimensions from geometry or override
    tex_w = geo_data.get("texturewidth", tex_w)
    tex_h = geo_data.get("textureheight", tex_h)

    raw_bones = geo_data.get("bones", [])

    # Merge with parent bones (child overrides)
    merged = {**parent_bones_map}
    for b in raw_bones:
        merged[b["name"]] = b

    bones = []
    for name, b in merged.items():
        bone = {
            "name": name,
            "parent": b.get("parent"),
            "pivot": b.get("pivot", [0, 0, 0]),
            "bind_pose_rotation": b.get("bind_pose_rotation", [0, 0, 0]),
            "never_render": b.get("neverRender", False),
            "mirror": b.get("mirror", False),
            "cubes": [],
        }
        for cube in b.get("cubes", []):
            uv = cube.get("uv")
            # Skip cubes without UV (some have "uv" as dict for per-face UV)
            if uv is None or isinstance(uv, dict):
                continue
            bone["cubes"].append({
                "origin": cube["origin"],
                "size": cube["size"],
                "uv": uv,
                "inflate": cube.get("inflate", 0.0),
                "mirror": cube.get("mirror", bone["mirror"]),
            })
        bones.append(bone)

    # Apply parent overrides for mobs with missing hierarchy
    if mob_name and mob_name in PARENT_OVERRIDES:
        overrides = PARENT_OVERRIDES[mob_name]
        bone_names_set = {b["name"] for b in bones}
        for bone in bones:
            if bone["parent"] is None and bone["name"] in overrides:
                target = overrides[bone["name"]]
                if target in bone_names_set:
                    bone["parent"] = target

    # Apply bind_pose_rotation overrides for mobs missing rotation in Bedrock data
    if mob_name and mob_name in BPR_OVERRIDES:
        bpr_overrides = BPR_OVERRIDES[mob_name]
        for bone in bones:
            if bone["name"] in bpr_overrides:
                existing = bone.get("bind_pose_rotation", [0, 0, 0])
                if not any(abs(v) > 0.01 for v in existing):
                    bone["bind_pose_rotation"] = bpr_overrides[bone["name"]]

    # Apply cube position overrides (shift pivot + cube origins)
    if mob_name and mob_name in CUBE_OFFSET_OVERRIDES:
        offsets = CUBE_OFFSET_OVERRIDES[mob_name]
        for bone in bones:
            if bone["name"] in offsets:
                dx, dy, dz = offsets[bone["name"]]
                bone["pivot"][0] += dx
                bone["pivot"][1] += dy
                bone["pivot"][2] += dz
                for cube in bone["cubes"]:
                    cube["origin"][0] += dx
                    cube["origin"][1] += dy
                    cube["origin"][2] += dz

    return bones, tex_w, tex_h


# ─── Mesh Generation ─────────────────────────────────────────────────────────

def generate_cube_faces(cube, tex_w, tex_h):
    """Generate vertex data for one cube (6 faces, 24 vertices, 36 indices).

    Uses Bedrock box UV layout. tex_w/tex_h define texture dimensions.
    """
    ox, oy, oz = cube["origin"]
    cw, ch, cd = cube["size"]
    u0, v0 = cube["uv"]
    inflate = cube.get("inflate", 0.0)
    mirror = cube.get("mirror", False)

    gx, gy, gz = ox - inflate, oy - inflate, oz - inflate
    gw, gh, gd = cw + inflate * 2, ch + inflate * 2, cd + inflate * 2

    x0, y0, z0 = gx * SCALE, gy * SCALE, gz * SCALE
    x1, y1, z1 = (gx + gw) * SCALE, (gy + gh) * SCALE, (gz + gd) * SCALE

    def uv(px, py):
        return [px / tex_w, py / tex_h]

    positions = []
    normals_out = []
    uvs = []
    indices = []

    # Box UV layout (Bedrock standard)
    face_defs = [
        # (name, 4 verts, normal, UV rect)
        ("front",  [[x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [x1, y0, z0]],
         [0, 0, -1], [u0 + cd, v0 + cd, cw, ch]),
        ("back",   [[x1, y0, z1], [x1, y1, z1], [x0, y1, z1], [x0, y0, z1]],
         [0, 0, 1],  [u0 + 2 * cd + cw, v0 + cd, cw, ch]),
        ("right",  [[x0, y0, z1], [x0, y1, z1], [x0, y1, z0], [x0, y0, z0]],
         [-1, 0, 0], [u0, v0 + cd, cd, ch]),
        ("left",   [[x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [x1, y0, z1]],
         [1, 0, 0],  [u0 + cd + cw, v0 + cd, cd, ch]),
        ("top",    [[x0, y1, z0], [x0, y1, z1], [x1, y1, z1], [x1, y1, z0]],
         [0, 1, 0],  [u0 + cd, v0, cw, cd]),
        ("bottom", [[x0, y0, z1], [x1, y0, z1], [x1, y0, z0], [x0, y0, z0]],
         [0, -1, 0], [u0 + cd + cw, v0, cw, cd]),
    ]

    for face_name, verts, normal, uv_rect in face_defs:
        base = len(positions)
        for v in verts:
            positions.append(v)
            normals_out.append(normal)

        fu, fv, fw, fh = uv_rect
        if mirror:
            face_uvs = [
                uv(fu + fw, fv + fh), uv(fu + fw, fv),
                uv(fu, fv),           uv(fu, fv + fh),
            ]
        else:
            face_uvs = [
                uv(fu, fv + fh),       uv(fu, fv),
                uv(fu + fw, fv),       uv(fu + fw, fv + fh),
            ]
        uvs.extend(face_uvs)
        # Bottom face has reversed winding to match its -Y normal
        if face_name == "bottom":
            indices.extend([base, base + 2, base + 1, base, base + 3, base + 2])
        else:
            indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    return positions, normals_out, uvs, indices


# ─── Skeleton & Skinned Mesh ─────────────────────────────────────────────────

def build_skeleton_and_mesh(bones, tex_w, tex_h):
    """Build complete skinned mesh + skeleton from parsed bones.

    Handles bind_pose_rotation via proper world transforms and IBMs.
    """
    # Topological sort: parents before children
    ordered = []
    remaining = list(bones)
    added = set()

    while remaining:
        progress = False
        for bone in remaining[:]:
            parent = bone["parent"]
            if parent is None or parent in added:
                ordered.append(bone)
                added.add(bone["name"])
                remaining.remove(bone)
                progress = True
        if not progress:
            for b in remaining:
                added.add(b["name"])
            ordered.extend(remaining)
            break

    bone_map = {}
    bone_names = []
    for i, bone in enumerate(ordered):
        bone_map[bone["name"]] = i
        bone_names.append(bone["name"])

    # Simple approach: bake bind_pose_rotation directly into mesh vertices
    # for the bone that has it (body). Everything else stays in model space.
    # No node rotations, no animation composition, no hierarchy propagation.
    # Same as bedrock_to_glb.py (Steve) but with vertex pre-rotation for bpr bones.
    world_pivots = {}
    local_translations = {}
    local_rotations = {}

    for bone in ordered:
        name = bone["name"]
        pivot = [p * SCALE for p in bone["pivot"]]
        world_pivots[name] = pivot
        local_rotations[name] = quat_identity()  # no node rotation

        parent = bone["parent"]
        if parent and parent in world_pivots:
            pp = world_pivots[parent]
            local_translations[name] = [pivot[i] - pp[i] for i in range(3)]
        else:
            local_translations[name] = pivot[:]

    # Build mesh — only bones with bind_pose_rotation get their vertices rotated
    all_pos = []
    all_nrm = []
    all_uv = []
    all_idx = []
    all_joints = []
    all_weights = []

    for bone in ordered:
        if bone["never_render"] or not bone["cubes"]:
            continue
        joint_idx = bone_map[bone["name"]]
        bpr = bone.get("bind_pose_rotation", [0, 0, 0])
        has_bpr = any(abs(v) > 0.01 for v in bpr)

        for cube in bone["cubes"]:
            positions, normals_data, uvs_data, indices_data = generate_cube_faces(cube, tex_w, tex_h)
            offset = len(all_pos)

            if has_bpr:
                # Rotate this bone's own vertices around its pivot
                # Negate angles: Bedrock convention is opposite to standard math
                bpr_quat = euler_to_quat(-bpr[0], -bpr[1], -bpr[2])
                piv = world_pivots[bone["name"]]
                for pos, nrm in zip(positions, normals_data):
                    v_rel = [pos[i] - piv[i] for i in range(3)]
                    v_rot = rotate_vec_by_quat(bpr_quat, v_rel)
                    all_pos.append([v_rot[i] + piv[i] for i in range(3)])
                    all_nrm.append(rotate_vec_by_quat(bpr_quat, nrm))
            else:
                all_pos.extend(positions)
                all_nrm.extend(normals_data)

            all_uv.extend(uvs_data)
            all_idx.extend([i + offset for i in indices_data])
            for _ in positions:
                all_joints.append([joint_idx, 0, 0, 0])
                all_weights.append([1.0, 0.0, 0.0, 0.0])

    # IBM = pure inverse translation (same as bedrock_to_glb.py for Steve)
    ibms = []
    for bone in ordered:
        p = world_pivots[bone["name"]]
        ibm = [0.0] * 16
        ibm[0] = 1.0; ibm[5] = 1.0; ibm[10] = 1.0; ibm[15] = 1.0
        ibm[12] = -p[0]; ibm[13] = -p[1]; ibm[14] = -p[2]
        ibms.append(ibm)

    return {
        "bones": ordered,
        "bone_map": bone_map,
        "bone_names": bone_names,
        "world_pivots": world_pivots,
        "world_rotations": {},
        "local_translations": local_translations,
        "local_rotations": local_rotations,
        "positions": all_pos,
        "normals": all_nrm,
        "uvs": all_uv,
        "indices": all_idx,
        "joints": all_joints,
        "weights": all_weights,
        "inverse_bind_matrices": ibms,
    }


def normalize_ground_level(mesh_data):
    """Shift entire model so that min Y = 0 (feet touch ground).

    Adjusts positions, world_pivots, local_translations (root bones), and IBMs.
    Returns the Y offset applied (in Godot units).
    """
    positions = mesh_data["positions"]
    if not positions:
        return 0.0

    min_y = min(p[1] for p in positions)
    if abs(min_y) < 1e-4:
        return 0.0  # Already grounded

    # Shift all vertex positions
    for p in positions:
        p[1] -= min_y

    # Shift all world pivots
    for name in mesh_data["world_pivots"]:
        mesh_data["world_pivots"][name][1] -= min_y

    # Shift local translations for root bones (no parent)
    for bone in mesh_data["bones"]:
        if bone["parent"] is None:
            mesh_data["local_translations"][bone["name"]][1] -= min_y

    # Recompute IBMs (pure inverse translation of world pivots)
    ibms = mesh_data["inverse_bind_matrices"]
    for i, bone in enumerate(mesh_data["bones"]):
        p = mesh_data["world_pivots"][bone["name"]]
        ibms[i][12] = -p[0]
        ibms[i][13] = -p[1]
        ibms[i][14] = -p[2]

    return min_y


# ─── Animation Baking ────────────────────────────────────────────────────────

def bake_mob_animations(mob_name, mob_info, bone_names, bone_map, mesh_data):
    """Bake animations for a specific mob type."""
    animations = []
    custom_anims = mob_info.get("custom_anims", ["walk", "idle"])

    def make_anim(name, duration, fps, eval_fn):
        n_frames = int(duration * fps) + 1
        timestamps = [i / fps for i in range(n_frames)]
        channels = {}
        pos_channels = {}

        for bname in bone_names:
            rots = []
            positions = []
            has_rot = False
            has_pos = False

            for t in timestamps:
                r = eval_fn(bname, t, duration)
                if r is not None:
                    if isinstance(r, dict):
                        rot = r.get("rot")
                        pos = r.get("pos")
                        if rot:
                            has_rot = True
                            rots.append(euler_to_quat(rot[0], rot[1], rot[2]))
                        else:
                            rots.append(quat_identity())
                        if pos:
                            has_pos = True
                            positions.append(list(pos))
                        else:
                            positions.append(None)
                    else:
                        has_rot = True
                        rots.append(euler_to_quat(r[0], r[1], r[2]))
                        positions.append(None)
                else:
                    rots.append(quat_identity())
                    positions.append(None)

            if has_rot:
                channels[bname] = rots
            if has_pos:
                lt = mesh_data["local_translations"].get(bname, [0, 0, 0])
                for i in range(len(positions)):
                    if positions[i] is None:
                        positions[i] = list(lt)
                pos_channels[bname] = positions

        return {"name": name, "timestamps": timestamps,
                "channels": channels, "pos_channels": pos_channels}

    # ── Quadruped walk (cow, pig, sheep, wolf, polar_bear, fox) ──
    if "walk" in custom_anims:
        if mob_name in ("cow", "pig", "sheep", "wolf", "horse", "polar_bear", "fox"):
            def quad_walk(bone, t, dur):
                a = math.cos(t / dur * 2 * math.pi) * 40
                m = {
                    "leg0": [a, 0, 0], "leg1": [-a, 0, 0],
                    "leg2": [-a, 0, 0], "leg3": [a, 0, 0],
                }
                # Fox/wolf: also wag tail
                if mob_name in ("fox", "wolf"):
                    m["tail"] = [0, math.sin(t / dur * 4 * math.pi) * 20, 0]
                return m.get(bone)
            animations.append(make_anim("walk", 1.0, 24, quad_walk))

        elif mob_name == "cat":
            def cat_walk(bone, t, dur):
                a = math.cos(t / dur * 2 * math.pi) * 35
                m = {
                    "frontLegL": [a, 0, 0], "frontLegR": [-a, 0, 0],
                    "backLegL": [-a, 0, 0], "backLegR": [a, 0, 0],
                    "tail1": [0, math.sin(t / dur * 4 * math.pi) * 25, 0],
                    "tail2": [0, math.sin(t / dur * 4 * math.pi + 0.5) * 15, 0],
                }
                return m.get(bone)
            animations.append(make_anim("walk", 0.8, 24, cat_walk))

        elif mob_name == "rabbit":
            def rabbit_walk(bone, t, dur):
                phase = (t / dur) % 1.0
                # Hop motion — bunny jumps
                hop = abs(math.sin(phase * math.pi)) * 30
                m = {
                    "haunchLeft": [-hop, 0, 0], "haunchRight": [-hop, 0, 0],
                    "rearFootLeft": [hop * 0.5, 0, 0], "rearFootRight": [hop * 0.5, 0, 0],
                    "frontLegLeft": [hop * 0.8, 0, 0], "frontLegRight": [hop * 0.8, 0, 0],
                    "body": {"rot": [-hop * 0.2, 0, 0], "pos": [0, hop * 0.1 * SCALE, 0]},
                }
                r = m.get(bone)
                if isinstance(r, dict):
                    return r
                return r
            animations.append(make_anim("walk", 0.5, 24, rabbit_walk))

        elif mob_name == "chicken":
            def chicken_walk(bone, t, dur):
                a = math.cos(t / dur * 2 * math.pi) * 40
                m = {"leg0": [a, 0, 0], "leg1": [-a, 0, 0]}
                return m.get(bone)
            animations.append(make_anim("walk", 1.0, 24, chicken_walk))

        elif mob_name == "bat":
            def bat_walk(bone, t, dur):
                # Wings flapping
                flap = math.sin(t / dur * 4 * math.pi) * 40
                m = {
                    "rightWing": [0, 0, flap],
                    "rightWingTip": [0, 0, flap * 0.7],
                    "leftWing": [0, 0, -flap],
                    "leftWingTip": [0, 0, -flap * 0.7],
                    "body": [math.sin(t / dur * 2 * math.pi) * 5, 0, 0],
                }
                return m.get(bone)
            animations.append(make_anim("walk", 0.5, 24, bat_walk))

        elif mob_name == "creeper":
            def creeper_walk(bone, t, dur):
                a = math.cos(t / dur * 2 * math.pi) * 40
                m = {
                    "leg0": [a, 0, 0], "leg1": [-a, 0, 0],
                    "leg2": [-a, 0, 0], "leg3": [a, 0, 0],
                }
                return m.get(bone)
            animations.append(make_anim("walk", 1.0, 24, creeper_walk))

        elif mob_name in ("zombie", "skeleton", "enderman"):
            def humanoid_walk(bone, t, dur):
                a = math.cos(t / dur * 2 * math.pi) * 40
                m = {
                    "leftArm": [-a, 0, 0], "rightArm": [a, 0, 0],
                    "leftLeg": [a * 1.4, 0, 0], "rightLeg": [-a * 1.4, 0, 0],
                }
                return m.get(bone)
            animations.append(make_anim("walk", 1.0, 24, humanoid_walk))

        elif mob_name == "spider":
            def spider_walk(bone, t, dur):
                phase_offsets = {
                    "leg0": 0, "leg1": 0, "leg2": 90, "leg3": 90,
                    "leg4": 180, "leg5": 180, "leg6": 270, "leg7": 270,
                }
                if bone not in phase_offsets:
                    return None
                offset = phase_offsets[bone]
                at = t / dur * 2 * math.pi
                y_swing = abs(math.cos(at + math.radians(offset))) * 22.92
                z_swing = abs(math.sin(at / 2 + math.radians(offset))) * 22.92
                sign_y = -1 if bone in ("leg0", "leg2", "leg4", "leg6") else 1
                sign_z = 1 if bone in ("leg0", "leg2", "leg4", "leg6") else -1
                return [0, sign_y * y_swing, sign_z * z_swing]
            animations.append(make_anim("walk", 1.0, 24, spider_walk))

    # ── Idle ──
    if "idle" in custom_anims:
        def idle_fn(bone, t, dur):
            if bone == "head":
                bob = math.sin(t / dur * 2 * math.pi) * 3
                return [bob, 0, 0]
            if bone.startswith("leg") or bone.startswith("front") or bone.startswith("back") or bone.startswith("haunch") or bone.startswith("rear"):
                return [0, 0, 0]
            if bone in ("leftArm", "rightArm", "leftLeg", "rightLeg"):
                return [0, 0, 0]
            if bone in ("rightWing", "leftWing", "rightWingTip", "leftWingTip"):
                # Bat: gentle wing fold
                sign = 1 if "right" in bone else -1
                return [0, 0, sign * 5 + math.sin(t / dur * 2 * math.pi) * sign * 3]
            return None
        animations.append(make_anim("idle", 3.0, 12, idle_fn))

    # ── Eat/Graze (quadrupeds) ──
    if "eat" in custom_anims:
        def eat_fn(bone, t, dur):
            if bone == "head":
                # Head bows down to eat
                phase = t / dur
                if phase < 0.3:
                    angle = (phase / 0.3) * 35
                elif phase < 0.7:
                    angle = 35 + math.sin((phase - 0.3) / 0.4 * 4 * math.pi) * 5
                else:
                    angle = 35 * (1 - (phase - 0.7) / 0.3)
                return [angle, 0, 0]
            return None
        animations.append(make_anim("eat", 2.0, 12, eat_fn))

    # ── Attack (humanoids) ──
    if "attack" in custom_anims:
        def attack_fn(bone, t, dur):
            at = min(t / dur, 1.0)
            if bone == "rightArm":
                s = math.sin((1 - (1 - at) ** 4) * math.pi)
                swing = (s * 1.2 + math.sin(at * math.pi)) * 30
                return [swing, 0, 0]
            if bone == "body":
                ry = math.sin(math.sqrt(at) * 2 * math.pi) * 11.46
                return [0, ry, 0]
            return None
        animations.append(make_anim("attack", 0.4, 24, attack_fn))

    return animations


# ─── GLB Writer ───────────────────────────────────────────────────────────────

class GLBWriter:
    """Builds a complete glTF 2.0 GLB from mesh, skeleton, animations."""

    def __init__(self):
        self.buf = bytearray()
        self.buffer_views = []
        self.accessors = []
        self.nodes = []
        self.meshes = []
        self.skins = []
        self.animations_gltf = []
        self.materials = []
        self.images = []
        self.textures_list = []
        self.samplers = []
        self.scene_nodes = []

    def _align4(self):
        pad = (4 - len(self.buf) % 4) % 4
        self.buf.extend(b"\x00" * pad)

    def _add_bv(self, data, target=None):
        self._align4()
        offset = len(self.buf)
        self.buf.extend(data)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            bv["target"] = target
        idx = len(self.buffer_views)
        self.buffer_views.append(bv)
        return idx

    def _add_acc(self, bv, comp_type, count, acc_type, min_v=None, max_v=None):
        acc = {"bufferView": bv, "componentType": comp_type, "count": count, "type": acc_type}
        if min_v is not None:
            acc["min"] = min_v
        if max_v is not None:
            acc["max"] = max_v
        idx = len(self.accessors)
        self.accessors.append(acc)
        return idx

    def _add_texture(self, png_path):
        # Convert TGA to PNG in memory if needed
        # Also binarize alpha: Bedrock TGA textures use alpha=3 for "opaque" pixels
        # which would be invisible with alphaMode MASK at alphaCutoff 0.5.
        # Fix: alpha > 0 → 255, alpha == 0 stays 0 (matches Minecraft rendering).
        if png_path.lower().endswith(".tga"):
            if not HAS_PIL:
                print(f"  WARN: Pillow requis pour les textures TGA, pip install Pillow")
                return len(self.materials) - 1 if self.materials else 0
            img = Image.open(png_path).convert("RGBA")
            # Binarize alpha for TGA (Bedrock uses low alpha for opaque pixels)
            pixels = img.load()
            for y in range(img.height):
                for x in range(img.width):
                    r, g, b, a = pixels[x, y]
                    if a > 0 and a < 255:
                        pixels[x, y] = (r, g, b, 255)
            buf = io.BytesIO()
            img.save(buf, format="PNG")
            img_data = buf.getvalue()
        else:
            with open(png_path, "rb") as f:
                img_data = f.read()
        bv = self._add_bv(img_data)
        img_idx = len(self.images)
        self.images.append({"bufferView": bv, "mimeType": "image/png"})
        samp_idx = len(self.samplers)
        self.samplers.append({"magFilter": 9728, "minFilter": 9728})  # NEAREST
        tex_idx = len(self.textures_list)
        self.textures_list.append({"sampler": samp_idx, "source": img_idx})
        mat_idx = len(self.materials)
        self.materials.append({
            "name": "mob_material",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": tex_idx},
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
            "alphaMode": "MASK",
            "alphaCutoff": 0.5,
            "doubleSided": True,
        })
        return mat_idx

    def build(self, mesh_data, animations, texture_path=None):
        # Material
        if texture_path and os.path.exists(texture_path):
            mat_idx = self._add_texture(texture_path)
        else:
            self.materials.append({
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.8, 0.7, 0.6, 1.0],
                    "metallicFactor": 0.0, "roughnessFactor": 1.0,
                },
            })
            mat_idx = 0

        # Vertex data
        positions = mesh_data["positions"]
        normals_data = mesh_data["normals"]
        uvs = mesh_data["uvs"]
        indices = mesh_data["indices"]
        joints = mesh_data["joints"]
        weights = mesh_data["weights"]

        pos_bytes = b"".join(struct.pack("<3f", *p) for p in positions)
        pos_min = [min(p[i] for p in positions) for i in range(3)]
        pos_max = [max(p[i] for p in positions) for i in range(3)]
        pos_bv = self._add_bv(pos_bytes, 34962)
        pos_acc = self._add_acc(pos_bv, 5126, len(positions), "VEC3", pos_min, pos_max)

        nrm_bytes = b"".join(struct.pack("<3f", *n) for n in normals_data)
        nrm_bv = self._add_bv(nrm_bytes, 34962)
        nrm_acc = self._add_acc(nrm_bv, 5126, len(normals_data), "VEC3")

        uv_bytes = b"".join(struct.pack("<2f", *u) for u in uvs)
        uv_bv = self._add_bv(uv_bytes, 34962)
        uv_acc = self._add_acc(uv_bv, 5126, len(uvs), "VEC2")

        jnt_bytes = b"".join(struct.pack("<4B", *j) for j in joints)
        jnt_bv = self._add_bv(jnt_bytes, 34962)
        jnt_acc = self._add_acc(jnt_bv, 5121, len(joints), "VEC4")

        wgt_bytes = b"".join(struct.pack("<4f", *w) for w in weights)
        wgt_bv = self._add_bv(wgt_bytes, 34962)
        wgt_acc = self._add_acc(wgt_bv, 5126, len(weights), "VEC4")

        use_u32 = len(positions) > 65535
        idx_ct = 5125 if use_u32 else 5123
        fmt = "<I" if use_u32 else "<H"
        idx_bytes = b"".join(struct.pack(fmt, i) for i in indices)
        idx_bv = self._add_bv(idx_bytes, 34963)
        idx_acc = self._add_acc(idx_bv, idx_ct, len(indices), "SCALAR")

        attrs = {
            "POSITION": pos_acc, "NORMAL": nrm_acc, "TEXCOORD_0": uv_acc,
            "JOINTS_0": jnt_acc, "WEIGHTS_0": wgt_acc,
        }
        mesh_idx = len(self.meshes)
        self.meshes.append({"primitives": [{"attributes": attrs, "indices": idx_acc, "material": mat_idx}]})

        # Skeleton nodes
        bone_list = mesh_data["bones"]
        bone_map = mesh_data["bone_map"]
        local_trans = mesh_data["local_translations"]
        local_rots = mesh_data["local_rotations"]
        bone_node_start = len(self.nodes)

        for bone in bone_list:
            node = {"name": bone["name"]}
            lt = local_trans[bone["name"]]
            if any(abs(v) > 1e-6 for v in lt):
                node["translation"] = lt
            lr = local_rots[bone["name"]]
            # Set rest rotation if non-identity
            if abs(lr[0]) > 1e-6 or abs(lr[1]) > 1e-6 or abs(lr[2]) > 1e-6 or abs(lr[3] - 1.0) > 1e-6:
                node["rotation"] = lr
            self.nodes.append(node)

        # Children references
        for bone in bone_list:
            children = []
            for other in bone_list:
                if other["parent"] == bone["name"]:
                    children.append(bone_node_start + bone_map[other["name"]])
            if children:
                self.nodes[bone_node_start + bone_map[bone["name"]]]["children"] = children

        joint_indices = [bone_node_start + i for i in range(len(bone_list))]

        # Inverse bind matrices
        ibm_bytes = b"".join(struct.pack("<16f", *m) for m in mesh_data["inverse_bind_matrices"])
        ibm_bv = self._add_bv(ibm_bytes)
        ibm_acc = self._add_acc(ibm_bv, 5126, len(mesh_data["inverse_bind_matrices"]), "MAT4")

        # Skin
        root_idx = None
        for bone in bone_list:
            if bone["parent"] is None:
                root_idx = bone_node_start + bone_map[bone["name"]]
                break
        if root_idx is None:
            root_idx = bone_node_start

        skin_idx = len(self.skins)
        self.skins.append({
            "joints": joint_indices,
            "inverseBindMatrices": ibm_acc,
            "skeleton": root_idx,
        })

        # Mesh node
        mesh_node_idx = len(self.nodes)
        self.nodes.append({"name": "MobModel", "mesh": mesh_idx, "skin": skin_idx})
        self.scene_nodes = [root_idx, mesh_node_idx]

        # Animations
        for anim in animations:
            ga = {"name": anim["name"], "channels": [], "samplers": []}
            for bname, rotations in anim["channels"].items():
                if bname not in bone_map:
                    continue
                node_idx = bone_node_start + bone_map[bname]

                ts = anim["timestamps"]
                ts_bytes = struct.pack(f"<{len(ts)}f", *ts)
                ts_bv = self._add_bv(ts_bytes)
                ts_acc = self._add_acc(ts_bv, 5126, len(ts), "SCALAR", [min(ts)], [max(ts)])

                rot_flat = []
                for q in rotations:
                    rot_flat.extend(q)
                rot_bytes = struct.pack(f"<{len(rot_flat)}f", *rot_flat)
                rot_bv = self._add_bv(rot_bytes)
                rot_acc = self._add_acc(rot_bv, 5126, len(rotations), "VEC4")

                samp_idx = len(ga["samplers"])
                ga["samplers"].append({"input": ts_acc, "output": rot_acc, "interpolation": "LINEAR"})
                ga["channels"].append({"sampler": samp_idx, "target": {"node": node_idx, "path": "rotation"}})

            # Translation channels
            for bname, positions in anim.get("pos_channels", {}).items():
                if bname not in bone_map or not positions:
                    continue
                node_idx = bone_node_start + bone_map[bname]

                ts = anim["timestamps"]
                ts_bytes = struct.pack(f"<{len(ts)}f", *ts)
                ts_bv = self._add_bv(ts_bytes)
                ts_acc = self._add_acc(ts_bv, 5126, len(ts), "SCALAR", [min(ts)], [max(ts)])

                pos_flat = []
                for p in positions:
                    pos_flat.extend(p)
                pos_bytes_data = struct.pack(f"<{len(pos_flat)}f", *pos_flat)
                pos_bv = self._add_bv(pos_bytes_data)
                pos_acc_anim = self._add_acc(pos_bv, 5126, len(positions), "VEC3")

                samp_idx = len(ga["samplers"])
                ga["samplers"].append({"input": ts_acc, "output": pos_acc_anim, "interpolation": "LINEAR"})
                ga["channels"].append({"sampler": samp_idx, "target": {"node": node_idx, "path": "translation"}})

            if ga["samplers"]:
                self.animations_gltf.append(ga)

    def to_glb(self):
        gltf = {
            "asset": {"version": "2.0", "generator": f"mob_converter v{APP_VERSION}"},
            "scene": 0,
            "scenes": [{"nodes": self.scene_nodes}],
            "nodes": self.nodes,
            "meshes": self.meshes,
            "accessors": self.accessors,
            "bufferViews": self.buffer_views,
            "buffers": [{"byteLength": len(self.buf)}],
            "skins": self.skins,
        }
        if self.materials:
            gltf["materials"] = self.materials
        if self.images:
            gltf["images"] = self.images
        if self.textures_list:
            gltf["textures"] = self.textures_list
        if self.samplers:
            gltf["samplers"] = self.samplers
        if self.animations_gltf:
            gltf["animations"] = self.animations_gltf

        json_str = json.dumps(gltf, separators=(",", ":"))
        json_str += " " * ((4 - len(json_str) % 4) % 4)
        json_bytes = json_str.encode("utf-8")

        bin_data = bytes(self.buf)
        bin_data += b"\x00" * ((4 - len(bin_data) % 4) % 4)

        total = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
        glb = bytearray()
        glb.extend(struct.pack("<III", 0x46546C67, 2, total))
        glb.extend(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        glb.extend(json_bytes)
        glb.extend(struct.pack("<II", len(bin_data), 0x004E4942))
        glb.extend(bin_data)
        return bytes(glb)


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Convertisseur Minecraft Bedrock Mobs -> GLB")
    parser.add_argument("mob", nargs="?", help="Nom du mob (cow, pig, zombie...)")
    parser.add_argument("--output", "-o", help="Chemin de sortie GLB")
    parser.add_argument("--list", action="store_true", help="Lister les mobs disponibles")
    parser.add_argument("--all", action="store_true", help="Convertir tous les mobs")
    args = parser.parse_args()

    if args.list:
        print(f"mob_converter.py v{APP_VERSION}")
        print(f"Mobs disponibles ({len(MOB_REGISTRY)}) :")
        for name, info in sorted(MOB_REGISTRY.items()):
            anims = ", ".join(info.get("custom_anims", []))
            cat = MOB_CATEGORY.get(name, "?")
            print(f"  {name:12s} [{cat:8s}] — texture {info['tex_size'][0]}x{info['tex_size'][1]}, anims: {anims}")
        return

    mobs_to_convert = []
    if args.all:
        mobs_to_convert = list(MOB_REGISTRY.keys())
    elif args.mob:
        if args.mob not in MOB_REGISTRY:
            print(f"Mob inconnu : '{args.mob}'")
            print(f"Mobs disponibles : {', '.join(sorted(MOB_REGISTRY.keys()))}")
            return
        mobs_to_convert = [args.mob]
    else:
        parser.print_help()
        return

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for mob_name in mobs_to_convert:
        mob_info = MOB_REGISTRY[mob_name]
        output_path = Path(args.output) if args.output else OUTPUT_DIR / f"{mob_name}.glb"

        print(f"\n{'='*60}")
        print(f"  {mob_name.upper()}")
        print(f"{'='*60}")

        # 1. Parse geometry
        print(f"Parsing modèle {mob_info['geo']}...")
        try:
            bones, tex_w, tex_h = parse_geo_json(mob_info, mob_name)
        except Exception as e:
            print(f"  ERREUR: {e}")
            continue
        renderable = [b for b in bones if not b["never_render"] and b["cubes"]]
        print(f"  {len(bones)} bones, {len(renderable)} avec géométrie, texture {tex_w}x{tex_h}")
        for b in bones:
            bpr = b.get("bind_pose_rotation", [0,0,0])
            bpr_str = f" bind_pose_rot={bpr}" if any(abs(v) > 0.01 for v in bpr) else ""
            parent_str = f" -> {b['parent']}" if b['parent'] else " (root)"
            cubes_str = f" [{len(b['cubes'])} cubes]" if b['cubes'] else ""
            print(f"    {b['name']}{parent_str}{cubes_str}{bpr_str}")

        # 2. Build mesh + skeleton
        print("Construction mesh + squelette...")
        mesh_data = build_skeleton_and_mesh(bones, tex_w, tex_h)

        # 2b. Normalize Y so feet touch ground (Y=0)
        y_shift = normalize_ground_level(mesh_data)
        if abs(y_shift) > 1e-4:
            print(f"  Y normalisé : décalage {y_shift*16:.1f} MC units ({y_shift:.3f} Godot)")

        n_v = len(mesh_data["positions"])
        n_t = len(mesh_data["indices"]) // 3
        print(f"  {n_v} vertices, {n_t} triangles")

        # 3. Bake animations
        print("Baking animations...")
        anims = bake_mob_animations(mob_name, mob_info, mesh_data["bone_names"],
                                     mesh_data["bone_map"], mesh_data)
        for a in anims:
            print(f"  {a['name']}: {len(a['channels'])} rot channels, "
                  f"{len(a.get('pos_channels', {}))} pos channels, "
                  f"{len(a['timestamps'])} frames")

        # 4. Texture
        tex_path = BEDROCK_PATH / mob_info["texture"]
        if tex_path.exists():
            print(f"Texture : {tex_path}")
            # Copy texture alongside GLB (convert TGA to PNG if needed)
            tex_out_dir = output_path.parent / "textures"
            tex_out_dir.mkdir(parents=True, exist_ok=True)
            if str(tex_path).lower().endswith(".tga") and HAS_PIL:
                png_out = tex_out_dir / f"{mob_name}.png"
                img = Image.open(tex_path).convert("RGBA")
                # Binarize alpha (Bedrock TGA uses alpha=3 for opaque)
                pixels = img.load()
                for y in range(img.height):
                    for x in range(img.width):
                        r, g, b, a = pixels[x, y]
                        if a > 0 and a < 255:
                            pixels[x, y] = (r, g, b, 255)
                img.save(png_out)
                print(f"  Texture convertie TGA->PNG : {png_out}")
            else:
                png_out = tex_out_dir / f"{mob_name}.png"
                shutil.copy2(tex_path, png_out)
        else:
            print(f"Texture introuvable : {tex_path}")
            tex_path = None

        # 5. Build GLB
        print("Construction GLB...")
        writer = GLBWriter()
        writer.build(mesh_data, anims, str(tex_path) if tex_path else None)
        glb = writer.to_glb()

        # 6. Write
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(glb)
        size_kb = len(glb) / 1024
        print(f"Écrit : {output_path} ({size_kb:.1f} KB)")

    print(f"\nTerminé !")


if __name__ == "__main__":
    main()
