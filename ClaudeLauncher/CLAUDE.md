# ClaudeLauncher

Lanceur de jeux/applications style Steam/Playnite, avec interface PyQt6 et images SteamGridDB.

**Version courante :** `APP_VERSION = "7.5"` (constante en haut du fichier, à incrémenter à chaque modification)

## Lancer

```bash
cd /mnt/Raid4Tb/Program/ClaudeCode/ClaudeLauncher
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python claudelauncher_v7.0.py
```

**Dépendances :** PyQt6 >= 6.6.0, requests >= 2.31.0, Pillow >= 10.0.0
**Système :** sous Linux, PyQt6 nécessite que les libs Qt6 du système soient présentes (déjà fournies par les wheels manylinux dans la plupart des cas — sinon `sudo apt install libxcb-cursor0 libxkbcommon-x11-0`).

## Architecture (fichier unique `claudelauncher_v7.0.py`, ~2900 lignes, 5 classes)

- **`ImageDownloader(QThread)`** : téléchargement asynchrone images SteamGridDB, cache local MD5 dans `~/.claudelauncher/images/`, recherche intelligente avec variantes du nom
- **`CustomImageDownloader(QThread)`** : téléchargement d'images personnalisées depuis URL avec cache MD5
- **`WebImageSearcher(QThread)`** : recherche d'images web multi-sources (SteamGridDB + DuckDuckGo), dialogue de sélection visuelle avec miniatures
- **`ProgramScanner(QThread)`** : scan multi-sources. **Code legacy 100% Windows** (Registry `HKLM`/`HKCU`, Steam `.acf`, Epic Games manifests, parcours `C:\` et `D:\`, `.bat/.exe/.lnk`). À porter sous Linux : parser `~/.local/share/applications/*.desktop` + `/usr/share/applications/*.desktop`, parser `~/.steam/steam/steamapps/*.acf` + `~/.local/share/Steam/steamapps/*.acf`, parser Lutris (`~/.config/lutris/games/*.yml`), Heroic Games Launcher (`~/.config/heroic/`), et scanner `/mnt/Raid4Tb/SteamLibrary/steamapps/*.acf` (présent sur ce poste).
- **`ClaudeLauncher(QMainWindow)`** : UI 4 onglets (Jeux, Applications, Favoris, Plus utilisés), persistance JSON dans `~/.claudelauncher/` (13 fichiers config), lancement programmes (`subprocess.Popen(['xdg-open', path])` côté Linux au lieu de `os.startfile()`), menu contextuel (renommer, favoris, masquer, tags, images, forcer catégorie, modifier exe/arguments), barre de recherche par nom/tag, carrousel d'images personnalisées
- **Auto-élévation UAC** : `main()` vérifie `IsUserAnAdmin()`, relance en admin si nécessaire via `ShellExecuteW("runas")`. **Inutile sous Linux** — le launcher tourne en utilisateur normal, pas d'élévation requise pour scanner les `.desktop` files. Bloc à neutraliser sous Linux.
- **Auto-démarrage** : tâche planifiée `schtasks` (Windows). Sous Linux, créer un fichier `~/.config/autostart/claudelauncher.desktop` à la place.

## Config runtime

`~/.claudelauncher/` — `favorites.json`, `launch_stats.json`, `hidden_programs.json`, `api_keys.json` (clé SteamGridDB), `overrides.json`, `custom_exes.json`, `custom_args.json`, `last_tab.json`, `custom_tags.json`, `custom_images.json`, `custom_files.json`, etc.

## Tâche planifiée Windows (legacy)

- **Nom :** `ClaudeLauncher_Startup` — suppression manuelle : `schtasks /Delete /TN ClaudeLauncher_Startup /F`

## Auto-démarrage Linux (à mettre en place)

Créer `~/.config/autostart/claudelauncher.desktop` :

```ini
[Desktop Entry]
Type=Application
Name=ClaudeLauncher
Exec=/mnt/Raid4Tb/Program/ClaudeCode/ClaudeLauncher/.venv/bin/python /mnt/Raid4Tb/Program/ClaudeCode/ClaudeLauncher/claudelauncher_v7.0.py
X-GNOME-Autostart-enabled=true
```

## Migration Linux à faire

- [ ] Neutraliser le bloc UAC (`IsUserAnAdmin`, `ShellExecuteW`)
- [ ] Remplacer `os.startfile()` par `subprocess.Popen(['xdg-open', path])`
- [ ] Réécrire `ProgramScanner` pour parser `.desktop`, `.acf` (Steam Linux), Lutris, Heroic
- [ ] Remplacer le bloc `schtasks` par création/suppression d'un `.desktop` autostart
- [ ] Garder `~/.claudelauncher/` (le path `~` est cross-platform)
