#!/usr/bin/env python3
"""
bedrock_to_glb.py v1.0.0
Convertisseur Minecraft Bedrock Edition → GLB pour ClaudeCraft

Extrait le modèle humanoid (geometry.humanoid.custom), le squelette
et les animations depuis les fichiers JSON de Bedrock Edition et génère
un fichier GLB (glTF 2.0 Binary) importable dans Godot 4.5+.

Le modèle utilise le système de texture-swap de Minecraft : un seul mesh,
une texture 64x64 PNG. Changer la texture = changer de personnage/armure.

Usage:
    python bedrock_to_glb.py
    python bedrock_to_glb.py --texture path/to/skin.png
    python bedrock_to_glb.py --output path/to/output.glb
    python bedrock_to_glb.py --no-overlay   (sans couches hat/sleeves/pants/jacket)

Changelog:
    v1.1.0 — Fix faces noires : 2 matériaux (opaque base + blend overlays),
             overlays rendus en dernier pour transparence correcte
    v1.0.0 — Création initiale : mesh, squelette, 4 animations bakées
"""

APP_VERSION = "1.1.0"

import json
import struct
import math
import os
import sys
import shutil
import argparse
from pathlib import Path

# ─── Configuration ────────────────────────────────────────────────────────────

BEDROCK_PATH = Path(r"D:\Games\Minecraft - Bedrock Edition\data\resource_packs\vanilla")
OUTPUT_DIR = Path(r"D:\Program\ClaudeCode\ClaudeCraft\assets\PlayerModel")
SCALE = 1.0 / 16.0   # 16 model units = 1 Godot unit (≈ 1 block)
TEX_SIZE = 64         # Skin texture 64×64 pixels

# Overlay bones (semi-transparent outer layer) — can be excluded
OVERLAY_BONES = {"hat", "leftSleeve", "rightSleeve", "leftPants", "rightPants", "jacket"}


# ─── Math Utilities ───────────────────────────────────────────────────────────

def euler_to_quat(x_deg, y_deg, z_deg):
    """Euler XYZ (degrees) → quaternion [x, y, z, w], ZYX intrinsic order."""
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


def mat4_inverse_translation(tx, ty, tz):
    """Inverse bind matrix for a translation-only transform (column-major)."""
    return [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        -tx, -ty, -tz, 1,
    ]


# ─── Model Parsing ───────────────────────────────────────────────────────────

