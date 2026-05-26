"""
generate_wtc_absences.py — Générateur du Wagetype Catalog Absences (multi-clients)

Modèle : `GFK Original Absence Catalog.xls` (catalogue NGA pour le client GFK)
Cibles : un fichier .xlsx par client (AKN, ABV, …) configuré dans CLIENT_CONFIGS.

Branding NGA → STRADA :
  - Logo NGA + Human Resources → logo Strada (logo_strada.png)
  - Mauve foncé  FF660066 → vert foncé Strada FF084028
  - Mauve moyen  FF993366 → vert moyen Strada FF207F4F
  - Violet       FF800080 → vert clair Strada FF18D878

Phases :
  Phase 1 — Copie du GFK + substitution logo + substitution couleurs
  Phase 2.1 — Injection des vraies données client (T554S + T554T, langue F)
  Phase 2.2 — Remplissage cols D-I via T554C → T512T + T511 (unités)

Changelog :
  v0.1.0 — Phase 1 : copie + rebranding visuel Strada
  v0.2.0 — Phase 2.0 : onglet <CLIENT>_Data avec les catégories d'absences
  v0.3.0 — Phase 2.1 : injection des vraies données dans l'onglet principal
  v0.4.0 — Phase 2.2 : remplissage cols D, E, F, G, H, I via T554C/T512T/T511
  v0.5.0 — Multi-clients : refactoring pour supporter ABV en plus de AKN.
           CLI `--client AKN|ABV`. Gestion de la colonne 'L.HCM' (AKN)
           OU 'GrPay' (ABV) selon la version de dump SAP. Tous les paramètres
           (GrSdP, GrPay, dossier, fichiers, sortie) sont dans CLIENT_CONFIGS.
  v0.6.0 — Remplissage cols J (Nombre) et K (Montant) via T511 col J ('C').
           Logique : rubrique recherchée dans T511.C = WTC col A → D → G ;
           la valeur trouvée en T511 col J (caractère ' ', 'A', '0'..'9') est
           traduite via NOMBRE_MONTANT_MAP en texte 'soit nbr / aucun nbr /
           oblig. / facult. / ou nbr' et symétrique côté montant.
  v0.7.0 — Inversion ordre de lookup : D → G → A (les CatAbsP en col A peuvent
           collisionner par hasard avec des rubriques de paie dans T511, donc on
           privilégie les vraies rubriques Paiement/Retenue). Si T511 col C est
           vide sur la ligne trouvée → cols J et K du WTC laissées vides (cas
           fréquent sur rubriques 9000+ chez certains clients).
  v0.8.0 — Remplissage col L (Unité de temps — sous-section "Pilotage Paie") :
           même lookup que F et I (via T511.UnT) mais en partant de la rubrique
           Paiement (col D), avec fallback sur la rubrique Retenue (col G).
           La col A (CatAbsP) n'est PAS utilisée ici puisque L est dans la zone
           Pilotage Paie — basée uniquement sur les rubriques de paie.
  v0.9.0 — Cols P/Q/R/S (pénalisants) via les 10 colonnes CLABS de T554C.
           Pour chaque règle de valorisation, on lit la liste des CLABS et on
           coche ■ dans la col WTC correspondante si la classe figure dedans :
             P = CLABS 30 (Pénalisant 13ème mois)
             Q = CLABS 40 (Pénalisant Prime de Vacances)
             R = CLABS 50 (Pénalisant Prime d'ancienneté)
             S = CLABS 70 (Pénalisant RATP → transport)
           T554E sert seulement de référentiel CLABS → libellé (non utilisée
           pour la jointure, qui se fait via Règle de valorisat. dans T554C).
"""
from __future__ import annotations

APP_VERSION = "0.9.0"

import argparse
import shutil
import subprocess
from pathlib import Path

import openpyxl
from openpyxl.drawing.image import Image as XLImage
from openpyxl.styles import PatternFill, Font

# ---- Chemins communs ------------------------------------------------------

ROOT = Path(__file__).resolve().parent
# Template .xlsx pré-converti depuis GFK Original Absence Catalog.xls
# (la conversion .xls→.xlsx est faite une fois pour toutes côté Linux/LibreOffice
#  et le résultat est commit dans le projet pour être utilisable sous Windows
#  sans dépendance externe)
GFK_TEMPLATE = ROOT / "GFK Original Absence Catalog.xlsx"
GFK_XLS_LEGACY = ROOT / "GFK Original Absence Catalog.xls"
LOGO_STRADA = ROOT / "logo_strada.png"

# Mapping numéros → libellés d'unités de temps (T511 col "UnT" → humain)
UNITS_MAP_FILE = ROOT / "numeros_vs_unités"

# ---- Configurations clients -----------------------------------------------

