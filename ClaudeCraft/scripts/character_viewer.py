#!/usr/bin/env python3
"""
character_viewer.py v1.5.0
Visualiseur de personnage GLB avec squelette, animations, skin swap et armures

Charge un modele GLB (Bedrock -> GLB converti) et permet de :
- Visualiser le personnage 3D avec rotation camera
- Changer de skin (texture 64x64) en un clic
- Selectionner et jouer les animations
- Voir le squelette (bones)
- Superposer des pieces d'armure (casque, plastron, jambieres, bottes)
  avec 5 materiaux (cuir, chaine, fer, or, diamant)

Usage:
    python character_viewer.py
    python character_viewer.py path/to/model.glb

Changelog:
    v1.5.0 — Systeme d'armures : overlay 3D inflated cubes (helmet, chestplate,
             leggings, boots), 5 materiaux (leather/chain/iron/gold/diamond),
             textures Bedrock vanilla, rendu skinne synchronise avec animations
    v1.4.0 — Support mobs : doubleSided (desactive culling + two-sided lighting),
             texture embarquee prioritaire dans la liste skins, GL_FRONT_AND_BACK
    v1.2.0 — Scan recursif sous-dossiers skins, labels avec prefixe dossier
    v1.1.0 — Fix faces noires : rendu alpha blend pour overlays, depth sort
    v1.0.0 — Creation initiale
    v2.0.0 — Moteur d'animation Bedrock natif : Molang, animations JSON Bedrock,
             remplacement complet des animations baked GLB
"""

APP_VERSION = "2.0.0"

import sys
import json
import struct
import math
import os
from pathlib import Path

# Import du moteur d'animation Bedrock
from bedrock_anim_engine import BedrockAnimPlayer, euler_deg_to_quat

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QComboBox, QPushButton, QSlider, QLabel, QListWidget, QGroupBox,
    QCheckBox, QFileDialog, QSplitter, QListWidgetItem,
)
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QImage, QIcon, QPixmap
from PyQt6.QtOpenGLWidgets import QOpenGLWidget

from OpenGL.GL import *
from OpenGL.GLU import *

DEFAULT_GLB = Path(__file__).parent.parent / "assets" / "PlayerModel" / "steve.glb"
DEFAULT_SKINS = Path(__file__).parent.parent / "assets" / "PlayerModel" / "skins"
DEFAULT_SKIN = Path(__file__).parent.parent / "assets" / "PlayerModel" / "steve_skin.png"

ARMOR_TEXTURES_DIR = Path(r"D:\Games\Minecraft - Bedrock Edition\data\resource_packs\vanilla\textures\models\armor")

# Armor materials: (layer1_file, layer2_file)
ARMOR_MATERIALS = {
    "leather": ("cloth_1.png", "cloth_2.png"),
    "chain": ("chain_1.png", "chain_2.png"),
    "iron": ("iron_1.png", "iron_2.png"),
    "gold": ("gold_1.png", "gold_2.png"),
    "diamond": ("diamond_1.png", "diamond_2.png"),
}

# Armor piece definitions from player_armor.json
# layer: 1 = _1 texture (helmet+chest+boots), 2 = _2 texture (leggings)
# Each cube: (bone_name, origin, size, uv_offset, inflate, mirror)
# All coords in Bedrock pixels (1/16 of a block)
ARMOR_PIECES = {
    "helmet": {
        "layer": 1,
        "cubes": [
            ("head", [-4, 24, -4], [8, 8, 8], [0, 0], 1.0, False),
            ("hat", [-4, 24, -4], [8, 8, 8], [32, 0], 1.5, False),
        ],
    },
    "chestplate": {
        "layer": 1,
        "cubes": [
            ("body", [-4, 12, -2], [8, 12, 4], [16, 16], 1.01, False),
            ("rightArm", [-8, 12, -2], [4, 12, 4], [40, 16], 1.0, False),
            ("leftArm", [4, 12, -2], [4, 12, 4], [40, 16], 1.0, True),
        ],
    },
    "leggings": {
        "layer": 2,
        "cubes": [
            ("body", [-4, 12, -2], [8, 12, 4], [16, 16], 0.5, False),
            ("rightLeg", [-3.9, 0, -2], [4, 12, 4], [0, 16], 0.5, False),
            ("leftLeg", [-0.1, 0, -2], [4, 12, 4], [0, 16], 0.5, True),
        ],
    },
    "boots": {
        "layer": 1,
        "cubes": [
            ("rightLeg", [-3.9, 0, -2], [4, 12, 4], [0, 16], 1.0, False),
            ("leftLeg", [-0.1, 0, -2], [4, 12, 4], [0, 16], 1.0, True),
        ],
    },
}

BEDROCK_SCALE = 1.0 / 16.0
ARMOR_TEX_W = 64
ARMOR_TEX_H = 32


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Quaternion & Matrix Math
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def quat_identity():
    return [0.0, 0.0, 0.0, 1.0]


def quat_multiply(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ]


def quat_slerp(a, b, t):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b = [-x for x in b]
        dot = -dot
    if dot > 0.9995:
        r = [a[i] + t * (b[i] - a[i]) for i in range(4)]
        l = math.sqrt(sum(x * x for x in r))
        return [x / l for x in r] if l > 0 else quat_identity()
    theta0 = math.acos(min(dot, 1.0))
    theta = theta0 * t
    st, st0 = math.sin(theta), math.sin(theta0)
    s0 = math.cos(theta) - dot * st / st0
    s1 = st / st0
    return [s0 * a[i] + s1 * b[i] for i in range(4)]


def quat_to_mat4(q):
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return [
        1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0,
        2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0,
        2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0,
        0, 0, 0, 1,
    ]


def mat4_identity():
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def mat4_multiply(a, b):
    r = [0.0] * 16
    for row in range(4):
        for col in range(4):
            s = 0.0
            for k in range(4):
                s += a[k * 4 + row] * b[col * 4 + k]
            r[col * 4 + row] = s
    return r


def mat4_trs(t, q, s):
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return [
        s[0] * (1 - 2 * (yy + zz)), s[0] * 2 * (xy + wz), s[0] * 2 * (xz - wy), 0,
        s[1] * 2 * (xy - wz), s[1] * (1 - 2 * (xx + zz)), s[1] * 2 * (yz + wx), 0,
        s[2] * 2 * (xz + wy), s[2] * 2 * (yz - wx), s[2] * (1 - 2 * (xx + yy)), 0,
        t[0], t[1], t[2], 1,
    ]


def mat4_transform_point(m, p):
    x, y, z = p
    return [
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    ]


