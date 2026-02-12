# 🌍 Système de Biomes - Documentation

## Vue d'ensemble

ClaudeCraft possède maintenant **4 biomes distincts** générés procéduralement ! Chaque biome a ses propres caractéristiques visuelles et de terrain.

---

## 🎨 Les 4 Biomes

### 🏜️ **1. DÉSERT**
**Conditions** : Chaud (température > 0.6) + Sec (humidité < 0.4)

**Caractéristiques** :
- 🟡 **Sol** : Sable jaune pâle `(0.95, 0.9, 0.7)`
- 📏 **Terrain** : Plat avec douces dunes (hauteur 28-36 blocs)
- 🌵 **Végétation** : Cactus verts (2-4 blocs de haut)
- 🎯 **Style** : Minimaliste, épuré, chaud

**Détails techniques** :
- Base de pierre sous 4 blocs de sable
- Cactus générés avec formule : `(world_x + world_z) % 17 == 0`
- Hauteur cactus : `2 + ((world_x * world_z) % 3)`

---

### 🌲 **2. FORÊT**
**Conditions** : Tempéré (température 0.4-0.7) + Humide (humidité > 0.5)

**Caractéristiques** :
- 🟢 **Sol** : Herbe vert foncé `(0.4, 0.7, 0.4)`
- 📏 **Terrain** : Légèrement vallonné (hauteur 30-45 blocs)
- 🌳 **Végétation** : Arbres cubiques (tronc brun + feuilles vertes)
- 🎯 **Style** : Dense, vivant, ombragé

**Détails techniques** :
- Structure : Pierre → Terre (3 blocs) → Herbe foncée
- Arbres générés avec formule : `(world_x + world_z * 2) % 11 == 0`
- Tronc : 3-5 blocs de WOOD
- Feuilles : 2 blocs de LEAVES au sommet

---

### ⛰️ **3. MONTAGNE**
**Conditions** : Froid (température < 0.4)

**Caractéristiques** :
- ⚪ **Sol** : Pierre grise + Neige blanche au sommet
- 📏 **Terrain** : Très haut et escarpé (hauteur 25-60 blocs)
- ❄️ **Végétation** : Aucune (juste neige au sommet si > 50 blocs)
- 🎯 **Style** : Imposant, rocheux, froid

**Détails techniques** :
- Structure profonde : Pierre (profond) → Gravier (transition) → Pierre → Neige (si hauteur > 50)
- Gravier gris `(0.5, 0.5, 0.55)`
- Neige blanche `(0.95, 0.95, 1.0)`
- Plus haute variation de terrain

---

### 🌾 **4. PLAINE** (Biome par défaut)
**Conditions** : Tout le reste (température et humidité moyennes)

**Caractéristiques** :
- 🟢 **Sol** : Herbe vert clair `(0.6, 0.9, 0.6)` (style original)
- 📏 **Terrain** : Moyen, légèrement vallonné (hauteur 30-50 blocs)
- 🌱 **Végétation** : Aucune pour l'instant
- 🎯 **Style** : Classique, équilibré

**Détails techniques** :
- Structure : Pierre → Terre (3 blocs) → Herbe
- C'est le biome "safe" pour spawner

---

## ⚙️ Génération Technique

### **Système à 3 Perlin Noise**

1. **Terrain Noise** (`frequency: 0.05`)
   - Détermine la hauteur de base du terrain
   - Utilisé pour TOUS les biomes

2. **Temperature Noise** (`frequency: 0.02`, seed: 54321)
   - Valeur 0.0 → 1.0 (froid → chaud)
   - Basse fréquence = grandes zones climatiques

3. **Humidity Noise** (`frequency: 0.025`, seed: 98765)
   - Valeur 0.0 → 1.0 (sec → humide)
   - Légèrement plus variable que température

### **Algorithme de sélection**

```gdscript
func _determine_biome(temperature: float, humidity: float) -> int:
    if temperature > 0.6 and humidity < 0.4:
        return DESERT  # Chaud et sec
    
    elif temperature > 0.4 and temperature < 0.7 and humidity > 0.5:
        return FOREST  # Tempéré et humide
    
    elif temperature < 0.4:
        return MOUNTAIN  # Froid
    
    else:
        return PLAINS  # Défaut
```

---

## 🎨 Palette de Couleurs