# Chaque client a son dossier de dumps SAP. Les noms de fichiers peuvent varier
# en casse (T554S.xlsx vs t554s.XLSX) selon la version du dump.
CLIENT_CONFIGS: dict[str, dict] = {
    "AKN": {
        "dir": ROOT / "AKN_17.05.2026",
        "tables": {  # case-insensitive lookup via _resolve_table()
            "T554S": "T554S.xlsx", "T554T": "T554T.xlsx", "T554C": "T554C.xlsx",
            "T511": "T511.xlsx", "T512T": "T512T.xlsx",
            "T508A": "T508A.xlsx", "Y00BA": "Y00BA_TAB_COMPAN.xlsx",
        },
        "grsdp": "6",       # Groupe subdivisions personnel
        "lang_fr": "F",     # Code langue français
        "grpay": "06",      # Groupe de paie / L.HCM
        "mdt": "984",       # Mandant SAP
        "output": ROOT / "AKN France Absences-Presences Catalogue.xlsx",
        "title_replace": ("FR Absences", "AKN Absences"),
    },
    "ABV": {
        "dir": ROOT / "ABV",
        "tables": {
            "T554S": "t554s.XLSX", "T554T": "t554t.XLSX", "T554C": "t554c.XLSX",
            "T511": "t511.XLSX", "T512T": "T512T.XLSX",
            "T508A": "t508a.XLSX", "Y00BA": "Y00BA_TAB_COMPAN.XLSX",
        },
        "grsdp": "6",       # France (LCC=FR1)
        "lang_fr": "F",
        "grpay": "06",      # ABV mappé à GrPay=06 dans Y00BA
        "mdt": None,        # ABV : pas de filtre Mdt (dumps sans colonne fiable)
        "output": ROOT / "ABV WTC.xlsx",
        "title_replace": ("FR Absences", "ABV Absences"),
    },
}

# Palette Strada (déjà utilisée dans patch_colors)
STRADA_DARK = "FF084028"   # vert très foncé (logo + bandeau titre)
STRADA_MED = "FF207F4F"    # vert moyen (entêtes catégorie)
STRADA_LIGHT = "FF18D878"  # vert clair
YELLOW = "FFFFFF99"        # jaune données (palette GFK conservée)
GREY_LIGHT = "FFC0C0C0"    # gris clair entêtes secondaires
GREY_MED = "FF969696"      # gris moyen entêtes groupes
WHITE = "FFFFFFFF"
BLACK = "FF000000"

# Mise en forme onglet principal
MAIN_SHEET = "Absences-Présences"
HEADER_ROW_END = 7        # lignes 1-7 = entêtes (à conserver)
DATA_ROW_START = 8        # première ligne de données
DATA_ROW_END = 156        # dernière ligne potentielle de données
MAIN_COL_COUNT = 25       # colonnes utiles A-Y

# Fichier intermédiaire (conversion .xls → .xlsx via libreoffice)
TMP_DIR = ROOT / ".tmp_build"
GFK_XLSX = TMP_DIR / "GFK Original Absence Catalog.xlsx"

# ---- Mapping T511.C → texte (Nombre, Montant) -----------------------------
# Le caractère trouvé en T511 col J (entête 'C') sur la ligne dont la rubrique
# correspond donne le couple (texte_Nombre, texte_Montant) à écrire dans les
# cols J et K du WTC. Référence : fichier 'nombre_montant' (racine projet).
# Note : un T511.C vide → J et K du WTC laissés vides (géré en amont).
NOMBRE_MONTANT_MAP: dict[str, tuple[str, str]] = {
    'A': ('soit nbr',  'soit mnt'),
    '0': ('aucun nbr', 'aucun mnt'),
    '1': ('aucun nbr', 'oblig.'),
    '2': ('oblig.',    'aucun mnt'),
    '3': ('ou nbr',    'au moins le mnt'),
    '4': ('facult.',   'oblig.'),
    '5': ('oblig.',    'facult.'),
    '6': ('oblig.',    'oblig.'),
    '7': ('facult.',   'facult.'),
    '8': ('aucun nbr', 'aucun mnt'),
    '9': ('aucun nbr', 'facult.'),
}


# ---- Palette de substitution NGA → STRADA ----------------------------------
# Format hex AARRGGBB (alpha = FF). openpyxl utilise des hex en argb.
COLOR_MAP = {
    "FF660066": "FF084028",  # mauve très foncé → vert foncé Strada
    "FF993366": "FF207F4F",  # mauve bordeaux  → vert moyen Strada
    "FF800080": "FF18D878",  # violet          → vert clair Strada
}


def convert_xls_to_xlsx(xls_path: Path, out_dir: Path) -> Path:
    """Convertit le .xls en .xlsx via LibreOffice headless (Linux uniquement).
    Renvoie le chemin du .xlsx produit. Utilisé pour générer le template
    une fois pour toutes ; sur Windows on utilise le .xlsx pré-converti."""
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"      Conversion .xls → .xlsx via libreoffice…")
    result = subprocess.run(
        ["libreoffice", "--headless", "--convert-to", "xlsx",
         str(xls_path), "--outdir", str(out_dir)],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"libreoffice conversion failed: {result.stderr}")
    produced = out_dir / (xls_path.stem + ".xlsx")
    if not produced.exists():
        raise FileNotFoundError(f"Conversion result not found: {produced}")
    return produced


def load_template(template_path: Path, xls_fallback: Path):
    """Charge le template .xlsx. Si absent, tente de le générer depuis le .xls
    via LibreOffice (uniquement disponible sur Linux/Mac avec LibreOffice installé)."""
    if template_path.exists():
        print(f"[1/5] Chargement template {template_path.name}…")
        return openpyxl.load_workbook(template_path)
    if not xls_fallback.exists():
        raise FileNotFoundError(
            f"Ni le template .xlsx ({template_path}) ni le .xls de fallback "
            f"({xls_fallback}) ne sont disponibles."
        )
    print(f"[1/5] Template .xlsx absent — conversion depuis .xls…")
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    converted = convert_xls_to_xlsx(xls_fallback, TMP_DIR)
    shutil.copy(converted, template_path)
    return openpyxl.load_workbook(template_path)


