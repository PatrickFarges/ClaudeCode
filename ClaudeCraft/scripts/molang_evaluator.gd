## MolangEvaluator v1.0.0
## Évaluateur d'expressions Molang (Minecraft Bedrock Edition)
## Parse, cache et évalue des expressions Molang pour le moteur d'animation Bedrock.
## Supporte : arithmétique, comparaisons, logique, ternaire, fonctions math.*,
## variables (variable.*, query.*, temp.*, context.*), mot-clé 'this', tableaux [x,y,z].
##
## Changelog :
## v1.0.0 - Implémentation initiale : tokenizer + parser récursif descent + évaluateur AST

class_name MolangEvaluator

# ─── AST Node Types ──────────────────────────────────────────────────────────
# AST = Array : [TYPE, ...data]
const N_NUMBER   := 0  # [0, float_value]
const N_VAR      := 1  # [1, "variable.name"]
const N_FUNC     := 2  # [2, "math.sin", [arg_nodes]]
const N_BINOP    := 3  # [3, op_char, left_node, right_node]
const N_UNOP     := 4  # [4, op_char, expr_node]
const N_TERNARY  := 5  # [5, cond_node, true_node, false_node]
const N_THIS     := 6  # [6]
const N_ARRAY    := 7  # [7, [element_nodes]]
const N_MULTI    := 8  # [8, [statement_nodes]]  (semicolon-separated, returns last)

# ─── Token Types ─────────────────────────────────────────────────────────────
const T_NUM   := 0
const T_IDENT := 1
const T_OP    := 2   # +, -, *, /, <, >, !, =, &, |, ?, :
const T_LPAR  := 3   # (
const T_RPAR  := 4   # )
const T_LBRAK := 5   # [
const T_RBRAK := 6   # ]
const T_DOT   := 7   # .
const T_COMMA := 8   # ,
const T_SEMI  := 9   # ;
const T_EOF   := 10

# ─── State ───────────────────────────────────────────────────────────────────
var context: Dictionary = {}   # Flat dict for all variables/queries
var this_value: float = 0.0    # Current 'this' value

# Cache: expression string -> AST node
var _cache: Dictionary = {}

# Parser state
var _tokens: Array = []
var _pos: int = 0


# ─── Public API ──────────────────────────────────────────────────────────────

## Parse et cache une expression. Retourne le noeud AST.
func parse(expr: String) -> Array:
	if expr in _cache:
		return _cache[expr]
	var ast := _parse_expr(expr)
	_cache[expr] = ast
	return ast


## Évalue une expression (string ou AST déjà parsé).
## this_val = valeur courante du canal (pour le mot-clé 'this').
func evaluate(expr, this_val: float = 0.0) -> float:
	this_value = this_val
	var node: Array
	if expr is String:
		if expr.is_empty():
			return 0.0
		node = parse(expr)
	else:
		node = expr
	return _eval(node)


## Évalue un tableau [x, y, z] où chaque élément peut être un nombre ou une expression Molang.
## Retourne Vector3.
func evaluate_vec3(arr: Array, this_vals: Vector3 = Vector3.ZERO) -> Vector3:
	var result := Vector3.ZERO
	for i in range(mini(arr.size(), 3)):
		var v = arr[i]
		if v is float or v is int:
			result[i] = float(v)
		elif v is String:
			this_value = this_vals[i]
			result[i] = evaluate(v, this_vals[i])
		elif v is Array:
			this_value = this_vals[i]
			result[i] = _eval(v)
	return result


## Raccourci pour set un variable/query dans le contexte.
func set_var(key: String, value: float) -> void:
	context[key] = value


## Raccourci pour get un variable/query du contexte.
func get_var(key: String, default: float = 0.0) -> float:
	return context.get(key, default)


## Vide le cache d'expressions.
func clear_cache() -> void:
	_cache.clear()


# ─── Tokenizer ───────────────────────────────────────────────────────────────

