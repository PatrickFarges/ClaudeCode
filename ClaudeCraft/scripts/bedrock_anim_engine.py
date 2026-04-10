"""
bedrock_anim_engine.py v1.1.0
Moteur d'animation Bedrock en Python (pour character_viewer.py et mob_gallery.py).
Contient l'evaluateur Molang et le chargeur/joueur d'animations Bedrock JSON.

Changelog:
    v1.1.0 - Entity defs versionnees (horse_v3 etc.), guess anim ameliore
             (common.look_at_target, fichiers _v3), scripts.animate legacy,
             has_bedrock_animations() pour filtrage galerie
    v1.0.0 - Implementation initiale : Molang parser + evaluator + animation player
"""

APP_VERSION = "1.1.0"

import math
import json
import os
import random
from pathlib import Path

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Molang Evaluator
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# AST node types
N_NUMBER, N_VAR, N_FUNC, N_BINOP, N_UNOP, N_TERNARY, N_THIS, N_ARRAY, N_MULTI = range(9)

# Token types
T_NUM, T_IDENT, T_OP, T_LPAR, T_RPAR, T_LBRAK, T_RBRAK, T_DOT, T_COMMA, T_SEMI, T_EOF = range(11)


class MolangEvaluator:
    """Parse et evalue des expressions Molang (Minecraft Bedrock Edition)."""

    def __init__(self):
        self.context = {}       # All variables/queries
        self.this_value = 0.0   # Current 'this' value
        self._cache = {}        # expr string -> AST

    def set_var(self, key, value):
        self.context[key] = float(value)

    def get_var(self, key, default=0.0):
        return self.context.get(key, default)

    def parse(self, expr):
        if expr in self._cache:
            return self._cache[expr]
        ast = self._parse_expr(expr)
        self._cache[expr] = ast
        return ast

    def evaluate(self, expr, this_val=0.0):
        self.this_value = this_val
        if isinstance(expr, str):
            if not expr.strip():
                return 0.0
            node = self.parse(expr)
        else:
            node = expr
        return self._eval(node)

    def evaluate_vec3(self, arr, this_vals=(0.0, 0.0, 0.0)):
        """Evaluate a [x, y, z] array where each element can be number or expression."""
        result = [0.0, 0.0, 0.0]
        for i in range(min(len(arr), 3)):
            v = arr[i]
            if isinstance(v, (int, float)):
                result[i] = float(v)
            elif isinstance(v, str):
                self.this_value = this_vals[i]
                result[i] = self.evaluate(v, this_vals[i])
            elif isinstance(v, list):
                self.this_value = this_vals[i]
                result[i] = self._eval(v)
        return result

    # ── Tokenizer ────────────────────────────────────────────────────────────

    def _tokenize(self, expr):
        tokens = []
        i, n = 0, len(expr)
        while i < n:
            c = expr[i]
            if c in " \t\n\r":
                i += 1
                continue
            if c.isdigit() or (c == '.' and i + 1 < n and expr[i + 1].isdigit()):
                start = i
                while i < n and (expr[i].isdigit() or expr[i] == '.'):
                    i += 1
                if i < n and expr[i] == 'f':
                    i += 1
                tokens.append((T_NUM, float(expr[start:i].rstrip('f'))))
                continue
            if c.isalpha() or c == '_':
                start = i
                while i < n and (expr[i].isalnum() or expr[i] == '_'):
                    i += 1
                tokens.append((T_IDENT, expr[start:i]))
                continue
            if i + 1 < n:
                two = expr[i:i + 2]
                if two in ('==', '!=', '<=', '>=', '&&', '||', '??', '->'):
                    tokens.append((T_OP, two))
                    i += 2
                    continue
            match c:
                case '(': tokens.append((T_LPAR, c))
                case ')': tokens.append((T_RPAR, c))
                case '[': tokens.append((T_LBRAK, c))
                case ']': tokens.append((T_RBRAK, c))
                case '.': tokens.append((T_DOT, c))
                case ',': tokens.append((T_COMMA, c))
                case ';': tokens.append((T_SEMI, c))
                case "'":
                    i += 1
                    while i < n and expr[i] != "'":
                        i += 1
                    if i < n:
                        i += 1
                    tokens.append((T_NUM, 0.0))
                    continue
                case _:
                    if c in '+-*/<>!?:':
                        tokens.append((T_OP, c))
                    # else skip unknown
            i += 1
        tokens.append((T_EOF, ''))
        return tokens

    # ── Parser ───────────────────────────────────────────────────────────────

    def _parse_expr(self, expr):
        self._tokens = self._tokenize(expr)
        self._pos = 0
        return self._p_multi()

    def _peek(self):
        return self._tokens[self._pos] if self._pos < len(self._tokens) else (T_EOF, '')

    def _advance(self):
        t = self._peek()
        self._pos += 1
        return t

    def _p_multi(self):
        stmts = [self._p_ternary()]
        while self._peek()[0] == T_SEMI:
            self._advance()
            if self._peek()[0] == T_EOF:
                break
            stmts.append(self._p_ternary())
        return stmts[0] if len(stmts) == 1 else (N_MULTI, stmts)

    def _p_ternary(self):
        expr = self._p_or()
        if self._peek() == (T_OP, '?'):
            self._advance()
            true_val = self._p_ternary()
            if self._peek() == (T_OP, ':'):
                self._advance()
            false_val = self._p_ternary()
            return (N_TERNARY, expr, true_val, false_val)
        return expr

    def _p_or(self):
        left = self._p_and()
        while self._peek() == (T_OP, '||'):
            self._advance()
            left = (N_BINOP, '||', left, self._p_and())
        return left

    def _p_and(self):
        left = self._p_comparison()
        while self._peek() == (T_OP, '&&'):
            self._advance()
            left = (N_BINOP, '&&', left, self._p_comparison())
        return left

    def _p_comparison(self):
        left = self._p_addition()
        p = self._peek()
        if p[0] == T_OP and p[1] in ('==', '!=', '<', '<=', '>', '>='):
            op = self._advance()[1]
            left = (N_BINOP, op, left, self._p_addition())
        return left

    def _p_addition(self):
        left = self._p_multiplication()
        while self._peek()[0] == T_OP and self._peek()[1] in ('+', '-'):
            op = self._advance()[1]
            left = (N_BINOP, op, left, self._p_multiplication())
        return left

    def _p_multiplication(self):
        left = self._p_unary()
        while self._peek()[0] == T_OP and self._peek()[1] in ('*', '/'):
            op = self._advance()[1]
            left = (N_BINOP, op, left, self._p_unary())
        return left

    def _p_unary(self):
        p = self._peek()
        if p == (T_OP, '-'):
            self._advance()
            expr = self._p_unary()
            if isinstance(expr, tuple) and expr[0] == N_NUMBER:
                return (N_NUMBER, -expr[1])
            return (N_UNOP, '-', expr)
        if p == (T_OP, '!'):
            self._advance()
            return (N_UNOP, '!', self._p_unary())
        return self._p_postfix()

    def _p_postfix(self):
        expr = self._p_primary()
        if isinstance(expr, tuple) and expr[0] == N_VAR:
            name = expr[1]
            while self._peek()[0] == T_DOT:
                self._advance()
                if self._peek()[0] == T_IDENT:
                    name += '.' + self._advance()[1]
                elif self._peek()[0] == T_NUM:
                    name += '.' + str(self._advance()[1])
            name = self._expand(name)
            if self._peek()[0] == T_LPAR:
                self._advance()
                args = []
                if self._peek()[0] != T_RPAR:
                    args.append(self._p_ternary())
                    while self._peek()[0] == T_COMMA:
                        self._advance()
                        args.append(self._p_ternary())
                if self._peek()[0] == T_RPAR:
                    self._advance()
                return (N_FUNC, name, args)
            if name == 'math.pi':
                return (N_NUMBER, math.pi)
            return (N_VAR, name)
        return expr

    def _p_primary(self):
        p = self._peek()
        if p[0] == T_NUM:
            self._advance()
            return (N_NUMBER, p[1])
        if p[0] == T_IDENT:
            name = self._advance()[1]
            if name == 'this': return (N_THIS,)
            if name == 'true': return (N_NUMBER, 1.0)
            if name == 'false': return (N_NUMBER, 0.0)
            if name == 'return': return self._p_ternary()
            if name == 'loop' and self._peek()[0] == T_LPAR:
                self._advance()
                cnt = self._p_ternary()
                if self._peek()[0] == T_COMMA: self._advance()
                body = self._p_ternary()
                if self._peek()[0] == T_RPAR: self._advance()
                return (N_FUNC, 'loop', [cnt, body])
            return (N_VAR, name)
        if p[0] == T_LPAR:
            self._advance()
            expr = self._p_multi()
            if self._peek()[0] == T_RPAR: self._advance()
            return expr
        if p[0] == T_LBRAK:
            self._advance()
            elems = []
            if self._peek()[0] != T_RBRAK:
                elems.append(self._p_ternary())
                while self._peek()[0] == T_COMMA:
                    self._advance()
                    elems.append(self._p_ternary())
            if self._peek()[0] == T_RBRAK: self._advance()
            return (N_ARRAY, elems)
        self._advance()
        return (N_NUMBER, 0.0)

    def _expand(self, name):
        for short, full in [('q.', 'query.'), ('v.', 'variable.'), ('m.', 'math.'),
                            ('c.', 'context.'), ('t.', 'temp.')]:
            if name.startswith(short):
                return full + name[len(short):]
        return name

    # ── Evaluator ────────────────────────────────────────────────────────────

    def _eval(self, node):
        if not isinstance(node, tuple):
            return 0.0
        t = node[0]
        if t == N_NUMBER: return node[1]
        if t == N_THIS: return self.this_value
        if t == N_VAR: return self.context.get(node[1], 0.0)
        if t == N_UNOP:
            v = self._eval(node[2])
            return -v if node[1] == '-' else (0.0 if v != 0.0 else 1.0)
        if t == N_BINOP: return self._eval_binop(node[1], node[2], node[3])
        if t == N_TERNARY:
            return self._eval(node[2]) if self._eval(node[1]) != 0.0 else self._eval(node[3])
        if t == N_FUNC: return self._eval_func(node[1], node[2])
        if t == N_ARRAY:
            return self._eval(node[1][0]) if node[1] else 0.0
        if t == N_MULTI:
            r = 0.0
            for s in node[1]: r = self._eval(s)
            return r
        return 0.0

    def _eval_binop(self, op, left, right):
        if op == '&&':
            l = self._eval(left)
            return (1.0 if self._eval(right) != 0.0 else 0.0) if l != 0.0 else 0.0
        if op == '||':
            return 1.0 if self._eval(left) != 0.0 else (1.0 if self._eval(right) != 0.0 else 0.0)
        l, r = self._eval(left), self._eval(right)
        match op:
            case '+': return l + r
            case '-': return l - r
            case '*': return l * r
            case '/': return l / r if r != 0 else 0.0
            case '<': return 1.0 if l < r else 0.0
            case '<=': return 1.0 if l <= r else 0.0
            case '>': return 1.0 if l > r else 0.0
            case '>=': return 1.0 if l >= r else 0.0
            case '==': return 1.0 if abs(l - r) < 0.0001 else 0.0
            case '!=': return 1.0 if abs(l - r) >= 0.0001 else 0.0
            case '??': return l if l != 0.0 else r
        return 0.0

    def _eval_func(self, name, args):
        def a(i): return self._eval(args[i]) if i < len(args) else 0.0

        match name:
            case 'math.sin': return math.sin(math.radians(a(0)))
            case 'math.cos': return math.cos(math.radians(a(0)))
            case 'math.asin': return math.degrees(math.asin(max(-1, min(1, a(0)))))
            case 'math.acos': return math.degrees(math.acos(max(-1, min(1, a(0)))))
            case 'math.atan': return math.degrees(math.atan(a(0)))
            case 'math.atan2': return math.degrees(math.atan2(a(0), a(1))) if len(args) >= 2 else 0.0
            case 'math.abs': return abs(a(0))
            case 'math.ceil': return math.ceil(a(0))
            case 'math.floor': return math.floor(a(0))
            case 'math.round': return round(a(0))
            case 'math.trunc': return float(int(a(0)))
            case 'math.sign': return math.copysign(1, a(0)) if a(0) != 0 else 0.0
            case 'math.sqrt': return math.sqrt(max(0, a(0)))
            case 'math.pow': return math.pow(a(0), a(1)) if len(args) >= 2 else 0.0
            case 'math.exp': return math.exp(min(a(0), 700))
            case 'math.ln': v = a(0); return math.log(v) if v > 0 else 0.0
            case 'math.mod': d = a(1); return math.fmod(a(0), d) if d != 0 else 0.0
            case 'math.min': return min(a(0), a(1)) if len(args) >= 2 else a(0)
            case 'math.max': return max(a(0), a(1)) if len(args) >= 2 else a(0)
            case 'math.clamp': return max(a(1), min(a(2), a(0))) if len(args) >= 3 else a(0)
            case 'math.lerp':
                if len(args) >= 3: s, e, t = a(0), a(1), a(2); return s + (e - s) * t
                return 0.0
            case 'math.lerprotate':
                if len(args) >= 3:
                    s, e, t = a(0), a(1), a(2)
                    d = ((e - s + 180) % 360) - 180
                    return s + d * t
                return 0.0
            case 'math.hermite_blend': t = a(0); return 3 * t * t - 2 * t * t * t
            case 'math.random': return random.uniform(a(0), a(1)) if len(args) >= 2 else random.random()
            case 'math.random_integer': return float(random.randint(int(a(0)), int(a(1)))) if len(args) >= 2 else 0.0
            case 'math.copy_sign': return math.copysign(abs(a(0)), a(1)) if len(args) >= 2 else 0.0
            case 'math.min_angle':
                v = a(0) % 360
                if v > 180: v -= 360
                elif v < -180: v += 360
                return v
            case 'loop':
                if len(args) >= 2:
                    cnt = min(int(a(0)), 1024)
                    r = 0.0
                    for _ in range(cnt): r = self._eval(args[1])
                    return r
                return 0.0
            case _:
                if name.startswith('query.') or name.startswith('context.'):
                    if args:
                        key = name + '.' + str(int(a(0)))
                        return self.context.get(key, self.context.get(name, 0.0))
                    return self.context.get(name, 0.0)
                return 0.0


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Euler → Quaternion
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def euler_deg_to_quat(x_deg, y_deg, z_deg):
    """Bedrock euler (degrees, XYZ applied as ZYX intrinsic) -> quaternion [x,y,z,w]."""
    x, y, z = math.radians(x_deg), math.radians(y_deg), math.radians(z_deg)
    cx, sx = math.cos(x / 2), math.sin(x / 2)
    cy, sy = math.cos(y / 2), math.sin(y / 2)
    cz, sz = math.cos(z / 2), math.sin(z / 2)
    return [
        sx * cy * cz - cx * sy * sz,
        cx * sy * cz + sx * cy * sz,
        cx * cy * sz - sx * sy * cz,
        cx * cy * cz + sx * sy * sz,
    ]


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Bedrock Animation Data
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class BedrockAnimation:
    """Represents a single Bedrock animation loaded from JSON."""

    def __init__(self, name, data):
        self.name = name
        self.loop = data.get("loop", False)
        self.length = data.get("animation_length", 0.0)
        self.override_previous = data.get("override_previous_animation", False)
        self.anim_time_update = str(data.get("anim_time_update", ""))
        self.blend_weight_expr = str(data.get("blend_weight", ""))
        self.bones = {}  # bone_name_lower -> {rotation, position, scale}

        for bone_name, bone_data in data.get("bones", {}).items():
            self.bones[bone_name.lower()] = {
                "rotation": bone_data.get("rotation"),
                "position": bone_data.get("position"),
                "scale": bone_data.get("scale"),
            }

        if self.length <= 0:
            self.length = self._detect_length()
        if self.length <= 0:
            self.length = 1.0

    def _detect_length(self):
        max_t = 0.0
        for bone_data in self.bones.values():
            for ch in (bone_data["rotation"], bone_data["position"], bone_data["scale"]):
                if isinstance(ch, dict):
                    for key in ch:
                        try:
                            t = float(key)
                            max_t = max(max_t, t)
                        except (ValueError, TypeError):
                            pass
        return max_t


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Bedrock Animation Player (Python version for viewers)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class BedrockAnimPlayer:
    """Evalue les animations Bedrock et retourne les transformations par bone."""

    def __init__(self):
        self.molang = MolangEvaluator()
        self.animations = {}       # name -> BedrockAnimation
        self.active_anims = []     # [{"name", "weight", "time", "loop", "length"}]
        self.variables = {}        # entity variables
        self.pre_animation = []    # pre-animation scripts
        self.life_time = 0.0
        self.distance_moved = 0.0
        self.move_speed = 0.0
        self.speed_scale = 1.0

    def load_animations_file(self, path):
        """Load all animations from a Bedrock animation JSON file."""
        try:
            with open(path) as f:
                data = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError):
            return 0
        count = 0
        for anim_name, anim_data in data.get("animations", {}).items():
            self.animations[anim_name] = BedrockAnimation(anim_name, anim_data)
            count += 1
        return count

    @staticmethod
    def _find_entity_def(entity_id, entity_dir):
        """Trouve le fichier entity definition (direct ou versionné)."""
        path = os.path.join(entity_dir, f"{entity_id}.entity.json")
        if os.path.exists(path):
            return path
        for v in [3, 2, 1]:
            vpath = os.path.join(entity_dir, f"{entity_id}_v{v}.entity.json")
            if os.path.exists(vpath):
                return vpath
        return None

    @staticmethod
    def _guess_anim_file(full_name, anim_dir):
        """Devine le fichier d'animation à charger depuis le nom complet."""
        parts = full_name.split(".")
        if len(parts) < 3 or parts[0] != "animation":
            return None
        entity = parts[1]
        candidates = [entity + ".animation.json"]
        if len(parts) >= 4:
            candidates.append(entity + "_" + parts[2] + ".animation.json")
        candidates.append(parts[2] + ".animation.json")
        for v in [3, 2, 1]:
            candidates.append(entity + f"_v{v}.animation.json")
        for fname in candidates:
            fpath = os.path.join(anim_dir, fname)
            if os.path.exists(fpath):
                return fpath
        return None

    def load_entity(self, entity_id, data_dir):
        """Configure from entity definition files."""
        entity_dir = os.path.join(data_dir, "entity_definitions")
        anim_dir = os.path.join(data_dir, "animations")

        # Try to load entity definition (direct or versioned)
        entity_path = self._find_entity_def(entity_id, entity_dir)
        if entity_path:
            try:
                with open(entity_path) as f:
                    edata = json.load(f)
            except (json.JSONDecodeError, UnicodeDecodeError):
                entity_path = None  # Fallback si JSON invalide
        if entity_path:
            desc = edata.get("minecraft:client_entity", {}).get("description", {})

            # Pre-animation scripts
            scripts = desc.get("scripts", {})
            for script in scripts.get("pre_animation", []):
                if script:
                    self.pre_animation.append(script)

            # Load animation files
            anim_map = desc.get("animations", {})
            loaded_files = set()
            for short_name, full_name in anim_map.items():
                fpath = self._guess_anim_file(full_name, anim_dir)
                if fpath and fpath not in loaded_files:
                    self.load_animations_file(fpath)
                    loaded_files.add(fpath)

            # scripts.animate legacy (cow, pig, chicken, horse...)
            animate_list = scripts.get("animate", [])
            if animate_list:
                for entry in animate_list:
                    alias = ""
                    if isinstance(entry, str):
                        alias = entry
                    elif isinstance(entry, dict):
                        alias = next(iter(entry), "")
                    if alias and alias in anim_map:
                        full_name = anim_map[alias]
                        fpath = self._guess_anim_file(full_name, anim_dir)
                        if fpath and fpath not in loaded_files:
                            self.load_animations_file(fpath)
                            loaded_files.add(fpath)

            return True

        # Fallback: load entity-specific + humanoid animation files
        for fname in [f"{entity_id}.animation.json", "humanoid.animation.json"]:
            fpath = os.path.join(anim_dir, fname)
            if os.path.exists(fpath):
                self.load_animations_file(fpath)

        # Default pre_animation for humanoids
        self.pre_animation.append(
            "variable.tcos0 = (math.cos(query.modified_distance_moved * 38.17) "
            "* query.modified_move_speed / variable.gliding_speed_value) * 57.3;"
        )
        return len(self.animations) > 0

    def has_bedrock_animations(self):
        """Retourne True si ce player a des animations Bedrock chargées (pas juste le fallback humanoid)."""
        if not self.animations:
            return False
        # Si on a UNIQUEMENT des animations humanoid, c'est un fallback
        humanoid_only = all(
            name.startswith("animation.humanoid.") for name in self.animations
        )
        return not humanoid_only

    def play(self, anim_name, weight=1.0):
        """Start playing an animation."""
        if anim_name not in self.animations:
            return
        # Remove existing
        self.active_anims = [a for a in self.active_anims if a["name"] != anim_name]
        anim = self.animations[anim_name]
        self.active_anims.append({
            "name": anim_name,
            "weight": weight,
            "time": 0.0,
            "loop": anim.loop,
            "length": anim.length,
        })

    def stop(self, anim_name):
        self.active_anims = [a for a in self.active_anims if a["name"] != anim_name]

    def stop_all(self):
        self.active_anims.clear()

    def get_animation_names(self):
        return sorted(self.animations.keys())

    def advance(self, dt):
        """Advance time and return bone transforms."""
        dt *= self.speed_scale
        self.life_time += dt

        # Update context
        self._update_context(dt)

        # Pre-animation scripts
        for script in self.pre_animation:
            self._eval_pre_anim(script)

        # Update animation times
        for entry in self.active_anims:
            anim = self.animations.get(entry["name"])
            if anim and not anim.anim_time_update:
                entry["time"] += dt
                if entry["loop"] and entry["length"] > 0:
                    entry["time"] = entry["time"] % entry["length"]
                elif not entry["loop"]:
                    entry["time"] = min(entry["time"], entry["length"])

        # Compute bone transforms
        return self._compute_bone_transforms()

    def _update_context(self, dt):
        ctx = self.molang.context
        ctx["query.life_time"] = self.life_time % 1000.0
        ctx["query.delta_time"] = dt
        ctx["query.modified_distance_moved"] = self.distance_moved
        ctx["query.modified_move_speed"] = self.move_speed
        ctx["query.ground_speed"] = self.move_speed
        # gliding_speed_value = move speed (normalise le swing des bras/jambes)
        gliding = ctx.get("variable.gliding_speed_value", 0.0)
        if gliding < 0.01:
            ctx["variable.gliding_speed_value"] = max(self.move_speed, 0.1)

        for key, val in self.variables.items():
            ctx["variable." + key] = val

    def _eval_pre_anim(self, script_text):
        for part in script_text.split(";"):
            part = part.strip()
            if not part:
                continue
            eq = part.find("=")
            if eq < 0:
                self.molang.evaluate(part)
                continue
            if eq + 1 < len(part) and part[eq + 1] == "=":
                self.molang.evaluate(part)
                continue
            if eq > 0 and part[eq - 1] == "!":
                self.molang.evaluate(part)
                continue
            var_name = part[:eq].strip()
            expr = part[eq + 1:].strip()
            # Expand shorthands
            for short, full in [("v.", "variable."), ("q.", "query."), ("m.", "math.")]:
                if var_name.startswith(short):
                    var_name = full + var_name[len(short):]
                    break
            # Fix Math -> math
            expr = expr.replace("Math.", "math.")
            value = self.molang.evaluate(expr)
            self.molang.context[var_name] = value

    def _compute_bone_transforms(self):
        """Returns dict: bone_name_lower -> {"rotation": [x,y,z], "position": [x,y,z], "scale": [x,y,z]}"""
        accumulated = {}

        for entry in self.active_anims:
            anim = self.animations.get(entry["name"])
            if not anim:
                continue
            weight = entry["weight"]
            anim_time = entry["time"]
            self.molang.context["query.anim_time"] = anim_time

            for bone_name, bone_data in anim.bones.items():
                if bone_name not in accumulated:
                    accumulated[bone_name] = {
                        "rotation": [0.0, 0.0, 0.0],
                        "position": [0.0, 0.0, 0.0],
                        "scale": [1.0, 1.0, 1.0],
                    }
                acc = accumulated[bone_name]
                current_rot = list(acc["rotation"])

                if bone_data["rotation"] is not None:
                    rot = self._eval_channel(bone_data["rotation"], anim_time, anim.length, current_rot)
                    for i in range(3):
                        acc["rotation"][i] += rot[i] * weight

                if bone_data["position"] is not None:
                    pos = self._eval_channel(bone_data["position"], anim_time, anim.length, [0, 0, 0])
                    for i in range(3):
                        acc["position"][i] += pos[i] * weight

                if bone_data["scale"] is not None:
                    scl = self._eval_scale_channel(bone_data["scale"], anim_time, anim.length)
                    for i in range(3):
                        acc["scale"][i] *= scl[i]

        return accumulated

    def _eval_channel(self, channel, anim_time, anim_length, current):
        if channel is None:
            return [0.0, 0.0, 0.0]
        if isinstance(channel, (int, float)):
            v = float(channel)
            return [v, v, v]
        if isinstance(channel, list):
            return self._eval_vec3_arr(channel, current)
        if isinstance(channel, dict):
            return self._eval_keyframe_timeline(channel, anim_time, current)
        if isinstance(channel, str):
            v = self.molang.evaluate(channel)
            return [v, v, v]
        return [0.0, 0.0, 0.0]

    def _eval_scale_channel(self, channel, anim_time, anim_length):
        if channel is None:
            return [1.0, 1.0, 1.0]
        if isinstance(channel, (int, float)):
            v = float(channel)
            return [v, v, v]
        if isinstance(channel, list):
            return self._eval_vec3_arr(channel, [1.0, 1.0, 1.0])
        if isinstance(channel, dict):
            return self._eval_keyframe_timeline(channel, anim_time, [1.0, 1.0, 1.0])
        if isinstance(channel, str):
            v = self.molang.evaluate(channel)
            return [v, v, v]
        return [1.0, 1.0, 1.0]

    def _eval_vec3_arr(self, arr, current):
        result = [0.0, 0.0, 0.0]
        for i in range(min(len(arr), 3)):
            v = arr[i]
            if isinstance(v, (int, float)):
                result[i] = float(v)
            elif isinstance(v, str):
                self.molang.this_value = current[i]
                result[i] = self.molang.evaluate(v, current[i])
        return result

    def _eval_keyframe_timeline(self, timeline, anim_time, current):
        times = sorted(float(k) for k in timeline.keys())
        if not times:
            return [0.0, 0.0, 0.0]

        t = anim_time
        if t <= times[0]:
            return self._eval_kf_value(timeline[str(times[0])], current, 0.0)
        if t >= times[-1]:
            return self._eval_kf_value(timeline[str(times[-1])], current, 1.0)

        # Find surrounding keyframes
        idx = 0
        for i in range(len(times) - 1):
            if times[i] <= t < times[i + 1]:
                idx = i
                break

        t0, t1 = times[idx], times[idx + 1]
        lerp_t = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
        self.molang.context["query.key_frame_lerp_time"] = lerp_t

        # Get key strings (handle int vs float keys)
        def key_str(tv):
            s = str(tv)
            if s in timeline: return s
            si = str(int(tv))
            if si in timeline: return si
            return s

        val0 = timeline.get(key_str(t0), [0, 0, 0])
        val1 = timeline.get(key_str(t1), [0, 0, 0])

        v0 = self._get_kf_post(val0, current, lerp_t)
        v1 = self._get_kf_pre(val1, current, lerp_t)

        return [v0[i] + (v1[i] - v0[i]) * lerp_t for i in range(3)]

    def _eval_kf_value(self, value, current, lerp_t):
        if isinstance(value, list):
            return self._eval_vec3_arr(value, current)
        if isinstance(value, dict):
            self.molang.context["query.key_frame_lerp_time"] = lerp_t
            if "post" in value:
                return self._eval_vec3_arr(value["post"], current)
            if "pre" in value:
                return self._eval_vec3_arr(value["pre"], current)
        if isinstance(value, (int, float)):
            v = float(value)
            return [v, v, v]
        return [0.0, 0.0, 0.0]

    def _get_kf_post(self, value, current, lerp_t):
        if isinstance(value, list): return self._eval_vec3_arr(value, current)
        if isinstance(value, dict):
            self.molang.context["query.key_frame_lerp_time"] = lerp_t
            if "post" in value: return self._eval_vec3_arr(value["post"], current)
            if "pre" in value: return self._eval_vec3_arr(value["pre"], current)
        if isinstance(value, (int, float)): v = float(value); return [v, v, v]
        return [0.0, 0.0, 0.0]

    def _get_kf_pre(self, value, current, lerp_t):
        if isinstance(value, list): return self._eval_vec3_arr(value, current)
        if isinstance(value, dict):
            self.molang.context["query.key_frame_lerp_time"] = lerp_t
            if "pre" in value: return self._eval_vec3_arr(value["pre"], current)
            if "post" in value: return self._eval_vec3_arr(value["post"], current)
        if isinstance(value, (int, float)): v = float(value); return [v, v, v]
        return [0.0, 0.0, 0.0]


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Utility: list available animations for an entity
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def get_entity_animations(entity_id, data_dir):
    """Returns list of animation names available for the given entity."""
    player = BedrockAnimPlayer()
    player.load_entity(entity_id, data_dir)
    return player.get_animation_names()
