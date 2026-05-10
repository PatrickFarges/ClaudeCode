# ClocloWebUi

Interface web locale (127.0.0.1:8420) pour piloter plusieurs sessions Claude Code en parallèle, une par projet du monorepo. Remplace le terminal CLI par un navigateur avec sidebar de navigation.

## Lancer

```bash
# Setup une fois :
cd /mnt/Raid4Tb/Program/ClaudeCode/ClocloWebUi
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Lancement :
source .venv/bin/activate && python server.py
# Ouvrir http://127.0.0.1:8420
```

**Dépendances Linux :** aiohttp >= 3.9, **ptyprocess >= 0.7** (remplace `pywinpty` qui n'existe que sous Windows). Le code de `server.py` doit être adapté : utiliser `pty.fork()` + `os.exec*` ou `ptyprocess.PtyProcessUnicode.spawn(['claude'])` au lieu de `winpty.PtyProcess.spawn`.

**Python :** `python3` système (3.12+). PEP 668 → obligation d'utiliser un venv local `.venv/`.

## Architecture (4 fichiers)

- **`server.py` (~300 lignes) :** Backend aiohttp async
  - `scan_projects()` : scan `/mnt/Raid4Tb/Program/ClaudeCode`, parse CLAUDE.md via regex pour extraire descriptions
  - `Session` : wrapper PTY (spawn `claude` binary, read pump via `asyncio.run_in_executor`, write, resize, kill). Buffer circulaire 128 KB (`_output_buffer`) rejoué à chaque attach pour ne pas perdre l'historique au refresh. **À porter vers `ptyprocess` ou `pty.fork()` côté Linux** (le code legacy utilise `winpty`).
  - `SessionManager` : dict de sessions par nom de projet, lazy creation (PTY spawn au premier clic)
  - Routes : `GET /` (index.html), `GET /api/projects` (JSON), `WS /ws` (terminal I/O)
  - Cleanup : kill de tous les PTY au shutdown
  - **Detail clé :** supprime toutes les variables d'env contenant `CLAUDE` avant spawn pour éviter la détection "nested session"
- **`static/index.html` (~200 lignes) :** SPA avec xterm.js + sidebar projets
  - CDN : `@xterm/xterm@5.5.0` + `@xterm/addon-fit@0.10.0` (attention : les anciennes versions `@5.3.0`/`@0.8.0` retournent 404 sur jsdelivr)
  - Un seul `Terminal` xterm.js réutilisé, `term.reset()` au switch projet
  - WebSocket unique `/ws`, auto-reconnexion toutes les 2s
  - Protocole JSON + base64 : `attach`, `input`, `resize`, `detach` (client→serveur) / `output`, `attached`, `exited` (serveur→client)
  - Décodage sortie : `atob()` → `Uint8Array` → `term.write(bytes)` pour UTF-8 correct (pas `atob` direct qui donne du latin1 cassé)
- **`static/style.css` (~170 lignes) :** Thème Tokyo Night (#1a1b26), layout flexbox, sidebar 320px
- **`start.bat` :** **Legacy Windows** — à supprimer ou remplacer par un `start.sh` Linux : `#!/usr/bin/env bash` + `cd "$(dirname "$0")" && source .venv/bin/activate && exec python server.py`
- **`start_minimized.vbs` :** **Legacy Windows** — non utilisable sous Linux. Pour l'auto-démarrage minimisé, utiliser à la place une unit `systemd --user` ou un `.desktop` dans `~/.config/autostart/` avec `Hidden=false` + `X-GNOME-Autostart-enabled=true`.

## Auto-démarrage Linux

À reconfigurer (l'ancien était une clé registre Windows). Approche recommandée : créer un fichier `~/.config/autostart/clocloweui.desktop` :

```ini
[Desktop Entry]
Type=Application
Name=ClocloWebUi
Exec=/mnt/Raid4Tb/Program/ClaudeCode/ClocloWebUi/start.sh
X-GNOME-Autostart-enabled=true
NoDisplay=true
```

Pour désactiver : supprimer le fichier ou décocher l'entrée dans l'app "Applications au démarrage" de Mint.

## Problèmes résolus durant le développement

1. CDN xterm.js 404 → corrigé vers `@xterm/xterm@5.5.0` + `@xterm/addon-fit@0.10.0`
2. Caractères Unicode cassés (ââââ) → décodage base64 en `Uint8Array` au lieu de string `atob()`
3. Terminal vide au refresh → buffer de replay 128 KB côté serveur, rejoué à chaque `attach`
4. (Windows historique) `Unable to create process using 'C:\Python314\python.exe'` → Python 3.14 installé accidentellement par un outil MCP avait corrompu les wrappers pip. Résolu en forçant Python 3.12 via `start.bat` et `--force-reinstall` de pywinpty. Sous Linux, problème équivalent évité par le venv local.

## Migration Linux à faire

- [ ] Remplacer `pywinpty` par `ptyprocess` dans `requirements.txt` et `server.py`
- [ ] Adapter `Session` pour utiliser `ptyprocess.PtyProcessUnicode.spawn(['claude'])`
- [ ] Créer `start.sh` (rendu exécutable via `chmod +x`)
- [ ] Supprimer `start.bat` et `start_minimized.vbs`
- [ ] Configurer l'autostart via `.desktop`