def mat4_transform_dir(m, n):
    x, y, z = n
    rx = m[0] * x + m[4] * y + m[8] * z
    ry = m[1] * x + m[5] * y + m[9] * z
    rz = m[2] * x + m[6] * y + m[10] * z
    l = math.sqrt(rx * rx + ry * ry + rz * rz)
    return [rx / l, ry / l, rz / l] if l > 1e-8 else [0, 1, 0]


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GLB Loader
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class GLBData:
    def __init__(self, path):
        self.path = Path(path)
        self.positions = []
        self.normals = []
        self.uvs = []
        self.indices = []
        self.joints = []
        self.weights = []
        self.bones = []
        self.bone_parent = {}
        self.ibms = []
        self.animations = {}
        self.embedded_texture = None
        self.double_sided = False
        self._parse()

    def _parse(self):
        with open(self.path, "rb") as f:
            magic, version, length = struct.unpack("<III", f.read(12))
            if magic != 0x46546C67:
                raise ValueError("Not a valid GLB file")
            json_len, _ = struct.unpack("<II", f.read(8))
            self.gltf = json.loads(f.read(json_len))
            bin_len, _ = struct.unpack("<II", f.read(8))
            self.bin = f.read(bin_len)
        self._extract_mesh()
        self._extract_skeleton()
        self._extract_animations()
        self._extract_texture()

    def _read_accessor(self, idx):
        acc = self.gltf["accessors"][idx]
        bv = self.gltf["bufferViews"][acc["bufferView"]]
        offset = bv.get("byteOffset", 0)
        data = self.bin[offset : offset + bv["byteLength"]]
        comp_fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
        type_n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
        fmt = comp_fmt[acc["componentType"]]
        n = type_n[acc["type"]]
        stride = struct.calcsize(f"<{n}{fmt}")
        result = []
        for i in range(acc["count"]):
            vals = struct.unpack_from(f"<{n}{fmt}", data, i * stride)
            result.append(vals[0] if n == 1 else list(vals))
        return result

    def _extract_mesh(self):
        primitives = self.gltf["meshes"][0]["primitives"]
        materials = self.gltf.get("materials", [])
        prim0 = primitives[0]
        attrs = prim0["attributes"]
        self.positions = self._read_accessor(attrs["POSITION"])
        self.normals = self._read_accessor(attrs["NORMAL"])
        self.uvs = self._read_accessor(attrs["TEXCOORD_0"])
        self.joints = self._read_accessor(attrs["JOINTS_0"])
        self.weights = self._read_accessor(attrs["WEIGHTS_0"])
        self.base_indices = []
        self.overlay_indices = []
        self.indices = []
        for prim in primitives:
            idx = self._read_accessor(prim["indices"])
            mat_idx = prim.get("material", 0)
            alpha_mode = "OPAQUE"
            if mat_idx < len(materials):
                alpha_mode = materials[mat_idx].get("alphaMode", "OPAQUE")
            if alpha_mode == "BLEND":
                self.overlay_indices.extend(idx)
            else:
                self.base_indices.extend(idx)
            self.indices.extend(idx)

    def _extract_skeleton(self):
        skin = self.gltf["skins"][0]
        joint_nodes = skin["joints"]
        self.ibms = self._read_accessor(skin["inverseBindMatrices"])
        node_to_bone = {}
        self.bones = []
        for bi, ni in enumerate(joint_nodes):
            node = self.gltf["nodes"][ni]
            self.bones.append({
                "name": node.get("name", f"bone_{bi}"),
                "translation": list(node.get("translation", [0, 0, 0])),
                "rotation": list(node.get("rotation", [0, 0, 0, 1])),
                "scale": list(node.get("scale", [1, 1, 1])),
                "children_nodes": node.get("children", []),
                "node_index": ni,
            })
            node_to_bone[ni] = bi
        self.bone_parent = {}
        for bi, bone in enumerate(self.bones):
            for cn in bone["children_nodes"]:
                if cn in node_to_bone:
                    self.bone_parent[node_to_bone[cn]] = bi

    def _extract_animations(self):
        self.animations = {}
        node_to_bone = {b["node_index"]: i for i, b in enumerate(self.bones)}
        for anim in self.gltf.get("animations", []):
            name = anim["name"]
            channels = {}
            max_t = 0.0
            for ch in anim["channels"]:
                samp = anim["samplers"][ch["sampler"]]
                target_node = ch["target"]["node"]
                target_path = ch["target"]["path"]
                if target_node not in node_to_bone:
                    continue
                bi = node_to_bone[target_node]
                bname = self.bones[bi]["name"]
                timestamps = self._read_accessor(samp["input"])
                values = self._read_accessor(samp["output"])
                if bname not in channels:
                    channels[bname] = {}
                channels[bname][target_path] = {"timestamps": timestamps, "values": values}
                if timestamps:
                    max_t = max(max_t, max(timestamps))
            self.animations[name] = {"channels": channels, "duration": max_t}

    def _extract_texture(self):
        images = self.gltf.get("images", [])
        if images:
            img = images[0]
            if "bufferView" in img:
                bv = self.gltf["bufferViews"][img["bufferView"]]
                offset = bv.get("byteOffset", 0)
                self.embedded_texture = self.bin[offset : offset + bv["byteLength"]]
        for mat in self.gltf.get("materials", []):
            if mat.get("doubleSided", False):
                self.double_sided = True
                break

    def bone_index_by_name(self, name):
        for i, b in enumerate(self.bones):
            if b["name"] == name:
                return i
        return -1


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Skeletal Animator
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SkeletalAnimator:
    """Animateur squelettique hybride : supporte les animations Bedrock JSON
    (via BedrockAnimPlayer) ET les animations baked GLB (legacy fallback)."""

    def __init__(self, glb: GLBData):
        self.glb = glb
        self.current_anim = None
        self.time = 0.0
        self.speed = 1.0
        self.playing = False
        self.loop = True
        self.last_skin_matrices = None

        # Bedrock animation engine
        self.bedrock = BedrockAnimPlayer()
        self._bedrock_anim_names = []  # Noms des animations Bedrock disponibles
        self._use_bedrock = False       # True si l'animation courante est Bedrock
        self._distance_sim = 0.0        # Distance simulee pour le walk cycle

        # Charger les animations Bedrock
        data_dir = Path(__file__).parent.parent / "data"
        if data_dir.exists():
            self._load_bedrock_anims(str(data_dir))

    def _load_bedrock_anims(self, data_dir):
        """Charge toutes les animations Bedrock disponibles."""
        # Determiner l'entity_id depuis le nom du GLB
        entity_id = "skeleton"  # Default: humanoid
        if self.glb.path:
            stem = self.glb.path.stem.lower()
            if stem != "steve":
                entity_id = stem

        self.bedrock.load_entity(entity_id, data_dir)

        # Charger AnimaTweaks si disponible
        animatweaks_dir = Path(data_dir).parent / "AnimaTweaks" / "animations"
        if animatweaks_dir.exists():
            for f in sorted(animatweaks_dir.glob("*.json")):
                self.bedrock.load_animations_file(str(f))

        self._bedrock_anim_names = self.bedrock.get_animation_names()

        # Pre_animation par defaut pour les humanoids
        if not self.bedrock.pre_animation:
            self.bedrock.pre_animation.append(
                "variable.tcos0 = (math.cos(query.modified_distance_moved * 38.17) "
                "* query.modified_move_speed / variable.gliding_speed_value) * 57.3;"
            )

    def get_all_animation_names(self):
        """Retourne les noms des animations (Bedrock + legacy GLB)."""
        names = []
        for name in self._bedrock_anim_names:
            names.append(("bedrock", name))
        for name in self.glb.animations:
            names.append(("legacy", name))
        return names

    # Animations qui vont en paire (jouer ensemble automatiquement)
    ANIM_PAIRS = {
        "animation.player.sprint.arms": "animation.player.sprint.legs",
        "animation.player.sprint.legs": "animation.player.sprint.arms",
        "animation.player.move.arms": "animation.player.move.legs",
        "animation.player.move.legs": "animation.player.move.arms",
        "animation.player.tiptoe.arms": "animation.player.tiptoe.legs",
        "animation.player.tiptoe.legs": "animation.player.tiptoe.arms",
    }

    # Animations first-person (pas faites pour le rendu 3e personne)
    FP_ANIMS = {"animation.fp.", "animation.player.first_person."}

    def set_animation(self, name, source="bedrock"):
        self.current_anim = name
        self.time = 0.0
        self._use_bedrock = (source == "bedrock" and name in self.bedrock.animations)
        if self._use_bedrock:
            self.bedrock.stop_all()
            self.bedrock.play(name)
            # Auto-jouer la paire si elle existe
            pair = self.ANIM_PAIRS.get(name)
            if pair and pair in self.bedrock.animations:
                self.bedrock.play(pair)
            self.bedrock.move_speed = 4.0
            self._distance_sim = 0.0
            # Auto-detect variables used by the animation and simulate them
            self._sim_attack = False
            self._sim_attack_phase = 0.0
            anim = self.bedrock.animations.get(name)
            if anim:
                if "attack_time" in name or "attack" in name:
                    self._sim_attack = True
                for bname, bdata in anim.bones.items():
                    for ch in (bdata.get("rotation"), bdata.get("position"), bdata.get("scale")):
                        if ch and "attack_time" in str(ch):
                            self._sim_attack = True
                            break
        else:
            pass

    def advance(self, dt):
        if not self.playing or not self.current_anim:
            return

        if self._use_bedrock:
            # Simuler le deplacement pour les animations expression-driven
            self._distance_sim += 4.0 * dt * self.speed
            self.bedrock.move_speed = 4.0 * self.speed
            self.bedrock.distance_moved = self._distance_sim
            self.bedrock.speed_scale = self.speed
            # Simuler variable.attack_time (cycle 0→0.7 sur 0.4s, puis pause 0.3s)
            if self._sim_attack:
                self._sim_attack_phase += dt * self.speed
                cycle = self._sim_attack_phase % 0.7  # 0.4s swing + 0.3s pause
                if cycle < 0.4:
                    self.bedrock.variables["attack_time"] = (cycle / 0.4) * 0.7
                else:
                    self.bedrock.variables["attack_time"] = -1.0
            self.bedrock.advance(dt)
        else:
            # Legacy animation
            anim = self.glb.animations.get(self.current_anim)
            if not anim:
                return
            self.time += dt * self.speed
            dur = anim["duration"]
            if dur > 0:
                if self.loop:
                    self.time = self.time % dur
                else:
                    self.time = min(self.time, dur)

    def _sample_channel(self, channel_data, t):
        ts = channel_data["timestamps"]
        vals = channel_data["values"]
        if not ts:
            return None
        if t <= ts[0]:
            return vals[0]
        if t >= ts[-1]:
            return vals[-1]
        for i in range(len(ts) - 1):
            if ts[i] <= t <= ts[i + 1]:
                frac = (t - ts[i]) / (ts[i + 1] - ts[i]) if ts[i + 1] != ts[i] else 0
                a, b = vals[i], vals[i + 1]
                if len(a) == 4:
                    return quat_slerp(a, b, frac)
                else:
                    return [a[j] + frac * (b[j] - a[j]) for j in range(len(a))]
        return vals[-1]

    def _compute_transforms(self):
        """Compute world transforms and skin matrices."""
        glb = self.glb
        n_bones = len(glb.bones)
        bone_rotations = {}
        bone_translations = {}
        bone_scales = {}

        if self._use_bedrock and self.playing:
            # Bedrock animations : convertir euler degrees en quaternions
            bone_transforms = self.bedrock._compute_bone_transforms()
            for bname_lower, transforms in bone_transforms.items():
                # Trouver le bone par nom (case-insensitive)
                for bi, bone in enumerate(glb.bones):
                    if bone["name"].lower() == bname_lower:
                        rot_deg = transforms["rotation"]
                        # Bedrock +X=forward, +Y=left ; GLB +X=backward, +Y=right
                        # → nier X et Y, garder Z
                        q = euler_deg_to_quat(-rot_deg[0], -rot_deg[1], rot_deg[2])
                        bone_rotations[bone["name"]] = q

                        pos = transforms["position"]
                        if any(abs(v) > 0.001 for v in pos):
                            S = 1.0 / 16.0
                            bone_translations[bone["name"]] = [
                                bone["translation"][0] + pos[0] * S,
                                bone["translation"][1] + pos[1] * S,
                                bone["translation"][2] + pos[2] * S,
                            ]

                        # Scale
                        scl = transforms["scale"]
                        if any(abs(v - 1.0) > 0.001 for v in scl):
                            if bone["name"] not in bone_scales:
                                bone_scales[bone["name"]] = list(bone["scale"])
                            bone_scales[bone["name"]] = [scl[0], scl[1], scl[2]]
                        break
        elif self.current_anim and self.current_anim in glb.animations:
            # Legacy GLB animation
            anim = glb.animations[self.current_anim]
            for bname, channels in anim["channels"].items():
                if "rotation" in channels:
                    q = self._sample_channel(channels["rotation"], self.time)
                    if q:
                        bone_rotations[bname] = q
                if "translation" in channels:
                    v = self._sample_channel(channels["translation"], self.time)
                    if v:
                        bone_translations[bname] = v

        world_transforms = [None] * n_bones
        for bi in range(n_bones):
            bone = glb.bones[bi]
            t = bone_translations.get(bone["name"], bone["translation"])
            r = bone_rotations.get(bone["name"], bone["rotation"])
            s = bone_scales.get(bone["name"], bone["scale"])
            local = mat4_trs(t, r, s)
            if bi in glb.bone_parent:
                parent_world = world_transforms[glb.bone_parent[bi]]
                if parent_world:
                    world_transforms[bi] = mat4_multiply(parent_world, local)
                else:
                    world_transforms[bi] = local
            else:
                world_transforms[bi] = local

        skin_matrices = [None] * n_bones
        for bi in range(n_bones):
            if world_transforms[bi]:
                skin_matrices[bi] = mat4_multiply(world_transforms[bi], glb.ibms[bi])
            else:
                skin_matrices[bi] = mat4_identity()

        return world_transforms, skin_matrices

    def compute_skinned(self):
        glb = self.glb
        n_bones = len(glb.bones)
        world_transforms, skin_matrices = self._compute_transforms()
        self.last_skin_matrices = skin_matrices

        skinned_pos = []
        skinned_nrm = []
        for vi in range(len(glb.positions)):
            joint_idx = glb.joints[vi][0]
            sm = skin_matrices[joint_idx] if joint_idx < n_bones else mat4_identity()
            skinned_pos.append(mat4_transform_point(sm, glb.positions[vi]))
            skinned_nrm.append(mat4_transform_dir(sm, glb.normals[vi]))

        return skinned_pos, skinned_nrm

    def get_bone_positions(self):
        glb = self.glb
        n_bones = len(glb.bones)
        world_transforms, _ = self._compute_transforms()
        positions = []
        for bi in range(n_bones):
            wt = world_transforms[bi]
            positions.append([wt[12], wt[13], wt[14]] if wt else [0, 0, 0])
        return positions


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Armor Renderer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _generate_box_faces(origin, size, uv_offset, inflate, mirror=False):
    """Generate 6 faces for a Bedrock box (in model space, scaled by 1/16).
    Returns list of (position, normal, uv) tuples, 6 vertices per face, 36 total."""
    ox, oy, oz = origin
    w, h, d = size
    u0, v0 = uv_offset
    inf = inflate
    S = BEDROCK_SCALE

    # Inflated corners in GLB space
    x0 = (ox - inf) * S
    y0 = (oy - inf) * S
    z0 = (oz - inf) * S
    x1 = (ox + w + inf) * S
    y1 = (oy + h + inf) * S
    z1 = (oz + d + inf) * S

    tw, th = ARMOR_TEX_W, ARMOR_TEX_H

    def uv(px, py):
        return [px / tw, py / th]

    verts = []

    # Bedrock box UV layout (from uv_offset [u0, v0], box size [w, h, d]):
    # Top:    (u0+d, v0)      size w x d
    # Bottom: (u0+d+w, v0)    size w x d
    # Left:   (u0, v0+d)      size d x h
    # Front:  (u0+d, v0+d)    size w x h
    # Right:  (u0+d+w, v0+d)  size d x h
    # Back:   (u0+d+w+d, v0+d) size w x h

    # Front face (-Z)
    u_f, v_f = u0 + d, v0 + d
    n_front = [0, 0, -1]
    quad_front = [
        ([x0, y0, z0], uv(u_f, v_f + h)),
        ([x1, y0, z0], uv(u_f + w, v_f + h)),
        ([x1, y1, z0], uv(u_f + w, v_f)),
        ([x0, y1, z0], uv(u_f, v_f)),
    ]

    # Back face (+Z)
    u_b, v_b = u0 + d + w + d, v0 + d
    n_back = [0, 0, 1]
    quad_back = [
        ([x1, y0, z1], uv(u_b, v_b + h)),
        ([x0, y0, z1], uv(u_b + w, v_b + h)),
        ([x0, y1, z1], uv(u_b + w, v_b)),
        ([x1, y1, z1], uv(u_b, v_b)),
    ]

    # Right face (+X)
    u_r, v_r = u0 + d + w, v0 + d
    n_right = [1, 0, 0]
    quad_right = [
        ([x1, y0, z0], uv(u_r, v_r + h)),
        ([x1, y0, z1], uv(u_r + d, v_r + h)),
        ([x1, y1, z1], uv(u_r + d, v_r)),
        ([x1, y1, z0], uv(u_r, v_r)),
    ]

    # Left face (-X)
    u_l, v_l = u0, v0 + d
    n_left = [-1, 0, 0]
    quad_left = [
        ([x0, y0, z1], uv(u_l, v_l + h)),
        ([x0, y0, z0], uv(u_l + d, v_l + h)),
        ([x0, y1, z0], uv(u_l + d, v_l)),
        ([x0, y1, z1], uv(u_l, v_l)),
    ]

    # Top face (+Y)
    u_t, v_t = u0 + d, v0
    n_top = [0, 1, 0]
    quad_top = [
        ([x0, y1, z0], uv(u_t, v_t + d)),
        ([x1, y1, z0], uv(u_t + w, v_t + d)),
        ([x1, y1, z1], uv(u_t + w, v_t)),
        ([x0, y1, z1], uv(u_t, v_t)),
    ]

    # Bottom face (-Y)
    u_bo, v_bo = u0 + d + w, v0
    n_bottom = [0, -1, 0]
    quad_bottom = [
        ([x0, y0, z1], uv(u_bo, v_bo + d)),
        ([x1, y0, z1], uv(u_bo + w, v_bo + d)),
        ([x1, y0, z0], uv(u_bo + w, v_bo)),
        ([x0, y0, z0], uv(u_bo, v_bo)),
    ]

    for quad, normal in [(quad_front, n_front), (quad_back, n_back),
                          (quad_right, n_right), (quad_left, n_left),
                          (quad_top, n_top), (quad_bottom, n_bottom)]:
        if mirror:
            # Mirror = flip UVs horizontally within each face (swap U of vertex 0<->1, 3<->2)
            q = [(quad[0][0], quad[1][1]), (quad[1][0], quad[0][1]),
                 (quad[2][0], quad[3][1]), (quad[3][0], quad[2][1])]
        else:
            q = quad
        # Two triangles per quad: 0-1-2, 0-2-3
        for idx in [0, 1, 2, 0, 2, 3]:
            pos, uvc = q[idx]
            verts.append((pos, normal, uvc))

    return verts


