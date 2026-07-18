#!/usr/bin/env python3
"""
kb_build.py — Construit la base de connaissance RAG `sap_kb.db` (SQLite FTS5).

APP_VERSION = 0.2.0

Change-log
----------
0.2.0 (2026-07-18) : passage à l'extraction robuste (rag/onenote_extract.py 0.2.0,
                     sans pyOneNote). Map de titres GLOBALE (ancres de segmentation +
                     jointure lien/ticket), correction du mojibake du CSV, section
                     déduite du nom de fichier .one.
0.1.0 : version pyOneNote (abandonnée — plantait sur les gros fichiers).

Usage :
    python kb_build.py                        # tous les .one (sauf sections filtrées)
    python kb_build.py "Tickets résolus.one"  # un fichier
    python kb_build.py --db /media/red/Samsung2TB/SAP_KB/sap_kb.db
"""
import os
import re
import sys
import csv
import sqlite3
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from onenote_extract import extract_pages, norm  # noqa: E402

DEFAULT_DB = os.environ.get("SAP_KB_DB", "/media/red/Samsung2TB/SAP_KB/sap_kb.db")
ONENOTE_DIR = os.path.join(HERE, "..", "OneNote")
CSV_SCAN = os.path.join(HERE, "..", "onenote_scan.csv")

SKIP_SECTIONS = {"email important", "Notes rapides", "Bordel en attente", "Info personnel"}

ID_RE = re.compile(r"\b(CS\d{7}|CHG\d{7,10}|INC\d{8,})\b", re.IGNORECASE)
TABLE_RE = re.compile(r"\bT\d{3}[A-Z0-9]{0,4}\b")

CLIENT_MAP = {
    "RKT": "RECKITT", "RECKITT": "RECKITT",
    "LEO": "LEO PHARMA",
    "ABV": "ABBVIE", "ABBVIE": "ABBVIE",
    "CORNING": "CORNING", "CORFR": "CORNING", "CRN": "CORNING",
    "ASTELLAS": "ASTELLAS", "AST": "ASTELLAS",
    "AKZO": "AKZO NOBEL", "AKN": "AKZO NOBEL",
    "ALCON": "ALCON",
    "LONZA": "LONZA",
}


def fix_mojibake(s: str) -> str:
    """Répare le double-encodage type 'Tickets rÃ©solus' -> 'Tickets résolus'.

    Ne s'applique que si la chaîne est un mojibake valide (sinon on garde l'original).
    """
    if not s or ("Ã" not in s and "Â" not in s and "�" not in s):
        return s
    try:
        return s.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s


def detect_client(title: str, body: str) -> str:
    hay = f"{title} {body[:200]}".upper()
    m = re.search(r"-\s*([A-Z]{2,8})\s*[-_]", title.upper())
    if m and m.group(1) in CLIENT_MAP:
        return CLIENT_MAP[m.group(1)]
    for code, name in CLIENT_MAP.items():
        if re.search(rf"\b{re.escape(code)}\b", hay):
            return name
    return ""


def load_onenote_csv():
    """Charge le CSV → (map globale norm(title)->infos, liste de tous les titres)."""
    title_map = {}
    titles = []
    if not os.path.exists(CSV_SCAN):
        print(f"  !! CSV introuvable : {CSV_SCAN}")
        return title_map, titles
    with open(CSV_SCAN, encoding="utf-8-sig", errors="replace") as fh:
        for row in csv.DictReader(fh, delimiter=";"):
            title = fix_mojibake(row.get("page_title", "").strip())
            if not title:
                continue
            info = {
                "title": title,
                "id": (row.get("id", "") or "").strip().upper(),
                "hyperlink": row.get("hyperlink", ""),
                "section": fix_mojibake(row.get("section", "").strip()),
            }
            titles.append(title)
            title_map.setdefault(norm(title), info)
    return title_map, titles


def section_from_filename(path: str) -> str:
    return os.path.splitext(os.path.basename(path))[0]