def parse_geometry(include_overlays=True):
    """Parse geometry.humanoid.custom from Bedrock mobs.json.

    Returns list of bone dicts with: name, parent, pivot, cubes, never_render, mirror.
    """
    mobs_path = BEDROCK_PATH / "models" / "mobs.json"
    with open(mobs_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    parent_key = "geometry.humanoid"
    child_key = None
    for key in data:
        if key.startswith("geometry.humanoid.custom"):
            child_key = key
            break
    if not child_key:
        raise RuntimeError("geometry.humanoid.custom introuvable dans mobs.json")

    # Merge: child overrides parent bones by name
    parent_bones = {b["name"]: b for b in data[parent_key].get("bones", [])}
    child_bones = {b["name"]: b for b in data[child_key].get("bones", [])}
    merged = {**parent_bones, **child_bones}

    bones = []
    for name, b in merged.items():
        # Skip overlay bones if requested
        if not include_overlays and name in OVERLAY_BONES:
            continue

        bone = {
            "name": name,
            "parent": b.get("parent"),
            "pivot": b.get("pivot", [0, 0, 0]),
            "never_render": b.get("neverRender", False),
            "mirror": b.get("mirror", False),
            "cubes": [],
        }
        for cube in b.get("cubes", []):
            bone["cubes"].append({
                "origin": cube["origin"],
                "size": cube["size"],
                "uv": cube["uv"],
                "inflate": cube.get("inflate", 0.0),
                "mirror": bone["mirror"],
            })
        bones.append(bone)

    return bones


# ─── Mesh Generation ─────────────────────────────────────────────────────────

def generate_cube_faces(cube):
    """Generate vertex data for one cube (6 faces, 24 vertices, 36 indices).

    Returns: (positions, normals, uvs, indices) — all lists.
    """
    ox, oy, oz = cube["origin"]
    cw, ch, cd = cube["size"]       # width(X), height(Y), depth(Z)
    u0, v0 = cube["uv"]
    inflate = cube.get("inflate", 0.0)
    mirror = cube.get("mirror", False)

    # Inflate affects geometry, not UVs
    gx, gy, gz = ox - inflate, oy - inflate, oz - inflate
    gw, gh, gd = cw + inflate * 2, ch + inflate * 2, cd + inflate * 2

    # Scale to Godot units
    x0, y0, z0 = gx * SCALE, gy * SCALE, gz * SCALE
    x1, y1, z1 = (gx + gw) * SCALE, (gy + gh) * SCALE, (gz + gd) * SCALE

    def uv(px, py):
        return [px / TEX_SIZE, py / TEX_SIZE]

    positions = []
    normals_out = []
    uvs = []
    indices = []

    # Box UV layout (Bedrock standard):
    #   Top(+Y):   (u0+cd,      v0,    cw, cd)
    #   Bottom(-Y):(u0+cd+cw,   v0,    cw, cd)
    #   Right(-X): (u0,         v0+cd, cd, ch)   [Steve's right]
    #   Front(-Z): (u0+cd,      v0+cd, cw, ch)
    #   Left(+X):  (u0+cd+cw,   v0+cd, cd, ch)   [Steve's left]
    #   Back(+Z):  (u0+2*cd+cw, v0+cd, cw, ch)
    face_defs = [
        # name, 4 verts CCW from outside, normal, UV rect (u, v, w, h pixels)
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

    for _, verts, normal, uv_rect in face_defs:
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
        indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    return positions, normals_out, uvs, indices


# ─── Skeleton & Skinned Mesh ─────────────────────────────────────────────────

def build_skeleton_and_mesh(bones):
    """Build complete skinned mesh + skeleton from parsed bones.

    Returns dict with all data needed for GLB construction.
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
            # Orphan bones — add them as roots
            for b in remaining:
                added.add(b["name"])
            ordered.extend(remaining)
            break

    bone_map = {}   # name → index
    bone_names = []
    for i, bone in enumerate(ordered):
        bone_map[bone["name"]] = i
        bone_names.append(bone["name"])

    # World pivots and local translations
    world_pivots = {}
    local_translations = {}
    for bone in ordered:
        name = bone["name"]
        pivot = [p * SCALE for p in bone["pivot"]]
        world_pivots[name] = pivot

        parent = bone["parent"]
        if parent and parent in world_pivots:
            pp = world_pivots[parent]
            local_translations[name] = [pivot[0] - pp[0], pivot[1] - pp[1], pivot[2] - pp[2]]
        else:
            local_translations[name] = pivot[:]

    # Build mesh — split into base (opaque) and overlay (transparent) primitives
    all_pos = []
    all_nrm = []
    all_uv = []
    all_idx = []
    all_joints = []
    all_weights = []
    # Track which vertex ranges belong to overlays
    base_idx = []
    overlay_idx = []

    for bone in ordered:
        if bone["never_render"] or not bone["cubes"]:
            continue
        joint_idx = bone_map[bone["name"]]
        is_overlay = bone["name"] in OVERLAY_BONES
        for cube in bone["cubes"]:
            positions, normals_data, uvs_data, indices_data = generate_cube_faces(cube)
            offset = len(all_pos)
            all_pos.extend(positions)
            all_nrm.extend(normals_data)
            all_uv.extend(uvs_data)
            shifted = [i + offset for i in indices_data]
            all_idx.extend(shifted)
            if is_overlay:
                overlay_idx.extend(shifted)
            else:
                base_idx.extend(shifted)
            for _ in positions:
                all_joints.append([joint_idx, 0, 0, 0])
                all_weights.append([1.0, 0.0, 0.0, 0.0])

    # Inverse bind matrices
    ibms = []
    for bone in ordered:
        p = world_pivots[bone["name"]]
        ibms.append(mat4_inverse_translation(p[0], p[1], p[2]))

    return {
        "bones": ordered,
        "bone_map": bone_map,
        "bone_names": bone_names,
        "world_pivots": world_pivots,
        "local_translations": local_translations,
        "positions": all_pos,
        "normals": all_nrm,
        "uvs": all_uv,
        "indices": all_idx,
        "base_indices": base_idx,
        "overlay_indices": overlay_idx,
        "joints": all_joints,
        "weights": all_weights,
        "inverse_bind_matrices": ibms,
    }


# ─── Animation Baking ────────────────────────────────────────────────────────

def bake_animations(bone_names, bone_map, mesh_data=None):
    """Bake walk, idle, attack, mine animations to quaternion keyframes."""
    animations = []

    def make_anim(name, duration, fps, eval_fn):
        """eval_fn(bone_name, t, duration) → (rx, ry, rz) degrees, or
        {"rot": (rx,ry,rz), "pos": (tx,ty,tz)} for rotation+translation, or None"""
        n_frames = int(duration * fps) + 1
        timestamps = [i / fps for i in range(n_frames)]
        channels = {}       # bone → [quaternions]
        pos_channels = {}   # bone → [(tx,ty,tz)]
        for bname in bone_names:
            rots = []
            positions = []
            has_rot = False
            has_pos = False
            for t in timestamps:
                r = eval_fn(bname, t, duration)
                if r is not None:
                    if isinstance(r, dict):
                        # Dict with "rot" and/or "pos"
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
                        # Tuple/list = rotation only
                        has_rot = True
                        rots.append(euler_to_quat(r[0], r[1], r[2]))
                        positions.append(None)
                else:
                    rots.append(quat_identity())
                    positions.append(None)
            if has_rot:
                channels[bname] = rots
            if has_pos:
                # Fill None positions with the bone's local translation (rest pose)
                lt = mesh_data["local_translations"].get(bname, [0, 0, 0])
                for i in range(len(positions)):
                    if positions[i] is None:
                        positions[i] = list(lt)
                pos_channels[bname] = positions
        return {"name": name, "timestamps": timestamps,
                "channels": channels, "pos_channels": pos_channels}

    # Walk (1s loop, ±40° arms, ±56° legs)
    # Note: en glTF, +X rotation = membre vers l'arrière, -X = vers l'avant
    def walk_fn(bone, t, dur):
        a = math.cos(t / dur * 2 * math.pi) * 40
        m = {"leftArm": [-a, 0, 0], "rightArm": [a, 0, 0],
             "leftLeg": [a * 1.4, 0, 0], "rightLeg": [-a * 1.4, 0, 0]}
        return m.get(bone)
    animations.append(make_anim("walk", 1.0, 24, walk_fn))

    # Idle (3.5s loop, subtle arm bob ±2.9°, jambes explicitement à 0°)
    def idle_fn(bone, t, dur):
        bob = math.cos(math.radians(t * 103.2)) * 2.865 + 2.865
        if bone == "leftArm":
            return [0, 0, -bob]
        if bone == "rightArm":
            return [0, 0, bob]
        # Jambes forcées à 0° pour éviter de garder la pose walk
        if bone in ("leftLeg", "rightLeg"):
            return [0, 0, 0]
        return None
    animations.append(make_anim("idle", 3.5, 24, idle_fn))

    # Attack (0.4s, right arm swing vers l'avant)
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

    # Mine (0.6s loop, right arm pickaxe swing vers l'avant)
    def mine_fn(bone, t, dur):
        at = (t / dur) % 1.0
        if bone == "rightArm":
            return [math.sin(at * math.pi) * 80, 0, 0]
        return None
    animations.append(make_anim("mine", 0.6, 24, mine_fn))

    # Sit (pose statique : jambes à l'horizontale vers l'avant, bras posés)
    # root descend de 12 unités Bedrock (= 0.75 blocs) pour poser le cul au sol
    LEG_HEIGHT = 12.0 * SCALE  # 0.75 game units
    def sit_fn(bone, t, dur):
        if bone == "root":
            return {"pos": (0, -LEG_HEIGHT, 0)}  # descendre au sol
        if bone == "leftLeg":
            return [90, 0, 0]   # jambe gauche horizontale vers l'avant
        if bone == "rightLeg":
            return [90, 0, 0]   # jambe droite horizontale vers l'avant
        if bone == "leftArm":
            return [30, 0, 5]   # bras posé sur les genoux
        if bone == "rightArm":
            return [30, 0, -5]  # bras posé sur les genoux
        return None
    animations.append(make_anim("sit", 2.0, 4, sit_fn))

    # Sleep (pose statique : couché sur le dos)
    # Rotation sur root = tout le perso bascule (legs sont children de root)
    def sleep_fn(bone, t, dur):
        if bone == "root":
            return [90, 0, 0]   # tout le corps à l'horizontale (couché face vers le haut)
        if bone == "leftArm":
            return [0, 0, -5]   # bras légèrement écarté
        if bone == "rightArm":
            return [0, 0, 5]
        if bone == "head":
            return [-10, 0, 0]  # tête légèrement relevée (oreiller)
        return None
    animations.append(make_anim("sleep", 2.0, 4, sleep_fn))

    # Attack2 (0.5s, double swing — bras droit et corps, plus ample)
    def attack2_fn(bone, t, dur):
        at = min(t / dur, 1.0)
        if bone == "rightArm":
            # Swing ample : monte puis frappe
            if at < 0.3:
                swing = -(at / 0.3) * 40  # arm-back wind-up
            else:
                progress = (at - 0.3) / 0.7
                swing = -40 + progress * 140  # swing forward 100°
            return [swing, 0, 0]
        if bone == "body":
            # Rotation du corps avec le coup
            ry = math.sin(at * math.pi) * 18
            return [0, ry, 0]
        if bone == "leftArm":
            # Le bras gauche recule légèrement pour l'élan
            return [-math.sin(at * math.pi) * 15, 0, 0]
        return None
    animations.append(make_anim("attack2", 0.5, 24, attack2_fn))

    # Cheer (1s, bras en l'air, petite oscillation)
    def cheer_fn(bone, t, dur):
        at = (t / dur) % 1.0
        wave = math.sin(at * 4 * math.pi) * 8  # oscillation rapide
        if bone == "leftArm":
            return [-10, 0, -170 + wave]  # bras gauche en l'air
        if bone == "rightArm":
            return [-10, 0, 170 - wave]   # bras droit en l'air
        if bone == "head":
            return [-10 + math.sin(at * 2 * math.pi) * 5, 0, 0]  # tête levée
        return None
    animations.append(make_anim("cheer", 1.0, 24, cheer_fn))

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
        """Add buffer view, return index."""
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
        """Add accessor, return index."""
        acc = {"bufferView": bv, "componentType": comp_type, "count": count, "type": acc_type}
        if min_v is not None:
            acc["min"] = min_v
        if max_v is not None:
            acc["max"] = max_v
        idx = len(self.accessors)
        self.accessors.append(acc)
        return idx

    def _add_texture(self, png_path):
        """Embed PNG texture, return (base_mat_idx, overlay_mat_idx)."""
        with open(png_path, "rb") as f:
            img_data = f.read()
        bv = self._add_bv(img_data)
        img_idx = len(self.images)
        self.images.append({"bufferView": bv, "mimeType": "image/png"})
        samp_idx = len(self.samplers)
        self.samplers.append({"magFilter": 9728, "minFilter": 9728})  # NEAREST filtering
        tex_idx = len(self.textures_list)
        self.textures_list.append({"sampler": samp_idx, "source": img_idx})
        # Material 0: OPAQUE for base body parts (head, body, arms, legs)
        base_mat = len(self.materials)
        self.materials.append({
            "name": "base_opaque",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": tex_idx},
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
            "alphaMode": "OPAQUE",
            "doubleSided": False,
        })
        # Material 1: BLEND for overlay bones (hat, sleeves, pants, jacket)
        overlay_mat = len(self.materials)
        self.materials.append({
            "name": "overlay_blend",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": tex_idx},
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
            "alphaMode": "BLEND",
            "doubleSided": False,
        })
        return base_mat, overlay_mat

    def build(self, mesh_data, animations, texture_path=None):
        """Construct all glTF structures."""
        # ── Materials ──
        has_overlays = len(mesh_data.get("overlay_indices", [])) > 0
        if texture_path and os.path.exists(texture_path):
            base_mat, overlay_mat = self._add_texture(texture_path)
        else:
            self.materials.append({
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.8, 0.7, 0.6, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 1.0,
                },
            })
            base_mat = 0
            overlay_mat = 0

        # ── Vertex data ──
        positions = mesh_data["positions"]
        normals_data = mesh_data["normals"]
        uvs = mesh_data["uvs"]
        indices = mesh_data["indices"]
        joints = mesh_data["joints"]
        weights = mesh_data["weights"]

        # Positions
        pos_bytes = b"".join(struct.pack("<3f", *p) for p in positions)
        pos_min = [min(p[i] for p in positions) for i in range(3)]
        pos_max = [max(p[i] for p in positions) for i in range(3)]
        pos_bv = self._add_bv(pos_bytes, 34962)
        pos_acc = self._add_acc(pos_bv, 5126, len(positions), "VEC3", pos_min, pos_max)

        # Normals
        nrm_bytes = b"".join(struct.pack("<3f", *n) for n in normals_data)
        nrm_bv = self._add_bv(nrm_bytes, 34962)
        nrm_acc = self._add_acc(nrm_bv, 5126, len(normals_data), "VEC3")

        # UVs
        uv_bytes = b"".join(struct.pack("<2f", *u) for u in uvs)
        uv_bv = self._add_bv(uv_bytes, 34962)
        uv_acc = self._add_acc(uv_bv, 5126, len(uvs), "VEC2")

        # Joints (VEC4 UNSIGNED_BYTE)
        jnt_bytes = b"".join(struct.pack("<4B", *j) for j in joints)
        jnt_bv = self._add_bv(jnt_bytes, 34962)
        jnt_acc = self._add_acc(jnt_bv, 5121, len(joints), "VEC4")

        # Weights (VEC4 FLOAT)
        wgt_bytes = b"".join(struct.pack("<4f", *w) for w in weights)
        wgt_bv = self._add_bv(wgt_bytes, 34962)
        wgt_acc = self._add_acc(wgt_bv, 5126, len(weights), "VEC4")

        # Indices — two separate index buffers for base and overlay
        base_indices = mesh_data.get("base_indices", indices)
        overlay_indices = mesh_data.get("overlay_indices", [])

        use_u32 = len(positions) > 65535
        idx_ct = 5125 if use_u32 else 5123
        fmt = "<I" if use_u32 else "<H"

        # Base indices
        base_idx_bytes = b"".join(struct.pack(fmt, i) for i in base_indices)
        base_idx_bv = self._add_bv(base_idx_bytes, 34963)
        base_idx_acc = self._add_acc(base_idx_bv, idx_ct, len(base_indices), "SCALAR")

        # Build primitives list
        attrs = {
            "POSITION": pos_acc, "NORMAL": nrm_acc, "TEXCOORD_0": uv_acc,
            "JOINTS_0": jnt_acc, "WEIGHTS_0": wgt_acc,
        }
        primitives = [{
            "attributes": attrs,
            "indices": base_idx_acc,
            "material": base_mat,
        }]

        # Overlay primitive (if overlays exist)
        if overlay_indices and has_overlays:
            ov_idx_bytes = b"".join(struct.pack(fmt, i) for i in overlay_indices)
            ov_idx_bv = self._add_bv(ov_idx_bytes, 34963)
            ov_idx_acc = self._add_acc(ov_idx_bv, idx_ct, len(overlay_indices), "SCALAR")
            primitives.append({
                "attributes": attrs,
                "indices": ov_idx_acc,
                "material": overlay_mat,
            })

        # ── Mesh ──
        mesh_idx = len(self.meshes)
        self.meshes.append({"primitives": primitives})

        # ── Skeleton nodes ──
        bone_list = mesh_data["bones"]
        bone_map = mesh_data["bone_map"]
        local_trans = mesh_data["local_translations"]
        bone_node_start = len(self.nodes)

        for bone in bone_list:
            node = {"name": bone["name"]}
            lt = local_trans[bone["name"]]
            if any(abs(v) > 1e-6 for v in lt):
                node["translation"] = lt
            self.nodes.append(node)

        # Set children references
        for bone in bone_list:
            children = []
            for other in bone_list:
                if other["parent"] == bone["name"]:
                    children.append(bone_node_start + bone_map[other["name"]])
            if children:
                self.nodes[bone_node_start + bone_map[bone["name"]]]["children"] = children

        joint_indices = [bone_node_start + i for i in range(len(bone_list))]

        # ── Inverse bind matrices ──
        ibm_bytes = b"".join(struct.pack("<16f", *m) for m in mesh_data["inverse_bind_matrices"])
        ibm_bv = self._add_bv(ibm_bytes)
        ibm_acc = self._add_acc(ibm_bv, 5126, len(mesh_data["inverse_bind_matrices"]), "MAT4")

        # ── Skin ──
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

        # ── Mesh node ──
        mesh_node_idx = len(self.nodes)
        self.nodes.append({"name": "PlayerModel", "mesh": mesh_idx, "skin": skin_idx})

        self.scene_nodes = [root_idx, mesh_node_idx]

        # ── Animations ──
        for anim in animations:
            ga = {"name": anim["name"], "channels": [], "samplers": []}
            for bname, rotations in anim["channels"].items():
                if bname not in bone_map:
                    continue
                node_idx = bone_node_start + bone_map[bname]

                # Timestamps
                ts = anim["timestamps"]
                ts_bytes = struct.pack(f"<{len(ts)}f", *ts)
                ts_bv = self._add_bv(ts_bytes)
                ts_acc = self._add_acc(ts_bv, 5126, len(ts), "SCALAR", [min(ts)], [max(ts)])

                # Rotations
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
                pos_bytes = struct.pack(f"<{len(pos_flat)}f", *pos_flat)
                pos_bv = self._add_bv(pos_bytes)
                pos_acc = self._add_acc(pos_bv, 5126, len(positions), "VEC3")

                samp_idx = len(ga["samplers"])
                ga["samplers"].append({"input": ts_acc, "output": pos_acc, "interpolation": "LINEAR"})
                ga["channels"].append({"sampler": samp_idx, "target": {"node": node_idx, "path": "translation"}})

            if ga["samplers"]:
                self.animations_gltf.append(ga)

    def to_glb(self):
        """Serialize to GLB binary bytes."""
        gltf = {
            "asset": {"version": "2.0", "generator": f"bedrock_to_glb v{APP_VERSION}"},
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

def find_steve_texture():
    """Locate steve.png in Bedrock files."""
    candidates = [
        BEDROCK_PATH / "textures" / "entity" / "steve.png",
        BEDROCK_PATH.parent / "skin_packs" / "vanilla" / "steve.png",
        Path(r"D:\Games\Minecraft - Bedrock Edition\data\skin_packs\vanilla\steve.png"),
    ]
    for p in candidates:
        if p.exists():
            return str(p)
    return None


def main():
    parser = argparse.ArgumentParser(description="Convertisseur Minecraft Bedrock → GLB")
    parser.add_argument("--output", "-o", default=str(OUTPUT_DIR / "steve.glb"))
    parser.add_argument("--texture", "-t", help="Texture skin PNG 64×64")
    parser.add_argument("--no-animations", action="store_true")
    parser.add_argument("--no-overlay", action="store_true", help="Exclure hat/sleeves/pants/jacket")
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    print(f"bedrock_to_glb.py v{APP_VERSION}")
    print(f"Source : {BEDROCK_PATH}")
    print()

    # 1. Parse
    print("Parsing du modèle humanoid...")
    bones = parse_geometry(include_overlays=not args.no_overlay)
    renderable = [b for b in bones if not b["never_render"] and b["cubes"]]
    print(f"  {len(bones)} bones, {len(renderable)} avec géométrie")

    # 2. Mesh + skeleton
    print("Construction mesh + squelette...")
    mesh_data = build_skeleton_and_mesh(bones)
    n_v = len(mesh_data["positions"])
    n_t = len(mesh_data["indices"]) // 3
    print(f"  {n_v} vertices, {n_t} triangles")

    # 3. Animations
    anims = []
    if not args.no_animations:
        print("Baking animations...")
        anims = bake_animations(mesh_data["bone_names"], mesh_data["bone_map"], mesh_data)
        for a in anims:
            print(f"  {a['name']}: {len(a['channels'])} channels, {len(a['timestamps'])} frames")

    # 4. Texture
    tex = args.texture or find_steve_texture()
    if tex:
        print(f"Texture : {tex}")
    else:
        print("Texture : aucune (matériau par défaut)")

    # 5. Build GLB
    print("Construction GLB...")
    writer = GLBWriter()
    writer.build(mesh_data, anims, tex)
    glb = writer.to_glb()

    # 6. Write
    with open(output, "wb") as f:
        f.write(glb)
    kb = len(glb) / 1024
    print(f"\n{'='*50}")
    print(f"GLB écrit : {output} ({kb:.1f} KB)")
    print(f"  Bones     : {len(bones)}")
    print(f"  Vertices  : {n_v}")
    print(f"  Triangles : {n_t}")
    print(f"  Animations: {len(anims)}")

    # Copy skin textures for easy swapping
    if tex and Path(tex).exists():
        dest = output.parent / "steve_skin.png"
        if not dest.exists():
            shutil.copy2(tex, dest)
            print(f"  Skin copiée : {dest}")

    # Also copy other skins if available
    skins_dir = BEDROCK_PATH.parent.parent / "skin_packs" / "vanilla"
    if skins_dir.exists():
        skins_out = output.parent / "skins"
        skins_out.mkdir(exist_ok=True)
        count = 0
        for png in skins_dir.glob("*.png"):
            dest = skins_out / png.name
            if not dest.exists():
                shutil.copy2(png, dest)
                count += 1
        if count:
            print(f"  {count} skins copiées dans {skins_out}")

    print("\nDone!")


if __name__ == "__main__":
    main()
