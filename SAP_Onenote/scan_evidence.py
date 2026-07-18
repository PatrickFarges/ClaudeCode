r"""
scan_evidence.py — Scanner des dossiers Test Evidence SAP

Walke E:\Dossier Manuel\NGA\OLD\Tickets et extrait pour chaque dossier ticket :
  - ID (CSxxxxxxx ou CHGxxxxxxx)
  - Client (niveau 1)
  - Annee/range (niveau 2)
  - Chemin absolu du dossier
  - Fichier(s) Excel commencant par l'ID

Sortie : evidence_scan.csv (UTF-8, separateur ;)

APP_VERSION 1.1.0 (2026-05-01) : walk recursif + tickets sans sous-dossier annee
APP_VERSION 1.0.0 (2026-05-01) : version initiale
"""

import csv
import re
from pathlib import Path

APP_VERSION = "1.1.0"

ROOT = Path(r"E:\Dossier Manuel (CV, taf, dev etc)\NGA\OLD\Tickets")
OUT_CSV = Path(__file__).parent / "evidence_scan.csv"

# Pattern ID en debut de nom de dossier : "CS0514848 - ..." ou "CHG0563104 - ..."
RE_ID_FOLDER = re.compile(r"^(CS|CHG)(\d+)\s*[-_]")
RE_ID_ANY = re.compile(r"\b(CS|CHG)(\d{6,})\b", re.IGNORECASE)


def find_excel_for_id(folder: Path, ticket_id: str) -> list[str]:
    """Retourne la liste des .xlsx du dossier dont le nom commence par l'ID."""
    matches = []
    if not folder.is_dir():
        return matches
    id_lower = ticket_id.lower()
    for f in folder.iterdir():
        if f.is_file() and f.suffix.lower() in (".xlsx", ".xlsm", ".xls"):
            if f.name.lower().startswith(id_lower):
                matches.append(f.name)
    return matches


def walk_for_tickets(client_dir: Path, client_name: str) -> dict[str, dict]:
    """Walk recursif du dossier client, repere tous les dossiers ticket.

    Retourne un dict ticket_id -> row.
    L'annee est le 1er sous-dossier rencontre apres le client (peut etre vide).
    """
    found: dict[str, dict] = {}

    for path in client_dir.rglob("*"):
        if not path.is_dir():
            continue
        m = RE_ID_FOLDER.match(path.name)
        if not m:
            continue
        prefix, num = m.group(1).upper(), m.group(2)
        ticket_id = f"{prefix}{num}"

        # Annee = premier composant relatif au client (si profondeur > 1)
        rel_parts = path.relative_to(client_dir).parts
        annee = rel_parts[0] if len(rel_parts) > 1 else ""

        excel_files = find_excel_for_id(path, ticket_id)

        # En cas de doublon (meme ID, plusieurs dossiers), on garde le plus profond
        if ticket_id not in found or len(rel_parts) > len(
            Path(found[ticket_id]["folder_path"]).relative_to(client_dir).parts
        ):
            found[ticket_id] = {
                "id": ticket_id,
                "client": client_name,
                "annee": annee,
                "folder_name": path.name,
                "folder_path": str(path),
                "excel_count": len(excel_files),
                "excel_files": " | ".join(excel_files),
            }
    return found


def find_orphan_excels(client_dir: Path, client_name: str,
                       seen_ids: set[str]) -> list[dict]:
    """Trouve les .xlsx eparpilles qui contiennent un ID non encore vu."""
    rows = []
    for path in client_dir.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in (".xlsx", ".xlsm", ".xls"):
            continue
        m = RE_ID_ANY.search(path.name)
        if not m:
            continue
        prefix, num = m.group(1).upper(), m.group(2)
        ticket_id = f"{prefix}{num}"
        if ticket_id in seen_ids:
            continue
        seen_ids.add(ticket_id)
        rel_parts = path.relative_to(client_dir).parts
        annee = rel_parts[0] if len(rel_parts) > 1 else ""
        rows.append({
            "id": ticket_id,
            "client": client_name,
            "annee": annee,
            "folder_name": "(fichier orphelin)",
            "folder_path": str(path.parent),
            "excel_count": 1,
            "excel_files": path.name,
        })
    return rows


def scan() -> list[dict]:
    rows = []
    if not ROOT.exists():
        print(f"[ERREUR] Racine introuvable : {ROOT}")
        return rows

    clients = sorted([d for d in ROOT.iterdir() if d.is_dir()])
    print(f"[INFO] {len(clients)} clients detectes sous {ROOT}")

    for client_dir in clients:
        client_name = client_dir.name
        tickets = walk_for_tickets(client_dir, client_name)
        seen_ids = set(tickets.keys())
        orphans = find_orphan_excels(client_dir, client_name, seen_ids)
        n = len(tickets) + len(orphans)
        print(f"  {client_name:20s} {n:>4d} ticket(s) ({len(orphans)} orphelin(s))")
        rows.extend(tickets.values())
        rows.extend(orphans)

    return rows


def write_csv(rows: list[dict]) -> None:
    if not rows:
        print("[WARN] Aucun ticket trouve.")
        return
    fields = ["id", "client", "annee", "folder_name", "folder_path",
              "excel_count", "excel_files"]
    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter=";")
        w.writeheader()
        w.writerows(rows)
    print(f"[OK] {len(rows)} tickets ecrits dans {OUT_CSV}")


def stats(rows: list[dict]) -> None:
    if not rows:
        return
    cs = sum(1 for r in rows if r["id"].startswith("CS"))
    chg = sum(1 for r in rows if r["id"].startswith("CHG"))
    with_excel = sum(1 for r in rows if r["excel_count"] > 0)
    no_excel = len(rows) - with_excel
    print()
    print(f"  Total tickets       : {len(rows)}")
    print(f"  Format CS           : {cs}")
    print(f"  Format CHG          : {chg}")
    print(f"  Avec Excel match ID : {with_excel}")
    print(f"  Sans Excel match ID : {no_excel}")
    print()
    by_client = {}
    for r in rows:
        by_client[r["client"]] = by_client.get(r["client"], 0) + 1
    print("  Par client :")
    for client, n in sorted(by_client.items(), key=lambda x: -x[1]):
        print(f"    {client:20s} {n:>5d}")


if __name__ == "__main__":
    print(f"scan_evidence.py v{APP_VERSION}")
    print(f"Racine : {ROOT}\n")
    rows = scan()
    write_csv(rows)
    stats(rows)