def patch_colors(wb) -> tuple[int, int]:
    """Substitue les couleurs mauves NGA par les couleurs vertes Strada
    sur toutes les feuilles. Renvoie (nb_cellules_fill_patches, nb_cellules_font_patches)."""
    print(f"[3/5] Substitution des couleurs NGA → Strada…")
    fill_count = 0
    font_count = 0
    for sname in wb.sheetnames:
        ws = wb[sname]
        for row in ws.iter_rows():
            for cell in row:
                # Fill background
                try:
                    if cell.fill and cell.fill.patternType and cell.fill.fgColor:
                        rgb = cell.fill.fgColor.rgb
                        if rgb and str(rgb) in COLOR_MAP:
                            new_rgb = COLOR_MAP[str(rgb)]
                            cell.fill = PatternFill(
                                patternType=cell.fill.patternType,
                                fgColor=new_rgb,
                                bgColor=cell.fill.bgColor.rgb if cell.fill.bgColor else "00000000",
                            )
                            fill_count += 1
                except (AttributeError, TypeError):
                    pass
                # Font color
                try:
                    if cell.font and cell.font.color and cell.font.color.rgb:
                        rgb = cell.font.color.rgb
                        if rgb and str(rgb) in COLOR_MAP:
                            new_rgb = COLOR_MAP[str(rgb)]
                            new_font = Font(
                                name=cell.font.name,
                                size=cell.font.size,
                                bold=cell.font.bold,
                                italic=cell.font.italic,
                                underline=cell.font.underline,
                                color=new_rgb,
                            )
                            cell.font = new_font
                            font_count += 1
                except (AttributeError, TypeError):
                    pass
    print(f"      → {fill_count} fills + {font_count} fontes patchées")
    return fill_count, font_count


def replace_logos(wb, logo_path: Path) -> int:
    """Remplace toutes les images des onglets par le logo Strada.
    Les anciens logos NGA sont supprimés et remplacés à la même position/taille
    (avec ratio préservé)."""
    print(f"[2/5] Remplacement des logos NGA → Strada…")
    if not logo_path.exists():
        raise FileNotFoundError(f"Logo Strada introuvable : {logo_path}")

    replaced = 0
    for sname in wb.sheetnames:
        ws = wb[sname]
        old_images = list(ws._images)
        if not old_images:
            continue
        print(f"      Sheet {sname!r}: {len(old_images)} image(s) à remplacer")
        # Capture les anchors avant de vider la liste
        anchors = [img.anchor for img in old_images]
        # Conserver les dimensions cible de chaque image originale (en EMU)
        # (openpyxl Image utilise width/height en pixels via PIL)
        from PIL import Image as PILImage
        ref_dims = []
        for img in old_images:
            # essayer de récupérer width/height ; fallback sur défaut
            w = getattr(img, "width", None)
            h = getattr(img, "height", None)
            ref_dims.append((w, h))
        # Vider la liste interne
        ws._images = []
        # Remettre une image Strada par anchor
        for anchor, (w, h) in zip(anchors, ref_dims):
            new_img = XLImage(str(logo_path))
            # Respect du ratio original du logo Strada (496×103)
            if w and h:
                # forcer à la même surface que l'original mais avec le ratio Strada
                ratio = 496 / 103
                # si on connait h, on adapte w pour conserver le ratio
                new_img.height = h
                new_img.width = int(h * ratio)
            new_img.anchor = anchor
            ws.add_image(new_img)
            replaced += 1
    print(f"      → {replaced} image(s) substituée(s)")
    return replaced


def load_units_map() -> dict[str, str]:
    """Lit numeros_vs_unités → dict { '001': 'Heures', '010': 'Jours', ... }.
    Ignore les 2 premières lignes d'en-tête explicatives (préfixées par '*')."""
    print(f"[4/5 c] Chargement mapping unités de temps ({UNITS_MAP_FILE.name})…")
    out: dict[str, str] = {}
    for raw in UNITS_MAP_FILE.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('*') or '=' not in line:
            continue
        # format possible "<n>\t<code>=<libellé>" ou "<code>=<libellé>"
        parts = line.split('\t', 1)
        kv = parts[-1].strip()
        code, _, label = kv.partition('=')
        code = code.strip()
        label = label.strip()
        if code and label:
            out[code] = label
    print(f"      → {len(out)} unités mappées")
    return out


def _resolve_table(cfg: dict, table_name: str) -> Path:
    """Renvoie le chemin de la table en gérant la casse (T554S.xlsx vs t554s.XLSX)."""
    p = cfg["dir"] / cfg["tables"][table_name]
    if p.exists():
        return p
    target = cfg["tables"][table_name].lower()
    for f in cfg["dir"].iterdir():
        if f.name.lower() == target:
            return f
    raise FileNotFoundError(f"Table {table_name} introuvable dans {cfg['dir']}")


def _idx(hdr, *names) -> int | None:
    """Renvoie l'index de la première colonne trouvée parmi 'names', ou None."""
    for n in names:
        if n in hdr:
            return hdr.index(n)
    return None


def _row_matches(r, idx_mdt, mdt_val, idx_grpay, grpay_val) -> bool:
    """Helper de filtrage Mdt + L.HCM/GrPay (chacun optionnel)."""
    if idx_mdt is not None and mdt_val is not None and r[idx_mdt] != mdt_val:
        return False
    if idx_grpay is not None and r[idx_grpay] != grpay_val:
        return False
    return True


