# 🎮 Minecraft-like Pastel - Projet Godot 4

Un jeu de type voxel avec une ambiance **pastel et chill**, créé avec Godot 4.3.

## 🎨 Caractéristiques

- **Style visuel pastel** : Couleurs douces et apaisantes
- **Génération procédurale** : Terrain généré avec Perlin noise
- **Système de chunks optimisé** : Chargement/déchargement dynamique
- **Greedy meshing** : Optimisation du rendu (faces cachées non affichées)
- **Contrôles FPS fluides** : Mouvement WASD/ZQSD + souris
- **Système de blocs** : Casser et placer des blocs
- **Hotbar minimaliste** : 5 slots comme Minecraft

## 🎮 Contrôles

### Mouvement
- **ZQSD / WASD** : Se déplacer
- **Espace** : Sauter
- **Souris** : Regarder autour
- **Échap** : Libérer/capturer la souris

### Blocs
- **Clic gauche** : Casser un bloc
- **Clic droit** : Placer un bloc
- **1-5** : Sélectionner un type de bloc dans la hotbar

## 📦 Types de blocs disponibles

1. **Terre (Dirt)** - Brun pastel
2. **Herbe (Grass)** - Vert pastel
3. **Pierre (Stone)** - Gris pastel
4. **Sable (Sand)** - Beige pastel
5. **Bois (Wood)** - Bois pastel

## 🏗️ Architecture du projet

```
minecraft_like_project/
├── scripts/
│   ├── block_registry.gd    # Définition des types de blocs
│   ├── chunk.gd              # Génération et gestion d'un chunk
│   ├── world_manager.gd      # Gestion du monde (chargement chunks)
│   ├── player.gd             # Contrôleur FPS + interactions
│   └── hotbar_ui.gd          # Interface utilisateur (hotbar)
├── scenes/
│   ├── main.tscn             # Scène principale
│   ├── player.tscn           # Scène du joueur
│   └── hotbar_ui.tscn        # Scène de l'UI
└── project.godot             # Configuration du projet
```

## 🚀 Fonctionnalités techniques

### Génération de chunks
- **Taille** : 16x16x64 blocs par chunk
- **Distance de rendu** : 4 chunks (configurable)
- **Chargement asynchrone** : 2 chunks par frame (évite les freezes)
- **Déchargement automatique** : Les chunks trop loin sont supprimés

### Optimisations
- **Greedy meshing** : Seules les faces visibles sont générées
- **Variation de luminosité** : Chaque face a une teinte légèrement différente
- **Collision optimisée** : ConcavePolygonShape basé sur le mesh

## 🔧 Prochaines améliorations possibles

- [ ] Améliorer la génération de terrain (biomes, grottes)
- [ ] Ajouter plus de types de blocs
- [ ] Système d'inventaire complet
- [ ] Crafting
- [ ] Sauvegarde/chargement du monde
- [ ] Multithreading pour la génération de chunks
- [ ] LOD (Level of Detail) pour les chunks lointains
- [ ] Particules lors de la destruction de blocs
- [ ] Sons et musique d'ambiance

## 📝 Notes

- Le projet utilise **Godot 4.3** avec le moteur de physique **JoltPhysics3D**
- Les couleurs sont définies dans `block_registry.gd` et peuvent être facilement modifiées
- La génération de terrain utilise `FastNoiseLite` intégré à Godot

## 🎯 Comment démarrer

1. Ouvrir le projet dans Godot 4.3 ou supérieur
2. Ouvrir la scène `scenes/main.tscn`
3. Appuyer sur **F5** pour lancer le jeu
4. Profiter de l'ambiance chill ! 🌸

---

**Bon jeu !** 🎮✨
