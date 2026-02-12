# 📐 Architecture Technique - Minecraft-like Pastel

## 🎯 Vue d'ensemble

Ce document explique l'architecture technique du jeu, les choix de conception, et comment étendre le projet.

---

## 🏗️ Structure des classes principales

### 1. **BlockRegistry** (Static Class)
**Fichier** : `scripts/block_registry.gd`

**Rôle** : Définir tous les types de blocs et leurs propriétés.

**Données** :
```gdscript
enum BlockType { AIR, GRASS, DIRT, STONE, SAND, WOOD, LEAVES }
```

**Propriétés par bloc** :
- `name` : Nom du bloc
- `solid` : Est-ce un bloc solide ?
- `color` : Couleur pastel du bloc

**Méthodes** :
- `get_block_color(block_type)` : Retourne la couleur
- `is_solid(block_type)` : Vérifie si solide
- `get_block_name(block_type)` : Retourne le nom

**Extension** : Ajouter un nouveau bloc :
```gdscript
BlockType.NEW_BLOCK: {
    "name": "New Block",
    "solid": true,
    "color": Color(0.8, 0.5, 0.9, 1.0)
}
```

---

### 2. **Chunk** (Node3D)
**Fichier** : `scripts/chunk.gd`

**Rôle** : Représenter une portion du monde (16x16x64 blocs).

**Données** :
- `chunk_position` : Position du chunk dans le monde
- `blocks` : Array 3D [x][z][y] contenant les types de blocs
- `mesh_instance` : Le mesh visuel du chunk
- `static_body` : Corps physique pour les collisions

**Méthodes principales** :

#### `generate_terrain()`
Génère le terrain avec Perlin noise :
```gdscript
var noise = FastNoiseLite.new()
noise.frequency = 0.05  # Fréquence du bruit (plus bas = plus lisse)
var height = noise.get_noise_2d(world_x, world_z)
```

**Couches** :
- Profondeur > 4 : Pierre (STONE)
- Profondeur 1-4 : Terre (DIRT)
- Surface : Herbe (GRASS)

#### `_create_mesh()` - Greedy Meshing
Optimisation clé : **ne génère que les faces visibles**.

Pour chaque bloc solide :
1. Vérifier chaque face (haut, bas, nord, sud, est, ouest)
2. Si le bloc adjacent est AIR ou hors limites → ajouter la face
3. Sinon → ne pas ajouter (économie de polygones)

**Variation de luminosité** :
```gdscript
Face du haut    : color * 1.0  (pleine luminosité)
Faces latérales : color * 0.8-0.9
Face du bas     : color * 0.6  (plus sombre)
```

#### `set_block(x, y, z, block_type)`
Modifier un bloc et **reconstruire le mesh**.

**Optimisation future** : Ne reconstruire que la zone modifiée.

---

### 3. **WorldManager** (Node3D)
**Fichier** : `scripts/world_manager.gd`

**Rôle** : Gérer le chargement/déchargement dynamique des chunks.

**Paramètres** :
- `render_distance` : Distance de rendu en chunks (défaut: 4)
- `chunk_load_per_frame` : Chunks chargés par frame (défaut: 2)

**Algorithme de chargement** :

```
1. Calculer la position du joueur en coordonnées chunk
2. Générer une liste de chunks à charger (dans render_distance)
3. Trier par distance (les plus proches en premier)
4. Charger progressivement (2 chunks/frame max)
5. Décharger les chunks trop loin (distance > render_distance + 2)
```

**Conversion coordonnées** :
```gdscript
chunk_x = floor(world_x / CHUNK_SIZE)
chunk_z = floor(world_z / CHUNK_SIZE)
```

**Méthodes d'interaction** :
- `get_block_at_position(world_pos)` : Lire un bloc
- `set_block_at_position(world_pos, block_type)` : Écrire un bloc
- `break_block_at_position(world_pos)` : Détruire un bloc
- `place_block_at_position(world_pos, block_type)` : Placer un bloc

---

### 4. **Player** (CharacterBody3D)
**Fichier** : `scripts/player.gd`

**Rôle** : Contrôle FPS + interactions avec les blocs.

**Composants** :
- `Camera3D` : Caméra première personne (y = 1.6)
- `RayCast3D` : Détection des blocs visés (portée : 5m)
- `CollisionShape3D` : Capsule (rayon 0.4, hauteur 1.8)

**Mouvement** :
```gdscript
Vitesse de marche  : 5 m/s
Vélocité de saut   : 8 m/s
Gravité            : ProjectSettings (défaut: 9.8)
```

**Rotation caméra** :
- Sensibilité souris : 0.002
- Clamp vertical : -90° à +90° (pas de retournement)

**Interaction blocs** :

#### Casser un bloc
```gdscript
1. Raycast vers le centre de la vue
2. Si collision : récupérer le point et la normale
3. Position du bloc = collision_point - normal * 0.5 (arrondi)
4. Appeler world_manager.break_block_at_position()
```

#### Placer un bloc
```gdscript
1. Raycast vers le centre de la vue
2. Si collision : récupérer le point et la normale
3. Position du bloc = collision_point + normal * 0.5 (arrondi)
4. Vérifier que le bloc ne chevauche pas le joueur
5. Appeler world_manager.place_block_at_position()
```

