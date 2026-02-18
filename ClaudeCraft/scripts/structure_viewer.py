#!/usr/bin/env python3
"""
Visualiseur 3D de structures ClaudeCraft.

Charge et affiche des structures voxel en 3D avec controles de camera.
Formats supportes : .json (ClaudeCraft), .schem (Sponge Schematic), .litematic (Litematica)

Controles souris :
  - Clic droit maintenu + deplacement  : rotation
  - Clic gauche maintenu + deplacement  : deplacement X/Y
  - Ctrl + clic gauche + deplacement    : deplacement Z (profondeur)
  - Molette souris                      : zoom

Dependances :
  pip install PyQt6 PyOpenGL

Usage :
  python structure_viewer.py
  python structure_viewer.py "chemin/vers/structure.litematic"
  python structure_viewer.py "chemin/vers/structure.json"
"""

import sys
import os
import json
import math
import gzip
import time
from pathlib import Path
from array import array

# Ajouter le repertoire du script au path pour l'import
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _SCRIPT_DIR)

try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QFileDialog, QMessageBox,
        QToolBar, QLabel, QProgressDialog, QSplitter, QTextEdit,
        QWidget, QVBoxLayout, QHBoxLayout, QSizePolicy,
        QListWidget, QListWidgetItem, QPushButton
    )
    from PyQt6.QtCore import Qt, QSize, QTimer, pyqtSignal
    from PyQt6.QtGui import QAction, QKeySequence, QSurfaceFormat, QColor
    from PyQt6.QtOpenGLWidgets import QOpenGLWidget
except ImportError:
    print("ERREUR : PyQt6 requis. Installer avec : pip install PyQt6")
    sys.exit(1)

try:
    from OpenGL.GL import *
    from OpenGL.GLU import *
except ImportError:
    print("ERREUR : PyOpenGL requis. Installer avec : pip install PyOpenGL")
    sys.exit(1)

# Import du parseur NBT et des fonctions de conversion
try:
    from convert_schem import (
        parse_nbt, decode_varints, encode_rle,
        smart_map_block, strip_block_states,
        unpack_litematic_blocks
    )
except ImportError:
    print("ERREUR : convert_schem.py introuvable dans le meme repertoire.")
    print(f"Repertoire cherche : {_SCRIPT_DIR}")
    sys.exit(1)


# ============================================================
# COULEURS DES BLOCS CLAUDECRAFT (depuis block_registry.gd)
# ============================================================

BLOCK_COLORS = {
    "AIR":            None,
    "GRASS":          (0.60, 0.90, 0.60),
    "DIRT":           (0.75, 0.60, 0.50),
    "STONE":          (0.70, 0.70, 0.75),
    "SAND":           (0.95, 0.90, 0.70),
    "WOOD":           (0.80, 0.65, 0.50),
    "LEAVES":         (0.65, 0.85, 0.65),
    "SNOW":           (0.95, 0.95, 1.00),
    "CACTUS":         (0.50, 0.75, 0.50),
    "DARK_GRASS":     (0.40, 0.70, 0.40),
    "GRAVEL":         (0.50, 0.50, 0.55),
    "PLANKS":         (0.85, 0.72, 0.50),
    "CRAFTING_TABLE": (0.55, 0.35, 0.20),
    "BRICK":          (0.80, 0.50, 0.40),
    "SANDSTONE":      (0.90, 0.82, 0.60),
    "WATER":          (0.30, 0.50, 0.90),
    "COAL_ORE":       (0.25, 0.25, 0.30),
    "IRON_ORE":       (0.75, 0.60, 0.55),
    "GOLD_ORE":       (0.85, 0.75, 0.30),
    "IRON_INGOT":     (0.80, 0.80, 0.85),
    "GOLD_INGOT":     (0.95, 0.85, 0.30),
    "FURNACE":        (0.45, 0.45, 0.50),
    "STONE_TABLE":    (0.60, 0.55, 0.50),
    "IRON_TABLE":     (0.65, 0.60, 0.60),
    "GOLD_TABLE":     (0.75, 0.65, 0.30),
    "KEEP":           (1.00, 0.00, 1.00),
}

# Blocs non-solides (transparents pour le face culling)
_TRANSPARENT = {"AIR", "WATER"}


# ============================================================
# STRUCTURE DE DONNEES
# ============================================================

class StructureData:
    """Structure voxel 3D."""

    def __init__(self, name, size, palette, blocks_3d):
        self.name = name
        self.size = size          # (sx, sy, sz) = (width, height, length)
        self.palette = palette    # liste de noms de blocs
        self.blocks = blocks_3d   # blocks[y][z][x] = index dans palette

    def get_block(self, x, y, z):
        sx, sy, sz = self.size
        if 0 <= x < sx and 0 <= y < sy and 0 <= z < sz:
            return self.blocks[y][z][x]
        return 0

    def is_transparent(self, x, y, z):
        """Retourne True si le bloc a cette position est transparent."""
        idx = self.get_block(x, y, z)
        if idx < 0 or idx >= len(self.palette):
            return True
        return self.palette[idx] in _TRANSPARENT

    def count_non_air(self):
        count = 0
        sx, sy, sz = self.size
        for y in range(sy):
            for z in range(sz):
                for x in range(sx):
                    if self.blocks[y][z][x] != 0:
                        count += 1
        return count


# ============================================================
# CHARGEMENT DE FICHIERS
# ============================================================

