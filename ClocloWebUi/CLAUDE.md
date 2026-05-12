# ClocloWebUi

Interface web locale (127.0.0.1:8420) pour piloter plusieurs sessions Claude Code en parallèle, une par projet du monorepo. Remplace le terminal CLI par un navigateur avec sidebar de navigation.

**Version actuelle :** 2.0.0 (2026-05-12) — portage Linux Mint terminé.

## Lancer

```bash
cd /mnt/Raid4Tb/Program/ClaudeCode/ClocloWebUi
./run.sh
# Ouvrir http://127.0.0.1:8420
```

Le `run.sh` crée automatiquement le venv `.venv/` et installe les dépendances depuis `requirements.txt` au premier lancement.

**Python :** `python3` système (3.12+). PEP 668 → venv local `.venv/` obligatoire (géré par `run.sh`).
**Dépendances :** `aiohttp >= 3.9`, `ptyprocess >= 0.7`.

## Architecture (4 fichiers)

- **`server.py` (~310 lignes) :** Backend aiohttp async
  - `APP_VERSION` en haut du fichier — à incrémenter à chaque modif
  - `BASE_DIR = Path(__file__).resolve().parent.parent` → autodétection du monorepo, plus de chemin Windows hardcodé
  - `scan_projects()` : scan du monorepo, parse `CLAUDE.md` racine pour extraire les descriptions
  - `_parse_claude_md()` : regex sur le **format tableau Markdown** (`| **NomProjet** | \`Dossier/\` | Description |`) — pas l'ancien format `### NomProjet`
  - `Session` : wrapper PTY via `ptyprocess.PtyProcessUnicode.spawn(['claude'], dimensions=(rows,cols), cwd=..., env=...)`. Buffer circulaire 128 KB (`_output_buffer`) rejoué à chaque attach pour ne pas perdre l'historique au refresh
  - `SessionManager` : dict de sessions par nom de projet, lazy creation (PTY spawn au premier clic)
  - Routes : `GET /` (index.html), `GET /api/projects` (JSON), `WS /ws` (terminal I/O)
  - Cleanup : kill de tous les PTY au shutdown
  - **Detail clé :** supprime toutes les variables d'env contenant `CLAUDE` (sauf `CLAUDE_CONFIG_DIR`) avant spawn pour éviter la détection "nested session"
- **`static/index.html` (~200 lignes) :** SPA avec xterm.js + sidebar projets
  - CDN : `@xterm/xterm@5.5.0` + `@xterm/addon-fit@0.10.0`
  - Un seul `Terminal` xterm.js réutilisé, `term.reset()` au switch projet
  - WebSocket unique `/ws`, auto-reconnexion toutes les 2s
  - Protocole JSON + base64 : `attach`, `input`, `resize`, `detach` (client→serveur) / `output`, `attached`, `exited` (serveur→client)
  - Décodage sortie : `atob()` → `Uint8Array` → `term.write(bytes)` pour UTF-8 correct
- **`static/style.css` (~170 lignes) :** Thème Tokyo Night (#1a1b26), layout flexbox, sidebar 320px
- **`run.sh` :** Bootstrap venv + lancement. Exécutable (`chmod +x` déjà fait).

## Auto-démarrage Linux Mint

Le fichier `clocloweui.desktop` est fourni dans le projet. Pour l'activer au démarrage de la session :

```bash
ln -s /mnt/Raid4Tb/Program/ClaudeCode/ClocloWebUi/clocloweui.desktop ~/.config/autostart/
```

Pour désactiver : `rm ~/.config/autostart/clocloweui.desktop` (ou décocher l'entrée dans l'app "Applications au démarrage" de Mint).

## Problèmes résolus

1. CDN xterm.js 404 → corrigé vers `@xterm/xterm@5.5.0` + `@xterm/addon-fit@0.10.0`
2. Caractères Unicode cassés (ââââ) → décodage base64 en `Uint8Array` au lieu de string `atob()`
3. Terminal vide au refresh → buffer de replay 128 KB côté serveur, rejoué à chaque `attach`
4. (Windows historique) Python 3.14 installé par un outil MCP corrompait pip — résolu sous Linux par le venv local du projet
5. (2026-05-12) Migration Linux : `pywinpty` → `ptyprocess.PtyProcessUnicode`, parser CLAUDE.md adapté au format tableau, fichiers `.bat`/`.vbs` supprimés, autostart via `.desktop`
