# ClocloWebUi

Interface web locale (127.0.0.1:8420) pour piloter plusieurs sessions Claude Code en parallèle, une par projet du monorepo. Remplace le terminal CLI par un navigateur avec sidebar de navigation.

## Lancer

```bash
pip install -r requirements.txt
python server.py
# Ouvrir http://127.0.0.1:8420
```

**Dépendances :** aiohttp >= 3.9, pywinpty >= 2.0

## Architecture (3 fichiers)

- **`server.py` (~300 lignes) :** Backend aiohttp async
  - `scan_projects()` : scan `D:\Program\ClaudeCode`, parse CLAUDE.md via regex pour extraire descriptions
  - `Session` : wrapper PTY pywinpty (spawn `claude.exe`, read pump via `asyncio.run_in_executor`, write, resize, kill). Buffer circulaire 128 KB (`_output_buffer`) rejoué à chaque attach pour ne pas perdre l'historique au refresh
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

## Problèmes résolus durant le développement

1. CDN xterm.js 404 → corrigé vers `@xterm/xterm@5.5.0` + `@xterm/addon-fit@0.10.0`
2. Caractères Unicode cassés (ââââ) → décodage base64 en `Uint8Array` au lieu de string `atob()`
3. Terminal vide au refresh → buffer de replay 128 KB côté serveur, rejoué à chaque `attach`
