"""ClocloWebUi - Interface web locale pour Claude Code."""

import asyncio
import base64
import json
import os
import re
import signal
import sys
from pathlib import Path

import aiohttp
from aiohttp import web

try:
    from winpty import PtyProcess
except ImportError:
    PtyProcess = None
    # Fallback: try pywinpty's other API
    try:
        import winpty as _winpty_mod
    except ImportError:
        _winpty_mod = None

HOST = "127.0.0.1"
PORT = 8420
BASE_DIR = Path(r"D:\Program\ClaudeCode")
CLAUDE_EXE = "claude"

# ---------------------------------------------------------------------------
# Project scanning
# ---------------------------------------------------------------------------

def scan_projects() -> list[dict]:
    """Scan BASE_DIR for subdirectories and extract descriptions from CLAUDE.md."""
    projects = []
    descriptions = _parse_claude_md()

    for entry in sorted(BASE_DIR.iterdir()):
        if not entry.is_dir():
            continue
        name = entry.name
        # Skip hidden dirs and common non-project dirs
        if name.startswith(".") or name.startswith("__"):
            continue
        desc = descriptions.get(name, "")
        projects.append({"name": name, "path": str(entry), "description": desc})

    return projects


def _parse_claude_md() -> dict[str, str]:
    """Parse CLAUDE.md to extract one-line descriptions per project."""
    claude_md = BASE_DIR / "CLAUDE.md"
    if not claude_md.exists():
        return {}

    text = claude_md.read_text(encoding="utf-8", errors="replace")
    descriptions = {}

    # Match patterns like: ### ProjectName (`ProjectName/`)
    # Then capture the next non-empty line as description
    pattern = re.compile(
        r"^###\s+(\S+)\s+\(`([^`]+)/`\)\s*\n(.*?)(?=\n---|\n###|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    for m in pattern.finditer(text):
        folder = m.group(2)
        block = m.group(3).strip()
        # First non-empty line of the block
        for line in block.split("\n"):
            line = line.strip()
            if line and not line.startswith("**") and not line.startswith("```"):
                descriptions[folder] = line
                break
            elif line.startswith("**") and ":**" not in line:
                # Likely not a section header
                descriptions[folder] = line.strip("*").strip()
                break

    return descriptions


# ---------------------------------------------------------------------------
# PTY Session
# ---------------------------------------------------------------------------

MAX_SCROLLBACK = 128 * 1024  # 128 KB of output history


class Session:
    """Wraps a single Claude Code PTY process."""

    def __init__(self, project_path: str, cols: int = 120, rows: int = 30):
        self.project_path = project_path
        self.cols = cols
        self.rows = rows
        self.process = None
        self.alive = False
        self._subscribers: list[web.WebSocketResponse] = []
        self._read_task: asyncio.Task | None = None
        self._output_buffer = bytearray()

    async def start(self):
        """Spawn claude.exe in a PTY."""
        env = os.environ.copy()
        # Remove CLAUDECODE to avoid nested session detection
        env.pop("CLAUDE_CODE_SESSION", None)
        env.pop("CLAUDECODE", None)
        env.pop("CLAUDE_CODE", None)
        # Also remove any env var that signals we're inside claude
        for key in list(env.keys()):
            if "CLAUDE" in key.upper() and key.upper() != "CLAUDE_CONFIG_DIR":
                env.pop(key, None)

        try:
            self.process = PtyProcess.spawn(
                CLAUDE_EXE,
                dimensions=(self.rows, self.cols),
                cwd=self.project_path,
                env=env,
            )
            self.alive = True
            self._read_task = asyncio.get_event_loop().create_task(self._read_pump())
        except Exception as e:
            error_msg = f"\r\n\x1b[31mErreur demarrage PTY: {e}\x1b[0m\r\n"
            await self._broadcast(error_msg)
            self.alive = False

    async def _read_pump(self):
        """Continuously read from PTY and broadcast to subscribers."""
        loop = asyncio.get_event_loop()
        while self.alive:
            try:
                data = await loop.run_in_executor(None, self._blocking_read)
                if data:
                    await self._broadcast(data)
                else:
                    # Process ended
                    self.alive = False
                    await self._notify_exit()
                    break
            except Exception:
                self.alive = False
                await self._notify_exit()
                break

    def _blocking_read(self) -> str:
        """Read from PTY (blocking, called in executor)."""
        if not self.process or not self.alive:
            return ""
        try:
            if not self.process.isalive():
                self.alive = False
                return ""
            return self.process.read(4096)
        except EOFError:
            return ""
        except Exception:
            return ""

    async def _broadcast(self, data: str):
        """Send data to all attached WebSocket subscribers and buffer it."""
        raw = data.encode("utf-8", errors="replace")
        # Always buffer, even without subscribers
        self._output_buffer.extend(raw)
        if len(self._output_buffer) > MAX_SCROLLBACK:
            self._output_buffer = self._output_buffer[-MAX_SCROLLBACK:]

        if not self._subscribers:
            return
        encoded = base64.b64encode(raw).decode("ascii")
        msg = json.dumps({"type": "output", "project": Path(self.project_path).name, "data": encoded})
        dead = []
        for ws_resp in self._subscribers:
            try:
                await ws_resp.send_str(msg)
            except Exception:
                dead.append(ws_resp)
        for d in dead:
            self._subscribers.remove(d)

    async def replay(self, ws_resp: web.WebSocketResponse):
        """Send buffered output history to a newly attached subscriber."""
        if not self._output_buffer:
            return
        encoded = base64.b64encode(bytes(self._output_buffer)).decode("ascii")
        msg = json.dumps({"type": "output", "project": Path(self.project_path).name, "data": encoded})
        try:
            await ws_resp.send_str(msg)
        except Exception:
            pass

    async def _notify_exit(self):
        """Notify subscribers that the session has exited."""
        msg = json.dumps({"type": "exited", "project": Path(self.project_path).name})
        dead = []
        for ws_resp in self._subscribers:
            try:
                await ws_resp.send_str(msg)
            except Exception:
                dead.append(ws_resp)
        for d in dead:
            self._subscribers.remove(d)

    def subscribe(self, ws_resp: web.WebSocketResponse):
        if ws_resp not in self._subscribers:
            self._subscribers.append(ws_resp)

    def unsubscribe(self, ws_resp: web.WebSocketResponse):
        if ws_resp in self._subscribers:
            self._subscribers.remove(ws_resp)

    def write(self, data: str):
        if self.process and self.alive:
            try:
                self.process.write(data)
            except Exception:
                pass

    def resize(self, cols: int, rows: int):
        self.cols = cols
        self.rows = rows
        if self.process and self.alive:
            try:
                self.process.setwinsize(rows, cols)
            except Exception:
                pass

    def kill(self):
        self.alive = False
        if self._read_task:
            self._read_task.cancel()
        if self.process:
            try:
                self.process.terminate()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Session Manager
# ---------------------------------------------------------------------------

class SessionManager:
    """Manages PTY sessions per project (lazy creation)."""

    def __init__(self):
        self._sessions: dict[str, Session] = {}
        self._projects: dict[str, dict] = {}

    def set_projects(self, projects: list[dict]):
        for p in projects:
            self._projects[p["name"]] = p

    async def get_or_create(self, project_name: str, cols: int = 120, rows: int = 30) -> Session | None:
        if project_name not in self._projects:
            return None

        if project_name in self._sessions:
            session = self._sessions[project_name]
            if session.alive:
                return session
            # Session died, clean up and recreate
            session.kill()

        proj = self._projects[project_name]
        session = Session(proj["path"], cols, rows)
        self._sessions[project_name] = session
        await session.start()
        return session

    def get_existing(self, project_name: str) -> Session | None:
        s = self._sessions.get(project_name)
        if s and s.alive:
            return s
        return None

    def kill_all(self):
        for s in self._sessions.values():
            s.kill()
        self._sessions.clear()


# ---------------------------------------------------------------------------
# Web handlers
# ---------------------------------------------------------------------------

session_mgr = SessionManager()
_projects_cache: list[dict] = []


async def handle_index(request: web.Request) -> web.Response:
    return web.FileResponse(Path(__file__).parent / "static" / "index.html")


async def handle_projects(request: web.Request) -> web.Response:
    # Return name + description (not path, for security)
    safe = [{"name": p["name"], "description": p["description"]} for p in _projects_cache]
    return web.json_response(safe)


async def handle_ws(request: web.Request) -> web.WebSocketResponse:
    ws_resp = web.WebSocketResponse(max_msg_size=4 * 1024 * 1024)
    await ws_resp.prepare(request)

    attached_project: str | None = None

    try:
        async for msg in ws_resp:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                except json.JSONDecodeError:
                    continue

                msg_type = data.get("type")

                if msg_type == "attach":
                    project = data.get("project", "")
                    cols = data.get("cols", 120)
                    rows = data.get("rows", 30)

                    # Detach from previous if any
                    if attached_project:
                        old = session_mgr.get_existing(attached_project)
                        if old:
                            old.unsubscribe(ws_resp)

                    session = await session_mgr.get_or_create(project, cols, rows)
                    if session:
                        session.subscribe(ws_resp)
                        attached_project = project
                        await ws_resp.send_str(json.dumps({
                            "type": "attached",
                            "project": project,
                        }))
                        # Replay buffered output then resize
                        await session.replay(ws_resp)
                        session.resize(cols, rows)

                elif msg_type == "input":
                    project = data.get("project", "")
                    raw = data.get("data", "")
                    if raw:
                        try:
                            decoded = base64.b64decode(raw).decode("utf-8", errors="replace")
                        except Exception:
                            decoded = raw
                        session = session_mgr.get_existing(project)
                        if session:
                            session.write(decoded)

                elif msg_type == "resize":
                    project = data.get("project", "")
                    cols = data.get("cols", 120)
                    rows = data.get("rows", 30)
                    session = session_mgr.get_existing(project)
                    if session:
                        session.resize(cols, rows)

                elif msg_type == "detach":
                    project = data.get("project", "")
                    session = session_mgr.get_existing(project)
                    if session:
                        session.unsubscribe(ws_resp)
                    if attached_project == project:
                        attached_project = None

            elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
                break
    finally:
        # Clean up subscription
        if attached_project:
            session = session_mgr.get_existing(attached_project)
            if session:
                session.unsubscribe(ws_resp)

    return ws_resp


# ---------------------------------------------------------------------------
# App lifecycle
# ---------------------------------------------------------------------------

async def on_startup(app: web.Application):
    global _projects_cache
    _projects_cache = scan_projects()
    session_mgr.set_projects(_projects_cache)
    print(f"  {len(_projects_cache)} projets trouves")


async def on_cleanup(app: web.Application):
    print("\nArret des sessions...")
    session_mgr.kill_all()


def main():
    # Verify pywinpty is available
    if PtyProcess is None:
        print("ERREUR: pywinpty n'est pas installe ou PtyProcess n'est pas disponible.")
        print("  pip install pywinpty")
        sys.exit(1)

    app = web.Application()
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)

    app.router.add_get("/", handle_index)
    app.router.add_get("/api/projects", handle_projects)
    app.router.add_get("/ws", handle_ws)
    app.router.add_static("/static", Path(__file__).parent / "static")

    print(f"ClocloWebUi -- http://{HOST}:{PORT}")
    web.run_app(app, host=HOST, port=PORT, print=None)


if __name__ == "__main__":
    main()