class ArmorRenderer:
    """Generates and renders armor overlay meshes."""

    def __init__(self, glb: GLBData):
        self.glb = glb
        self.enabled_pieces = {"helmet": False, "chestplate": False,
                               "leggings": False, "boots": False}
        self.material = "iron"
        self.tex_ids = {}  # "iron_1" -> GL tex id, etc.
        # Pre-generate armor meshes
        # Each piece: list of (bone_index, positions[], normals[], uvs[])
        self.piece_meshes = {}
        for piece_name, piece_def in ARMOR_PIECES.items():
            meshes = []
            for bone_name, origin, size, uv_offset, inflate, mirror in piece_def["cubes"]:
                bi = glb.bone_index_by_name(bone_name)
                if bi < 0:
                    continue
                faces = _generate_box_faces(origin, size, uv_offset, inflate, mirror)
                positions = [f[0] for f in faces]
                normals = [f[1] for f in faces]
                uvs = [f[2] for f in faces]
                meshes.append((bi, positions, normals, uvs))
            self.piece_meshes[piece_name] = meshes

    def load_textures(self):
        """Load armor textures for all materials. Call after GL context is ready."""
        for mat_name, (file1, file2) in ARMOR_MATERIALS.items():
            for suffix, filename in [("1", file1), ("2", file2)]:
                key = f"{mat_name}_{suffix}"
                path = ARMOR_TEXTURES_DIR / filename
                if path.exists():
                    tid = self._load_tex(path)
                    if tid:
                        self.tex_ids[key] = tid

    def _load_tex(self, path):
        img = QImage(str(path))
        if img.isNull():
            return None
        img = img.convertToFormat(QImage.Format.Format_RGBA8888)
        w, h = img.width(), img.height()
        bits = img.bits()
        bits.setsize(w * h * 4)
        data = bytes(bits)
        tex_id = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, tex_id)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data)
        return tex_id

    def render(self, skin_matrices):
        """Render enabled armor pieces using the current skin matrices."""
        if not skin_matrices:
            return
        any_enabled = any(self.enabled_pieces.values())
        if not any_enabled:
            return

        glEnable(GL_TEXTURE_2D)
        glEnable(GL_LIGHTING)
        glDisable(GL_CULL_FACE)  # Armor may be seen from inside
        glEnable(GL_ALPHA_TEST)
        glAlphaFunc(GL_GREATER, 0.5)
        # Slight depth offset to prevent z-fighting with body
        glEnable(GL_POLYGON_OFFSET_FILL)
        glPolygonOffset(-1.0, -1.0)

        for piece_name, enabled in self.enabled_pieces.items():
            if not enabled:
                continue
            layer = ARMOR_PIECES[piece_name]["layer"]
            tex_key = f"{self.material}_{layer}"
            tex_id = self.tex_ids.get(tex_key)
            if not tex_id:
                continue
            glBindTexture(GL_TEXTURE_2D, tex_id)

            meshes = self.piece_meshes.get(piece_name, [])
            glColor4f(1.0, 1.0, 1.0, 1.0)
            glBegin(GL_TRIANGLES)
            for bone_idx, positions, normals, uvs in meshes:
                sm = skin_matrices[bone_idx] if bone_idx < len(skin_matrices) else mat4_identity()
                for i in range(len(positions)):
                    sp = mat4_transform_point(sm, positions[i])
                    sn = mat4_transform_dir(sm, normals[i])
                    glTexCoord2f(*uvs[i])
                    glNormal3f(*sn)
                    glVertex3f(*sp)
            glEnd()

        glDisable(GL_POLYGON_OFFSET_FILL)
        glDisable(GL_ALPHA_TEST)
        glDisable(GL_TEXTURE_2D)
        glEnable(GL_CULL_FACE)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# OpenGL Viewport
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class GLViewport(QOpenGLWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.glb = None
        self.animator = None
        self.armor_renderer = None
        self.texture_id = 0
        # Camera
        self.cam_theta = 200.0
        self.cam_phi = 15.0
        self.cam_dist = 4.0
        self.cam_target = [0.0, 0.8, 0.0]
        self.cam_pan = [0.0, 0.0]
        # Mouse
        self._last_mouse = None
        self._mouse_button = None
        # Display options
        self.show_grid = True
        self.show_bones = False
        self.show_wireframe = False
        # Animation timer
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._tick)
        self._timer.start(16)

    def set_model(self, glb: GLBData):
        self.glb = glb
        self.animator = SkeletalAnimator(glb)
        self.armor_renderer = ArmorRenderer(glb)
        if glb.animations:
            first = list(glb.animations.keys())[0]
            self.animator.set_animation(first)
            self.animator.playing = True

    def load_texture_from_file(self, path):
        self.makeCurrent()
        img = QImage(str(path))
        if img.isNull():
            return
        img = img.convertToFormat(QImage.Format.Format_RGBA8888)
        w, h = img.width(), img.height()
        bits = img.bits()
        bits.setsize(w * h * 4)
        data = bytes(bits)
        if self.texture_id:
            glDeleteTextures([self.texture_id])
        self.texture_id = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, self.texture_id)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data)
        self.doneCurrent()
        self.update()

    def load_texture_from_bytes(self, png_bytes):
        self.makeCurrent()
        img = QImage()
        img.loadFromData(png_bytes)
        if img.isNull():
            return
        img = img.convertToFormat(QImage.Format.Format_RGBA8888)
        w, h = img.width(), img.height()
        bits = img.bits()
        bits.setsize(w * h * 4)
        data = bytes(bits)
        if self.texture_id:
            glDeleteTextures([self.texture_id])
        self.texture_id = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, self.texture_id)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data)
        self.doneCurrent()
        self.update()

    def _tick(self):
        if self.animator:
            self.animator.advance(0.016)
            self.update()

    # -- OpenGL --

    def initializeGL(self):
        glClearColor(0.18, 0.20, 0.25, 1.0)
        glEnable(GL_DEPTH_TEST)
        if self.glb and self.glb.double_sided:
            glDisable(GL_CULL_FACE)
        else:
            glEnable(GL_CULL_FACE)
            glCullFace(GL_BACK)
        glEnable(GL_LIGHTING)
        glEnable(GL_LIGHT0)
        glLightfv(GL_LIGHT0, GL_POSITION, [-2.0, 5.0, -3.0, 0.0])
        glLightfv(GL_LIGHT0, GL_DIFFUSE, [0.9, 0.85, 0.8, 1.0])
        glLightfv(GL_LIGHT0, GL_AMBIENT, [0.45, 0.45, 0.5, 1.0])
        glEnable(GL_LIGHT1)
        glLightfv(GL_LIGHT1, GL_POSITION, [2.0, 3.0, 3.0, 0.0])
        glLightfv(GL_LIGHT1, GL_DIFFUSE, [0.4, 0.4, 0.45, 1.0])
        glLightfv(GL_LIGHT1, GL_AMBIENT, [0.0, 0.0, 0.0, 1.0])
        glEnable(GL_COLOR_MATERIAL)
        glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE)
        if self.glb and self.glb.double_sided:
            glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        # Load default texture (direct GL calls — context is current in initializeGL)
        if self.glb and self.glb.embedded_texture:
            img = QImage()
            img.loadFromData(self.glb.embedded_texture)
            if not img.isNull():
                img = img.convertToFormat(QImage.Format.Format_RGBA8888)
                w, h = img.width(), img.height()
                bits = img.bits(); bits.setsize(w * h * 4)
                self.texture_id = glGenTextures(1)
                glBindTexture(GL_TEXTURE_2D, self.texture_id)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, bytes(bits))
        elif DEFAULT_SKIN.exists():
            img = QImage(str(DEFAULT_SKIN))
            if not img.isNull():
                img = img.convertToFormat(QImage.Format.Format_RGBA8888)
                w, h = img.width(), img.height()
                bits = img.bits(); bits.setsize(w * h * 4)
                self.texture_id = glGenTextures(1)
                glBindTexture(GL_TEXTURE_2D, self.texture_id)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, bytes(bits))
        # Load armor textures (context still current)
        if self.armor_renderer:
            self.armor_renderer.load_textures()
            n = len(self.armor_renderer.tex_ids)
            print(f"Armor textures loaded: {n}")

    def resizeGL(self, w, h):
        glViewport(0, 0, w, h)
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        aspect = w / h if h > 0 else 1.0
        gluPerspective(45, aspect, 0.01, 100.0)
        glMatrixMode(GL_MODELVIEW)

    def paintGL(self):
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        glLoadIdentity()

        # Camera
        theta = math.radians(self.cam_theta)
        phi = math.radians(self.cam_phi)
        cx = self.cam_dist * math.cos(phi) * math.sin(theta)
        cy = self.cam_dist * math.sin(phi)
        cz = self.cam_dist * math.cos(phi) * math.cos(theta)
        tx, ty = self.cam_pan
        gluLookAt(
            cx + self.cam_target[0] + tx, cy + self.cam_target[1], cz + self.cam_target[2] + ty,
            self.cam_target[0] + tx, self.cam_target[1], self.cam_target[2] + ty,
            0, 1, 0,
        )

        if self.show_grid:
            self._draw_grid()

        if not self.glb or not self.animator:
            return

        # Compute skinned mesh
        skinned_pos, skinned_nrm = self.animator.compute_skinned()

        # Draw mesh
        if self.show_wireframe:
            glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
            glDisable(GL_LIGHTING)
        else:
            glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
            glEnable(GL_LIGHTING)

        if self.texture_id and not self.show_wireframe:
            glEnable(GL_TEXTURE_2D)
            glBindTexture(GL_TEXTURE_2D, self.texture_id)
        else:
            glDisable(GL_TEXTURE_2D)

        base_idx = getattr(self.glb, 'base_indices', None) or self.glb.indices
        overlay_idx = getattr(self.glb, 'overlay_indices', None) or []

        # Pass 1: Base body
        glDisable(GL_BLEND)
        glColor4f(1.0, 1.0, 1.0, 1.0)
        glBegin(GL_TRIANGLES)
        for idx in base_idx:
            if idx < len(skinned_pos):
                glTexCoord2f(*self.glb.uvs[idx])
                glNormal3f(*skinned_nrm[idx])
                glVertex3f(*skinned_pos[idx])
        glEnd()

        # Pass 2: Overlay
        if overlay_idx:
            glEnable(GL_BLEND)
            glDepthMask(GL_FALSE)
            glBegin(GL_TRIANGLES)
            for idx in overlay_idx:
                if idx < len(skinned_pos):
                    glTexCoord2f(*self.glb.uvs[idx])
                    glNormal3f(*skinned_nrm[idx])
                    glVertex3f(*skinned_pos[idx])
            glEnd()
            glDepthMask(GL_TRUE)
            glDisable(GL_BLEND)

        glDisable(GL_TEXTURE_2D)
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

        # Pass 3: Armor overlay
        if self.armor_renderer and not self.show_wireframe:
            self.armor_renderer.render(self.animator.last_skin_matrices)

        # Draw bones
        if self.show_bones:
            self._draw_bones()

    def _draw_grid(self):
        glDisable(GL_LIGHTING)
        glDisable(GL_TEXTURE_2D)
        glLineWidth(1.0)
        glBegin(GL_LINES)
        extent = 3.0
        step = 0.25
        n = int(extent / step)
        for i in range(-n, n + 1):
            v = i * step
            if i == 0:
                glColor3f(0.4, 0.4, 0.5)
            else:
                glColor3f(0.25, 0.25, 0.3)
            glVertex3f(v, 0, -extent)
            glVertex3f(v, 0, extent)
            glVertex3f(-extent, 0, v)
            glVertex3f(extent, 0, v)
        glEnd()
        glLineWidth(2.0)
        glBegin(GL_LINES)
        glColor3f(0.9, 0.2, 0.2); glVertex3f(0, 0, 0); glVertex3f(0.5, 0, 0)
        glColor3f(0.2, 0.9, 0.2); glVertex3f(0, 0, 0); glVertex3f(0, 0.5, 0)
        glColor3f(0.2, 0.2, 0.9); glVertex3f(0, 0, 0); glVertex3f(0, 0, 0.5)
        glEnd()
        glLineWidth(1.0)
        glEnable(GL_LIGHTING)

    def _draw_bones(self):
        glDisable(GL_LIGHTING)
        glDisable(GL_DEPTH_TEST)
        glDisable(GL_TEXTURE_2D)
        bone_pos = self.animator.get_bone_positions()
        glLineWidth(2.0)
        glBegin(GL_LINES)
        glColor3f(1.0, 1.0, 0.0)
        for bi, bone in enumerate(self.glb.bones):
            if bi in self.glb.bone_parent:
                pi = self.glb.bone_parent[bi]
                glVertex3f(*bone_pos[pi])
                glVertex3f(*bone_pos[bi])
        glEnd()
        glPointSize(6.0)
        glBegin(GL_POINTS)
        glColor3f(1.0, 0.3, 0.3)
        for pos in bone_pos:
            glVertex3f(*pos)
        glEnd()
        glPointSize(1.0)
        glLineWidth(1.0)
        glEnable(GL_DEPTH_TEST)
        glEnable(GL_LIGHTING)

    # -- Mouse --

    def mousePressEvent(self, event):
        self._last_mouse = event.pos()
        self._mouse_button = event.button()

    def mouseMoveEvent(self, event):
        if self._last_mouse is None:
            return
        dx = event.pos().x() - self._last_mouse.x()
        dy = event.pos().y() - self._last_mouse.y()
        if self._mouse_button == Qt.MouseButton.LeftButton:
            self.cam_theta -= dx * 0.5
            self.cam_phi = max(-89, min(89, self.cam_phi + dy * 0.5))
        elif self._mouse_button == Qt.MouseButton.MiddleButton:
            self.cam_pan[0] -= dx * 0.005 * self.cam_dist
            self.cam_pan[1] += dy * 0.005 * self.cam_dist
        self._last_mouse = event.pos()
        self.update()

    def mouseReleaseEvent(self, event):
        self._last_mouse = None
        self._mouse_button = None

    def wheelEvent(self, event):
        delta = event.angleDelta().y()
        self.cam_dist *= 0.95 if delta > 0 else 1.05
        self.cam_dist = max(0.5, min(20.0, self.cam_dist))
        self.update()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Window
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class CharacterViewer(QMainWindow):
    def __init__(self, glb_path=None):
        super().__init__()
        self.setWindowTitle(f"Character Viewer v{APP_VERSION}")
        self.setMinimumSize(900, 650)
        self.resize(1100, 750)

        path = Path(glb_path) if glb_path else DEFAULT_GLB
        self.glb = GLBData(path)

        self._build_ui()
        self.viewport.set_model(self.glb)
        self._populate_animations()
        QTimer.singleShot(100, self._populate_skins)

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QHBoxLayout(central)
        main_layout.setContentsMargins(4, 4, 4, 4)

        # -- Left panel --
        left = QWidget()
        left.setFixedWidth(240)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)

        # Skins
        skin_group = QGroupBox("Skins")
        skin_layout = QVBoxLayout(skin_group)
        self.skin_list = QListWidget()
        self.skin_list.setIconSize(QPixmap(48, 48).size())
        self.skin_list.currentItemChanged.connect(self._on_skin_changed)
        skin_layout.addWidget(self.skin_list)
        btn_load = QPushButton("Charger texture...")
        btn_load.clicked.connect(self._load_custom_skin)
        skin_layout.addWidget(btn_load)
        left_layout.addWidget(skin_group)

        # Armor
        armor_group = QGroupBox("Armure")
        armor_layout = QVBoxLayout(armor_group)

        # Material selector
        mat_row = QHBoxLayout()
        mat_row.addWidget(QLabel("Materiau:"))
        self.armor_material_combo = QComboBox()
        for mat_name in ARMOR_MATERIALS:
            self.armor_material_combo.addItem(mat_name.capitalize())
        self.armor_material_combo.setCurrentText("Iron")
        self.armor_material_combo.currentTextChanged.connect(self._on_armor_material_changed)
        mat_row.addWidget(self.armor_material_combo)
        armor_layout.addLayout(mat_row)

        # Piece checkboxes
        self.armor_checks = {}
        pieces_row1 = QHBoxLayout()
        pieces_row2 = QHBoxLayout()
        for i, (piece_name, label) in enumerate([
            ("helmet", "Casque"), ("chestplate", "Plastron"),
            ("leggings", "Jambieres"), ("boots", "Bottes"),
        ]):
            cb = QCheckBox(label)
            cb.toggled.connect(lambda checked, pn=piece_name: self._on_armor_toggled(pn, checked))
            self.armor_checks[piece_name] = cb
            if i < 2:
                pieces_row1.addWidget(cb)
            else:
                pieces_row2.addWidget(cb)
        armor_layout.addLayout(pieces_row1)
        armor_layout.addLayout(pieces_row2)

        # All on/off
        btn_row = QHBoxLayout()
        btn_all = QPushButton("Tout")
        btn_all.setFixedWidth(60)
        btn_all.clicked.connect(lambda: self._set_all_armor(True))
        btn_none = QPushButton("Rien")
        btn_none.setFixedWidth(60)
        btn_none.clicked.connect(lambda: self._set_all_armor(False))
        btn_row.addWidget(btn_all)
        btn_row.addWidget(btn_none)
        btn_row.addStretch()
        armor_layout.addLayout(btn_row)

        left_layout.addWidget(armor_group)

        # Animations
        self.anim_group = QGroupBox("Animations")
        anim_layout = QVBoxLayout(self.anim_group)
        self.anim_list = QListWidget()
        self.anim_list.currentItemChanged.connect(self._on_anim_list_changed)
        anim_layout.addWidget(self.anim_list)
        # Play/Pause + Speed row
        play_row = QHBoxLayout()
        self.btn_play = QPushButton("Play")
        self.btn_play.setFixedWidth(70)
        self.btn_play.clicked.connect(self._toggle_play)
        play_row.addWidget(self.btn_play)
        self.speed_slider = QSlider(Qt.Orientation.Horizontal)
        self.speed_slider.setRange(10, 300)
        self.speed_slider.setValue(100)
        self.speed_slider.valueChanged.connect(self._on_speed_changed)
        play_row.addWidget(self.speed_slider)
        self.speed_label = QLabel("1.0x")
        self.speed_label.setFixedWidth(35)
        play_row.addWidget(self.speed_label)
        anim_layout.addLayout(play_row)
        left_layout.addWidget(self.anim_group)

        # Bones
        bone_group = QGroupBox(f"Bones ({len(self.glb.bones)})")
        bone_layout = QVBoxLayout(bone_group)
        self.bone_list = QListWidget()
        self.bone_list.setMaximumHeight(120)
        for bone in self.glb.bones:
            self.bone_list.addItem(bone["name"])
        bone_layout.addWidget(self.bone_list)
        left_layout.addWidget(bone_group)
        main_layout.addWidget(left)

        # -- Center: viewport + controls --
        center = QWidget()
        center_layout = QVBoxLayout(center)
        center_layout.setContentsMargins(0, 0, 0, 0)

        self.viewport = GLViewport()
        center_layout.addWidget(self.viewport, stretch=1)

        # Controls bar (options de rendu seulement)
        controls = QWidget()
        controls.setFixedHeight(40)
        ctrl_layout = QHBoxLayout(controls)

        cb_grid = QCheckBox("Grille")
        cb_grid.setChecked(True)
        cb_grid.toggled.connect(lambda v: setattr(self.viewport, "show_grid", v))
        ctrl_layout.addWidget(cb_grid)

        cb_bones = QCheckBox("Bones")
        cb_bones.toggled.connect(lambda v: setattr(self.viewport, "show_bones", v))
        ctrl_layout.addWidget(cb_bones)

        cb_wire = QCheckBox("Fil de fer")
        cb_wire.toggled.connect(lambda v: setattr(self.viewport, "show_wireframe", v))
        ctrl_layout.addWidget(cb_wire)

        ctrl_layout.addStretch()
        center_layout.addWidget(controls)
        main_layout.addWidget(center, stretch=1)

    # -- Armor --

    def _on_armor_material_changed(self, text):
        if self.viewport.armor_renderer:
            self.viewport.armor_renderer.material = text.lower()
            self.viewport.update()

    def _on_armor_toggled(self, piece_name, checked):
        if self.viewport.armor_renderer:
            self.viewport.armor_renderer.enabled_pieces[piece_name] = checked
            self.viewport.update()

    def _set_all_armor(self, enabled):
        for cb in self.armor_checks.values():
            cb.setChecked(enabled)

    # -- Skins / Animations --

    def _populate_animations(self):
        self.anim_list.blockSignals(True)
        self.anim_list.clear()
        self._anim_entries = []  # [(source, real_name)]

        # (bind pose)
        self.anim_list.addItem("(bind pose)")
        self._anim_entries.append(("none", ""))

        # Animations Bedrock (prioritaires)
        if self.viewport.animator:
            for source, name in self.viewport.animator.get_all_animation_names():
                if source == "bedrock":
                    anim = self.viewport.animator.bedrock.animations.get(name)
                    dur = anim.length if anim else 0
                    short = name.replace("animation.", "")
                    # Marquer les anims first-person
                    is_fp = any(name.startswith(prefix) for prefix in ("animation.fp.", "animation.player.first_person."))
                    tag = "[FP]" if is_fp else "[B]"
                    label = f"{tag} {short} ({dur:.1f}s)"
                    self.anim_list.addItem(label)
                    self._anim_entries.append(("bedrock", name))

        # Animations legacy GLB
        for name in self.glb.animations:
            dur = self.glb.animations[name]["duration"]
            label = f"[L] {name} ({dur:.1f}s)"
            self.anim_list.addItem(label)
            self._anim_entries.append(("legacy", name))

        count_b = sum(1 for s, _ in self._anim_entries if s == "bedrock")
        count_l = sum(1 for s, _ in self._anim_entries if s == "legacy")
        self.anim_group.setTitle(f"Animations ({count_b} Bedrock + {count_l} Legacy)")

        if self.anim_list.count() > 1:
            self.anim_list.setCurrentRow(1)
        self.anim_list.blockSignals(False)
        # Trigger initial animation
        if self.anim_list.count() > 1:
            self._on_anim_list_changed(self.anim_list.item(1), None)

    def _populate_skins(self):
        self.skin_list.clear()
        has_embedded = self.glb and self.glb.embedded_texture
        is_mob = has_embedded and self.glb.path != DEFAULT_GLB

        if has_embedded:
            item = QListWidgetItem("(Texture embarquee)")
            item.setData(Qt.ItemDataRole.UserRole, "__embedded__")
            self.skin_list.addItem(item)

        skin_files = []
        if not is_mob:
            if DEFAULT_SKIN.exists():
                skin_files.append(DEFAULT_SKIN)
            if DEFAULT_SKINS.exists():
                for f in sorted(DEFAULT_SKINS.rglob("*.png")):
                    if f not in skin_files:
                        skin_files.append(f)

        glb_dir = self.glb.path.parent
        tex_dir = glb_dir / "textures"
        if tex_dir.exists():
            for f in sorted(tex_dir.rglob("*.png")):
                if f not in skin_files:
                    skin_files.append(f)
        for f in sorted(glb_dir.glob("*.png")):
            if f not in skin_files:
                skin_files.append(f)

        for f in skin_files:
            if f.parent != DEFAULT_SKINS and f.parent.parent == DEFAULT_SKINS:
                label = f"{f.parent.name}/{f.stem}"
            else:
                label = f.stem
            item = QListWidgetItem(label)
            item.setData(Qt.ItemDataRole.UserRole, str(f))
            try:
                pixmap = QPixmap(str(f))
                if not pixmap.isNull() and pixmap.width() >= 16:
                    face = pixmap.copy(8, 8, 8, 8).scaled(
                        32, 32, transformMode=Qt.TransformationMode.FastTransformation)
                    item.setIcon(QIcon(face))
            except Exception:
                pass
            self.skin_list.addItem(item)

        if self.skin_list.count() > 0:
            self.skin_list.setCurrentRow(0)

    def _on_skin_changed(self, current, previous=None):
        if current is None:
            return
        path = current.data(Qt.ItemDataRole.UserRole)
        if path == "__embedded__":
            if self.glb and self.glb.embedded_texture:
                self.viewport.load_texture_from_bytes(self.glb.embedded_texture)
        elif path and os.path.exists(path):
            self.viewport.load_texture_from_file(path)

    def _on_anim_list_changed(self, current, previous=None):
        if not self.viewport.animator or current is None:
            return
        row = self.anim_list.row(current)
        if row < 0 or row >= len(self._anim_entries):
            return
        source, name = self._anim_entries[row]
        if source == "none":
            self.viewport.animator.current_anim = None
            self.viewport.animator.playing = False
            self.btn_play.setText("Play")
        else:
            self.viewport.animator.set_animation(name, source)
            self.viewport.animator.playing = True
            self.btn_play.setText("Pause")

    def _toggle_play(self):
        if not self.viewport.animator:
            return
        self.viewport.animator.playing = not self.viewport.animator.playing
        self.btn_play.setText("Pause" if self.viewport.animator.playing else "Play")

    def _on_speed_changed(self, value):
        speed = value / 100.0
        self.speed_label.setText(f"{speed:.1f}x")
        if self.viewport.animator:
            self.viewport.animator.speed = speed

    def _load_custom_skin(self):
        path, _ = QFileDialog.getOpenFileName(self, "Charger une texture skin", "", "PNG (*.png)")
        if path:
            self.viewport.load_texture_from_file(path)
            f = Path(path)
            item = QListWidgetItem(f.stem)
            item.setData(Qt.ItemDataRole.UserRole, str(f))
            try:
                pixmap = QPixmap(str(f))
                if not pixmap.isNull() and pixmap.width() >= 16:
                    face = pixmap.copy(8, 8, 8, 8).scaled(
                        32, 32, transformMode=Qt.TransformationMode.FastTransformation)
                    item.setIcon(QIcon(face))
            except Exception:
                pass
            self.skin_list.addItem(item)
            self.skin_list.setCurrentItem(item)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def main():
    import os
    os.environ.setdefault("PYOPENGL_PLATFORM", "nt")
    if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    if sys.stderr and hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8')

    print(f"character_viewer.py v{APP_VERSION}", flush=True)
    app = QApplication(sys.argv)
    glb_path = sys.argv[1] if len(sys.argv) > 1 else None
    print(f"Loading GLB: {glb_path or DEFAULT_GLB}", flush=True)
    win = CharacterViewer(glb_path)
    screen = app.primaryScreen()
    if screen:
        geo = screen.availableGeometry()
        win.setGeometry(geo)
    win.show()
    win.raise_()
    win.activateWindow()
    print("Ready.", flush=True)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