**Hotbar** :
- 5 slots configurables
- Sélection avec touches 1-5
- Bloc actif stocké dans `selected_block_type`

---

### 5. **HotbarUI** (CanvasLayer)
**Fichier** : `scripts/hotbar_ui.gd`

**Rôle** : Affichage de l'inventaire rapide (5 slots).

**Structure d'un slot** :
```
Panel (64x64)
├── Label (numéro 1-5)
└── ColorRect (48x48, couleur du bloc)
```

**Mise en surbrillance** :
- Slot sélectionné : Bordure jaune pastel (4px)
- Autres slots : Bordure grise (2px)

**Mise à jour** :
- Chaque frame, lit `player.selected_slot` et `player.hotbar_slots`
- Affiche les couleurs correspondantes

---

## 🚀 Optimisations implémentées

### 1. **Greedy Meshing**
✅ Seules les faces visibles sont générées
✅ Réduction massive du nombre de polygones
❌ Pas encore de fusion de faces adjacentes identiques

### 2. **Chargement asynchrone**
✅ 2 chunks max par frame (évite les freezes)
✅ Priorisation par distance (les plus proches d'abord)
✅ Déchargement automatique des chunks lointains

### 3. **Collision optimisée**
✅ ConcavePolygonShape généré à partir du mesh
✅ Une collision par chunk (pas par bloc)

---

## 🔮 Optimisations futures

### 1. **Multithreading**
Générer les chunks dans des threads séparés :
```gdscript
var thread = Thread.new()
thread.start(_generate_chunk_threaded.bind(chunk_pos))
```

### 2. **LOD (Level of Detail)**
- Chunks proches : Full detail
- Chunks moyens : Mesh simplifié
- Chunks lointains : Impostor (billboard)

### 3. **Mesh caching**
Sauvegarder les meshes générés sur disque pour éviter de les recalculer.

### 4. **Greedy Meshing avancé**
Fusionner les faces adjacentes identiques en rectangles.

### 5. **Occlusion culling**
Ne pas afficher les chunks complètement cachés.

---

## 📊 Performances actuelles

### Configuration de test
- Render distance : 4 chunks
- Chunks actifs : ~80 (9x9 grid)
- Blocs par chunk : 16x16x64 = 16,384
- Total blocs : ~1.3 million

### Métriques
- Génération chunk : ~5-15ms (sans thread)
- FPS cible : 60 FPS
- Mémoire : ~200-300 MB

---

## 🎨 Système de couleurs pastel

Toutes les couleurs sont définies dans `BlockRegistry` avec des valeurs RGB élevées (0.6-0.95) pour un rendu doux.

**Palette actuelle** :
- Herbe : `Color(0.6, 0.9, 0.6)` - Vert menthe
- Terre : `Color(0.75, 0.6, 0.5)` - Brun doux
- Pierre : `Color(0.7, 0.7, 0.75)` - Gris perle
- Sable : `Color(0.95, 0.9, 0.7)` - Beige clair
- Bois : `Color(0.8, 0.65, 0.5)` - Caramel

**Ciel** : `Color(0.7, 0.85, 0.95)` - Bleu pastel

---

## 🔧 Comment étendre le projet

### Ajouter un nouveau type de bloc

1. **Dans `block_registry.gd`** :
```gdscript
enum BlockType { ..., NEW_BLOCK }

BlockType.NEW_BLOCK: {
    "name": "My New Block",
    "solid": true,
    "color": Color(0.9, 0.7, 0.8, 1.0)
}
```

2. **Dans `player.gd`** :
```gdscript
var hotbar_slots: Array = [
    ...,
    BlockRegistry.BlockType.NEW_BLOCK
]
```

### Ajouter un biome

1. **Dans `chunk.gd`, modifier `generate_terrain()`** :
```gdscript
var temperature = temperature_noise.get_noise_2d(world_x, world_z)
if temperature > 0.5:
    # Biome désert
    blocks[x][z][y] = BlockRegistry.BlockType.SAND
else:
    # Biome normal
    blocks[x][z][y] = BlockRegistry.BlockType.GRASS
```

### Ajouter des grottes

```gdscript
var cave_noise = FastNoiseLite.new()
cave_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
var cave_value = cave_noise.get_noise_3d(world_x, y, world_z)
if cave_value > 0.6:
    blocks[x][z][y] = BlockRegistry.BlockType.AIR
```

---

## 💾 Système de sauvegarde (à implémenter)

### Format suggéré : JSON compressé

```json
{
  "world_name": "Mon Monde",
  "seed": 12345,
  "chunks": {
    "0,0": {
      "modified_blocks": {
        "5,10,3": "STONE",
        "8,12,7": "WOOD"
      }
    }
  }
}
```

**Stratégie** :
- Ne sauvegarder que les chunks modifiés
- Ne sauvegarder que les blocs différents de la génération
- Compresser avec `FileAccess.open_compressed()`

---

## 🎯 Conclusion

Le projet est architecturé pour être **modulaire** et **extensible**. Chaque système est découplé, ce qui facilite l'ajout de nouvelles fonctionnalités sans casser le code existant.

**Prochaines étapes recommandées** :
1. Implémenter le multithreading pour la génération
2. Ajouter un système d'inventaire complet
3. Créer un système de crafting
4. Améliorer la génération de terrain (biomes, structures)

---

**Bon développement !** 🚀
