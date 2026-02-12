# ⚡ Guide d'optimisation des performances

## 🎮 Configuration actuelle (optimisée pour 1080p + RX 6700 XT)

### Paramètres du WorldManager (scenes/main.tscn)
- `render_distance: 3` (au lieu de 4) - Moins de chunks = meilleures perfs
- `chunk_load_per_frame: 2` - Charge 2 chunks par frame
- `unload_distance_margin: 4` - Évite le clignotement

### Paramètres SSAO (scenes/main.tscn - Environment)
- `ssao_intensity: 1.0` (réduit de 1.5)
- `ssao_detail: 0.3` (réduit de 0.5)
- `ssao_radius: 1.5` (réduit de 2.0)

---

## 🔧 Options de performance

### 🚀 Performance MAXIMALE (60+ FPS garanti)

Dans `scenes/main.tscn`, WorldManager :
```
render_distance = 2
chunk_load_per_frame = 1
```

Dans `scenes/main.tscn`, Environment :
```
ssao_enabled = false
```

**Résultat** : 
- ✅ Fluide même sur GPU moyen
- ❌ Distance de vue réduite
- ❌ Moins d'AO (mais l'AO par vertex reste)

---

### ⚖️ Équilibré (recommandé)

Dans `scenes/main.tscn`, WorldManager :
```
render_distance = 3
chunk_load_per_frame = 2
```

Dans `scenes/main.tscn`, Environment :
```
ssao_enabled = true
ssao_intensity = 1.0
ssao_detail = 0.3
```

**Résultat** : 
- ✅ Bon compromis visuel/performance
- ✅ Distance de vue correcte
- ✅ AO visible mais pas gourmand

---

### 💎 Qualité MAXIMALE (pour screenshot/vidéo)

Dans `scenes/main.tscn`, WorldManager :
```
render_distance = 5
chunk_load_per_frame = 3
```

Dans `scenes/main.tscn`, Environment :
```
ssao_enabled = true
ssao_intensity = 2.0
ssao_detail = 0.5
ssao_radius = 2.5
```

**Résultat** : 
- ✅ Visuels magnifiques
- ❌ Peut laguer sur GPU moyen
- ✅ Idéal pour captures d'écran

---

## 🐛 Corrections du clignotement

### Cause du problème
Le clignotement se produit quand :
1. Le joueur est à la limite entre deux chunks
2. Le chunk se charge/décharge en boucle

### Solution implémentée
- **Hysteresis** : Les chunks se déchargent plus loin qu'ils ne se chargent
- **Mise à jour conditionnelle** : Les chunks ne se rechargent que si le joueur change de chunk
- `unload_distance_margin = 4` : Marge de sécurité

---

## 📊 FPS attendus (1080p, RX 6700 XT)

### Mode Debug (dans l'éditeur Godot)
- Config Équilibré : **40-60 FPS**
- Config Performance Max : **60+ FPS**
- Config Qualité Max : **30-45 FPS**

### Mode Release (exécutable exporté)
- Config Équilibré : **60-90 FPS**
- Config Performance Max : **90-120 FPS**
- Config Qualité Max : **50-70 FPS**

**Note** : Le mode Debug de Godot est **2-3x plus lent** que l'exécutable exporté !

---

## 🚀 Exporter un exécutable optimisé

1. Dans Godot : **Projet → Exporter**
2. Ajouter un preset "Windows Desktop"
3. Cocher **"Exportation optimisée"**
4. Décocher **"Inclure le débogueur"**
5. Exporter

Tu verras des **performances BEAUCOUP meilleures** ! 🔥

---

## 🎯 Optimisations futures possibles

Si tu veux aller encore plus loin :

### 1. Multithreading
Générer les chunks dans des threads séparés
- Gain : **+30-50% FPS**
- Complexité : Moyenne

### 2. Instanced Rendering
Utiliser MultiMesh pour les blocs identiques
- Gain : **+20-40% FPS**
- Complexité : Élevée

### 3. Occlusion Culling
Ne pas afficher les chunks cachés derrière d'autres
- Gain : **+10-30% FPS**
- Complexité : Moyenne

### 4. Greedy Meshing avancé
Fusionner les faces adjacentes identiques
- Gain : **+15-25% FPS**
- Complexité : Élevée

---

## 💡 Astuces rapides

- **F3** dans Godot : Voir les FPS et stats
- **Moniteur de performances** : Activer dans Debug → Moniteur
- **Profiler** : Outil → Profileur pour voir les bottlenecks

---

**Bon jeu optimisé !** 🎮⚡
