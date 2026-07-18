r"""
scan_onenote.py — Enrichit le dump OneNote produit par dump_onenote.ps1

Pipeline :
  1. Lance dump_onenote.ps1 (PowerShell + COM OneNote) si force=True ou si CSV absent
  2. Lit onenote_pages.csv (titres + notebooks + sections + hyperlinks)
  3. Applique les filtres (skip "Notes rapides", "email important", etc.)
  4. Extrait l'ID ticket (CSxxxxxxx ou CHGxxxxxxx) du titre
  5. Sortie : onenote_scan.csv

Pre-requis :
  - PowerShell (deja sur Windows)
  - OneNote desktop (pour le dump initial)
  - Notebook ouvert dans OneNote

APP_VERSION 2.0.0 (2026-05-01) : delegue la partie COM a PowerShell
APP_VERSION 1.0.0 (2026-05-01) : version initiale (pywin32 — abandonnee)
"""

import csv
import re
import subprocess
import sys
from pathlib import Path

APP_VERSION = "2.0.0"

HERE = Path(__file__).parent
PS_SCRIPT = HERE / "dump_onenote.ps1"
DUMP_CSV = HERE / "onenote_pages.csv"
OUT_CSV = HERE / "onenote_scan.csv"

# Filtres : on skip les pages dont le notebook OU la section contient un de ces mots
SKIP_KEYWORDS = [
    "bordel en attente",
    "info personnel",
    "email important",
    "notes rapides",   # le notebook par defaut Windows, contenu non SAP
]

RE_ID_ANY = re.compile(r"\b(CS|CHG)(\d{6,})\b", re.IGNORECASE)


def run_powershell_dump() -> None:
    print(f"[INFO] Lancement de {PS_SCRIPT.name}...")
    result = subprocess.run(
        ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(PS_SCRIPT)],
        capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    if result.returncode != 0:
        print(f"[ERREUR] PowerShell a echoue (code {result.returncode})")
        print(result.stdout)
        print(result.stderr)
        sys.exit(1)
    # Affiche les lignes interessantes
    for line in result.stdout.splitlines():
        if line.strip():
            print(f"  | {line}")


def should_skip(notebook: str, section: str) -> bool:
    text = f"{notebook} {section}".lower()
    return any(kw in text for kw in SKIP_KEYWORDS)


def enrich() -> list[dict]:
    if not DUMP_CSV.exists():
        print(f"[ERREUR] {DUMP_CSV} introuvable. Lancer le PowerShell d'abord.")
        sys.exit(1)

    rows = []
    with DUMP_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f, delimiter=";")
        for row in r:
            notebook = row.get("notebook", "")
            section = row.get("section", "")
            if should_skip(notebook, section):
                continue
            title = row.get("page_title", "")
            m = RE_ID_ANY.search(title)
            ticket_id = f"{m.group(1).upper()}{m.group(2)}" if m else ""
            rows.append({
                "id": ticket_id,
                "page_title": title,
                "notebook": notebook,
                "section": section,
                "page_id": row.get("page_id", ""),
                "hyperlink": row.get("hyperlink", ""),
            })
    return rows


def write_csv(rows: list[dict]) -> None:
    fields = ["id", "page_title", "notebook", "section", "page_id", "hyperlink"]
    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter=";")
        w.writeheader()
        w.writerows(rows)
    print(f"[OK] {len(rows)} pages ecrites dans {OUT_CSV}")


def stats(rows: list[dict]) -> None:
    if not rows:
        return
    with_id = sum(1 for r in rows if r["id"])
    cs = sum(1 for r in rows if r["id"].startswith("CS"))
    chg = sum(1 for r in rows if r["id"].startswith("CHG"))
    print()
    print(f"  Total pages (apres filtre) : {len(rows)}")
    print(f"  Pages avec ID CS/CHG       : {with_id}")
    print(f"    dont format CS           : {cs}")
    print(f"    dont format CHG          : {chg}")
    print()
    by_sec: dict[str, int] = {}
    for r in rows:
        by_sec[r["section"]] = by_sec.get(r["section"], 0) + 1
    print("  Par section :")
    for sec, n in sorted(by_sec.items(), key=lambda x: -x[1]):
        print(f"    {sec:25s} {n:>6d}")


if __name__ == "__main__":
    print(f"scan_onenote.py v{APP_VERSION}\n")
    force = "--refresh" in sys.argv
    if force or not DUMP_CSV.exists():
        run_powershell_dump()
    else:
        print(f"[INFO] Utilise le dump existant : {DUMP_CSV}")
        print(f"       (lancer avec --refresh pour redumper)\n")
    rows = enrich()
    write_csv(rows)
    stats(rows)