def decode_rle(rle_data):
    """Decode RLE : [valeur, count, ...] -> liste."""
    result = []
    for i in range(0, len(rle_data), 2):
        result.extend([rle_data[i]] * rle_data[i + 1])
    return result


def flat_to_3d(flat, sx, sy, sz):
    """Convertit 1D en 3D : blocks[y][z][x]. Ordre: y * (sx*sz) + z * sx + x."""
    blocks = [[[0] * sx for _ in range(sz)] for _ in range(sy)]
    for i, val in enumerate(flat):
        if i >= sx * sy * sz:
            break
        y = i // (sx * sz)
        r = i % (sx * sz)
        z = r // sx
        x = r % sx
        blocks[y][z][x] = val
    return blocks


def load_json(path):
    """Charge un fichier JSON ClaudeCraft."""
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    name = data.get("name", Path(path).stem)
    sx, sy, sz = data["size"]
    palette = data["palette"]
    flat = decode_rle(data["blocks_rle"])
    blocks = flat_to_3d(flat, sx, sy, sz)
    return StructureData(name, (sx, sy, sz), palette, blocks)


def load_schem(path):
    """Charge un fichier .schem (Sponge Schematic)."""
    with open(path, 'rb') as f:
        raw = f.read()
    data = gzip.decompress(raw) if raw[:2] == b'\x1f\x8b' else raw
    nbt = parse_nbt(data)
    root = nbt.get("Schematic", nbt)

    width  = root.get("Width", 0)
    height = root.get("Height", 0)
    length = root.get("Length", 0)

    blocks_compound = root.get("Blocks", {})
    if blocks_compound and isinstance(blocks_compound, dict):
        palette_data = blocks_compound.get("Palette", root.get("Palette", {}))
        block_data_raw = blocks_compound.get("Data", b"")
    else:
        palette_data = root.get("Palette", {})
        block_data_raw = root.get("BlockData", b"")

    if not palette_data:
        raise ValueError("Palette introuvable dans le fichier .schem")

    # Fallback pour block_data_raw
    if not isinstance(block_data_raw, (bytes, bytearray)):
        for key in ["Data", "BlockData", "data"]:
            for src in [root, blocks_compound]:
                if isinstance(src, dict) and key in src:
                    candidate = src[key]
                    if isinstance(candidate, (bytes, bytearray)):
                        block_data_raw = candidate
                        break

    id_to_name = {idx: name for name, idx in palette_data.items()}
    total = width * height * length
    block_ids = decode_varints(block_data_raw, total)

    # Mapper vers ClaudeCraft
    cc_palette_set = {"AIR"}
    mc_id_to_cc = {}
    for mc_id, mc_name in id_to_name.items():
        stripped = strip_block_states(mc_name)
        cc_name = smart_map_block(stripped) or "STONE"
        mc_id_to_cc[mc_id] = cc_name
        cc_palette_set.add(cc_name)

    cc_palette = ["AIR"] + sorted(cc_palette_set - {"AIR"})
    cc_idx = {n: i for i, n in enumerate(cc_palette)}

    flat = [cc_idx[mc_id_to_cc.get(bid, "STONE")] for bid in block_ids]
    blocks = flat_to_3d(flat, width, height, length)

    name = Path(path).stem.lower().replace(" ", "_").replace("-", "_")
    return StructureData(name, (width, height, length), cc_palette, blocks)


def load_litematic(path):
    """Charge un fichier .litematic (Litematica)."""
    with open(path, 'rb') as f:
        raw = f.read()
    data = gzip.decompress(raw) if raw[:2] == b'\x1f\x8b' else raw
    nbt = parse_nbt(data)
    regions = nbt.get("Regions", {})

    if not regions:
        raise ValueError("Aucune region trouvee dans le fichier .litematic")

    # Collecter tous les blocs avec coordonnees globales
    all_blocks = []  # (x, y, z, cc_name)

    for region_name, region in regions.items():
        pos  = region.get("Position", {})
        size = region.get("Size", {})

        px, py, pz = pos.get("x", 0), pos.get("y", 0), pos.get("z", 0)
        sx, sy, sz = size.get("x", 0), size.get("y", 0), size.get("z", 0)

        # Gerer les dimensions negatives
        if sx < 0:
            px += sx + 1; sx = -sx
        if sy < 0:
            py += sy + 1; sy = -sy
        if sz < 0:
            pz += sz + 1; sz = -sz

        palette_list  = region.get("BlockStatePalette", [])
        block_states  = region.get("BlockStates", [])

        if not palette_list or not block_states:
            continue

        palette_names = []
        for entry in palette_list:
            if isinstance(entry, dict):
                palette_names.append(entry.get("Name", "minecraft:air"))
            else:
                palette_names.append(str(entry))

        volume = sx * sy * sz
        block_ids = unpack_litematic_blocks(block_states, len(palette_names), volume)

        for i, bid in enumerate(block_ids):
            mc_name = palette_names[bid] if 0 <= bid < len(palette_names) else "minecraft:air"
            stripped = strip_block_states(mc_name)
            cc_name = smart_map_block(stripped) or "STONE"
            if cc_name == "AIR":
                continue

            y = i // (sx * sz)
            r = i % (sx * sz)
            z = r // sx
            x = r % sx
            all_blocks.append((px + x, py + y, pz + z, cc_name))

    if not all_blocks:
        raise ValueError("Aucun bloc non-air trouve")

    # Normaliser l'origine
    min_x = min(b[0] for b in all_blocks)
    min_y = min(b[1] for b in all_blocks)
    min_z = min(b[2] for b in all_blocks)
    max_x = max(b[0] for b in all_blocks)
    max_y = max(b[1] for b in all_blocks)
    max_z = max(b[2] for b in all_blocks)

    width  = max_x - min_x + 1
    height = max_y - min_y + 1
    length = max_z - min_z + 1

    cc_set = {"AIR"}
    for _, _, _, n in all_blocks:
        cc_set.add(n)
    cc_palette = ["AIR"] + sorted(cc_set - {"AIR"})
    cc_idx = {n: i for i, n in enumerate(cc_palette)}

    blocks_3d = [[[0] * width for _ in range(length)] for _ in range(height)]
    for wx, wy, wz, cc_name in all_blocks:
        blocks_3d[wy - min_y][wz - min_z][wx - min_x] = cc_idx[cc_name]

    name = Path(path).stem.lower().replace(" ", "_").replace("-", "_")
    return StructureData(name, (width, height, length), cc_palette, blocks_3d)