func _tokenize(expr: String) -> Array:
	var tokens: Array = []
	var i := 0
	var len := expr.length()

	while i < len:
		var c := expr[i]

		# Whitespace
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue

		# Numbers
		if c >= "0" and c <= "9":
			var start := i
			while i < len and ((expr[i] >= "0" and expr[i] <= "9") or expr[i] == "."):
				i += 1
			# Handle trailing 'f' (Bedrock sometimes uses 0.0f)
			if i < len and expr[i] == "f":
				i += 1
			tokens.append([T_NUM, expr.substr(start, i - start).replace("f", "").to_float()])
			continue

		# Identifiers (a-z, A-Z, _)
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_":
			var start := i
			while i < len and ((expr[i] >= "a" and expr[i] <= "z") or (expr[i] >= "A" and expr[i] <= "Z") or (expr[i] >= "0" and expr[i] <= "9") or expr[i] == "_"):
				i += 1
			tokens.append([T_IDENT, expr.substr(start, i - start)])
			continue

		# Two-character operators
		if i + 1 < len:
			var two := expr.substr(i, 2)
			if two == "==" or two == "!=" or two == "<=" or two == ">=" or two == "&&" or two == "||" or two == "??" or two == "->":
				tokens.append([T_OP, two])
				i += 2
				continue

		# Single-character tokens
		match c:
			"(": tokens.append([T_LPAR, "("]); i += 1
			")": tokens.append([T_RPAR, ")"]); i += 1
			"[": tokens.append([T_LBRAK, "["]); i += 1
			"]": tokens.append([T_RBRAK, "]"]); i += 1
			".": tokens.append([T_DOT, "."]); i += 1
			",": tokens.append([T_COMMA, ","]); i += 1
			";": tokens.append([T_SEMI, ";"]); i += 1
			"+", "-", "*", "/", "<", ">", "!", "?", ":":
				tokens.append([T_OP, c]); i += 1
			"'":
				# String literal (skip, return 0 for now)
				i += 1
				while i < len and expr[i] != "'":
					i += 1
				if i < len:
					i += 1
				tokens.append([T_NUM, 0.0])
			_:
				i += 1  # Skip unknown

	tokens.append([T_EOF, ""])
	return tokens


# ─── Parser (Recursive Descent) ─────────────────────────────────────────────

func _parse_expr(expr: String) -> Array:
	_tokens = _tokenize(expr)
	_pos = 0
	var result := _p_multi_statement()
	return result


func _peek() -> Array:
	if _pos < _tokens.size():
		return _tokens[_pos]
	return [T_EOF, ""]

func _advance() -> Array:
	var t := _peek()
	_pos += 1
	return t

func _expect(type: int) -> Array:
	var t := _advance()
	return t


# multi_statement := ternary (';' ternary)*
func _p_multi_statement() -> Array:
	var stmts: Array = [_p_ternary()]
	while _peek()[0] == T_SEMI:
		_advance()  # consume ;
		if _peek()[0] == T_EOF:
			break
		stmts.append(_p_ternary())
	if stmts.size() == 1:
		return stmts[0]
	return [N_MULTI, stmts]


# ternary := or ('?' ternary ':' ternary)?
func _p_ternary() -> Array:
	var expr := _p_or()
	if _peek()[0] == T_OP and _peek()[1] == "?":
		_advance()  # consume ?
		var true_val := _p_ternary()
		if _peek()[0] == T_OP and _peek()[1] == ":":
			_advance()  # consume :
		var false_val := _p_ternary()
		return [N_TERNARY, expr, true_val, false_val]
	return expr


# or := and ('||' and)*
func _p_or() -> Array:
	var left := _p_and()
	while _peek()[0] == T_OP and _peek()[1] == "||":
		_advance()
		var right := _p_and()
		left = [N_BINOP, "||", left, right]
	return left


# and := null_coalesce ('&&' null_coalesce)*
func _p_and() -> Array:
	var left := _p_null_coalesce()
	while _peek()[0] == T_OP and _peek()[1] == "&&":
		_advance()
		var right := _p_null_coalesce()
		left = [N_BINOP, "&&", left, right]
	return left


# null_coalesce := comparison ('??' comparison)?
func _p_null_coalesce() -> Array:
	var left := _p_comparison()
	if _peek()[0] == T_OP and _peek()[1] == "??":
		_advance()
		var right := _p_comparison()
		left = [N_BINOP, "??", left, right]
	return left


# comparison := addition (('==' | '!=' | '<' | '<=' | '>' | '>=') addition)?
func _p_comparison() -> Array:
	var left := _p_addition()
	var p := _peek()
	if p[0] == T_OP and (p[1] == "==" or p[1] == "!=" or p[1] == "<" or p[1] == "<=" or p[1] == ">" or p[1] == ">="):
		var op: String = _advance()[1]
		var right := _p_addition()
		left = [N_BINOP, op, left, right]
	return left


