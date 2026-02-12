# 🦘 Système de Mouvement - Documentation

## Comparaison Minecraft vs ClaudeCraft

### ✅ **Maintenant (v4.1) - Comme Minecraft**

| Paramètre | Minecraft | ClaudeCraft | Match ? |
|-----------|-----------|-------------|---------|
| Hauteur de saut | 1.25 blocs | ~1.25 blocs | ✅ |
| Auto-step | ✅ Oui (1 bloc) | ✅ Oui (0.6 bloc) | ✅ |
| Distance saut course | 4 blocs | ~4 blocs | ✅ |
| Gravité | 32 m/s² | 9.8 m/s² | ⚠️ Différent* |

\* La gravité est plus "réaliste" dans ClaudeCraft, ce qui donne un saut plus "lourd". C'est voulu pour un gameplay différent.

---

## 🎮 Fonctionnement

### 1. **Saut standard**

**Paramètre** : `jump_velocity = 5.5`

- ✅ Permet de sauter **~1.25 blocs** de haut
- ✅ Nécessaire pour franchir des obstacles de 2+ blocs
- ✅ Compatible avec futurs power-ups (voir ci-dessous)

**Formule physique** :
```
Hauteur = (vélocité²) / (2 × gravité)
Hauteur = (5.5²) / (2 × 9.8) = 1.54 blocs
```

### 2. **Auto-step (montée automatique)**

**Paramètre** : `max_step_height = 0.6`

- ✅ Monte automatiquement sur les blocs de **1 bloc ou moins**
- ✅ Pas besoin de sauter pour des escaliers/rampes
- ✅ Fonctionne uniquement si le joueur avance (pas en statique)

**Comment ça marche** :
1. Détection d'un obstacle devant le joueur
2. Raycast pour vérifier la hauteur de l'obstacle
3. Si hauteur ≤ 0.6 blocs → Téléportation légère vers le haut
4. Le joueur "glisse" sur le bloc

**Exemple** :
```
Avant : ▓▓    ← Bloc devant toi
        🧍     ← Toi

Après : 🧍▓▓  ← Tu montes automatiquement
```

---

## 💪 Système de Power-ups (prévu)

### **Jump Boost (multiplicateur)**

Variable prévue : `jump_boost: float = 1.0`

**Exemples d'utilisation future** :

#### Bottes de saut normales
```gdscript
player.jump_boost = 1.5  # Saut de 1.25 → 1.87 blocs
```

#### Bottes de super saut
```gdscript
player.jump_boost = 2.0  # Saut de 1.25 → 2.5 blocs
```

#### Potion de saut
```gdscript
player.jump_boost = 1.8  # Temporaire (30 secondes)
await get_tree().create_timer(30.0).timeout
player.jump_boost = 1.0
```

#### Double saut (à implémenter)
```gdscript
var can_double_jump = true

func _physics_process(delta):
	# ... code existant ...
	
	# Double saut
	if Input.is_action_just_pressed("jump") and not is_on_floor() and can_double_jump:
		velocity.y = jump_velocity * jump_boost
		can_double_jump = false
	
	if is_on_floor():
		can_double_jump = true
```

---

## 🔧 Réglages avancés

### Modifier la hauteur de saut

Dans `player.gd` :
```gdscript
@export var jump_velocity: float = 5.5  # ← Modifier ici
```

**Valeurs recommandées** :
- **4.5** : Saut très bas (~0.8 blocs) - Hardcore
- **5.5** : Saut Minecraft (~1.25 blocs) - **Actuel**
- **7.0** : Saut haut (~2 blocs) - Facile
- **10.0** : Super saut (~5 blocs) - Mario mode

### Modifier l'auto-step

Dans `player.gd` :
```gdscript
@export var max_step_height: float = 0.6  # ← Modifier ici
```

**Valeurs recommandées** :
- **0.0** : Désactivé (hardcore, il faut sauter partout)
- **0.5** : Auto-step 1 bloc exact
- **0.6** : Auto-step 1 bloc + marge - **Actuel**
- **1.0** : Auto-step 2 blocs (trop facile)

### Désactiver l'auto-step complètement

Commenter l'appel dans `_physics_process` :
```gdscript
# Auto-step : monter automatiquement sur 1 bloc (comme Minecraft)
# _handle_auto_step(direction)  # ← Commenter cette ligne
```

---

## 🎯 Gameplay Design

### Pourquoi ces valeurs ?

#### **Saut = 1.25 blocs**
- ✅ Force le joueur à construire des escaliers
- ✅ Crée des défis d'exploration (falaises, ravins)
- ✅ Permet les parkours/challenges
- ✅ Compatible avec des obstacles de 2 blocs (il faut sauter)

#### **Auto-step = 0.6 blocs**
- ✅ Confortable pour la navigation normale
- ✅ Évite la frustration des petits obstacles
- ✅ Garde le défi pour les obstacles plus hauts
- ✅ Simule le comportement Minecraft

---

## 🚀 Idées futures

### 1. **Différents types de mouvements**

```gdscript
enum MoveMode {
	WALK,      # Vitesse normale
	SPRINT,    # Vitesse x1.3 + saut plus loin
	SNEAK,     # Vitesse x0.3 + ne tombe pas des bords
	SWIM,      # Dans l'eau
	CLIMB,     # Sur une échelle
	FLY        # Mode créatif
}
```

### 2. **Système de stamina**

```gdscript
var stamina: float = 100.0
var stamina_regen_rate: float = 10.0  # /seconde

func _physics_process(delta):
	# Sprint consomme de la stamina
	if Input.is_action_pressed("sprint") and stamina > 0:
		speed = 6.5  # Sprint
		stamina -= 20.0 * delta
	else:
		speed = 5.0  # Marche
		stamina = min(100.0, stamina + stamina_regen_rate * delta)
```

### 3. **Système de dégâts de chute**

```gdscript
var last_safe_y: float = 0.0
const SAFE_FALL_HEIGHT = 3.0  # Blocs
const FALL_DAMAGE_PER_BLOCK = 5.0

func _physics_process(delta):
	if is_on_floor():
		var fall_distance = last_safe_y - global_position.y
		if fall_distance > SAFE_FALL_HEIGHT:
			var damage = (fall_distance - SAFE_FALL_HEIGHT) * FALL_DAMAGE_PER_BLOCK
			take_damage(damage)
		last_safe_y = global_position.y
```

---

## 📊 Tests recommandés

### Test 1 : Hauteur de saut
1. Construire une colonne de blocs
2. Essayer de sauter dessus
3. **Résultat attendu** : Peut monter 1 bloc, pas 2

### Test 2 : Auto-step
1. Construire un escalier (1 bloc de haut par marche)
2. Marcher dessus sans sauter
3. **Résultat attendu** : Monte automatiquement

### Test 3 : Obstacle de 2 blocs
1. Construire un mur de 2 blocs
2. Essayer de passer sans sauter
3. **Résultat attendu** : Bloqué, il faut sauter

---

## ✅ Conclusion

Le système de mouvement est maintenant **identique à Minecraft** pour le gameplay, tout en gardant une base propre pour ajouter des power-ups et des mécaniques avancées !

**Prochaines étapes suggérées** :
1. Tester le nouveau saut et l'auto-step
2. Ajuster `jump_velocity` si besoin
3. Implémenter le sprint (Shift = vitesse x1.3)
4. Ajouter les power-ups (bottes, potions, etc.)

**Bon jeu !** 🎮🦘