def load_structure(path):
    """Charge une structure depuis n'importe quel format supporte."""
    ext = Path(path).suffix.lower()
    if ext == ".json":
        return load_json(path)
    elif ext in (".schem", ".schematic"):
        return load_schem(path)
    elif ext == ".litematic":
        return load_litematic(path)
    else:
        raise ValueError(f"Format non supporte : {ext}")


# ============================================================
# WIDGET OPENGL 3D
# ============================================================

class VoxelGLWidget(QOpenGLWidget):
    """Widget OpenGL pour le rendu de structures voxel en 3D."""

    # Definitions des 6 faces d'un cube unitaire
    # Chaque face : (normal, 4 vertices CCW vu de l'exterieur)
    FACE_DEFS = {
        "top":    ((0, 1, 0),    lambda x, y, z: [(x,y+1,z),(x,y+1,z+1),(x+1,y+1,z+1),(x+1,y+1,z)]),
        "bottom": ((0,-1, 0),    lambda x, y, z: [(x,y,z),(x+1,y,z),(x+1,y,z+1),(x,y,z+1)]),
        "north":  ((0, 0,-1),    lambda x, y, z: [(x,y,z),(x,y+1,z),(x+1,y+1,z),(x+1,y,z)]),
        "south":  ((0, 0, 1),    lambda x, y, z: [(x+1,y,z+1),(x+1,y+1,z+1),(x,y+1,z+1),(x,y,z+1)]),
        "west":   ((-1, 0, 0),   lambda x, y, z: [(x,y,z+1),(x,y+1,z+1),(x,y+1,z),(x,y,z)]),
        "east":   ((1, 0, 0),    lambda x, y, z: [(x+1,y,z),(x+1,y+1,z),(x+1,y+1,z+1),(x+1,y,z+1)]),
    }

    # Facteur de luminosite par face (simule un eclairage directionnel simple)
    FACE_BRIGHTNESS = {
        "top": 1.0, "bottom": 0.5, "north": 0.7, "south": 0.8, "west": 0.6, "east": 0.9
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self.structure = None
        self.display_list_id = 0
        self.face_count = 0

        # Camera
        self.rot_x = 25.0
        self.rot_y = -45.0
        self.pan_x = 0.0
        self.pan_y = 0.0
        self.pan_z = 0.0
        self.zoom = 50.0
        self.center = (0.0, 0.0, 0.0)

        # Mouse
        self.last_pos = None
        self.right_pressed = False
        self.left_pressed = False

        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setMinimumSize(640, 480)

    def set_structure(self, structure):
        """Charge une nouvelle structure et reconstruit le mesh."""
        self.structure = structure
        sx, sy, sz = structure.size
        self.center = (sx / 2.0, sy / 2.0, sz / 2.0)
        self.zoom = max(sx, sy, sz) * 1.8
        self.rot_x = 25.0
        self.rot_y = -45.0
        self.pan_x = 0.0
        self.pan_y = 0.0
        self.pan_z = 0.0
        self._rebuild_display_list()
        self.update()

    # ---- OpenGL lifecycle ----

    def initializeGL(self):
        glClearColor(0.12, 0.12, 0.18, 1.0)
        glEnable(GL_DEPTH_TEST)
        glEnable(GL_CULL_FACE)
        glCullFace(GL_BACK)
        glFrontFace(GL_CCW)
        glShadeModel(GL_FLAT)

        # Eclairage desactive — on simule la lumiere via les couleurs par face
        glDisable(GL_LIGHTING)

    def resizeGL(self, w, h):
        if h == 0:
            h = 1
        glViewport(0, 0, w, h)
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        gluPerspective(50.0, w / h, 0.1, 50000.0)
        glMatrixMode(GL_MODELVIEW)

    def paintGL(self):
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        glLoadIdentity()

        # Camera : recul + rotation orbitale autour du centre
        glTranslatef(self.pan_x, self.pan_y, -self.zoom + self.pan_z)
        glRotatef(self.rot_x, 1.0, 0.0, 0.0)
        glRotatef(self.rot_y, 0.0, 1.0, 0.0)
        glTranslatef(-self.center[0], -self.center[1], -self.center[2])

        # Axes X/Y/Z
        self._draw_axes()

        # Grille au sol
        self._draw_grid()

        # Structure
        if self.display_list_id:
            glCallList(self.display_list_id)

    # ---- Dessin des helpers ----

    def _draw_axes(self):
        sx, sy, sz = (10, 10, 10)
        if self.structure:
            sx, sy, sz = self.structure.size
        length = max(sx, sy, sz) * 0.3
        length = max(length, 3.0)

        glLineWidth(2.5)
        glBegin(GL_LINES)
        # X = Rouge
        glColor3f(1.0, 0.2, 0.2)
        glVertex3f(0, 0, 0); glVertex3f(length, 0, 0)
        # Y = Vert
        glColor3f(0.2, 1.0, 0.2)
        glVertex3f(0, 0, 0); glVertex3f(0, length, 0)
        # Z = Bleu
        glColor3f(0.2, 0.4, 1.0)
        glVertex3f(0, 0, 0); glVertex3f(0, 0, length)
        glEnd()

        # Labels aux extremites (petits cubes colores)
        for pos, color in [((length, 0, 0), (1, 0.2, 0.2)),
                           ((0, length, 0), (0.2, 1, 0.2)),
                           ((0, 0, length), (0.2, 0.4, 1))]:
            s = length * 0.03
            glColor3f(*color)
            glBegin(GL_QUADS)
            px, py, pz = pos
            for dx, dy, dz in [(-s,-s,-s),(-s,-s,s),(s,-s,s),(s,-s,-s),
                                (-s,s,-s),(s,s,-s),(s,s,s),(-s,s,s),
                                (-s,-s,-s),(-s,s,-s),(-s,s,s),(-s,-s,s),
                                (s,-s,-s),(s,-s,s),(s,s,s),(s,s,-s),
                                (-s,-s,-s),(s,-s,-s),(s,s,-s),(-s,s,-s),
                                (-s,-s,s),(-s,s,s),(s,s,s),(s,-s,s)]:
                glVertex3f(px+dx, py+dy, pz+dz)
            glEnd()

    def _draw_grid(self):
        """Dessine une grille au sol (y=0)."""
        if not self.structure:
            return
        sx, _, sz = self.structure.size
        glColor4f(0.3, 0.3, 0.4, 0.5)
        glLineWidth(1.0)
        glBegin(GL_LINES)
        for x in range(sx + 1):
            glVertex3f(x, 0, 0)
            glVertex3f(x, 0, sz)
        for z in range(sz + 1):
            glVertex3f(0, 0, z)
            glVertex3f(sx, 0, z)
        glEnd()

    # ---- Construction du mesh ----

    def _rebuild_display_list(self):
        """Construit un display list OpenGL avec toutes les faces visibles."""
        if self.display_list_id:
            glDeleteLists(self.display_list_id, 1)
            self.display_list_id = 0
            self.face_count = 0

        if not self.structure:
            return

        s = self.structure
        sx, sy, sz = s.size

        self.display_list_id = glGenLists(1)
        glNewList(self.display_list_id, GL_COMPILE)
        glBegin(GL_QUADS)

        face_count = 0

        # Directions d'adjacence pour chaque face
        adj_dirs = {
            "top": (0, 1, 0), "bottom": (0, -1, 0),
            "north": (0, 0, -1), "south": (0, 0, 1),
            "west": (-1, 0, 0), "east": (1, 0, 0),
        }

        for y in range(sy):
            for z in range(sz):
                for x in range(sx):
                    block_idx = s.blocks[y][z][x]
                    if block_idx == 0:
                        continue

                    block_name = s.palette[block_idx] if block_idx < len(s.palette) else "STONE"
                    base_color = BLOCK_COLORS.get(block_name)
                    if base_color is None:
                        base_color = (0.7, 0.7, 0.75)

                    for face_name, (normal, verts_fn) in self.FACE_DEFS.items():
                        dx, dy, dz = adj_dirs[face_name]
                        nx, ny, nz = x + dx, y + dy, z + dz

                        # Ne dessiner que si le bloc adjacent est transparent
                        if 0 <= nx < sx and 0 <= ny < sy and 0 <= nz < sz:
                            adj_idx = s.blocks[ny][nz][nx]
                            adj_name = s.palette[adj_idx] if adj_idx < len(s.palette) else "AIR"
                            if adj_name not in _TRANSPARENT:
                                continue

                        # Couleur avec variation par face
                        brightness = self.FACE_BRIGHTNESS[face_name]
                        r = min(1.0, base_color[0] * brightness)
                        g = min(1.0, base_color[1] * brightness)
                        b = min(1.0, base_color[2] * brightness)

                        glColor3f(r, g, b)
                        for vx, vy, vz in verts_fn(x, y, z):
                            glVertex3f(vx, vy, vz)
                        face_count += 1

        glEnd()
        glEndList()
        self.face_count = face_count

    # ---- Controles souris ----

    def mousePressEvent(self, event):
        self.last_pos = event.position()
        if event.button() == Qt.MouseButton.RightButton:
            self.right_pressed = True
        elif event.button() == Qt.MouseButton.LeftButton:
            self.left_pressed = True

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.MouseButton.RightButton:
            self.right_pressed = False
        elif event.button() == Qt.MouseButton.LeftButton:
            self.left_pressed = False

    def mouseMoveEvent(self, event):
        if not self.last_pos:
            self.last_pos = event.position()
            return

        dx = event.position().x() - self.last_pos.x()
        dy = event.position().y() - self.last_pos.y()
        self.last_pos = event.position()

        if self.right_pressed:
            # Rotation orbitale
            self.rot_y += dx * 0.4
            self.rot_x += dy * 0.4
            self.rot_x = max(-90, min(90, self.rot_x))
            self.update()
        elif self.left_pressed:
            modifiers = QApplication.keyboardModifiers()
            if modifiers & Qt.KeyboardModifier.ControlModifier:
                # Deplacement Z (profondeur)
                self.pan_z += dy * 0.05 * max(1.0, self.zoom / 50.0)
            else:
                # Deplacement X/Y
                scale = max(0.01, self.zoom / 800.0)
                self.pan_x += dx * scale
                self.pan_y -= dy * scale
            self.update()

    def wheelEvent(self, event):
        delta = event.angleDelta().y()
        factor = 0.9 if delta > 0 else 1.1
        self.zoom = max(1.0, min(50000.0, self.zoom * factor))
        self.update()

    def keyPressEvent(self, event):
        """Raccourcis clavier : R=reset vue, F=vue de face, T=vue de dessus."""
        key = event.key()
        if key == Qt.Key.Key_R:
            # Reset camera
            if self.structure:
                sx, sy, sz = self.structure.size
                self.center = (sx / 2.0, sy / 2.0, sz / 2.0)
                self.zoom = max(sx, sy, sz) * 1.8
            self.rot_x = 25.0
            self.rot_y = -45.0
            self.pan_x = self.pan_y = self.pan_z = 0.0
            self.update()
        elif key == Qt.Key.Key_F:
            # Vue de face (sud)
            self.rot_x = 0.0
            self.rot_y = 0.0
            self.update()
        elif key == Qt.Key.Key_T:
            # Vue de dessus
            self.rot_x = 90.0
            self.rot_y = 0.0
            self.update()
        else:
            super().keyPressEvent(event)


# ============================================================
# CONFIG PERSISTANCE
# ============================================================

_CONFIG_PATH = os.path.join(os.path.expanduser("~"), ".claudecraft_viewer_config.json")

def _load_config():
    """Charge la configuration persistante."""
    try:
        with open(_CONFIG_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def _save_config(cfg):
    """Sauvegarde la configuration persistante."""
    try:
        with open(_CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(cfg, f, indent=2)
    except OSError:
        pass


# ============================================================
# PANNEAU NAVIGATEUR DE FICHIERS
# ============================================================

_SUPPORTED_EXTENSIONS = {".json", ".schem", ".litematic", ".schematic"}

class FileBrowserPanel(QWidget):
    """Panneau de navigation dans les fichiers et dossiers."""

    file_selected = pyqtSignal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.current_dir = None

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)

        # Barre de chemin
        path_bar = QHBoxLayout()
        path_bar.setContentsMargins(4, 4, 4, 0)
        path_bar.setSpacing(4)

        self.btn_parent = QPushButton("\u2191")
        self.btn_parent.setFixedSize(28, 28)
        self.btn_parent.setToolTip("Dossier parent")
        self.btn_parent.clicked.connect(self._go_parent)
        self.btn_parent.setStyleSheet("""
            QPushButton {
                background: #313244; color: #cdd6f4; border: 1px solid #45475a;
                border-radius: 4px; font-size: 14px; font-weight: bold;
            }
            QPushButton:hover { background: #45475a; }
        """)
        path_bar.addWidget(self.btn_parent)

        self.path_label = QLabel("")
        self.path_label.setStyleSheet("""
            QLabel {
                color: #a6adc8; font-size: 11px; font-family: Consolas, monospace;
                padding: 2px 4px;
            }
        """)
        self.path_label.setWordWrap(False)
        path_bar.addWidget(self.path_label, 1)
        layout.addLayout(path_bar)

        # Liste de fichiers
        self.file_list = QListWidget()
        self.file_list.setStyleSheet("""
            QListWidget {
                background-color: #1e1e2e; border: 1px solid #45475a;
                font-family: Consolas, monospace; font-size: 12px;
                outline: none;
            }
            QListWidget::item {
                padding: 3px 6px; border: none;
            }
            QListWidget::item:selected {
                background-color: #313244;
            }
            QListWidget::item:hover {
                background-color: #2a2b3d;
            }
        """)
        self.file_list.itemClicked.connect(self._on_item_clicked)
        self.file_list.itemDoubleClicked.connect(self._on_item_double_clicked)
        layout.addWidget(self.file_list)

        self.setStyleSheet("background-color: #1e1e2e;")

    def set_directory(self, dir_path):
        """Navigue vers un repertoire et rafraichit la liste."""
        dir_path = os.path.abspath(dir_path)
        if not os.path.isdir(dir_path):
            return
        self.current_dir = dir_path

        # Tronquer le chemin affiche si trop long
        display = dir_path
        if len(display) > 40:
            display = "..." + display[-37:]
        self.path_label.setText(display)
        self.path_label.setToolTip(dir_path)

        # Activer/desactiver bouton parent
        parent = os.path.dirname(dir_path)
        self.btn_parent.setEnabled(parent != dir_path)

        # Lister le contenu
        self.file_list.clear()
        try:
            entries = os.listdir(dir_path)
        except OSError:
            return

        dirs = []
        files = []
        for entry in entries:
            full = os.path.join(dir_path, entry)
            if os.path.isdir(full):
                dirs.append(entry)
            else:
                ext = os.path.splitext(entry)[1].lower()
                if ext in _SUPPORTED_EXTENSIONS:
                    files.append(entry)

        dirs.sort(key=str.lower)
        files.sort(key=str.lower)

        # Entree parent (..)
        if os.path.dirname(dir_path) != dir_path:
            item = QListWidgetItem("\U0001f4c1  ..")
            item.setData(Qt.ItemDataRole.UserRole, ("dir", os.path.dirname(dir_path)))
            item.setForeground(QColor("#f9e2af"))
            self.file_list.addItem(item)

        # Dossiers
        for d in dirs:
            item = QListWidgetItem(f"\U0001f4c1  {d}")
            item.setData(Qt.ItemDataRole.UserRole, ("dir", os.path.join(dir_path, d)))
            item.setForeground(QColor("#f9e2af"))
            self.file_list.addItem(item)

        # Fichiers
        for f in files:
            item = QListWidgetItem(f"\U0001f4c4  {f}")
            item.setData(Qt.ItemDataRole.UserRole, ("file", os.path.join(dir_path, f)))
            item.setForeground(QColor("#89b4fa"))
            self.file_list.addItem(item)

        # Sauvegarder le dernier repertoire
        cfg = _load_config()
        cfg["last_directory"] = dir_path
        _save_config(cfg)

    def highlight_file(self, file_path):
        """Met en surbrillance un fichier dans la liste s'il est visible."""
        file_path = os.path.abspath(file_path)
        for i in range(self.file_list.count()):
            item = self.file_list.item(i)
            data = item.data(Qt.ItemDataRole.UserRole)
            if data and data[0] == "file" and os.path.abspath(data[1]) == file_path:
                self.file_list.setCurrentItem(item)
                self.file_list.scrollToItem(item)
                return

    def _go_parent(self):
        if self.current_dir:
            parent = os.path.dirname(self.current_dir)
            if parent != self.current_dir:
                self.set_directory(parent)

    def _on_item_clicked(self, item):
        data = item.data(Qt.ItemDataRole.UserRole)
        if not data:
            return
        kind, path = data
        if kind == "file":
            self.file_selected.emit(path)

    def _on_item_double_clicked(self, item):
        data = item.data(Qt.ItemDataRole.UserRole)
        if not data:
            return
        kind, path = data
        if kind == "dir":
            self.set_directory(path)
        elif kind == "file":
            self.file_selected.emit(path)


# ============================================================
# FENETRE PRINCIPALE
# ============================================================

class StructureViewer(QMainWindow):
    """Fenetre principale du visualiseur de structures."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("ClaudeCraft - Visualiseur de Structures 3D")
        self.resize(1280, 800)

        self.current_structure = None
        self.current_path = None

        # Widget OpenGL
        self.gl_widget = VoxelGLWidget(self)

        # Panneau d'informations (en bas, compact)
        self.info_panel = QTextEdit(self)
        self.info_panel.setReadOnly(True)
        self.info_panel.setMaximumHeight(160)
        self.info_panel.setStyleSheet("""
            QTextEdit {
                background-color: #1e1e2e;
                color: #cdd6f4;
                border: 1px solid #45475a;
                font-family: Consolas, monospace;
                font-size: 11px;
                padding: 4px 8px;
            }
        """)
        self.info_panel.setHtml(self._default_info_html())

        # Panneau navigateur de fichiers (gauche)
        self.file_browser = FileBrowserPanel(self)
        self.file_browser.file_selected.connect(self._on_browser_file_selected)

        # Layout : splitter vertical (viewport + info)
        right_splitter = QSplitter(Qt.Orientation.Vertical, self)
        right_splitter.addWidget(self.gl_widget)
        right_splitter.addWidget(self.info_panel)
        right_splitter.setStretchFactor(0, 1)
        right_splitter.setStretchFactor(1, 0)
        right_splitter.setSizes([700, 140])

        # Layout principal : splitter horizontal (browser | viewport+info)
        main_splitter = QSplitter(Qt.Orientation.Horizontal, self)
        main_splitter.addWidget(self.file_browser)
        main_splitter.addWidget(right_splitter)
        main_splitter.setStretchFactor(0, 0)
        main_splitter.setStretchFactor(1, 1)
        main_splitter.setSizes([250, 1030])
        self.setCentralWidget(main_splitter)

        # Initialiser le navigateur avec le dernier repertoire ou CWD
        cfg = _load_config()
        start_dir = cfg.get("last_directory", "")
        if not start_dir or not os.path.isdir(start_dir):
            start_dir = os.getcwd()
        self.file_browser.set_directory(start_dir)

        # Toolbar
        self._create_toolbar()

        # Status bar
        self.statusBar().showMessage("Pret — Ouvrir un fichier .json, .schem ou .litematic  |  Ctrl+O: Ouvrir  |  Echap/Ctrl+Q: Quitter")
        self.statusBar().setStyleSheet("color: #a6adc8;")

        # Drag and drop
        self.setAcceptDrops(True)

        # Demarrer maximise
        self.showMaximized()

    def _create_toolbar(self):
        toolbar = self.addToolBar("Outils")
        toolbar.setMovable(False)
        toolbar.setIconSize(QSize(20, 20))

        # Ouvrir
        act_open = QAction("Ouvrir", self)
        act_open.setShortcut(QKeySequence("Ctrl+O"))
        act_open.triggered.connect(self.open_file)
        toolbar.addAction(act_open)

        toolbar.addSeparator()

        # Exporter JSON
        act_export = QAction("Exporter JSON", self)
        act_export.setShortcut(QKeySequence("Ctrl+S"))
        act_export.triggered.connect(self.export_json)
        toolbar.addAction(act_export)

        toolbar.addSeparator()

        # Reset vue
        act_reset = QAction("Reset vue (R)", self)
        act_reset.triggered.connect(lambda: self.gl_widget.keyPressEvent(
            type('Event', (), {'key': lambda: Qt.Key.Key_R})()
        ) if False else self._reset_view())
        toolbar.addAction(act_reset)

        # Vue de face
        act_front = QAction("Vue face (F)", self)
        act_front.triggered.connect(self._view_front)
        toolbar.addAction(act_front)

        # Vue de dessus
        act_top = QAction("Vue dessus (T)", self)
        act_top.triggered.connect(self._view_top)
        toolbar.addAction(act_top)

        # Masquer/afficher panneau info
        act_toggle = QAction("Infos (I)", self)
        act_toggle.setShortcut(QKeySequence("I"))
        act_toggle.triggered.connect(self._toggle_info_panel)
        toolbar.addAction(act_toggle)

        # Spacer pour pousser Quitter a droite
        spacer = QWidget()
        spacer.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        toolbar.addWidget(spacer)

        # Quitter
        act_quit = QAction("Quitter", self)
        act_quit.setShortcut(QKeySequence("Ctrl+Q"))
        act_quit.triggered.connect(self.close)
        toolbar.addAction(act_quit)

    def _reset_view(self):
        if self.gl_widget.structure:
            sx, sy, sz = self.gl_widget.structure.size
            self.gl_widget.center = (sx/2, sy/2, sz/2)
            self.gl_widget.zoom = max(sx, sy, sz) * 1.8
        self.gl_widget.rot_x = 25.0
        self.gl_widget.rot_y = -45.0
        self.gl_widget.pan_x = self.gl_widget.pan_y = self.gl_widget.pan_z = 0.0
        self.gl_widget.update()

    def _view_front(self):
        self.gl_widget.rot_x = 0.0
        self.gl_widget.rot_y = 0.0
        self.gl_widget.update()

    def _view_top(self):
        self.gl_widget.rot_x = 90.0
        self.gl_widget.rot_y = 0.0
        self.gl_widget.update()

    def _toggle_info_panel(self):
        self.info_panel.setVisible(not self.info_panel.isVisible())

    def _on_browser_file_selected(self, path):
        """Appele quand un fichier est selectionne dans le navigateur."""
        self.load_file(path)

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)

    def _default_info_html(self):
        return """
        <table width="100%"><tr>
        <td valign="top" width="33%">
            <b style="color:#89b4fa;">Controles souris</b><br>
            Clic droit + drag = Rotation &nbsp;|&nbsp;
            Clic gauche + drag = Deplacement X/Y &nbsp;|&nbsp;
            Ctrl + clic gauche = Deplacement Z &nbsp;|&nbsp;
            Molette = Zoom
        </td>
        <td valign="top" width="33%">
            <b style="color:#89b4fa;">Raccourcis</b><br>
            R = Reset vue &nbsp;|&nbsp; F = Vue face &nbsp;|&nbsp; T = Vue dessus &nbsp;|&nbsp;
            I = Masquer/afficher ce panneau &nbsp;|&nbsp;
            Ctrl+O = Ouvrir &nbsp;|&nbsp; Ctrl+S = Exporter &nbsp;|&nbsp; Echap = Quitter
        </td>
        <td valign="top" width="33%">
            <b style="color:#89b4fa;">Formats</b><br>
            .json (ClaudeCraft) &nbsp;|&nbsp; .schem (Sponge) &nbsp;|&nbsp; .litematic (Litematica)
        </td>
        </tr></table>
        """

    # ---- Actions ----

    def open_file(self):
        # Repertoire de depart : assets/ si existe, sinon structures/
        start_dir = os.path.join(os.path.dirname(_SCRIPT_DIR), "assets")
        if not os.path.isdir(start_dir):
            start_dir = os.path.join(os.path.dirname(_SCRIPT_DIR), "structures")

        path, _ = QFileDialog.getOpenFileName(
            self,
            "Ouvrir une structure",
            start_dir,
            "Structures (*.json *.schem *.litematic *.schematic);;Tous les fichiers (*.*)"
        )
        if path:
            self.load_file(path)

    def load_file(self, path):
        """Charge et affiche un fichier de structure."""
        basename = os.path.basename(path)
        self.statusBar().showMessage(f"Chargement de {basename}...")
        QApplication.processEvents()

        t0 = time.time()

        try:
            structure = load_structure(path)
        except Exception as e:
            QMessageBox.critical(self, "Erreur de chargement",
                                 f"Impossible de charger :\n{basename}\n\n{e}")
            import traceback
            traceback.print_exc()
            self.statusBar().showMessage("Erreur de chargement")
            return

        t_load = time.time() - t0

        self.current_structure = structure
        self.current_path = path

        # Afficher dans le viewport
        self.statusBar().showMessage(f"Construction du mesh 3D...")
        QApplication.processEvents()

        t1 = time.time()
        self.gl_widget.set_structure(structure)
        t_mesh = time.time() - t1

        # Stats
        sx, sy, sz = structure.size
        non_air = structure.count_non_air()
        total = sx * sy * sz
        faces = self.gl_widget.face_count

        self.statusBar().showMessage(
            f"{structure.name} — {sx}x{sy}x{sz} — "
            f"{non_air:,} blocs — {faces:,} faces — "
            f"Charge en {t_load:.1f}s, mesh en {t_mesh:.1f}s"
        )
        self.setWindowTitle(f"ClaudeCraft Viewer — {structure.name}")

        # Panneau d'infos
        self._update_info_panel(structure, non_air, total, faces, t_load, t_mesh)

        # Mettre en surbrillance dans le navigateur
        self.file_browser.highlight_file(path)

    def _update_info_panel(self, s, non_air, total, faces, t_load, t_mesh):
        sx, sy, sz = s.size

        # Compter par type
        counts = {}
        for y in range(sy):
            for z in range(sz):
                for x in range(sx):
                    idx = s.blocks[y][z][x]
                    name = s.palette[idx] if idx < len(s.palette) else "?"
                    if name != "AIR":
                        counts[name] = counts.get(name, 0) + 1

        # Format horizontal : stats a gauche, blocs a droite
        # Stats
        html = f"""<table width="100%"><tr>
        <td valign="top" width="30%">
            <b style="color:#89b4fa;">{s.name}</b> &nbsp;
            <span style="color:#cdd6f4;">
            Taille: <b>{sx}x{sy}x{sz}</b> &nbsp;|&nbsp;
            Blocs: <b>{non_air:,}</b> / {total:,} &nbsp;|&nbsp;
            Faces: {faces:,} &nbsp;|&nbsp;
            Types: {len(s.palette)} &nbsp;|&nbsp;
            Charge: {t_load:.2f}s &nbsp; Mesh: {t_mesh:.2f}s
            </span>
        </td>
        <td valign="top" width="70%">
            <b style="color:#a6e3a1;">Repartition :</b> &nbsp;
        """

        for name, count in sorted(counts.items(), key=lambda kv: -kv[1]):
            pct = count / non_air * 100 if non_air else 0
            color = BLOCK_COLORS.get(name, (0.7, 0.7, 0.75))
            if color:
                hex_color = "#{:02x}{:02x}{:02x}".format(
                    int(color[0]*255), int(color[1]*255), int(color[2]*255))
                swatch = f'<span style="color:{hex_color};">&#9608;</span>'
            else:
                swatch = ""
            html += f"{swatch} {name}:{count:,} ({pct:.0f}%) &nbsp; "

        html += "</td></tr></table>"

        self.info_panel.setHtml(html)

    def export_json(self):
        if not self.current_structure:
            QMessageBox.information(self, "Info", "Aucune structure chargee.")
            return

        s = self.current_structure
        default_path = os.path.join(
            os.path.dirname(_SCRIPT_DIR), "structures", s.name + ".json")

        path, _ = QFileDialog.getSaveFileName(
            self, "Exporter en JSON ClaudeCraft", default_path, "JSON (*.json)")
        if not path:
            return

        # Aplatir en 1D
        sx, sy, sz = s.size
        flat = []
        for y in range(sy):
            for z in range(sz):
                for x in range(sx):
                    flat.append(s.blocks[y][z][x])

        rle = encode_rle(flat)

        output = {
            "name": s.name,
            "size": list(s.size),
            "palette": s.palette,
            "blocks_rle": rle
        }

        with open(path, 'w', encoding='utf-8') as f:
            json.dump(output, f, separators=(',', ':'))

        file_size = os.path.getsize(path)
        self.statusBar().showMessage(
            f"Exporte vers {os.path.basename(path)} ({file_size:,} octets)")

    # ---- Drag and Drop ----

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event):
        urls = event.mimeData().urls()
        if urls:
            path = urls[0].toLocalFile()
            if path:
                self.load_file(path)


# ============================================================
# MAIN
# ============================================================

def main():
    # Surface format pour antialiasing
    fmt = QSurfaceFormat()
    fmt.setSamples(4)
    fmt.setDepthBufferSize(24)
    QSurfaceFormat.setDefaultFormat(fmt)

    app = QApplication(sys.argv)
    app.setApplicationName("ClaudeCraft Structure Viewer")
    app.setStyle("Fusion")

    # Style sombre
    app.setStyleSheet("""
        QMainWindow { background-color: #1e1e2e; }
        QToolBar { background-color: #181825; border: none; padding: 4px; spacing: 6px; }
        QToolBar QToolButton { color: #cdd6f4; background: #313244; border: 1px solid #45475a;
                               padding: 4px 10px; border-radius: 4px; font-size: 12px; }
        QToolBar QToolButton:hover { background: #45475a; }
        QStatusBar { background-color: #181825; color: #a6adc8; font-size: 11px; }
        QSplitter::handle { background-color: #45475a; width: 2px; }
        QSplitter::handle:horizontal { width: 3px; }
    """)

    viewer = StructureViewer()
    viewer.show()

    # Charger un fichier depuis la ligne de commande
    if len(sys.argv) > 1:
        path = sys.argv[1]
        if os.path.exists(path):
            QTimer.singleShot(200, lambda: viewer.load_file(path))
        else:
            print(f"Fichier introuvable : {path}")

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