# addition := multiplication (('+' | '-') multiplication)*
func _p_addition() -> Array:
	var left := _p_multiplication()
	while _peek()[0] == T_OP and (_peek()[1] == "+" or _peek()[1] == "-"):
		var op: String = _advance()[1]
		var right := _p_multiplication()
		left = [N_BINOP, op, left, right]
	return left


# multiplication := unary (('*' | '/') unary)*
func _p_multiplication() -> Array:
	var left := _p_unary()
	while _peek()[0] == T_OP and (_peek()[1] == "*" or _peek()[1] == "/"):
		var op: String = _advance()[1]
		var right := _p_unary()
		left = [N_BINOP, op, left, right]
	return left


# unary := ('-' | '!') unary | postfix
func _p_unary() -> Array:
	var p := _peek()
	if p[0] == T_OP and p[1] == "-":
		_advance()
		var expr := _p_unary()
		# Optimize: -(number) -> number
		if expr[0] == N_NUMBER:
			return [N_NUMBER, -expr[1]]
		return [N_UNOP, "-", expr]
	if p[0] == T_OP and p[1] == "!":
		_advance()
		return [N_UNOP, "!", _p_unary()]
	return _p_postfix()


# postfix := primary ('.' IDENT ('(' args ')')? )*
# Handles: math.sin(x), variable.name, query.func(args)
func _p_postfix() -> Array:
	var expr := _p_primary()

	# Handle dotted identifiers: math.sin, variable.attack_time, etc.
	if expr[0] == N_VAR:
		var name: String = expr[1]
		while _peek()[0] == T_DOT:
			_advance()  # consume .
			if _peek()[0] == T_IDENT:
				name += "." + _advance()[1]
			elif _peek()[0] == T_NUM:
				# Edge case: something.0 (shouldn't happen but safety)
				name += "." + str(_advance()[1])

		# Expand abbreviations
		name = _expand_shorthand(name)

		# Check if it's a function call
		if _peek()[0] == T_LPAR:
			_advance()  # consume (
			var args: Array = []
			if _peek()[0] != T_RPAR:
				args.append(_p_ternary())
				while _peek()[0] == T_COMMA:
					_advance()
					args.append(_p_ternary())
			if _peek()[0] == T_RPAR:
				_advance()  # consume )
			return [N_FUNC, name, args]

		# It's a variable/query access or constant
		if name == "math.pi":
			return [N_NUMBER, PI]
		return [N_VAR, name]

	return expr


# primary := NUMBER | 'this' | 'true' | 'false' | '(' expression ')' | '[' array ']' | IDENT
func _p_primary() -> Array:
	var p := _peek()

	# Number
	if p[0] == T_NUM:
		_advance()
		return [N_NUMBER, p[1]]

	# Identifier
	if p[0] == T_IDENT:
		var name: String = _advance()[1]
		# Keywords
		match name:
			"this":
				return [N_THIS]
			"true":
				return [N_NUMBER, 1.0]
			"false":
				return [N_NUMBER, 0.0]
			"return":
				return _p_ternary()
			"loop":
				# loop(count, expr)
				if _peek()[0] == T_LPAR:
					_advance()
					var count_node := _p_ternary()
					if _peek()[0] == T_COMMA:
						_advance()
					var body_node := _p_ternary()
					if _peek()[0] == T_RPAR:
						_advance()
					return [N_FUNC, "loop", [count_node, body_node]]
				return [N_VAR, name]
		return [N_VAR, name]

	# Parenthesized expression
	if p[0] == T_LPAR:
		_advance()
		var expr := _p_multi_statement()
		if _peek()[0] == T_RPAR:
			_advance()
		return expr

	# Array literal [x, y, z]
	if p[0] == T_LBRAK:
		_advance()
		var elems: Array = []
		if _peek()[0] != T_RBRAK:
			elems.append(_p_ternary())
			while _peek()[0] == T_COMMA:
				_advance()
				elems.append(_p_ternary())
		if _peek()[0] == T_RBRAK:
			_advance()
		return [N_ARRAY, elems]

	# Fallback: skip and return 0
	_advance()
	return [N_NUMBER, 0.0]


