#!/usr/bin/env python3
"""
mob_gallery.py v1.1.0
Galerie 3D de mobs — affiche tous les GLB d'un répertoire en vignettes 3D

Affiche une grille 4 colonnes de modèles GLB avec rendu 3D interactif.
Chaque vignette montre le modèle en rotation lente avec son nom.
Clic pour sélectionner, [A] ou double-clic pour passer en plein écran.

En plein écran : panneau gauche avec liste d'animations et textures,
visualisation des bones (touche [B]), changement d'animation et de texture
par clic.

Usage:
    python mob_gallery.py                              # Charge assets/Mobs/Bedrock/
    python mob_gallery.py path/to/glb/folder/

Controles:
    Clic gauche          Selectionner un modele
    Double-clic / [A]    Plein ecran <-> galerie
    Clic gauche + drag   Orbite camera (modele selectionne / plein ecran)
    Molette              Scroll galerie / Zoom plein ecran
    [B]                  Toggle bones (plein ecran)
    Echap                Retour galerie / Quitter

Changelog:
    v1.1.0 — Plein ecran enrichi : panneau gauche avec liste animations
             (cliquable) + liste textures Bedrock (cliquable, swap dynamique),
             rendu bones (lignes jaunes + joints rouges, toggle [B]),
             scan auto des textures entity Bedrock par mob
    v1.0.1 — Fix faces inversees : reset etat GL au debut de paintGL (QPainter
             modifiait l'etat GL entre les frames), glPushAttrib/glPopAttrib
    v1.0.0 — Creation : galerie 4 colonnes, rotation auto, fullscreen toggle,
             orbite camera, QPainter overlay pour noms
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

from PyQt6.QtWidgets import QApplication, QMainWindow
from PyQt6.QtCore import Qt, QTimer, QRectF
from PyQt6.QtGui import QFont, QPainter, QColor, QPen, QBrush, QImage
from PyQt6.QtOpenGLWidgets import QOpenGLWidget

from OpenGL.GL import *
from OpenGL.GLU import *

DEFAULT_MOB_DIR = Path(__file__).parent.parent / "assets" / "Mobs" / "Bedrock"
BEDROCK_TEX_DIR = Path(r"D:\Games\Minecraft - Bedrock Edition\data\resource_packs\vanilla\textures\entity")
GRID_COLS = 4
LABEL_HEIGHT = 28
AUTO_ROTATE_SPEED = 0.3  # radians/sec

# Fullscreen panel
PANEL_WIDTH = 270
PANEL_BG = QColor(28, 28, 32)
PANEL_HEADER_BG = QColor(40, 40, 48)
ITEM_HEIGHT = 26
HEADER_HEIGHT = 32
ITEM_SELECTED_BG = QColor(60, 120, 200)
ITEM_HOVER_BG = QColor(50, 50, 60)

# Texture folder mapping — some mobs use different folder names
TEX_FOLDER_ALIASES = {
    "horse": ["horse2", "horse"],
    "polar_bear": ["polarbear"],
}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Math (same as character_viewer.py)
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
    sa, sb = math.cos(theta) - dot * st / st0, st / st0
    return [sa * a[i] + sb * b[i] for i in range(4)]

def quat_to_mat4(q):
    x, y, z, w = q
    m = [0.0] * 16
    m[0] = 1 - 2*(y*y + z*z); m[1] = 2*(x*y + z*w); m[2] = 2*(x*z - y*w)
    m[4] = 2*(x*y - z*w); m[5] = 1 - 2*(x*x + z*z); m[6] = 2*(y*z + x*w)
    m[8] = 2*(x*z + y*w); m[9] = 2*(y*z - x*w); m[10] = 1 - 2*(x*x + y*y)
    m[15] = 1.0
    return m

def mat4_identity():
    m = [0.0] * 16; m[0] = m[5] = m[10] = m[15] = 1.0; return m

def mat4_multiply(a, b):
    r = [0.0] * 16
    for c in range(4):
        for rr in range(4):
            r[c*4+rr] = sum(a[k*4+rr] * b[c*4+k] for k in range(4))
    return r

def mat4_trs(t, q, s):
    m = quat_to_mat4(q)
    m[0] *= s[0]; m[1] *= s[0]; m[2] *= s[0]
    m[4] *= s[1]; m[5] *= s[1]; m[6] *= s[1]
    m[8] *= s[2]; m[9] *= s[2]; m[10] *= s[2]
    m[12] = t[0]; m[13] = t[1]; m[14] = t[2]
    return m

def mat4_transform_point(m, p):
    return [
        m[0]*p[0] + m[4]*p[1] + m[8]*p[2] + m[12],
        m[1]*p[0] + m[5]*p[1] + m[9]*p[2] + m[13],
        m[2]*p[0] + m[6]*p[1] + m[10]*p[2] + m[14],
    ]

def mat4_transform_dir(m, n):
    r = [m[0]*n[0]+m[4]*n[1]+m[8]*n[2], m[1]*n[0]+m[5]*n[1]+m[9]*n[2], m[2]*n[0]+m[6]*n[1]+m[10]*n[2]]
    l = math.sqrt(sum(x*x for x in r))
    return [x/l for x in r] if l > 0 else [0, 1, 0]


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GLB Loader (from character_viewer.py)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class GLBData:
    def __init__(self, path):
        self.path = Path(path)
        self.positions = []; self.normals = []; self.uvs = []
        self.indices = []; self.base_indices = []; self.overlay_indices = []
        self.joints = []; self.weights = []
        self.bones = []; self.bone_parent = {}; self.ibms = []
        self.animations = {}
        self.embedded_texture = None; self.double_sided = False
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
        data = self.bin[offset: offset + bv["byteLength"]]
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
        self.base_indices = []; self.overlay_indices = []; self.indices = []
        for prim in primitives:
            idx = self._read_accessor(prim["indices"])
            mat_idx = prim.get("material", 0)
            alpha = materials[mat_idx].get("alphaMode", "OPAQUE") if mat_idx < len(materials) else "OPAQUE"
            if alpha == "BLEND":
                self.overlay_indices.extend(idx)
            else:
                self.base_indices.extend(idx)
            self.indices.extend(idx)

    def _extract_skeleton(self):
        skin = self.gltf["skins"][0]
        joint_nodes = skin["joints"]
        self.ibms = self._read_accessor(skin["inverseBindMatrices"])
        node_to_bone = {}; self.bones = []
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
            channels = {}; max_t = 0.0
            for ch in anim["channels"]:
                samp = anim["samplers"][ch["sampler"]]
                tn = ch["target"]["node"]; tp = ch["target"]["path"]
                if tn not in node_to_bone: continue
                bname = self.bones[node_to_bone[tn]]["name"]
                timestamps = self._read_accessor(samp["input"])
                values = self._read_accessor(samp["output"])
                if bname not in channels: channels[bname] = {}
                channels[bname][tp] = {"timestamps": timestamps, "values": values}
                if timestamps: max_t = max(max_t, max(timestamps))
            self.animations[name] = {"channels": channels, "duration": max_t}

    def _extract_texture(self):
        images = self.gltf.get("images", [])
        if images and "bufferView" in images[0]:
            bv = self.gltf["bufferViews"][images[0]["bufferView"]]
            offset = bv.get("byteOffset", 0)
            self.embedded_texture = self.bin[offset: offset + bv["byteLength"]]
        for mat in self.gltf.get("materials", []):
            if mat.get("doubleSided", False):
                self.double_sided = True; break


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Skeletal Animator (from character_viewer.py)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SkeletalAnimator:
    """Animateur hybride Bedrock + Legacy GLB pour la galerie de mobs."""

    def __init__(self, glb):
        self.glb = glb
        self.current_anim = None; self.time = 0.0
        self.speed = 1.0; self.playing = False; self.loop = True
        self.last_world_transforms = None

        # Bedrock animation engine
        self.bedrock = BedrockAnimPlayer()
        self._bedrock_anim_names = []
        self._use_bedrock = False
        self._distance_sim = 0.0

        # Auto-load Bedrock animations
        data_dir = Path(__file__).parent.parent / "data"
        if data_dir.exists() and glb.path:
            entity_id = glb.path.stem.lower()
            if entity_id == "steve":
                entity_id = "skeleton"
            self.bedrock.load_entity(entity_id, str(data_dir))
            self._bedrock_anim_names = self.bedrock.get_animation_names()

    def get_all_animation_names(self):
        """Retourne tous les noms d'animations (Bedrock + Legacy)."""
        names = []
        for name in self._bedrock_anim_names:
            names.append(("bedrock", name))
        for name in self.glb.animations:
            names.append(("legacy", name))
        return names

    def set_animation(self, name, source="auto"):
        self.current_anim = name; self.time = 0.0
        # Auto-detect source
        if source == "auto":
            source = "bedrock" if name in self.bedrock.animations else "legacy"
        self._use_bedrock = (source == "bedrock" and name in self.bedrock.animations)
        if self._use_bedrock:
            self.bedrock.stop_all()
            self.bedrock.play(name)
            self.bedrock.move_speed = 1.0

    def advance(self, dt):
        if not self.playing or not self.current_anim: return
        if self._use_bedrock:
            self._distance_sim += 4.0 * dt * self.speed
            self.bedrock.move_speed = 4.0 * self.speed
            self.bedrock.distance_moved = self._distance_sim
            self.bedrock.speed_scale = self.speed
            self.bedrock.advance(dt)
        else:
            anim = self.glb.animations.get(self.current_anim)
            if not anim: return
            self.time += dt * self.speed
            dur = anim["duration"]
            if dur > 0:
                self.time = self.time % dur if self.loop else min(self.time, dur)

    def _sample_channel(self, cd, t):
        ts, vals = cd["timestamps"], cd["values"]
        if not ts: return None
        if t <= ts[0]: return vals[0]
        if t >= ts[-1]: return vals[-1]
        for i in range(len(ts) - 1):
            if ts[i] <= t <= ts[i + 1]:
                frac = (t - ts[i]) / (ts[i + 1] - ts[i]) if ts[i + 1] != ts[i] else 0
                a, b = vals[i], vals[i + 1]
                return quat_slerp(a, b, frac) if len(a) == 4 else [a[j] + frac * (b[j] - a[j]) for j in range(len(a))]
        return vals[-1]

    def compute_skinned(self):
        glb = self.glb; n = len(glb.bones)
        br, bt, bs = {}, {}, {}

        if self._use_bedrock and self.playing:
            # Bedrock animations
            bone_transforms = self.bedrock._compute_bone_transforms()
            for bname_lower, transforms in bone_transforms.items():
                for bi, bone in enumerate(glb.bones):
                    if bone["name"].lower() == bname_lower:
                        rot_deg = transforms["rotation"]
                        # Bedrock +X=forward, +Y=left ; GLB +X=backward, +Y=right
                        # → nier X et Y, garder Z
                        q = euler_deg_to_quat(-rot_deg[0], -rot_deg[1], rot_deg[2])
                        br[bone["name"]] = q
                        pos = transforms["position"]
                        if any(abs(v) > 0.001 for v in pos):
                            S = 1.0 / 16.0
                            bt[bone["name"]] = [
                                bone["translation"][0] + pos[0] * S,
                                bone["translation"][1] + pos[1] * S,
                                bone["translation"][2] + pos[2] * S,
                            ]
                        scl = transforms["scale"]
                        if any(abs(v - 1.0) > 0.001 for v in scl):
                            bs[bone["name"]] = scl
                        break
        elif self.current_anim and self.current_anim in glb.animations:
            for bname, chs in glb.animations[self.current_anim]["channels"].items():
                if "rotation" in chs:
                    q = self._sample_channel(chs["rotation"], self.time)
                    if q: br[bname] = q
                if "translation" in chs:
                    v = self._sample_channel(chs["translation"], self.time)
                    if v: bt[bname] = v

        wt = [None] * n
        for bi in range(n):
            bone = glb.bones[bi]
            local = mat4_trs(bt.get(bone["name"], bone["translation"]),
                           br.get(bone["name"], bone["rotation"]),
                           bs.get(bone["name"], bone["scale"]))
            if bi in glb.bone_parent and wt[glb.bone_parent[bi]]:
                wt[bi] = mat4_multiply(wt[glb.bone_parent[bi]], local)
            else:
                wt[bi] = local
        self.last_world_transforms = wt
        sm = [mat4_multiply(wt[bi], glb.ibms[bi]) if wt[bi] else mat4_identity() for bi in range(n)]
        sp, sn = [], []
        for vi in range(len(glb.positions)):
            ji = glb.joints[vi][0]
            m = sm[ji] if ji < n else mat4_identity()
            sp.append(mat4_transform_point(m, glb.positions[vi]))
            sn.append(mat4_transform_dir(m, glb.normals[vi]))
        return sp, sn


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Texture discovery
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def find_mob_textures(mob_name):
    """Find all texture variants for a mob in Bedrock data.
    Returns list of (display_name, file_path)."""
    textures = []
    seen_paths = set()

    if not BEDROCK_TEX_DIR.is_dir():
        return textures

    # Determine folder names to search
    folder_names = TEX_FOLDER_ALIASES.get(mob_name, [mob_name])

    for folder_name in folder_names:
        folder = BEDROCK_TEX_DIR / folder_name
        if folder.is_dir():
            for f in sorted(folder.iterdir()):
                # Skip armor subfolders
                if f.is_dir():
                    continue
                if f.suffix.lower() in ('.png', '.tga') and f.resolve() not in seen_paths:
                    seen_paths.add(f.resolve())
                    textures.append((f.stem, f))

    # Also check for direct file (e.g., chicken.png, polarbear.png)
    for f in sorted(BEDROCK_TEX_DIR.iterdir()):
        if f.is_file() and f.suffix.lower() in ('.png', '.tga'):
            if f.stem == mob_name or f.stem.replace("_", "") == mob_name.replace("_", ""):
                if f.resolve() not in seen_paths:
                    seen_paths.add(f.resolve())
                    textures.append((f.stem, f))

    return textures


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Model Entry (one per GLB)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MobEntry:
    def __init__(self, glb_path):
        self.name = glb_path.stem
        self.glb = GLBData(glb_path)
        self.animator = SkeletalAnimator(self.glb)
        # Build animation list: Bedrock first, then legacy
        self.anim_names = []
        self.anim_sources = {}  # name -> "bedrock" or "legacy"
        for source, name in self.animator.get_all_animation_names():
            short = name.split(".")[-1] if source == "bedrock" else name
            display = f"[B] {name}" if source == "bedrock" else f"[L] {name}"
            self.anim_names.append(display)
            self.anim_sources[display] = (source, name)
        # Auto-play: prefer Bedrock walk/move, fallback legacy idle
        started = False
        for source, name in self.animator.get_all_animation_names():
            if source == "bedrock" and ("move" in name or "walk" in name):
                self.animator.set_animation(name, "bedrock")
                started = True
                break
        if not started:
            legacy_names = list(self.glb.animations.keys())
            if "idle" in legacy_names:
                self.animator.set_animation("idle", "legacy")
            elif legacy_names:
                self.animator.set_animation(legacy_names[0], "legacy")
        self.animator.playing = True
        # Camera state
        self.theta = 200.0  # degrees
        self.phi = 15.0
        self.cam_dist = self._auto_distance()
        self.cam_target_y = self._auto_target_y()
        # GL texture
        self.tex_id = None
        # Available textures from Bedrock (discovered lazily)
        self.available_textures = []  # [(display_name, path)]
        self.current_tex_idx = -1  # -1 = embedded
        self.loaded_tex_ids = {}  # path -> GL tex_id

    def _auto_distance(self):
        if not self.glb.positions:
            return 3.0
        ys = [p[1] for p in self.glb.positions]
        xs = [p[0] for p in self.glb.positions]
        zs = [p[2] for p in self.glb.positions]
        height = max(ys) - min(ys)
        width = max(max(xs) - min(xs), max(zs) - min(zs))
        return max(height, width) * 1.8 + 0.5

    def _auto_target_y(self):
        if not self.glb.positions:
            return 0.5
        ys = [p[1] for p in self.glb.positions]
        return (max(ys) + min(ys)) / 2.0

    def discover_textures(self):
        """Find available Bedrock textures for this mob."""
        if not self.available_textures:
            self.available_textures = find_mob_textures(self.name)

    def get_active_tex_id(self):
        """Return the GL texture ID currently in use."""
        if self.current_tex_idx < 0:
            return self.tex_id  # embedded
        if self.current_tex_idx < len(self.available_textures):
            _, path = self.available_textures[self.current_tex_idx]
            return self.loaded_tex_ids.get(str(path), self.tex_id)
        return self.tex_id


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Gallery Widget
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class MobGalleryWidget(QOpenGLWidget):
    def __init__(self, mob_dir, parent=None):
        super().__init__(parent)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setMouseTracking(True)
        self.models = []
        self.selected_idx = 0
        self.fullscreen_mode = False
        self.scroll_y = 0.0
        self.mouse_last = None
        self.mouse_button = None
        self.show_bones = False
        self.hover_item = None  # (list_type, index) for panel hover

        # Load all GLB files from directory
        glb_files = sorted(Path(mob_dir).glob("*.glb"))
        print(f"Chargement de {len(glb_files)} modeles depuis {mob_dir}...")
        for p in glb_files:
            try:
                entry = MobEntry(p)
                self.models.append(entry)
                print(f"  {entry.name} -- {len(entry.glb.positions)} verts, "
                      f"{len(entry.glb.animations)} anims, "
                      f"height={entry.cam_target_y*2:.2f}")
            except Exception as e:
                print(f"  ERREUR {p.name}: {e}")
        print(f"{len(self.models)} modeles charges")

        # Animation timer
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._tick)
        self._timer.start(16)

    def _tick(self):
        dt = 0.016
        for m in self.models:
            m.animator.advance(dt)
            if not self.fullscreen_mode:
                m.theta += math.degrees(AUTO_ROTATE_SPEED * dt)
        self.update()

    # -- Cell geometry --

    def _cell_size(self):
        w = self.width() / GRID_COLS
        return int(w), int(w + LABEL_HEIGHT)

    def _cell_rect(self, idx):
        cw, ch = self._cell_size()
        col = idx % GRID_COLS
        row = idx // GRID_COLS
        x = col * cw
        y = row * ch - int(self.scroll_y)
        return x, y, cw, ch

    def _total_height(self):
        _, ch = self._cell_size()
        rows = math.ceil(len(self.models) / GRID_COLS)
        return rows * ch

    def _hit_test(self, mx, my):
        for i in range(len(self.models)):
            x, y, w, h = self._cell_rect(i)
            if x <= mx < x + w and y <= my < y + h:
                return i
        return -1

    # -- Panel layout helpers (fullscreen) --

    def _panel_item_at(self, mx, my):
        """Return (list_type, index) for a click in the panel, or None."""
        if mx >= PANEL_WIDTH:
            return None
        m = self.models[self.selected_idx]
        y = 8

        # Animations header
        y += HEADER_HEIGHT
        for i, aname in enumerate(m.anim_names):
            if y <= my < y + ITEM_HEIGHT:
                return ("anim", i)
            y += ITEM_HEIGHT

        y += 12  # spacing

        # Textures header
        y += HEADER_HEIGHT
        # "Embedded" item
        if y <= my < y + ITEM_HEIGHT:
            return ("tex", -1)
        y += ITEM_HEIGHT
        for i in range(len(m.available_textures)):
            if y <= my < y + ITEM_HEIGHT:
                return ("tex", i)
            y += ITEM_HEIGHT

        return None

    # -- OpenGL --

    def initializeGL(self):
        glClearColor(0.12, 0.12, 0.14, 1.0)
        glEnable(GL_DEPTH_TEST)
        glEnable(GL_LIGHTING)
        glEnable(GL_LIGHT0)
        glLightfv(GL_LIGHT0, GL_POSITION, [2.0, 4.0, 3.0, 0.0])
        glLightfv(GL_LIGHT0, GL_DIFFUSE, [0.9, 0.9, 0.9, 1.0])
        glLightfv(GL_LIGHT0, GL_AMBIENT, [0.3, 0.3, 0.3, 1.0])
        glEnable(GL_COLOR_MATERIAL)
        glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE)
        glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE)
        for m in self.models:
            if m.glb.embedded_texture:
                m.tex_id = self._upload_texture_bytes(m.glb.embedded_texture)

    def _upload_texture_bytes(self, png_bytes):
        img = QImage()
        img.loadFromData(png_bytes)
        if img.isNull():
            return None
        return self._upload_qimage(img)

    def _upload_texture_file(self, filepath):
        img = QImage(str(filepath))
        if img.isNull():
            return None
        return self._upload_qimage(img)

    def _upload_qimage(self, img):
        img = img.convertToFormat(QImage.Format.Format_RGBA8888)
        w, h = img.width(), img.height()
        bits = img.bits(); bits.setsize(w * h * 4)
        data = bytes(bits)
        tex_id = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, tex_id)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data)
        return tex_id

    def _ensure_tex_loaded(self, mob_entry, tex_idx):
        """Lazy-load a Bedrock texture and return its GL ID."""
        if tex_idx < 0 or tex_idx >= len(mob_entry.available_textures):
            return
        _, path = mob_entry.available_textures[tex_idx]
        key = str(path)
        if key not in mob_entry.loaded_tex_ids:
            tid = self._upload_texture_file(path)
            if tid:
                mob_entry.loaded_tex_ids[key] = tid
                print(f"  Texture chargee: {path.name}")
            else:
                print(f"  ERREUR texture: {path.name}")

    def resizeGL(self, w, h):
        pass

    def paintGL(self):
        # Reset GL state
        glDisable(GL_CULL_FACE)
        glEnable(GL_DEPTH_TEST)
        glDepthMask(GL_TRUE)
        glDisable(GL_BLEND)
        glEnable(GL_LIGHTING)
        glEnable(GL_LIGHT0)
        glEnable(GL_COLOR_MATERIAL)
        glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE)
        glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE)
        glFrontFace(GL_CCW)

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        w, h = self.width(), self.height()
        dpr = self.devicePixelRatio()
        pw, ph = int(w * dpr), int(h * dpr)

        if self.fullscreen_mode and 0 <= self.selected_idx < len(self.models):
            # Render model in viewport area (right of panel)
            panel_px = int(PANEL_WIDTH * dpr)
            vp_x = panel_px
            vp_w = pw - panel_px
            glViewport(vp_x, 0, max(vp_w, 1), ph)
            glScissor(vp_x, 0, max(vp_w, 1), ph)
            glEnable(GL_SCISSOR_TEST)
            m = self.models[self.selected_idx]
            self._render_model(m, max(vp_w, 1), ph)
            if self.show_bones:
                self._render_bones(m)
            glDisable(GL_SCISSOR_TEST)
        else:
            glEnable(GL_SCISSOR_TEST)
            for i, m in enumerate(self.models):
                x, y, cw, ch = self._cell_rect(i)
                vh = ch - LABEL_HEIGHT
                if y + ch < 0 or y > h:
                    continue
                gl_x = int(x * dpr)
                gl_y = int((h - y - vh) * dpr)
                gl_w = int(cw * dpr)
                gl_h = int(vh * dpr)
                glViewport(gl_x, gl_y, max(gl_w, 1), max(gl_h, 1))
                glScissor(gl_x, gl_y, max(gl_w, 1), max(gl_h, 1))
                self._render_model(m, max(gl_w, 1), max(gl_h, 1))
            glDisable(GL_SCISSOR_TEST)

    def _render_model(self, m, vw, vh):
        glClear(GL_DEPTH_BUFFER_BIT)
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        aspect = vw / vh if vh > 0 else 1.0
        gluPerspective(45.0, aspect, 0.01, 100.0)

        glMatrixMode(GL_MODELVIEW)
        glLoadIdentity()
        theta = math.radians(m.theta)
        phi = math.radians(m.phi)
        cx = m.cam_dist * math.cos(phi) * math.sin(theta)
        cy = m.cam_dist * math.sin(phi)
        cz = m.cam_dist * math.cos(phi) * math.cos(theta)
        ty = m.cam_target_y
        gluLookAt(cx, cy + ty, cz, 0, ty, 0, 0, 1, 0)

        # Grid
        glDisable(GL_LIGHTING)
        glDisable(GL_TEXTURE_2D)
        glBegin(GL_LINES)
        glColor3f(0.25, 0.25, 0.25)
        extent = 2.0
        step = 0.5
        x = -extent
        while x <= extent + 0.001:
            glVertex3f(x, 0, -extent); glVertex3f(x, 0, extent)
            glVertex3f(-extent, 0, x); glVertex3f(extent, 0, x)
            x += step
        glEnd()

        # Mesh
        glEnable(GL_LIGHTING)
        sp, sn = m.animator.compute_skinned()
        active_tex = m.get_active_tex_id()
        has_tex = active_tex is not None
        if has_tex:
            glEnable(GL_TEXTURE_2D)
            glBindTexture(GL_TEXTURE_2D, active_tex)
        else:
            glDisable(GL_TEXTURE_2D)

        if m.glb.double_sided:
            glDisable(GL_CULL_FACE)
        else:
            glEnable(GL_CULL_FACE)

        glEnable(GL_ALPHA_TEST)
        glAlphaFunc(GL_GREATER, 0.5)

        glColor3f(1.0, 1.0, 1.0)
        indices = m.glb.base_indices if m.glb.base_indices else m.glb.indices
        glBegin(GL_TRIANGLES)
        for idx in indices:
            if idx < len(sp):
                glNormal3f(*sn[idx])
                if has_tex:
                    glTexCoord2f(*m.glb.uvs[idx])
                glVertex3f(*sp[idx])
        glEnd()

        if m.glb.overlay_indices:
            glEnable(GL_BLEND)
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
            glDepthMask(GL_FALSE)
            glBegin(GL_TRIANGLES)
            for idx in m.glb.overlay_indices:
                if idx < len(sp):
                    glNormal3f(*sn[idx])
                    if has_tex:
                        glTexCoord2f(*m.glb.uvs[idx])
                    glVertex3f(*sp[idx])
            glEnd()
            glDepthMask(GL_TRUE)
            glDisable(GL_BLEND)

        glDisable(GL_ALPHA_TEST)
        glDisable(GL_TEXTURE_2D)

    def _render_bones(self, m):
        """Draw bone skeleton overlay."""
        wt = m.animator.last_world_transforms
        if not wt:
            return
        glb = m.glb
        n = len(glb.bones)

        glDisable(GL_LIGHTING)
        glDisable(GL_TEXTURE_2D)
        glDisable(GL_DEPTH_TEST)

        # Bone lines (yellow)
        glLineWidth(2.0)
        glBegin(GL_LINES)
        glColor3f(1.0, 0.9, 0.0)
        for bi in range(n):
            if bi in glb.bone_parent and wt[bi] and wt[glb.bone_parent[bi]]:
                pi = glb.bone_parent[bi]
                glVertex3f(wt[pi][12], wt[pi][13], wt[pi][14])
                glVertex3f(wt[bi][12], wt[bi][13], wt[bi][14])
        glEnd()

        # Joint dots (red)
        glPointSize(6.0)
        glBegin(GL_POINTS)
        glColor3f(1.0, 0.2, 0.2)
        for bi in range(n):
            if wt[bi]:
                glVertex3f(wt[bi][12], wt[bi][13], wt[bi][14])
        glEnd()

        # Bone name labels at joint positions
        # (skipped in GL — done via QPainter for readability)

        glLineWidth(1.0)
        glPointSize(1.0)
        glEnable(GL_DEPTH_TEST)
        glEnable(GL_LIGHTING)

    def paintEvent(self, event):
        super().paintEvent(event)

        self.makeCurrent()
        glPushAttrib(GL_ALL_ATTRIB_BITS)
        glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS)
        self.doneCurrent()

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        font = QFont("Segoe UI", 10, QFont.Weight.Bold)
        painter.setFont(font)

        if self.fullscreen_mode and 0 <= self.selected_idx < len(self.models):
            m = self.models[self.selected_idx]
            self._draw_panel(painter, m)
            # Bottom bar in viewport area
            painter.setPen(QColor(180, 180, 180))
            small_font = QFont("Segoe UI", 9)
            painter.setFont(small_font)
            bar_rect = QRectF(PANEL_WIDTH, self.height() - 32, self.width() - PANEL_WIDTH, 28)
            bones_status = "ON" if self.show_bones else "OFF"
            painter.drawText(bar_rect, Qt.AlignmentFlag.AlignCenter,
                           f"{m.name.upper()}   |   [B] Bones: {bones_status}   |   [A]/Echap retour galerie   |   Molette = Zoom")
        else:
            for i, m in enumerate(self.models):
                x, y, cw, ch = self._cell_rect(i)
                vh = ch - LABEL_HEIGHT
                if y + ch < 0 or y > self.height():
                    continue
                if i == self.selected_idx:
                    painter.setPen(QPen(QColor(80, 160, 255), 3))
                    painter.drawRect(x + 1, y + 1, cw - 3, vh - 3)
                painter.setPen(QColor(200, 200, 200))
                label_rect = QRectF(x, y + vh, cw, LABEL_HEIGHT)
                painter.drawText(label_rect, Qt.AlignmentFlag.AlignCenter, m.name)

        painter.end()

        self.makeCurrent()
        glPopClientAttrib()
        glPopAttrib()
        self.doneCurrent()

    def _draw_panel(self, painter, m):
        """Draw the left info panel in fullscreen mode."""
        h = self.height()

        # Panel background
        painter.fillRect(0, 0, PANEL_WIDTH, h, PANEL_BG)

        # Separator line
        painter.setPen(QPen(QColor(60, 60, 70), 1))
        painter.drawLine(PANEL_WIDTH - 1, 0, PANEL_WIDTH - 1, h)

        y = 8
        header_font = QFont("Segoe UI", 11, QFont.Weight.Bold)
        item_font = QFont("Segoe UI", 9)
        small_font = QFont("Segoe UI", 8)

        # ── ANIMATIONS ──
        painter.setFont(header_font)
        painter.fillRect(4, y, PANEL_WIDTH - 8, HEADER_HEIGHT, PANEL_HEADER_BG)
        painter.setPen(QColor(100, 180, 255))
        painter.drawText(QRectF(12, y, PANEL_WIDTH - 20, HEADER_HEIGHT),
                        Qt.AlignmentFlag.AlignVCenter, f"ANIMATIONS ({len(m.anim_names)})")
        y += HEADER_HEIGHT

        painter.setFont(item_font)
        for i, aname in enumerate(m.anim_names):
            is_current = (m.animator.current_anim == aname)
            is_hover = (self.hover_item == ("anim", i))

            if is_current:
                painter.fillRect(4, y, PANEL_WIDTH - 8, ITEM_HEIGHT, ITEM_SELECTED_BG)
            elif is_hover:
                painter.fillRect(4, y, PANEL_WIDTH - 8, ITEM_HEIGHT, ITEM_HOVER_BG)

            painter.setPen(QColor(255, 255, 255) if is_current else QColor(190, 190, 190))

            # Duration info
            anim_data = m.glb.animations.get(aname, {})
            dur = anim_data.get("duration", 0)
            n_channels = len(anim_data.get("channels", {}))
            label = f"  {aname}"
            painter.drawText(QRectF(4, y, PANEL_WIDTH - 70, ITEM_HEIGHT),
                           Qt.AlignmentFlag.AlignVCenter, label)
            # Duration + channels on the right
            painter.setFont(small_font)
            painter.setPen(QColor(120, 120, 130))
            painter.drawText(QRectF(PANEL_WIDTH - 74, y, 66, ITEM_HEIGHT),
                           Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignRight,
                           f"{dur:.1f}s {n_channels}b")
            painter.setFont(item_font)
            y += ITEM_HEIGHT

        y += 12

        # ── TEXTURES ──
        m.discover_textures()
        n_tex = len(m.available_textures)
        painter.setFont(header_font)
        painter.fillRect(4, y, PANEL_WIDTH - 8, HEADER_HEIGHT, PANEL_HEADER_BG)
        painter.setPen(QColor(100, 255, 160))
        painter.drawText(QRectF(12, y, PANEL_WIDTH - 20, HEADER_HEIGHT),
                        Qt.AlignmentFlag.AlignVCenter, f"TEXTURES ({n_tex + 1})")
        y += HEADER_HEIGHT

        painter.setFont(item_font)

        # "Embedded" (default GLB texture)
        is_current = (m.current_tex_idx < 0)
        is_hover = (self.hover_item == ("tex", -1))
        if is_current:
            painter.fillRect(4, y, PANEL_WIDTH - 8, ITEM_HEIGHT, ITEM_SELECTED_BG)
        elif is_hover:
            painter.fillRect(4, y, PANEL_WIDTH - 8, ITEM_HEIGHT, ITEM_HOVER_BG)
        painter.setPen(QColor(255, 255, 255) if is_current else QColor(190, 190, 190))
        painter.drawText(QRectF(12, y, PANEL_WIDTH - 20, ITEM_HEIGHT),
                        Qt.AlignmentFlag.AlignVCenter, "[embedded]")
        y += ITEM_HEIGHT

        for i, (tex_name, tex_path) in enumerate(m.available_textures):
            is_current = (m.current_tex_idx == i)
            is_hover = (self.hover_item == ("tex", i))
            if is_current:
                painter.fillRect(4, y, PANEL_WIDTH - 8, ITEM_HEIGHT, ITEM_SELECTED_BG)
            elif is_hover:
                painter.fillRect(4, y, PANEL_WIDTH - 8, ITEM_HEIGHT, ITEM_HOVER_BG)
            painter.setPen(QColor(255, 255, 255) if is_current else QColor(190, 190, 190))
            painter.drawText(QRectF(12, y, PANEL_WIDTH - 20, ITEM_HEIGHT),
                           Qt.AlignmentFlag.AlignVCenter, tex_name)
            y += ITEM_HEIGHT

        y += 12

        # ── BONES INFO ──
        painter.setFont(header_font)
        painter.fillRect(4, y, PANEL_WIDTH - 8, HEADER_HEIGHT, PANEL_HEADER_BG)
        painter.setPen(QColor(255, 200, 80))
        painter.drawText(QRectF(12, y, PANEL_WIDTH - 20, HEADER_HEIGHT),
                        Qt.AlignmentFlag.AlignVCenter, f"BONES ({len(m.glb.bones)})")
        y += HEADER_HEIGHT

        painter.setFont(small_font)
        painter.setPen(QColor(160, 160, 170))
        for bi, bone in enumerate(m.glb.bones):
            if y + 18 > h - 20:
                painter.drawText(QRectF(12, y, PANEL_WIDTH - 20, 18),
                               Qt.AlignmentFlag.AlignVCenter, "...")
                break
            parent_name = ""
            if bi in m.glb.bone_parent:
                parent_name = f" <- {m.glb.bones[m.glb.bone_parent[bi]]['name']}"
            painter.drawText(QRectF(12, y, PANEL_WIDTH - 20, 18),
                           Qt.AlignmentFlag.AlignVCenter,
                           f"{bone['name']}{parent_name}")
            y += 18

    # -- Input --

    def mousePressEvent(self, event):
        pos = event.position()
        self.mouse_last = (pos.x(), pos.y())
        self.mouse_button = event.button()

        if self.fullscreen_mode and pos.x() < PANEL_WIDTH:
            # Panel click
            hit = self._panel_item_at(pos.x(), pos.y())
            if hit:
                self._handle_panel_click(hit)
            return

        if not self.fullscreen_mode:
            hit = self._hit_test(pos.x(), pos.y())
            if hit >= 0:
                self.selected_idx = hit
                self.update()

    def _handle_panel_click(self, hit):
        m = self.models[self.selected_idx]
        list_type, idx = hit

        if list_type == "anim":
            if 0 <= idx < len(m.anim_names):
                display_name = m.anim_names[idx]
                if display_name in m.anim_sources:
                    source, real_name = m.anim_sources[display_name]
                    m.animator.set_animation(real_name, source)
                else:
                    m.animator.set_animation(display_name, "auto")
                m.animator.playing = True
                print(f"Animation: {display_name}")

        elif list_type == "tex":
            if idx < 0:
                # Embedded
                m.current_tex_idx = -1
                print("Texture: [embedded]")
            elif 0 <= idx < len(m.available_textures):
                self.makeCurrent()
                self._ensure_tex_loaded(m, idx)
                self.doneCurrent()
                m.current_tex_idx = idx
                tex_name = m.available_textures[idx][0]
                print(f"Texture: {tex_name}")

        self.update()

    def mouseDoubleClickEvent(self, event):
        pos = event.position()
        if self.fullscreen_mode:
            if pos.x() >= PANEL_WIDTH:
                self.fullscreen_mode = False
                self.update()
        else:
            hit = self._hit_test(pos.x(), pos.y())
            if hit >= 0:
                self.selected_idx = hit
                self.fullscreen_mode = True
                self.update()

    def mouseMoveEvent(self, event):
        pos = event.position()

        # Update hover for panel
        if self.fullscreen_mode and pos.x() < PANEL_WIDTH:
            self.hover_item = self._panel_item_at(pos.x(), pos.y())
        else:
            self.hover_item = None

        if self.mouse_last is None:
            return
        dx = pos.x() - self.mouse_last[0]
        dy = pos.y() - self.mouse_last[1]
        self.mouse_last = (pos.x(), pos.y())

        if self.mouse_button == Qt.MouseButton.LeftButton:
            # Don't orbit if dragging in panel
            if self.fullscreen_mode and self.mouse_last[0] < PANEL_WIDTH:
                return
            if self.fullscreen_mode:
                target = self.models[self.selected_idx]
            elif 0 <= self.selected_idx < len(self.models):
                target = self.models[self.selected_idx]
            else:
                return
            target.theta -= dx * 0.5
            target.phi = max(-89, min(89, target.phi + dy * 0.3))
            self.update()

    def mouseReleaseEvent(self, event):
        self.mouse_last = None
        self.mouse_button = None

    def wheelEvent(self, event):
        delta = event.angleDelta().y()
        if self.fullscreen_mode:
            m = self.models[self.selected_idx]
            m.cam_dist *= 0.95 if delta > 0 else 1.05
            m.cam_dist = max(0.3, min(20.0, m.cam_dist))
        else:
            self.scroll_y -= delta * 0.5
            max_scroll = max(0, self._total_height() - self.height())
            self.scroll_y = max(0, min(self.scroll_y, max_scroll))
        self.update()

    def keyPressEvent(self, event):
        key = event.key()
        if key == Qt.Key.Key_A:
            if self.fullscreen_mode:
                self.fullscreen_mode = False
            elif 0 <= self.selected_idx < len(self.models):
                self.fullscreen_mode = True
            self.update()
        elif key == Qt.Key.Key_B and self.fullscreen_mode:
            self.show_bones = not self.show_bones
            print(f"Bones: {'ON' if self.show_bones else 'OFF'}")
            self.update()
        elif key == Qt.Key.Key_Escape:
            if self.fullscreen_mode:
                self.fullscreen_mode = False
                self.update()
            else:
                QApplication.quit()
        elif key == Qt.Key.Key_Right and not self.fullscreen_mode:
            self.selected_idx = min(self.selected_idx + 1, len(self.models) - 1)
            self.update()
        elif key == Qt.Key.Key_Left and not self.fullscreen_mode:
            self.selected_idx = max(self.selected_idx - 1, 0)
            self.update()
        elif key == Qt.Key.Key_Down and not self.fullscreen_mode:
            self.selected_idx = min(self.selected_idx + GRID_COLS, len(self.models) - 1)
            self.update()
        elif key == Qt.Key.Key_Up and not self.fullscreen_mode:
            self.selected_idx = max(self.selected_idx - GRID_COLS, 0)
            self.update()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Window
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class GalleryWindow(QMainWindow):
    def __init__(self, mob_dir):
        super().__init__()
        self.setWindowTitle(f"Mob Gallery v{APP_VERSION} -- {mob_dir}")
        self.gallery = MobGalleryWidget(mob_dir, self)
        self.setCentralWidget(self.gallery)


def main():
    os.environ["PYOPENGL_PLATFORM"] = "nt"
    app = QApplication(sys.argv)

    mob_dir = DEFAULT_MOB_DIR
    if len(sys.argv) > 1:
        mob_dir = Path(sys.argv[1])

    if not mob_dir.is_dir():
        print(f"Repertoire introuvable : {mob_dir}")
        sys.exit(1)

    win = GalleryWindow(mob_dir)
    screen = app.primaryScreen()
    if screen:
        geo = screen.geometry()
        win.setGeometry(geo)
        win.showFullScreen()
    else:
        win.resize(1920, 1080)
        win.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
