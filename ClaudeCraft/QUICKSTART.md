# 🚀 Guide de démarrage rapide

## 📥 Installation

1. **Télécharger Godot 4.3+** : https://godotengine.org/download
2. **Ouvrir Godot** et importer le projet
3. Sélectionner le dossier `minecraft_like_project`
4. Cliquer sur "Importer et éditer"

---

## ▶️ Lancer le jeu

1. Dans Godot, ouvrir `scenes/main.tscn`
2. Appuyer sur **F5** ou cliquer sur le bouton "Play"
3. Le jeu se lance, la souris est capturée automatiquement

**Note** : Le joueur spawn à y=50, le terrain se génère en dessous.

---

## 🎮 Contrôles de base

### Mouvement
- **Z/W** : Avancer
- **S** : Reculer
- **Q/A** : Gauche
- **D** : Droite
- **Espace** : Sauter
- **Souris** : Regarder autour

### Blocs
- **Clic gauche** : Casser le bloc visé
- **Clic droit** : Placer un bloc
- **1-5** : Changer de type de bloc

### Système
- **Échap** : Libérer la souris (rappuyer pour re-capturer)
- **F11** : Plein écran (Windows/Linux)

---

## 🛠️ Personnalisation rapide

### Changer les couleurs des blocs

Ouvrir `scripts/block_registry.gd` et modifier les valeurs RGB :

```gdscript
BlockType.GRASS: {
    "color": Color(0.6, 0.9, 0.6, 1.0)  # Modifier ici
}
```

### Changer la distance de rendu

Ouvrir `scenes/main.tscn`, sélectionner `WorldManager` :
- `render_distance` : Distance en chunks (défaut: 4)
- `chunk_load_per_frame` : Chunks chargés/frame (défaut: 2)

### Changer la vitesse du joueur

Ouvrir `scripts/player.gd` :

```gdscript
@export var speed: float = 5.0          # Vitesse de marche
@export var jump_velocity: float = 8.0  # Force du saut
```

### Changer la couleur du ciel

Ouvrir `project.godot` ou modifier dans l'éditeur :
```
[rendering]
environment/defaults/default_clear_color=Color(0.7, 0.85, 0.95, 1)
```

---

## 🐛 Résolution de problèmes

### Le jeu freeze lors du chargement
**Solution** : Réduire `render_distance` dans WorldManager (mettre à 2-3).

### Le joueur traverse le sol
**Cause** : Les chunks ne sont pas encore générés.
**Solution** : Augmenter la position y initiale du joueur (actuellement y=50).

### Les couleurs ne s'affichent pas
**Cause** : Material mal configuré.
**Solution** : Vérifier dans `chunk.gd` que `vertex_color_use_as_albedo = true`.

### La souris ne se capture pas
**Solution** : Cliquer dans la fenêtre du jeu et appuyer sur Échap puis re-cliquer.

---

## 📚 Aller plus loin

- Lire `ARCHITECTURE.md` pour comprendre le code
- Lire `README.md` pour les fonctionnalités
- Expérimenter avec les paramètres dans l'éditeur Godot

---

## 💡 Astuces

### Tester rapidement un nouveau bloc
1. Ouvrir `block_registry.gd`
2. Ajouter le bloc dans l'enum et le dictionnaire
3. Ouvrir `player.gd` et l'ajouter à `hotbar_slots`
4. Relancer le jeu (F5)

### Optimiser les performances
- Réduire `render_distance` (2-3 chunks)
- Réduire `chunk_load_per_frame` (1 chunk/frame)
- Activer VSync dans les paramètres Godot

### Débugger la génération
Dans `chunk.gd`, ajouter des prints :
```gdscript
func generate_terrain():
    print("Generating chunk at ", chunk_position)
    # ...
```

---

**Bon jeu !** 🎮✨