def load_t511(cfg: dict) -> dict[str, dict]:
    """Charge T511 → dict { rubrique: {'unt': ..., 'c': ...} }.

    Filtre Mdt (si présent et défini) + L.HCM ou GrPay (selon la version du
    dump). Garde la version la plus récente (date Fin la plus haute).

    Le champ 'c' (entête T511 col J = 'C') sert au remplissage des cols J et K
    du WTC via NOMBRE_MONTANT_MAP. Espace et chaîne vide y sont normalisés à ' '.
    """
    table = _resolve_table(cfg, "T511")
    print(f"[4/5 d] Chargement T511 ({table.name})…")
    wb = openpyxl.load_workbook(table, data_only=True, read_only=True)
    ws = wb.active
    rows = ws.iter_rows(values_only=True)
    hdr = next(rows)
    iM = _idx(hdr, 'Mdt')
    iG = _idx(hdr, 'L.HCM', 'GrPay')
    iR = hdr.index('Rubrique')
    iU = hdr.index('UnT')
    iC = hdr.index('C')
    iF = hdr.index('Fin')
    by_rub: dict[str, tuple] = {}
    for r in rows:
        if not _row_matches(r, iM, cfg["mdt"], iG, cfg["grpay"]):
            continue
        rub = r[iR]
        if not rub:
            continue
        fin = r[iF]
        unt = r[iU] or ''
        c_raw = r[iC]
        c = c_raw if isinstance(c_raw, str) and c_raw != '' else ' '
        prev = by_rub.get(rub)
        if prev is None or (fin and (not prev[2] or fin > prev[2])):
            by_rub[rub] = (unt, c, fin)
    wb.close()
    out = {k: {'unt': v[0], 'c': v[1]} for k, v in by_rub.items()}
    print(f"      → {len(out)} rubriques T511 trouvées")
    return out


def load_t512t(cfg: dict) -> dict[str, str]:
    """Charge T512T → dict { rubrique: libellé FR }."""
    table = _resolve_table(cfg, "T512T")
    print(f"[4/5 e] Chargement T512T ({table.name}, Langue={cfg['lang_fr']})…")
    wb = openpyxl.load_workbook(table, data_only=True, read_only=True)
    ws = wb.active
    rows = ws.iter_rows(values_only=True)
    hdr = next(rows)
    iM = _idx(hdr, 'Mdt')
    iL = hdr.index('Langue')
    iH = _idx(hdr, 'L.HCM', 'GrPay')
    iR = hdr.index('Rubrique')
    iT = hdr.index('Libellé de rubrique')
    out: dict[str, str] = {}
    for r in rows:
        if not _row_matches(r, iM, cfg["mdt"], iH, cfg["grpay"]):
            continue
        if r[iL] != cfg["lang_fr"]:
            continue
        rub = r[iR]
        if not rub:
            continue
        out[rub] = r[iT] or ''
    wb.close()
    print(f"      → {len(out)} libellés FR trouvés")
    return out


def _classify_rubrique(rub: str, libelle: str) -> str:
    """Renvoie 'paiement', 'retenue' ou '' selon le libellé T512T.
    L'ordre des sous-blocs dans T554C n'est pas fiable (parfois retenue en
    premier), donc on s'appuie sur la convention de nommage des libellés AKN :
       - 'Paiement…', 'Paiem.…' → paiement
       - 'Retenue…', 'Ret.…', 'Reten…' → retenue
    """
    if not libelle:
        return ''
    low = libelle.lower().lstrip()
    if low.startswith(('paiement', 'paiem.', 'paiem ', 'pay.', 'pay ')):
        return 'paiement'
    if low.startswith(('retenue', 'ret.', 'ret ', 'reten')):
        return 'retenue'
    return ''