# ─── Shorthand expansion ────────────────────────────────────────────────────

func _expand_shorthand(name: String) -> String:
	if name.begins_with("q."):
		return "query." + name.substr(2)
	if name.begins_with("v."):
		return "variable." + name.substr(2)
	if name.begins_with("m."):
		return "math." + name.substr(2)
	if name.begins_with("c."):
		return "context." + name.substr(2)
	if name.begins_with("t."):
		return "temp." + name.substr(2)
	return name


# ─── Evaluator ───────────────────────────────────────────────────────────────

func _eval(node: Array) -> float:
	match node[0]:
		N_NUMBER:
			return node[1]

		N_THIS:
			return this_value

		N_VAR:
			return context.get(node[1], 0.0)

		N_UNOP:
			var val := _eval(node[2])
			if node[1] == "-":
				return -val
			else:  # "!"
				return 0.0 if val != 0.0 else 1.0

		N_BINOP:
			return _eval_binop(node[1], node[2], node[3])

		N_TERNARY:
			var cond := _eval(node[1])
			if cond != 0.0:
				return _eval(node[2])
			else:
				return _eval(node[3])

		N_FUNC:
			return _eval_func(node[1], node[2])

		N_ARRAY:
			# Return first element (for single-value contexts)
			var elems: Array = node[1]
			if elems.is_empty():
				return 0.0
			return _eval(elems[0])

		N_MULTI:
			# Evaluate all statements, return last
			var stmts: Array = node[1]
			var result := 0.0
			for stmt in stmts:
				result = _eval(stmt)
			return result

	return 0.0


func _eval_binop(op: String, left_node: Array, right_node: Array) -> float:
	# Short-circuit for logical operators
	if op == "&&":
		var l := _eval(left_node)
		if l == 0.0:
			return 0.0
		return 1.0 if _eval(right_node) != 0.0 else 0.0
	if op == "||":
		var l := _eval(left_node)
		if l != 0.0:
			return 1.0
		return 1.0 if _eval(right_node) != 0.0 else 0.0

	var l := _eval(left_node)
	var r := _eval(right_node)

	match op:
		"+": return l + r
		"-": return l - r
		"*": return l * r
		"/": return r if r == 0.0 else l / r  # Protection div by zero
		"<": return 1.0 if l < r else 0.0
		"<=": return 1.0 if l <= r else 0.0
		">": return 1.0 if l > r else 0.0
		">=": return 1.0 if l >= r else 0.0
		"==": return 1.0 if absf(l - r) < 0.0001 else 0.0
		"!=": return 1.0 if absf(l - r) >= 0.0001 else 0.0
		"??": return l if l != 0.0 else r

	return 0.0


