# ClaudeLauncher

Lanceur de jeux/applications style Steam/Playnite, avec interface PyQt6 et images SteamGridDB.

## Lancer

```bash
pip install -r requirements.txt
python claudelauncher_v7.0.py
```

**Dépendances :** PyQt6 >= 6.6.0, requests >= 2.31.0, Pillow >= 10.0.0

## Architecture (fichier unique `claudelauncher_v7.0.py`, ~2240 lignes, 4 classes)

- **`ImageDownloader(QThread)`** : téléchargement asynchrone images SteamGridDB, cache local MD5 dans `~/.claudelauncher/images/`, recherche intelligente avec variantes du nom
- **`CustomImageDownloader(QThread)`** : téléchargement d'images personnalisées depuis URL avec cache MD5
- **`ProgramScanner(QThread)`** : scan multi-sources (Registry Windows, Steam `.acf`, Epic Games manifests, dossiers custom, tous les disques), classification jeux vs apps (blacklist, publishers, chemins)
- **`ClaudeLauncher(QMainWindow)`** : UI 4 onglets (Jeux, Applications, Favoris, Plus utilisés), persistance JSON dans `~/.claudelauncher/` (13 fichiers config), lancement programmes, menu contextuel (renommer, favoris, masquer, tags, images, forcer catégorie, modifier exe/arguments), barre de recherche par nom/tag, carrousel d'images personnalisées

## Config runtime

`~/.claudelauncher/` — `favorites.json`, `launch_stats.json`, `hidden_programs.json`, `api_keys.json` (clé SteamGridDB), `overrides.json`, `custom_exes.json`, `custom_args.json`, `last_tab.json`, `custom_tags.json`, `custom_images.json`, etc.
