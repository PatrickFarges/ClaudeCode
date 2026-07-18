#!/usr/bin/env python3
"""
onenote_extract.py — Extraction ROBUSTE du contenu des .one sous Linux (sans OneNote).

APP_VERSION = 0.2.0

Change-log
----------
0.2.0 (2026-07-18) : abandon de pyOneNote (plante sur les gros fichiers réels :
                     NotImplementedError 'ArrayOfPropertyValues' 0x10 sur Utility.one,
                     AttributeError 'data' sur Tickets résolus 1,25 Go). Nouvelle
                     méthode : lecture texte au niveau OCTET via `strings`
                     (UTF-16LE + 8-bit), filtrage par lisibilité, puis segmentation
                     en pages en utilisant les titres connus (onenote_scan.csv) comme
                     ancres. Ne plante jamais, marche sur les 7 fichiers.
0.1.0 : première version basée pyOneNote (abandonnée).

Principe
--------
OneNote stocke le texte des pages en clair dans le .one, en deux encodages :
  - UTF-16LE : titres + texte français accentué   -> `strings -e l`
  - 8-bit    : blocs anglais (schémas PCR, etc.)   -> `strings -e S`
On récupère les deux flux avec leur offset, on les fusionne dans l'ordre du fichier,
on jette le bruit (runs illisibles), puis on découpe en pages : chaque fois qu'un
segment correspond EXACTEMENT à un titre de page connu (fourni par le CSV), on ouvre
une nouvelle page et le texte qui suit lui est rattaché.

Usage :
    from onenote_extract import extract_pages
    pages = extract_pages("OneNote/PCR.one", known_titles_normset)
"""
import re
import subprocess
import unicodedata

# Caractères considérés "lisibles" (FR/EN + technique SAP).
_GOOD = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    " .,;:/=+-_()[]{}%'\"\n\t°&<>#*@!?|\\$€\r"
    "éèêëàâäîïôöùûüçÿœæ ÉÈÊËÀÂÄÎÏÔÖÙÛÜÇ"
)

MIN_LEN = 4  # longueur minimale d'un run de texte
SCORE_MIN = 0.75  # fraction minimale de caractères lisibles pour garder un run

# Un vrai run de texte contient au moins un mot de 4+ lettres (le binaire, non).
_WORD_RE = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿ]{4,}")

# Bruit OneNote récurrent (métadonnées / structure non pertinentes pour la recherche).
_NOISE_RE = re.compile(
    r"resolutionId|provider=|O365id|localId|=\"AD\"|hash=|"          # ids de résolution
    r"PageTitle|PageDateTime|OneNote|NotebookManagement|"           # marqueurs OneNote
    r"IHDR|sRGB|gAMA|pHYs|IDAT|IEND|PLTE|tEXt|bKGD|cHRM|iTXt|zTXt|" # chunks PNG
    r"JFIF|Exif|Adobe|Photoshop|"                                   # entêtes image
    r"Lucida Sans|Segoe|Calibri|Cambria|Consolas|Verdana|Tahoma|"   # polices
    r"Times New Roman|Courier|MS Gothic|Typewriter|Arial",
    re.IGNORECASE,
)

# Run qui n'est qu'un GUID / une balise interne.
_GUID_RE = re.compile(r"^[<{]?\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{20,}")


def _keep_run(txt: str) -> bool:
    """Filtre un run : rejette binaire, caractères de remplacement et métadonnées."""
    if "�" in txt:
        return False
    if _score(txt) < SCORE_MIN:
        return False
    if not _WORD_RE.search(txt):
        return False
    if _GUID_RE.match(txt.strip()):
        return False
    if _NOISE_RE.search(txt):
        return False
    return True


def norm(s: str) -> str:
    """Forme normalisée pour comparer/joindre des titres (sans accents, minuscule)."""
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s).strip().lower()


def _score(t: str) -> float:
    if not t:
        return 0.0
    return sum(1 for c in t if c in _GOOD) / len(t)


def _clean(text: str) -> str:
    text = text.replace("\x00", " ").replace("\xa0", " ")
    text = "".join(ch if (ch >= " " or ch in "\n\t") else " " for ch in text)
    lines = [re.sub(r"[ \t]+", " ", ln).strip() for ln in text.splitlines()]
    return "\n".join(ln for ln in lines if ln)


def _strings(path: str, mode: str, min_len: int = MIN_LEN):
    """Yield (offset, texte) pour chaque run extrait par `strings -e <mode>`."""
    proc = subprocess.Popen(
        ["strings", "-t", "d", "-e", mode, "-n", str(min_len), path],
        stdout=subprocess.PIPE, encoding="utf-8", errors="replace",
    )
    pat = re.compile(r"^\s*(\d+)\s(.*)$")
    try:
        for line in proc.stdout:
            m = pat.match(line.rstrip("\n"))
            if m:
                yield int(m.group(1)), m.group(2)
    finally:
        proc.stdout.close()
        proc.wait()


def extract_segments(path: str):
    """Flux ordonné de (offset, texte) : UTF-16LE + 8-bit fusionnés, bruit filtré."""
    segs = []
    for mode in ("l", "S"):  # l = UTF-16 little-endian, S = 8-bit
        for off, txt in _strings(path, mode):
            if _keep_run(txt):
                segs.append((off, txt))
    segs.sort(key=lambda x: x[0])
    return segs


def extract_pages(path: str, known_titles):
    """
    Segmente le .one en pages à l'aide des titres connus.

    known_titles : itérable de titres de page (bruts) issus du CSV OneNote.
    Retour : [{"title": <titre canonique>, "text": <corps>, "n_runs": int}, ...]
             dédoublonné par titre (on garde le corps le plus long).
    """
    title_map = {}
    for t in known_titles:
        nt = norm(t)
        if nt:
            title_map.setdefault(nt, t)

    segs = extract_segments(path)

    pages = []
    cur = None
    for _off, txt in segs:
        nt = norm(txt)
        if nt in title_map:  # frontière de page
            if cur is not None:
                pages.append(cur)
            cur = {"title": title_map[nt], "runs": []}
        else:
            if cur is None:
                cur = {"title": "", "runs": []}
            cur["runs"].append(txt)
    if cur is not None:
        pages.append(cur)

    # Assemble + dédoublonne par titre (garde le corps le plus long).
    best = {}
    for p in pages:
        body = _clean("\n".join(p["runs"]))
        key = norm(p["title"])
        cand = {"title": p["title"], "text": body, "n_runs": len(p["runs"])}
        if key not in best or len(body) > len(best[key]["text"]):
            best[key] = cand
    return list(best.values())


if __name__ == "__main__":
    import sys
    import csv
    import os

    path = sys.argv[1] if len(sys.argv) > 1 else "OneNote/PCR.one"
    # charge tous les titres du CSV comme ancres
    csv_path = os.path.join(os.path.dirname(__file__), "..", "onenote_scan.csv")
    titles = []
    with open(csv_path, encoding="utf-8-sig", errors="replace") as fh:
        for row in csv.DictReader(fh, delimiter=";"):
            titles.append(row.get("page_title", ""))
    pages = extract_pages(path, titles)
    print(f"[{path}] {len(pages)} pages\n")
    for p in pages[:20]:
        print(f"--- {p['title']!r} ({len(p['text'])} car.)")
        print(p["text"][:300])
        print()