| Biome | Bloc Principal | Code RGB | Hex | Vibe |
|-------|---------------|----------|-----|------|
| Désert | Sable | `(0.95, 0.9, 0.7)` | #F2E6B3 | Chaud, sec |
| Forêt | Herbe foncée | `(0.4, 0.7, 0.4)` | #66B266 | Ombragé, vivant |
| Montagne | Pierre + Neige | `(0.6, 0.6, 0.65)` / `(0.95, 0.95, 1.0)` | #999AA6 / #F2F2FF | Froid, imposant |
| Plaine | Herbe | `(0.6, 0.9, 0.6)` | #99E699 | Classique, neutre |

---

## 🔧 Personnalisation

### **Changer les couleurs**

Dans `block_registry.gd` :
```gdscript
BlockType.SAND: {
    "color": Color(0.95, 0.9, 0.7, 1.0)  // ← Change ici !
}
```

### **Modifier les seuils de biomes**

Dans `chunk_generator.gd`, fonction `_determine_biome()` :
```gdscript
if temperature > 0.6 and humidity < 0.4:  // ← Ajuste les seuils
    return DESERT
```

**Exemples** :
- Plus de déserts → Baisse le seuil de température à `0.5`
- Plus de forêts → Baisse le seuil d'humidité à `0.4`
- Plus de montagnes → Augmente le seuil de froid à `0.5`

### **Ajuster la taille des biomes**

Dans `chunk_generator.gd` :
```gdscript
temperature_noise.frequency = 0.02  // ← Baisse = biomes plus grands
humidity_noise.frequency = 0.025    // ← Monte = biomes plus petits
```

**Exemples** :
- Biomes **gigantesques** → `frequency = 0.01`
- Biomes **minuscules** → `frequency = 0.05`

---

## 📊 Distribution Théorique

Avec les seuils actuels :
- 🏜️ **Désert** : ~20% du monde
- 🌲 **Forêt** : ~25% du monde
- ⛰️ **Montagne** : ~30% du monde
- 🌾 **Plaine** : ~25% du monde

*(Valeurs approximatives, dépend du seed)*

---

## 🚀 Prochaines Améliorations Possibles

### **Court terme** :
- [ ] Arbres dans les plaines
- [ ] Fleurs/herbes hautes (blocs semi-transparents)
- [ ] Lacs dans les plaines/forêts

### **Moyen terme** :
- [ ] Biomes de transition (bordures douces)
- [ ] Rivières (génération avancée)
- [ ] Villages dans les plaines
- [ ] Plus de variété d'arbres (chêne, pin, bouleau)

### **Long terme** :
- [ ] Océans + plages
- [ ] Jungle (tropical)
- [ ] Toundra (neige partout)
- [ ] Mesa (désert avec falaises)
- [ ] Champignons géants (biome rare)

---

## 🎮 Exploration

### **Comment trouver chaque biome ?**

1. **Spawn** : Tu spawnes généralement dans une **Plaine** (biome par défaut)

2. **Désert** : Marche vers les zones **plates et jaunes**

3. **Forêt** : Cherche les zones avec **arbres** et herbe **vert foncé**

4. **Montagne** : Facile à voir de loin, ce sont les **pics hauts** avec neige au sommet

5. **Astuce** : Monte en hauteur (saute sur des colonnes de blocs) pour repérer les biomes au loin !

---

## 🐛 Debug / Testing

### **Voir les valeurs de biome**

Ajoute dans `chunk_generator.gd` :
```gdscript
print("Biome: ", biome, " Temp: ", temperature, " Hum: ", humidity)
```

### **Forcer un biome spécifique**

Dans `_generate_chunk_data()`, remplace :
```gdscript
var biome = _determine_biome(temperature, humidity)
```

Par :
```gdscript
var biome = 0  # Force DESERT partout
```

---

## ✅ Conclusion

Le système de biomes est **simple, performant et extensible** ! Les transitions sont naturelles grâce au Perlin noise, et tu peux facilement ajouter de nouveaux biomes ou ajuster ceux existants.

**Style visuel** : Minimaliste pastel, parfait pour un jeu chill/relaxant ! 🎨✨

**Performance** : Génération threadée, aucun impact sur les FPS ! 🚀

---

**Bon voyage dans ClaudeCraft !** 🌍🎮