def create_schema(con):
    con.executescript(
        """
        DROP TABLE IF EXISTS docs;
        DROP TABLE IF EXISTS docs_fts;
        CREATE TABLE docs (
            id            INTEGER PRIMARY KEY,
            source        TEXT,
            section       TEXT,
            title         TEXT,
            ticket_ids    TEXT,
            client        TEXT,
            tables_sap    TEXT,
            onenote_link  TEXT,
            evidence_path TEXT,
            body          TEXT
        );
        CREATE VIRTUAL TABLE docs_fts USING fts5(
            title, ticket_ids, tables_sap, body,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
    )


def ingest_onenote(con, files, title_map, all_titles):
    n_pages = n_ids = n_linked = 0
    for path in files:
        section = fix_mojibake(section_from_filename(path))
        if section in SKIP_SECTIONS:
            print(f"  (ignoré : section filtrée {section!r})")
            continue
        print(f"  extraction {os.path.basename(path)} …", flush=True)
        try:
            pages = extract_pages(path, all_titles)
        except Exception as e:  # noqa: BLE001
            print(f"    !! échec extraction {path}: {e!r}")
            continue
        print(f"    → {len(pages)} pages", flush=True)
        for p in pages:
            title = p["title"]
            body = p["text"]
            if not (title.strip() or body.strip()):
                continue
            info = title_map.get(norm(title), {})
            blob = f"{title}\n{body}"
            ids = sorted(set(m.group(0).upper() for m in ID_RE.finditer(blob)))
            csv_id = info.get("id", "")
            if csv_id and csv_id not in ids:
                ids.insert(0, csv_id)
            tables = sorted(set(m.group(0).upper() for m in TABLE_RE.finditer(blob)))
            client = detect_client(title, body)
            link = info.get("hyperlink", "")
            ids_s, tables_s = " ".join(ids), " ".join(tables)
            if ids_s:
                n_ids += 1
            if link:
                n_linked += 1
            cur = con.execute(
                "INSERT INTO docs(source,section,title,ticket_ids,client,tables_sap,"
                "onenote_link,evidence_path,body) VALUES(?,?,?,?,?,?,?,?,?)",
                ("onenote", section, title, ids_s, client, tables_s, link, "", body),
            )
            con.execute(
                "INSERT INTO docs_fts(rowid,title,ticket_ids,tables_sap,body) VALUES(?,?,?,?,?)",
                (cur.lastrowid, title, ids_s, tables_s, body),
            )
            n_pages += 1
    return n_pages, n_ids, n_linked


def main():
    ap = argparse.ArgumentParser(description="Construit sap_kb.db (RAG SQLite/FTS5)")
    ap.add_argument("files", nargs="*", help="fichiers .one (défaut : tous)")
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--onenote-dir", default=ONENOTE_DIR)
    args = ap.parse_args()

    if args.files:
        files = [f if os.path.isabs(f) else os.path.join(args.onenote_dir, f)
                 for f in args.files]
    else:
        files = sorted(
            os.path.join(args.onenote_dir, f)
            for f in os.listdir(args.onenote_dir)
            if f.lower().endswith(".one")
        )

    print(f"Base   : {args.db}")
    title_map, all_titles = load_onenote_csv()
    print(f"CSV    : {len(all_titles)} titres OneNote (ancres + jointure)")
    print(f"Sources: {len(files)} fichier(s) .one\n")

    con = sqlite3.connect(args.db)
    create_schema(con)
    n_pages, n_ids, n_linked = ingest_onenote(con, files, title_map, all_titles)
    con.commit()
    total = con.execute("SELECT COUNT(*) FROM docs").fetchone()[0]
    con.close()

    print(f"\n✓ {n_pages} pages indexées | {n_ids} avec N° ticket | "
          f"{n_linked} avec lien OneNote | total docs = {total}")
    print(f"  → {args.db}")


if __name__ == "__main__":
    main()