func _eval_func(name: String, args: Array) -> float:
	var argc := args.size()

	match name:
		# ─── Trigonométrie (entrée en degrés) ────────────────────────────
		"math.sin":
			return sin(deg_to_rad(_eval(args[0]))) if argc > 0 else 0.0
		"math.cos":
			return cos(deg_to_rad(_eval(args[0]))) if argc > 0 else 0.0
		"math.asin":
			return rad_to_deg(asin(clampf(_eval(args[0]), -1.0, 1.0))) if argc > 0 else 0.0
		"math.acos":
			return rad_to_deg(acos(clampf(_eval(args[0]), -1.0, 1.0))) if argc > 0 else 0.0
		"math.atan":
			return rad_to_deg(atan(_eval(args[0]))) if argc > 0 else 0.0
		"math.atan2":
			if argc >= 2:
				return rad_to_deg(atan2(_eval(args[0]), _eval(args[1])))
			return 0.0

		# ─── Math de base ────────────────────────────────────────────────
		"math.abs":
			return absf(_eval(args[0])) if argc > 0 else 0.0
		"math.ceil":
			return ceilf(_eval(args[0])) if argc > 0 else 0.0
		"math.floor":
			return floorf(_eval(args[0])) if argc > 0 else 0.0
		"math.round":
			return roundf(_eval(args[0])) if argc > 0 else 0.0
		"math.trunc":
			return float(int(_eval(args[0]))) if argc > 0 else 0.0
		"math.sign":
			return signf(_eval(args[0])) if argc > 0 else 0.0
		"math.sqrt":
			return sqrt(maxf(0.0, _eval(args[0]))) if argc > 0 else 0.0
		"math.pow":
			if argc >= 2:
				return pow(_eval(args[0]), _eval(args[1]))
			return 0.0
		"math.exp":
			return exp(_eval(args[0])) if argc > 0 else 0.0
		"math.ln":
			var v := _eval(args[0]) if argc > 0 else 0.0
			return log(v) if v > 0.0 else 0.0
		"math.mod":
			if argc >= 2:
				var denom := _eval(args[1])
				return fmod(_eval(args[0]), denom) if denom != 0.0 else 0.0
			return 0.0
		"math.min":
			if argc >= 2:
				return minf(_eval(args[0]), _eval(args[1]))
			return _eval(args[0]) if argc > 0 else 0.0
		"math.max":
			if argc >= 2:
				return maxf(_eval(args[0]), _eval(args[1]))
			return _eval(args[0]) if argc > 0 else 0.0
		"math.clamp":
			if argc >= 3:
				return clampf(_eval(args[0]), _eval(args[1]), _eval(args[2]))
			return _eval(args[0]) if argc > 0 else 0.0

		# ─── Interpolation ───────────────────────────────────────────────
		"math.lerp":
			if argc >= 3:
				var a := _eval(args[0])
				var b := _eval(args[1])
				var t := _eval(args[2])
				return a + (b - a) * t
			return 0.0
		"math.lerprotate":
			if argc >= 3:
				var a := _eval(args[0])
				var b := _eval(args[1])
				var t := _eval(args[2])
				var diff := fmod(b - a + 180.0, 360.0) - 180.0
				return a + diff * t
			return 0.0
		"math.inverse_lerp":
			if argc >= 3:
				var a := _eval(args[0])
				var b := _eval(args[1])
				var v := _eval(args[2])
				var d := b - a
				return (v - a) / d if d != 0.0 else 0.0
			return 0.0
		"math.hermite_blend":
			if argc > 0:
				var t := _eval(args[0])
				return 3.0 * t * t - 2.0 * t * t * t
			return 0.0

		# ─── Random ──────────────────────────────────────────────────────
		"math.random":
			if argc >= 2:
				var lo := _eval(args[0])
				var hi := _eval(args[1])
				return randf_range(lo, hi)
			return randf()
		"math.random_integer":
			if argc >= 2:
				return float(randi_range(int(_eval(args[0])), int(_eval(args[1]))))
			return 0.0
		"math.die_roll":
			if argc >= 3:
				var n := int(_eval(args[0]))
				var lo := _eval(args[1])
				var hi := _eval(args[2])
				var total := 0.0
				for _i in range(mini(n, 1024)):
					total += randf_range(lo, hi)
				return total
			return 0.0
		"math.die_roll_integer":
			if argc >= 3:
				var n := int(_eval(args[0]))
				var lo := int(_eval(args[1]))
				var hi := int(_eval(args[2]))
				var total := 0.0
				for _i in range(mini(n, 1024)):
					total += float(randi_range(lo, hi))
				return total
			return 0.0

		# ─── Misc ────────────────────────────────────────────────────────
		"math.copy_sign":
			if argc >= 2:
				var mag := absf(_eval(args[0]))
				var s := _eval(args[1])
				return mag if s >= 0.0 else -mag
			return 0.0
		"math.min_angle":
			if argc > 0:
				var a := fmod(_eval(args[0]), 360.0)
				if a > 180.0: a -= 360.0
				elif a < -180.0: a += 360.0
				return a
			return 0.0

		# ─── Loop ────────────────────────────────────────────────────────
		"loop":
			if argc >= 2:
				var count := mini(int(_eval(args[0])), 1024)
				var result := 0.0
				for _i in range(count):
					result = _eval(args[1])
				return result
			return 0.0

		# ─── Query functions with args ───────────────────────────────────
		# query.position(axis), query.head_x_rotation(n), etc.
		_:
			if name.begins_with("query.") or name.begins_with("context."):
				# Try context with args appended
				if argc > 0:
					var key := name + "." + str(int(_eval(args[0])))
					return context.get(key, context.get(name, 0.0))
				return context.get(name, 0.0)
			# Unknown function: return 0
			return 0.0

	return 0.0
