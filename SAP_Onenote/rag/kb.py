#!/usr/bin/env python3
"""
kb.py — Moteur de requête du RAG SAP (le "retrieval").

APP_VERSION = 0.1.0

C'est CE fichier que cloclo lance via Bash pour interroger la connaissance SAP
sans charger les Go de sources. Sortie compacte (titre, N° ticket, client, section,
extrait, lien OneNote, chemin evidence) — quelques centaines de tokens, pas 4 Go.

Change-log
----------
0.1.0 (2026-07-18) : recherche FTS5/BM25 + snippet + filtres --client/--source/--section.

Usage :
    python kb.py "MDC allègement retraite RKT"
    python kb.py "arrondi commercial" -k 5
    python kb.py "net social" --client RECKITT --json
"""
import os
import re
import sys
import json
import sqlite3
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))


def _default_db():
    """Emplacement de la base : $SAP_KB_DB, sinon le NVMe Samsung, sinon local."""
    env = os.environ.get("SAP_KB_DB")
    if env:
        return env
    for p in ("/media/red/Samsung2TB/SAP_KB/sap_kb.db", os.path.join(HERE, "sap_kb.db")):
        if os.path.exists(p):
            return p
    return os.path.join(HERE, "sap_kb.db")


DEFAULT_DB = _default_db()

# Caractères spéciaux FTS5 à neutraliser dans la requête utilisateur.
_FTS_SPECIAL = re.compile(r'["*():^]')


def build_match(query: str) -> str:
    """Transforme une requête libre en expression FTS5 tolérante.

    Chaque terme devient un préfixe (terme*) et on les relie par OR ; le
    classement BM25 fait remonter les docs qui matchent le plus de termes.
    Les identifiants (CS…, CHG…, INC…) et codes tables sont gardés tels quels.
    """
    query = _FTS_SPECIAL.sub(" ", query)
    terms = [t for t in re.split(r"\s+", query.strip()) if t]
    parts = []
    for t in terms:
        # un token alphanumérique -> recherche préfixe pour attraper les variantes
        safe = re.sub(r"[^\w\-]", "", t)
        if not safe:
            continue
        parts.append(f'"{safe}"*' if len(safe) >= 3 else f'"{safe}"')
    return " OR ".join(parts) if parts else '""'


def snippet(body: str, terms, width: int = 240) -> str:
    """Extrait un passage autour du premier terme trouvé."""
    if not body:
        return ""
    low = body.lower()
    pos = -1
    for t in terms:
        t = re.sub(r"[^\w\-]", "", t).lower()
        if not t:
            continue
        pos = low.find(t)
        if pos >= 0:
            break
    if pos < 0:
        pos = 0
    start = max(0, pos - width // 3)
    end = min(len(body), start + width)
    snip = body[start:end].replace("\n", " ")
    snip = re.sub(r"\s+", " ", snip).strip()
    return ("…" if start > 0 else "") + snip + ("…" if end < len(body) else "")


def search(db, query, k=8, client=None, source=None, section=None):
    con = sqlite3.connect(db)
    con.row_factory = sqlite3.Row
    match = build_match(query)
    where = ["docs_fts MATCH ?"]
    params = [match]
    if client:
        where.append("d.client = ?")
        params.append(client.upper())
    if source:
        where.append("d.source = ?")
        params.append(source)
    if section:
        where.append("d.section = ?")
        params.append(section)
    sql = f"""
        SELECT d.*, bm25(docs_fts) AS score
        FROM docs_fts
        JOIN docs d ON d.id = docs_fts.rowid
        WHERE {' AND '.join(where)}
        ORDER BY score
        LIMIT ?
    """
    params.append(k)
    try:
        rows = con.execute(sql, params).fetchall()
    except sqlite3.OperationalError as e:
        con.close()
        raise SystemExit(f"Erreur FTS5 ({e}). Requête traduite : {match}")
    con.close()
    return rows, match


def main():
    ap = argparse.ArgumentParser(description="Interroge le RAG SAP (sap_kb.db)")
    ap.add_argument("query", help="requête en langage libre / mots-clés")
    ap.add_argument("-k", type=int, default=8, help="nombre de résultats (défaut 8)")
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--client", help="filtre client (RECKITT, LEO PHARMA, …)")
    ap.add_argument("--source", choices=["onenote", "evidence"], help="filtre source")
    ap.add_argument("--section", help="filtre section OneNote (PCR, PCC, …)")
    ap.add_argument("--json", action="store_true", help="sortie JSON (pour un agent)")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"Base introuvable : {args.db}. Lance d'abord kb_build.py")

    rows, match = search(args.db, args.query, args.k, args.client, args.source, args.section)
    terms = re.split(r"\s+", args.query)

    if args.json:
        out = []
        for r in rows:
            out.append({
                "score": round(r["score"], 3),
                "ticket_ids": r["ticket_ids"],
                "client": r["client"],
                "section": r["section"],
                "title": r["title"],
                "snippet": snippet(r["body"], terms),
                "onenote_link": r["onenote_link"],
                "evidence_path": r["evidence_path"],
            })
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return

    if not rows:
        print(f"Aucun résultat pour : {args.query!r}  (FTS: {match})")
        return
    print(f"🔎 {args.query!r} — {len(rows)} résultat(s)\n")
    for i, r in enumerate(rows, 1):
        ids = r["ticket_ids"] or "—"
        head = f"{i}. [{r['section']}] {r['title']}"
        print(head)
        meta = f"   ticket: {ids}"
        if r["client"]:
            meta += f"  |  client: {r['client']}"
        if r["tables_sap"]:
            meta += f"  |  tables: {r['tables_sap']}"
        print(meta)
        snip = snippet(r["body"], terms)
        if snip:
            print(f"   « {snip} »")
        if r["onenote_link"]:
            print(f"   ↳ {r['onenote_link'][:110]}")
        print()


if __name__ == "__main__":
    main()