def load_t554c_rules(cfg: dict, t512t: dict[str, str]) -> dict[str, dict]:
    """Charge T554C → dict { règle_valorisation: {'paiement': rub, 'retenue': rub} }.

    T554C contient 15 sous-blocs (DH, Pourc., Tp, RB, Rubrique, RègleJourn). Pour
    chaque règle de valorisation on extrait les 2 premières rubriques non vides,
    puis on les classe en Paiement/Retenue via les libellés T512T (les libellés
    AKN commencent par 'Paiement…' ou 'Retenue…' — fiable).
    Si plusieurs lignes existent pour la même règle (versions par dates), on garde
    celle dont la date Fin est la plus haute.
    """
    table = _resolve_table(cfg, "T554C")
    print(f"[4/5 f] Chargement T554C ({table.name}, Grpe={cfg['grpay']})…")
    wb = openpyxl.load_workbook(table, data_only=True, read_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    hdr = rows[0]
    iM = _idx(hdr, 'Mdt')
    iL = _idx(hdr, 'L.HCM', 'GrPay')
    iG = hdr.index('Grpe')
    iR = hdr.index('Règle de valorisat.')
    iF = hdr.index('Fin')

    # Indices des 15 colonnes "Rubrique" (2e moitié) et des 10 colonnes "CLABS"
    # (1re moitié — sous-blocs de pénalisation).
    rubrique_cols = [i for i, h in enumerate(hdr) if h == 'Rubrique']
    clabs_cols = [i for i, h in enumerate(hdr) if h == 'CLABS']

    by_rule: dict[str, tuple] = {}
    n_swapped = 0
    for r in rows[1:]:
        if not _row_matches(r, iM, cfg["mdt"], iL, cfg["grpay"]):
            continue
        if r[iG] != cfg["grpay"]:
            continue
        rule = r[iR]
        if not rule:
            continue
        fin = r[iF]
        rubriques = [r[i] for i in rubrique_cols if r[i]]
        first = rubriques[0] if rubriques else ''
        second = rubriques[1] if len(rubriques) >= 2 else ''

        # Classification par libellé (T512T) — l'ordre dans T554C n'est pas fiable
        c1 = _classify_rubrique(first, t512t.get(first, ''))
        c2 = _classify_rubrique(second, t512t.get(second, ''))
        paiement, retenue = first, second
        if c1 == 'retenue' and c2 == 'paiement':
            paiement, retenue = second, first
            n_swapped += 1
        elif c1 == 'retenue' and not c2:
            paiement, retenue = '', first
        elif c1 == 'paiement' and c2 == 'paiement':
            # Cas rare — on garde l'ordre
            pass

        # Liste des CLABS pénalisées (ignore '0' qui veut dire "pas pénalisant")
        clabs = {str(r[i]) for i in clabs_cols
                 if r[i] not in (None, '', '0')}

        prev = by_rule.get(rule)
        if prev is None or (fin and (not prev[3] or fin > prev[3])):
            by_rule[rule] = (paiement, retenue, clabs, fin)
    wb.close()
    out = {k: {'paiement': v[0], 'retenue': v[1], 'clabs': v[2]}
           for k, v in by_rule.items()}
    print(f"      → {len(out)} règles de valorisation indexées "
          f"({n_swapped} swaps Paiement/Retenue corrigés)")
    return out


def load_client_data(cfg: dict) -> list[dict]:
    """Charge les catégories d'absences pour le client depuis T554S + T554T.

    Filtre :
      - T554S : GrSdP = cfg['grsdp']
      - T554T : GrSdP = cfg['grsdp'] ET Langue = cfg['lang_fr']

    Renvoie une liste de dicts ordonnée par CatAbsP.
    """
    table_s = _resolve_table(cfg, "T554S")
    print(f"[4/5 a] Chargement T554S ({table_s.name}, GrSdP={cfg['grsdp']})…")
    wb554s = openpyxl.load_workbook(table_s, data_only=True, read_only=False)
    ws = wb554s.active
    rows = list(ws.iter_rows(values_only=True))
    hdr = rows[0]
    iS = {name: hdr.index(name) for name in
          ('GrSdP', 'CatAbsP', 'Règle de valorisat.', 'Classe', 'TypAb', 'Fin', 'Début')}
    # Une CatAbsP peut avoir plusieurs lignes (versions par dates). On garde
    # celle dont la date Fin est la plus haute (la plus récente / 9999-12-31).
    by_cat = {}
    for r in rows[1:]:
        if r[iS['GrSdP']] != cfg["grsdp"]:
            continue
        cat = r[iS['CatAbsP']]
        if not cat:
            continue
        fin = r[iS['Fin']]
        prev = by_cat.get(cat)
        if prev is None or (fin and (not prev['_fin'] or fin > prev['_fin'])):
            by_cat[cat] = {
                'CatAbsP': cat,
                'RegleValorisat': r[iS['Règle de valorisat.']] or '',
                'Classe': r[iS['Classe']] or '',
                'TypAb': r[iS['TypAb']] or '',
                '_fin': fin,
            }
    print(f"      → {len(by_cat)} catégories trouvées")

    table_t = _resolve_table(cfg, "T554T")
    print(f"[4/5 b] Chargement T554T ({table_t.name}, Langue={cfg['lang_fr']}, "
          f"GrSdP={cfg['grsdp']})…")
    wb554t = openpyxl.load_workbook(table_t, data_only=True, read_only=False)
    ws2 = wb554t.active
    rows2 = list(ws2.iter_rows(values_only=True))
    hdr2 = rows2[0]
    iT = {name: hdr2.index(name) for name in
          ('Langue', 'GrSdP', 'CatAbsP', 'Texte cat. prés./abs.')}
    labels = {}
    for r in rows2[1:]:
        if r[iT['Langue']] != cfg["lang_fr"] or r[iT['GrSdP']] != cfg["grsdp"]:
            continue
        labels[r[iT['CatAbsP']]] = r[iT['Texte cat. prés./abs.']]
    print(f"      → {len(labels)} libellés FR trouvés")

    # Charge les ressources nécessaires pour enrichir les colonnes D-I
    units_map = load_units_map()
    t511 = load_t511(cfg)
    t512t = load_t512t(cfg)
    t554c = load_t554c_rules(cfg, t512t)

    def lookup_unit(rub: str) -> str:
        """rubrique → libellé d'unité humain via T511 + numeros_vs_unités."""
        if not rub:
            return ''
        info = t511.get(rub)
        unt = info['unt'] if info else ''
        return units_map.get(unt, unt) if unt else ''

    def lookup_nombre_montant(cat: str, rub_p: str, rub_r: str) -> tuple[str, str]:
        """Détermine les textes (Nombre, Montant) à écrire en cols J/K du WTC.

        Ordre de recherche dans T511.C (Rubrique) :
          1. rub_p (col D = Rubrique Paiement) — vraie rubrique de paie
          2. rub_r (col G = Rubrique Retenue)  — vraie rubrique de paie
          3. cat   (col A = CatAbsP)           — fallback (peut collisionner par
             hasard avec une rubrique de paie sans rapport)
        Le 1er candidat trouvé dans T511 donne le caractère 'c' qui sert de
        clé dans NOMBRE_MONTANT_MAP. Si le 'c' trouvé est vide (espace), on
        laisse J et K du WTC vides (cas fréquent sur rubriques 9000+).
        Si aucun candidat n'est trouvé dans T511, J et K restent aussi vides.
        """
        for candidate in (rub_p, rub_r, cat):
            if not candidate:
                continue
            info = t511.get(candidate)
            if info is None:
                continue
            c = info['c']
            if not c or c == ' ':
                return ('', '')
            return NOMBRE_MONTANT_MAP.get(c, ('', ''))
        return ('', '')

    # Combine et tri
    out = []
    n_paiement = 0
    n_retenue = 0
    n_jk = 0
    n_pen = {'30': 0, '40': 0, '50': 0, '70': 0}
    for cat in sorted(by_cat.keys()):
        rec = by_cat[cat]
        rule = rec['RegleValorisat']
        rubs = t554c.get(rule, {'paiement': '', 'retenue': '', 'clabs': set()})
        rub_p = rubs['paiement']
        rub_r = rubs['retenue']
        clabs = rubs.get('clabs', set())
        if rub_p:
            n_paiement += 1
        if rub_r:
            n_retenue += 1
        jk_nombre, jk_montant = lookup_nombre_montant(cat, rub_p, rub_r)
        if jk_nombre or jk_montant:
            n_jk += 1
        for k in n_pen:
            if k in clabs:
                n_pen[k] += 1
        out.append({
            'CatAbsP': cat,
            'Libelle': labels.get(cat, '(libellé FR manquant)'),
            'RegleValorisat': rule,
            'Classe': rec['Classe'],
            'TypAb': rec['TypAb'],
            'Categorie': cat[:2] + 'xx' if len(cat) >= 2 else cat,
            # Enrichissement v0.4.0
            'RubPaiement': rub_p,
            'LibPaiement': t512t.get(rub_p, '') if rub_p else '',
            'UnitPaiement': lookup_unit(rub_p),
            'RubRetenue': rub_r,
            'LibRetenue': t512t.get(rub_r, '') if rub_r else '',
            'UnitRetenue': lookup_unit(rub_r),
            # Enrichissement v0.6.0 — cols J + K via T511.C
            'Nombre': jk_nombre,
            'Montant': jk_montant,
            # Enrichissement v0.8.0 — col L (Pilotage Paie : unité de temps)
            # Basée sur rub Paiement (D) prioritaire, sinon rub Retenue (G).
            'UnitL': lookup_unit(rub_p) or lookup_unit(rub_r),
            # Enrichissement v0.9.0 — cols P/Q/R/S (pénalisants)
            # via les 10 cols CLABS de T554C pour la règle de valorisation.
            'Pen13eMois':    '30' in clabs,
            'PenPrimeVac':   '40' in clabs,
            'PenPrimeAnc':   '50' in clabs,
            'PenRATP':       '70' in clabs,
        })
    print(f"      → {n_paiement} rub. Paiement / {n_retenue} rub. Retenue résolues")
    print(f"      → {n_jk} lignes avec textes Nombre/Montant remplis depuis T511.C")
    print(f"      → pénalisants : 13ème mois={n_pen['30']}, Prime vac={n_pen['40']}, "
          f"Prime anc={n_pen['50']}, RATP={n_pen['70']}")
    return out


def add_data_sheet(wb, data: list[dict], client: str, cfg: dict) -> None:
    """Ajoute un onglet '<CLIENT>_Data' au classeur avec les catégories du client."""
    sheet_name = f"{client}_Data"
    print(f"[5/5 a] Ajout de l'onglet '{sheet_name}' ({len(data)} lignes)…")
    if sheet_name in wb.sheetnames:
        del wb[sheet_name]
    ws = wb.create_sheet(sheet_name)

    from openpyxl.styles import Alignment, Border, Side

    # Titre
    ws['A1'] = f"Données {client} — Catégories d'absences/présences"
    ws['A1'].font = Font(name='Arial', size=14, bold=True, color=WHITE)
    ws['A1'].fill = PatternFill('solid', fgColor=STRADA_DARK)
    ws['A1'].alignment = Alignment(horizontal='center', vertical='center')
    ws.merge_cells('A1:F1')
    ws.row_dimensions[1].height = 28

    ws['A2'] = (f"Source : T554S + T554T  |  GrSdP={cfg['grsdp']}  |  "
                f"Langue={cfg['lang_fr']}  |  GrPay={cfg['grpay']}  |  "
                f"Customer Code={client}")
    ws['A2'].font = Font(name='Arial', size=9, italic=True, color="FF333333")
    ws['A2'].alignment = Alignment(horizontal='center')
    ws.merge_cells('A2:F2')

    # Entêtes
    headers = ['Catégorie', 'Code (CatAbsP)', 'Libellé Absence (FR)',
               'Règle Valorisat.', 'Classe', 'TypAb']
    for col_idx, h in enumerate(headers, start=1):
        c = ws.cell(row=4, column=col_idx, value=h)
        c.font = Font(name='Arial', size=10, bold=True, color=WHITE)
        c.fill = PatternFill('solid', fgColor=STRADA_MED)
        c.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
    ws.row_dimensions[4].height = 32

    # Données
    thin = Side(border_style="thin", color="FF888888")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    prev_cat = None
    for i, rec in enumerate(data, start=5):
        # Séparateur visuel quand la catégorie change
        cat_changed = prev_cat is not None and rec['Categorie'] != prev_cat
        row_fill = STRADA_MED if cat_changed else YELLOW

        for col_idx, key in enumerate(
            ['Categorie', 'CatAbsP', 'Libelle', 'RegleValorisat', 'Classe', 'TypAb'],
            start=1,
        ):
            c = ws.cell(row=i, column=col_idx, value=rec[key])
            c.font = Font(name='Arial', size=9,
                          bold=cat_changed,
                          color=WHITE if cat_changed else "FF000000")
            c.fill = PatternFill('solid', fgColor=row_fill)
            c.border = border
            c.alignment = Alignment(
                horizontal='center' if col_idx != 3 else 'left',
                vertical='center',
            )
        prev_cat = rec['Categorie']

    # Largeurs de colonnes
    widths = {'A': 12, 'B': 14, 'C': 40, 'D': 16, 'E': 9, 'F': 9}
    for col, w in widths.items():
        ws.column_dimensions[col].width = w

    ws.freeze_panes = 'A5'
    print(f"      → onglet {sheet_name} créé")


def populate_main_sheet(wb, data: list[dict], cfg: dict) -> int:
    """Remplace les données du sheet principal 'Absences-Présences' par
    les vraies données client, groupées par catégorie '(0Xxx)'."""
    from openpyxl.styles import Alignment, Border, Side

    print(f"[5/5 b] Injection données dans onglet '{MAIN_SHEET}'…")
    ws = wb[MAIN_SHEET]

    # 1. Mettre à jour le titre (ex. "FR Absences" → "AKN Absences")
    old, new = cfg["title_replace"]
    for r in range(1, HEADER_ROW_END + 1):
        for c in range(1, MAIN_COL_COUNT + 1):
            cell = ws.cell(row=r, column=c)
            if cell.value and isinstance(cell.value, str) and "Absences/Présences Catalogue" in cell.value:
                cell.value = cell.value.replace(old, new)

    # 2. Supprimer toutes les fusions dans la zone de données
    to_remove = [mr for mr in list(ws.merged_cells.ranges)
                 if mr.min_row >= DATA_ROW_START]
    for mr in to_remove:
        ws.unmerge_cells(str(mr))

    # 3. Vider valeurs + reset basique des styles dans les lignes 8-156
    blank_fill = PatternFill(fill_type=None)
    blank_font = Font(name='Arial', size=10, color=BLACK)
    thin = Side(border_style="thin", color="FF888888")
    blank_border = Border(left=thin, right=thin, top=thin, bottom=thin)
    for r in range(DATA_ROW_START, DATA_ROW_END + 1):
        for c in range(1, MAIN_COL_COUNT + 1):
            cell = ws.cell(row=r, column=c)
            cell.value = None
            cell.fill = blank_fill
            cell.font = blank_font

    # 4. Grouper les données par catégorie (préfixe '0Xxx', '1Hxx', 'P1xx'…)
    by_category: dict[str, list[dict]] = {}
    cat_order: list[str] = []
    for rec in data:
        cat = rec['Categorie']
        if cat not in by_category:
            by_category[cat] = []
            cat_order.append(cat)
        by_category[cat].append(rec)

    # 5. Écrire les données par catégorie
    cat_font = Font(name='Arial', size=10, bold=True, color=WHITE)
    cat_fill = PatternFill('solid', fgColor=STRADA_MED)
    cat_align = Alignment(horizontal='left', vertical='center', indent=1)
    data_font = Font(name='Arial', size=10, color=BLACK)
    data_fill = PatternFill('solid', fgColor=YELLOW)
    code_align = Alignment(horizontal='center', vertical='center')
    label_align = Alignment(horizontal='left', vertical='center', indent=1)
    used_font = Font(name='Arial', size=14, color="FF666666")
    used_align = Alignment(horizontal='center', vertical='center')

    cur_row = DATA_ROW_START
    n_data_rows = 0
    for cat in cat_order:
        recs = by_category[cat]
        # Heuristique du nom : libellé du 1er code dont le libellé existe
        cat_name = next((r['Libelle'] for r in recs
                         if r['Libelle'] and 'manquant' not in r['Libelle']), '')
        # Garder seulement les 3-4 premiers mots pour un nom court
        cat_short = ' '.join(cat_name.split()[:3]) if cat_name else ''
        cat_title = f"({cat}) {cat_short}".strip()

        # Ligne d'entête de catégorie : merge A:B, fond vert moyen, texte blanc gras
        ws.cell(row=cur_row, column=1, value=cat_title).font = cat_font
        ws.cell(row=cur_row, column=1).fill = cat_fill
        ws.cell(row=cur_row, column=1).alignment = cat_align
        for c in range(2, MAIN_COL_COUNT + 1):
            ws.cell(row=cur_row, column=c).fill = cat_fill
        ws.merge_cells(start_row=cur_row, start_column=1, end_row=cur_row, end_column=2)
        ws.row_dimensions[cur_row].height = 22
        cur_row += 1

        # Lignes de données
        for rec in recs:
            # Col A : Code
            c_a = ws.cell(row=cur_row, column=1, value=rec['CatAbsP'])
            c_a.font = data_font
            c_a.fill = data_fill
            c_a.alignment = code_align
            c_a.border = blank_border
            # Col B : Libellé
            c_b = ws.cell(row=cur_row, column=2, value=rec['Libelle'])
            c_b.font = data_font
            c_b.fill = data_fill
            c_b.alignment = label_align
            c_b.border = blank_border
            # Col C : Used (□ par défaut)
            c_c = ws.cell(row=cur_row, column=3, value='□')
            c_c.font = used_font
            c_c.fill = data_fill
            c_c.alignment = used_align
            c_c.border = blank_border
            # Cols D-I : Paiement (D, E, F) puis Retenue (G, H, I)
            #   D = Rubrique Paiement / E = Libellé rubrique / F = Unité de temps
            #   G = Rubrique Retenue  / H = Libellé rubrique / I = Unité de temps
            paiement_retenue_vals = [
                (4, rec['RubPaiement'], code_align),
                (5, rec['LibPaiement'], label_align),
                (6, rec['UnitPaiement'], code_align),
                (7, rec['RubRetenue'], code_align),
                (8, rec['LibRetenue'], label_align),
                (9, rec['UnitRetenue'], code_align),
            ]
            for col_idx, val, align in paiement_retenue_vals:
                cx = ws.cell(row=cur_row, column=col_idx, value=val or None)
                cx.font = data_font
                cx.fill = data_fill
                cx.alignment = align
                cx.border = blank_border
            # Col J (10) = Nombre / Col K (11) = Montant — issus de T511.C
            for col_idx, val in ((10, rec['Nombre']), (11, rec['Montant'])):
                cj = ws.cell(row=cur_row, column=col_idx, value=val or None)
                cj.font = data_font
                cj.fill = data_fill
                cj.alignment = code_align
                cj.border = blank_border
            # Col L (12) = Unité de temps (Pilotage Paie) — issue de T511.UnT
            # via rub Paiement (D) avec fallback rub Retenue (G)
            cl = ws.cell(row=cur_row, column=12, value=rec['UnitL'] or None)
            cl.font = data_font
            cl.fill = data_fill
            cl.alignment = code_align
            cl.border = blank_border
            # Colonnes M-O : laissées vides (métier) avec fond jaune cohérent
            for col in range(13, 16):
                cd = ws.cell(row=cur_row, column=col)
                cd.fill = data_fill
                cd.border = blank_border
            # Cols P/Q/R/S (16-19) = pénalisants : ■ si CLABS 30/40/50/70 dans
            # la liste, □ sinon — issus de T554C.CLABS pour la règle de valorisat.
            pen_vals = [
                (16, rec['Pen13eMois']),
                (17, rec['PenPrimeVac']),
                (18, rec['PenPrimeAnc']),
                (19, rec['PenRATP']),
            ]
            for col_idx, on in pen_vals:
                cp = ws.cell(row=cur_row, column=col_idx, value='■' if on else '□')
                cp.font = used_font
                cp.fill = data_fill
                cp.alignment = used_align
                cp.border = blank_border
            ws.row_dimensions[cur_row].height = 16
            cur_row += 1
            n_data_rows += 1

        # Ligne séparatrice "GAP with euHReka standard" si on a marge
        # (style cohérent avec le GFK original — fond jaune, texte vert foncé gras)
        if cur_row <= DATA_ROW_END:
            gap_cell = ws.cell(row=cur_row, column=1, value="(à compléter manuellement)")
            gap_cell.font = Font(name='Arial', size=9, italic=True, color=STRADA_DARK)
            gap_cell.fill = data_fill
            gap_cell.alignment = Alignment(horizontal='center', vertical='center')
            for c in range(2, MAIN_COL_COUNT + 1):
                ws.cell(row=cur_row, column=c).fill = data_fill
            ws.merge_cells(start_row=cur_row, start_column=1, end_row=cur_row, end_column=15)
            ws.row_dimensions[cur_row].height = 14
            cur_row += 1

    print(f"      → {len(cat_order)} catégories, {n_data_rows} lignes d'absence injectées")
    return n_data_rows


def generate(client: str) -> None:
    cfg = CLIENT_CONFIGS[client]
    output = cfg["output"]
    print(f"=== generate_wtc_absences.py v{APP_VERSION} — client {client} ===")
    print(f"Template : {GFK_TEMPLATE.name}")
    print(f"Cible    : {output.name}")

    # 1. Charger le template (.xlsx pré-converti, ou conversion .xls si nécessaire sous Linux)
    wb = load_template(GFK_TEMPLATE, GFK_XLS_LEGACY)

    # 2. Remplacer les images (logos NGA → logo Strada)
    n_imgs = replace_logos(wb, LOGO_STRADA)

    # 3. Patcher les couleurs (mauve NGA → vert Strada)
    n_fill, n_font = patch_colors(wb)

    # 4. Charger les données client
    data = load_client_data(cfg)

    # 5a. Onglet <CLIENT>_Data (vue à plat de référence)
    add_data_sheet(wb, data, client, cfg)

    # 5b. Injecter les données dans l'onglet principal
    n_inj = populate_main_sheet(wb, data, cfg)

    # 6. Sauvegarder
    print(f"[6/6] Sauvegarde → {output.name}")
    wb.save(output)

    # Nettoyer le dossier temporaire (cas conversion .xls fallback)
    shutil.rmtree(TMP_DIR, ignore_errors=True)

    print()
    print(f"=== Terminé : {n_imgs} images, {n_fill} fills, {n_font} fontes, "
          f"{len(data)} catégories {client} ({n_inj} lignes injectées) ===")
    print(f"Sortie : {output}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Générateur Wagetype Catalog Absences (multi-clients)")
    parser.add_argument("--client", choices=sorted(CLIENT_CONFIGS.keys()),
                        default="AKN", help="Client à traiter (défaut : AKN)")
    parser.add_argument("--all", action="store_true",
                        help="Génère le fichier pour tous les clients configurés")
    args = parser.parse_args()

    clients = sorted(CLIENT_CONFIGS.keys()) if args.all else [args.client]
    for c in clients:
        generate(c)
        if len(clients) > 1:
            print()


if __name__ == "__main__":
    main()
