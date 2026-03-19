#!/usr/bin/env python3
"""
character_viewer.py v1.3.0
Visualiseur de personnage GLB avec squelette, animations et skin swap

Charge un modèle GLB (Bedrock → GLB converti) et permet de :
- Visualiser le personnage 3D avec rotation caméra
- Changer de skin (texture 64×64) en un clic
- Sélectionner et jouer les animations
- Voir le squelette (bones)

Usage:
    python character_viewer.py
    python character_viewer.py path/to/model.glb

Changelog:
    v1.4.0 — Support mobs : doubleSided (désactive culling + two-sided lighting),
             texture embarquée prioritaire dans la liste skins, GL_FRONT_AND_BACK
    v1.2.0 — Scan récursif sous-dossiers skins, labels avec préfixe dossier (professions/...)
    v1.1.0 — Fix faces noires : rendu alpha blend pour overlays, depth sort
    v1.0.0 — Création initiale
"""

APP_VERSION = "1.4.0"

import sys
import json
import struct
import math
import os
from pathlib import Path

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
    """Build TRS matrix (column-major) from translation, quaternion, scale."""
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
    """Parse a GLB file and extract mesh, skeleton, animations."""

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
        # First primitive provides vertex data (shared across primitives)
        prim0 = primitives[0]
        attrs = prim0["attributes"]
        self.positions = self._read_accessor(attrs["POSITION"])
        self.normals = self._read_accessor(attrs["NORMAL"])
        self.uvs = self._read_accessor(attrs["TEXCOORD_0"])
        self.joints = self._read_accessor(attrs["JOINTS_0"])
        self.weights = self._read_accessor(attrs["WEIGHTS_0"])
        # Split indices into base (opaque) and overlay (blend)
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
        # Check doubleSided on any material
        for mat in self.gltf.get("materials", []):
            if mat.get("doubleSided", False):
                self.double_sided = True
                break


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Skeletal Animator
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SkeletalAnimator:
    """Compute skinned vertex positions for a given animation time."""

    def __init__(self, glb: GLBData):
        self.glb = glb
        self.current_anim = None
        self.time = 0.0
        self.speed = 1.0
        self.playing = False
        self.loop = True

    def set_animation(self, name):
        self.current_anim = name
        self.time = 0.0

    def advance(self, dt):
        if not self.playing or not self.current_anim:
            return
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
        """Interpolate keyframes at time t."""
        ts = channel_data["timestamps"]
        vals = channel_data["values"]
        if not ts:
            return None
        if t <= ts[0]:
            return vals[0]
        if t >= ts[-1]:
            return vals[-1]
        # Find bracketing keyframes
        for i in range(len(ts) - 1):
            if ts[i] <= t <= ts[i + 1]:
                frac = (t - ts[i]) / (ts[i + 1] - ts[i]) if ts[i + 1] != ts[i] else 0
                a, b = vals[i], vals[i + 1]
                if len(a) == 4:  # quaternion → slerp
                    return quat_slerp(a, b, frac)
                else:  # linear interpolation
                    return [a[j] + frac * (b[j] - a[j]) for j in range(len(a))]
        return vals[-1]

    def compute_skinned(self):
        """Compute skinned positions and normals. Returns (positions, normals)."""
        glb = self.glb
        n_bones = len(glb.bones)

        # Get animated bone rotations and translations
        bone_rotations = {}
        bone_translations = {}
        if self.current_anim and self.current_anim in glb.animations:
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

        # Compute world transforms
        world_transforms = [None] * n_bones
        for bi in range(n_bones):
            bone = glb.bones[bi]
            t = bone_translations.get(bone["name"], bone["translation"])
            r = bone_rotations.get(bone["name"], bone["rotation"])
            s = bone["scale"]
            local = mat4_trs(t, r, s)
            if bi in glb.bone_parent:
                parent_world = world_transforms[glb.bone_parent[bi]]
                if parent_world:
                    world_transforms[bi] = mat4_multiply(parent_world, local)
                else:
                    world_transforms[bi] = local
            else:
                world_transforms[bi] = local

        # Compute skinning matrices
        skin_matrices = [None] * n_bones
        for bi in range(n_bones):
            if world_transforms[bi]:
                ibm = glb.ibms[bi]
                skin_matrices[bi] = mat4_multiply(world_transforms[bi], ibm)
            else:
                skin_matrices[bi] = mat4_identity()

        # Skin vertices
        skinned_pos = []
        skinned_nrm = []
        for vi in range(len(glb.positions)):
            joint_idx = glb.joints[vi][0]
            sm = skin_matrices[joint_idx] if joint_idx < n_bones else mat4_identity()
            skinned_pos.append(mat4_transform_point(sm, glb.positions[vi]))
            skinned_nrm.append(mat4_transform_dir(sm, glb.normals[vi]))

        return skinned_pos, skinned_nrm

    def get_bone_positions(self):
        """Get world positions of all bones (for skeleton visualization)."""
        glb = self.glb
        n_bones = len(glb.bones)
        bone_rotations = {}
        bone_translations = {}
        if self.current_anim and self.current_anim in glb.animations:
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
            s = bone["scale"]
            local = mat4_trs(t, r, s)
            if bi in glb.bone_parent:
                parent_world = world_transforms[glb.bone_parent[bi]]
                world_transforms[bi] = mat4_multiply(parent_world, local) if parent_world else local
            else:
                world_transforms[bi] = local

        positions = []
        for bi in range(n_bones):
            wt = world_transforms[bi]
            positions.append([wt[12], wt[13], wt[14]] if wt else [0, 0, 0])
        return positions


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# OpenGL Viewport
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class GLViewport(QOpenGLWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.glb = None
        self.animator = None
        self.texture_id = 0
        # Camera
        self.cam_theta = 200.0  # horizontal angle (degrees) — face the front of the model
        self.cam_phi = 15.0     # vertical angle (degrees)
        self.cam_dist = 4.0     # distance
        self.cam_target = [0.0, 0.8, 0.0]  # look-at point (roughly chest height)
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
        self._timer.start(16)  # ~60fps

    def set_model(self, glb: GLBData):
        self.glb = glb
        self.animator = SkeletalAnimator(glb)
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

    # ── OpenGL ──

    def initializeGL(self):
        glClearColor(0.18, 0.20, 0.25, 1.0)
        glEnable(GL_DEPTH_TEST)
        # Disable face culling for doubleSided models (mobs), enable for single-sided (Steve)
        if self.glb and self.glb.double_sided:
            glDisable(GL_CULL_FACE)
        else:
            glEnable(GL_CULL_FACE)
            glCullFace(GL_BACK)
        glEnable(GL_LIGHTING)
        # Key light (front-right-above)
        glEnable(GL_LIGHT0)
        glLightfv(GL_LIGHT0, GL_POSITION, [-2.0, 5.0, -3.0, 0.0])
        glLightfv(GL_LIGHT0, GL_DIFFUSE, [0.9, 0.85, 0.8, 1.0])
        glLightfv(GL_LIGHT0, GL_AMBIENT, [0.45, 0.45, 0.5, 1.0])
        # Fill light (back-left, softer) to reduce harsh shadows
        glEnable(GL_LIGHT1)
        glLightfv(GL_LIGHT1, GL_POSITION, [2.0, 3.0, 3.0, 0.0])
        glLightfv(GL_LIGHT1, GL_DIFFUSE, [0.4, 0.4, 0.45, 1.0])
        glLightfv(GL_LIGHT1, GL_AMBIENT, [0.0, 0.0, 0.0, 1.0])
        glEnable(GL_COLOR_MATERIAL)
        # FRONT_AND_BACK so both sides are properly lit (important for doubleSided mobs)
        glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE)
        # Two-sided lighting: back faces get flipped normals for proper illumination
        if self.glb and self.glb.double_sided:
            glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE)
        # Alpha blending setup
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        # Load default texture
        if self.glb and self.glb.embedded_texture:
            self.load_texture_from_bytes(self.glb.embedded_texture)
        elif DEFAULT_SKIN.exists():
            self.load_texture_from_file(DEFAULT_SKIN)

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

        # Grid
        if self.show_grid:
            self._draw_grid()

        if not self.glb or not self.animator:
            return

        # Compute skinned mesh
        skinned_pos, skinned_nrm = self.animator.compute_skinned()

        # Draw mesh — two passes: base (opaque) then overlay (alpha blend)
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

        # Use base_indices if available (split primitives), else fallback to all indices
        base_idx = getattr(self.glb, 'base_indices', None) or self.glb.indices
        overlay_idx = getattr(self.glb, 'overlay_indices', None) or []

        # Pass 1: Base body (opaque, no blending)
        glDisable(GL_BLEND)
        glColor4f(1.0, 1.0, 1.0, 1.0)
        glBegin(GL_TRIANGLES)
        for idx in base_idx:
            if idx < len(skinned_pos):
                glTexCoord2f(*self.glb.uvs[idx])
                glNormal3f(*skinned_nrm[idx])
                glVertex3f(*skinned_pos[idx])
        glEnd()

        # Pass 2: Overlay (hat, sleeves, pants, jacket — alpha blended)
        if overlay_idx:
            glEnable(GL_BLEND)
            glDepthMask(GL_FALSE)  # Don't write depth for transparent parts
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
        # Axes
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
        # Draw bones as lines
        glLineWidth(2.0)
        glBegin(GL_LINES)
        glColor3f(1.0, 1.0, 0.0)
        for bi, bone in enumerate(self.glb.bones):
            if bi in self.glb.bone_parent:
                pi = self.glb.bone_parent[bi]
                glVertex3f(*bone_pos[pi])
                glVertex3f(*bone_pos[bi])
        glEnd()
        # Draw joints as points
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

    # ── Mouse ──

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

        # Load model
        path = Path(glb_path) if glb_path else DEFAULT_GLB
        self.glb = GLBData(path)

        self._build_ui()
        self.viewport.set_model(self.glb)
        self._populate_animations()
        # Defer skin population to after window is shown (avoids QPixmap before GL init)
        QTimer.singleShot(100, self._populate_skins)

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QHBoxLayout(central)
        main_layout.setContentsMargins(4, 4, 4, 4)

        # ── Left panel ──
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

        # Bones
        bone_group = QGroupBox(f"Bones ({len(self.glb.bones)})")
        bone_layout = QVBoxLayout(bone_group)
        self.bone_list = QListWidget()
        self.bone_list.setMaximumHeight(200)
        for bone in self.glb.bones:
            self.bone_list.addItem(bone["name"])
        bone_layout.addWidget(self.bone_list)
        left_layout.addWidget(bone_group)

        left_layout.addStretch()
        main_layout.addWidget(left)

        # ── Center: viewport + controls ──
        center = QWidget()
        center_layout = QVBoxLayout(center)
        center_layout.setContentsMargins(0, 0, 0, 0)

        # Viewport
        self.viewport = GLViewport()
        center_layout.addWidget(self.viewport, stretch=1)

        # Controls bar
        controls = QWidget()
        controls.setFixedHeight(50)
        ctrl_layout = QHBoxLayout(controls)

        # Animation selector
        ctrl_layout.addWidget(QLabel("Animation:"))
        self.anim_combo = QComboBox()
        self.anim_combo.setMinimumWidth(120)
        self.anim_combo.currentTextChanged.connect(self._on_anim_changed)
        ctrl_layout.addWidget(self.anim_combo)

        # Play/Pause
        self.btn_play = QPushButton("⏸ Pause")
        self.btn_play.setFixedWidth(90)
        self.btn_play.clicked.connect(self._toggle_play)
        ctrl_layout.addWidget(self.btn_play)

        # Speed
        ctrl_layout.addWidget(QLabel("Vitesse:"))
        self.speed_slider = QSlider(Qt.Orientation.Horizontal)
        self.speed_slider.setRange(10, 300)
        self.speed_slider.setValue(100)
        self.speed_slider.setFixedWidth(120)
        self.speed_slider.valueChanged.connect(self._on_speed_changed)
        ctrl_layout.addWidget(self.speed_slider)
        self.speed_label = QLabel("1.0x")
        self.speed_label.setFixedWidth(40)
        ctrl_layout.addWidget(self.speed_label)

        ctrl_layout.addSpacing(20)

        # Display toggles
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

    def _populate_animations(self):
        self.anim_combo.blockSignals(True)
        self.anim_combo.clear()
        self.anim_combo.addItem("(bind pose)")
        for name in self.glb.animations:
            dur = self.glb.animations[name]["duration"]
            n_ch = len(self.glb.animations[name]["channels"])
            self.anim_combo.addItem(f"{name} ({dur:.1f}s, {n_ch}ch)")
        if self.glb.animations:
            self.anim_combo.setCurrentIndex(1)
        self.anim_combo.blockSignals(False)
        self._on_anim_changed(self.anim_combo.currentText())

    def _populate_skins(self):
        self.skin_list.clear()
        has_embedded = self.glb and self.glb.embedded_texture
        is_mob = has_embedded and self.glb.path != DEFAULT_GLB

        # If mob model with embedded texture, add it as first entry
        if has_embedded:
            item = QListWidgetItem("(Texture embarquée)")
            item.setData(Qt.ItemDataRole.UserRole, "__embedded__")
            self.skin_list.addItem(item)

        skin_files = []
        if not is_mob:
            # Steve model — add default skins
            if DEFAULT_SKIN.exists():
                skin_files.append(DEFAULT_SKIN)
            if DEFAULT_SKINS.exists():
                for f in sorted(DEFAULT_SKINS.rglob("*.png")):
                    if f not in skin_files:
                        skin_files.append(f)

        # Also check alongside GLB (mob textures or custom skins)
        glb_dir = self.glb.path.parent
        # Check in textures/ subdir first (mob_converter output structure)
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
            # Reload the embedded texture from the GLB
            if self.glb and self.glb.embedded_texture:
                self.viewport.load_texture_from_bytes(self.glb.embedded_texture)
        elif path and os.path.exists(path):
            self.viewport.load_texture_from_file(path)

    def _on_anim_changed(self, text):
        if not self.viewport.animator:
            return
        if text.startswith("(bind"):
            self.viewport.animator.current_anim = None
            self.viewport.animator.playing = False
        else:
            name = text.split(" (")[0]
            self.viewport.animator.set_animation(name)
            self.viewport.animator.playing = True
            self.btn_play.setText("⏸ Pause")

    def _toggle_play(self):
        if not self.viewport.animator:
            return
        self.viewport.animator.playing = not self.viewport.animator.playing
        self.btn_play.setText("⏸ Pause" if self.viewport.animator.playing else "▶ Play")

    def _on_speed_changed(self, value):
        speed = value / 100.0
        self.speed_label.setText(f"{speed:.1f}x")
        if self.viewport.animator:
            self.viewport.animator.speed = speed

    def _load_custom_skin(self):
        path, _ = QFileDialog.getOpenFileName(self, "Charger une texture skin", "", "PNG (*.png)")
        if path:
            self.viewport.load_texture_from_file(path)
            # Add to list
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
    # Force UTF-8 output
    if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    if sys.stderr and hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8')

    print(f"character_viewer.py v{APP_VERSION}", flush=True)
    print("Creating QApplication...", flush=True)
    app = QApplication(sys.argv)
    glb_path = sys.argv[1] if len(sys.argv) > 1 else None
    print(f"Loading GLB: {glb_path or DEFAULT_GLB}", flush=True)
    win = CharacterViewer(glb_path)
    print(f"Window created: {win.width()}x{win.height()}", flush=True)
    # Plein écran sur l'écran principal (1080p)
    screen = app.primaryScreen()
    if screen:
        geo = screen.availableGeometry()
        win.setGeometry(geo)
        print(f"Window fullscreen on primary: {geo.width()}x{geo.height()} at ({geo.x()},{geo.y()})", flush=True)
    win.show()
    win.raise_()
    win.activateWindow()
    print("Entering event loop...", flush=True)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
