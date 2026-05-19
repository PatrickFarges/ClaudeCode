"""
generate_wtc_absences.py — Générateur du Wagetype Catalog Absences (client AKN)

Modèle : `GFK Original Absence Catalog.xls` (catalogue NGA pour le client GFK)
Cible : `AKN France Absences-Presences Catalogue.xlsx` (catalogue STRADA pour le client AKN)

Branding NGA → STRADA :
  - Logo NGA + Human Resources → logo Strada (logo_strada.png)
  - Mauve foncé  FF660066 → vert foncé Strada FF084028
  - Mauve moyen  FF993366 → vert moyen Strada FF207F4F
  - Violet       FF800080 → vert clair Strada FF18D878

Phases :
  Phase 1 (cette version) : Copie du GFK + substitution logo + substitution couleurs
                            (les DONNÉES GFK sont conservées pour validation visuelle)
  Phase 2 (à venir)        : Remplacement des données par celles d'AKN (GrSdP=6, langue=F)
                             via les tables T554S / T554T / T554C / Y00BA_TAB_COMPAN

Changelog :
  v0.1.0 — Phase 1 : copie + rebranding visuel Strada
  v0.2.0 — Phase 2.0 : ajout d'un onglet "AKN_Data" avec les 122 catégories
                       d'absences AKN (Code + Libellé FR + Règle valorisat. + TypAb)
                       extraites des tables T554S et T554T (GrSdP='6', Langue='F')
  v0.3.0 — Phase 2.1 : injection des vraies données AKN dans l'onglet principal
                       "Absences-Présences" (remplace les données GFK)
                       Utilise désormais le template .xlsx pré-converti
                       (plus besoin de LibreOffice côté Windows)
  v0.4.0 — Phase 2.2 : remplissage des colonnes D, E, F, G, H, I via jointure
                       T554S → T554C (1ère/2ème rubrique = Paiement/Retenue)
                       → T512T (libellés FR) + T511 (UnT → unité de temps).
                       Lit désormais depuis AKN_17.05.2026/ (tables fraîches
                       du 2026-05-17, avec T511, T512T, T508A en plus).
"""
from __future__ import annotations

APP_VERSION = "0.4.0"

import shutil
import subprocess
from pathlib import Path

import openpyxl
from openpyxl.drawing.image import Image as XLImage
from openpyxl.styles import PatternFill, Font

# ---- Chemins ---------------------------------------------------------------

ROOT = Path(__file__).resolve().parent
# Template .xlsx pré-converti depuis GFK Original Absence Catalog.xls
# (la conversion .xls→.xlsx est faite une fois pour toutes côté Linux/LibreOffice
#  et le résultat est commit dans le projet pour être utilisable sous Windows
#  sans dépendance externe)
GFK_TEMPLATE = ROOT / "GFK Original Absence Catalog.xlsx"
GFK_XLS_LEGACY = ROOT / "GFK Original Absence Catalog.xls"
LOGO_STRADA = ROOT / "logo_strada.png"
OUTPUT = ROOT / "AKN France Absences-Presences Catalogue.xlsx"

# Tables SAP AKN — version 2026-05-17 (tables fraîches retéléchargées par Pat)
AKN_DIR = ROOT / "AKN_17.05.2026"
T554S = AKN_DIR / "T554S.xlsx"
T554T = AKN_DIR / "T554T.xlsx"
T554C = AKN_DIR / "T554C.xlsx"
T511 = AKN_DIR / "T511.xlsx"
T512T = AKN_DIR / "T512T.xlsx"
T508A = AKN_DIR / "T508A.xlsx"
Y00BA = AKN_DIR / "Y00BA_TAB_COMPAN.xlsx"

# Mapping numéros → libellés d'unités de temps (T511 col "UnT" → humain)
UNITS_MAP_FILE = ROOT / "numeros_vs_unités"

# Clés AKN
AKN_GRSDP = "6"   # Groupe subdivisions personnel AKN
AKN_LANG_FR = "F"  # Code langue français
AKN_GRPAY = "06"   # Groupe de paie AKN

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


def load_t511(mdt: str = '984', lhcm: str = '06') -> dict[str, str]:
    """Charge T511 → dict { rubrique: UnT_code }.
    Filtre Mdt + L.HCM. Garde la version la plus récente (Fin max) pour chaque rubrique.
    """
    print(f"[4/5 d] Chargement T511 (Mdt={mdt}, L.HCM={lhcm})…")
    wb = openpyxl.load_workbook(T511, data_only=True, read_only=True)
    ws = wb.active
    rows = ws.iter_rows(values_only=True)
    hdr = next(rows)
    iM = hdr.index('Mdt')
    iL = hdr.index('L.HCM')
    iR = hdr.index('Rubrique')
    iU = hdr.index('UnT')
    iF = hdr.index('Fin')
    by_rub: dict[str, tuple] = {}
    for r in rows:
        if r[iM] != mdt or r[iL] != lhcm:
            continue
        rub = r[iR]
        if not rub:
            continue
        fin = r[iF]
        unt = r[iU] or ''
        prev = by_rub.get(rub)
        if prev is None or (fin and (not prev[1] or fin > prev[1])):
            by_rub[rub] = (unt, fin)
    wb.close()
    out = {k: v[0] for k, v in by_rub.items()}
    print(f"      → {len(out)} rubriques T511 trouvées")
    return out


def load_t512t(mdt: str = '984', lhcm: str = '06', lang: str = 'F') -> dict[str, str]:
    """Charge T512T → dict { rubrique: libellé FR }."""
    print(f"[4/5 e] Chargement T512T (Langue={lang}, L.HCM={lhcm})…")
    wb = openpyxl.load_workbook(T512T, data_only=True, read_only=True)
    ws = wb.active
    rows = ws.iter_rows(values_only=True)
    hdr = next(rows)
    iM = hdr.index('Mdt')
    iL = hdr.index('Langue')
    iH = hdr.index('L.HCM')
    iR = hdr.index('Rubrique')
    iT = hdr.index('Libellé de rubrique')
    out: dict[str, str] = {}
    for r in rows:
        if r[iM] != mdt or r[iL] != lang or r[iH] != lhcm:
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


def load_t554c_rules(t512t: dict[str, str], mdt: str = '984',
                     lhcm: str = '06', grpe: str = '06') -> dict[str, dict]:
    """Charge T554C → dict { règle_valorisation: {'paiement': rub, 'retenue': rub} }.

    T554C contient 15 sous-blocs (DH, Pourc., Tp, RB, Rubrique, RègleJourn). Pour
    chaque règle de valorisation on extrait les 2 premières rubriques non vides,
    puis on les classe en Paiement/Retenue via les libellés T512T (les libellés
    AKN commencent par 'Paiement…' ou 'Retenue…' — fiable).
    Si plusieurs lignes existent pour la même règle (versions par dates), on garde
    celle dont la date Fin est la plus haute.
    """
    print(f"[4/5 f] Chargement T554C (L.HCM={lhcm}, Grpe={grpe})…")
    wb = openpyxl.load_workbook(T554C, data_only=True, read_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    hdr = rows[0]
    iM = hdr.index('Mdt')
    iL = hdr.index('L.HCM')
    iG = hdr.index('Grpe')
    iR = hdr.index('Règle de valorisat.')
    iF = hdr.index('Fin')

    # Indices des 15 colonnes "Rubrique" dans la 2e moitié de la table.
    rubrique_cols = [i for i, h in enumerate(hdr) if h == 'Rubrique']

    by_rule: dict[str, tuple] = {}
    n_swapped = 0
    for r in rows[1:]:
        if r[iM] != mdt or r[iL] != lhcm or r[iG] != grpe:
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

        prev = by_rule.get(rule)
        if prev is None or (fin and (not prev[2] or fin > prev[2])):
            by_rule[rule] = (paiement, retenue, fin)
    wb.close()
    out = {k: {'paiement': v[0], 'retenue': v[1]} for k, v in by_rule.items()}
    print(f"      → {len(out)} règles de valorisation indexées "
          f"({n_swapped} swaps Paiement/Retenue corrigés)")
    return out


def load_akn_data() -> list[dict]:
    """Charge les catégories d'absences AKN depuis T554S + T554T.

    Filtre :
      - T554S : GrSdP = '6'
      - T554T : GrSdP = '6' ET Langue = 'F'

    Renvoie une liste de dicts ordonnée par CatAbsP :
      {'CatAbsP': '0100', 'Libelle': 'Congés payés acquis',
       'RegleValorisat': '01', 'TypAb': '', 'Classe': '1', 'Categorie': '01xx'}
    """
    print(f"[4/5 a] Chargement T554S (GrSdP={AKN_GRSDP})…")
    wb554s = openpyxl.load_workbook(T554S, data_only=True, read_only=False)
    ws = wb554s.active
    rows = list(ws.iter_rows(values_only=True))
    hdr = rows[0]
    iS = {name: hdr.index(name) for name in
          ('GrSdP', 'CatAbsP', 'Règle de valorisat.', 'Classe', 'TypAb', 'Fin', 'Début')}
    # Une CatAbsP peut avoir plusieurs lignes (versions par dates). On garde
    # celle dont la date Fin est la plus haute (la plus récente / 9999-12-31).
    by_cat = {}
    for r in rows[1:]:
        if r[iS['GrSdP']] != AKN_GRSDP:
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
    print(f"      → {len(by_cat)} catégories AKN trouvées")

    print(f"[4/5 b] Chargement T554T (Langue={AKN_LANG_FR}, GrSdP={AKN_GRSDP})…")
    wb554t = openpyxl.load_workbook(T554T, data_only=True, read_only=False)
    ws2 = wb554t.active
    rows2 = list(ws2.iter_rows(values_only=True))
    hdr2 = rows2[0]
    iT = {name: hdr2.index(name) for name in
          ('Langue', 'GrSdP', 'CatAbsP', 'Texte cat. prés./abs.')}
    labels = {}
    for r in rows2[1:]:
        if r[iT['Langue']] != AKN_LANG_FR or r[iT['GrSdP']] != AKN_GRSDP:
            continue
        labels[r[iT['CatAbsP']]] = r[iT['Texte cat. prés./abs.']]
    print(f"      → {len(labels)} libellés FR trouvés")

    # Charge les ressources nécessaires pour enrichir les colonnes D-I
    units_map = load_units_map()
    t511 = load_t511()
    t512t = load_t512t()
    t554c = load_t554c_rules(t512t)

    def lookup_unit(rub: str) -> str:
        """rubrique → libellé d'unité humain via T511 + numeros_vs_unités."""
        if not rub:
            return ''
        unt = t511.get(rub, '')
        return units_map.get(unt, unt) if unt else ''

    # Combine et tri
    out = []
    n_paiement = 0
    n_retenue = 0
    for cat in sorted(by_cat.keys()):
        rec = by_cat[cat]
        rule = rec['RegleValorisat']
        rubs = t554c.get(rule, {'paiement': '', 'retenue': ''})
        rub_p = rubs['paiement']
        rub_r = rubs['retenue']
        if rub_p:
            n_paiement += 1
        if rub_r:
            n_retenue += 1
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
        })
    print(f"      → {n_paiement} rub. Paiement / {n_retenue} rub. Retenue résolues")
    return out


def add_akn_data_sheet(wb, data: list[dict]) -> None:
    """Ajoute un onglet 'AKN_Data' au classeur avec les 122 catégories AKN.
    Mise en forme cohérente avec la palette Strada."""
    print(f"[5/5 a] Ajout de l'onglet 'AKN_Data' ({len(data)} lignes)…")
    if 'AKN_Data' in wb.sheetnames:
        del wb['AKN_Data']
    ws = wb.create_sheet('AKN_Data')

    from openpyxl.styles import Alignment, Border, Side

    # Titre
    ws['A1'] = "Données AKN — Catégories d'absences/présences"
    ws['A1'].font = Font(name='Arial', size=14, bold=True, color=WHITE)
    ws['A1'].fill = PatternFill('solid', fgColor=STRADA_DARK)
    ws['A1'].alignment = Alignment(horizontal='center', vertical='center')
    ws.merge_cells('A1:F1')
    ws.row_dimensions[1].height = 28

    ws['A2'] = (f"Source : T554S + T554T  |  GrSdP={AKN_GRSDP}  |  "
                f"Langue={AKN_LANG_FR}  |  GrPay={AKN_GRPAY}  |  Customer Code=AKN")
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
    print(f"      → onglet AKN_Data créé")


def populate_main_sheet(wb, data: list[dict]) -> int:
    """Remplace les données du sheet principal 'Absences-Présences' par
    les vraies données AKN, groupées par catégorie '(0Xxx)'.

    - Conserve les entêtes (lignes 1-7) et le titre (modifié pour AKN).
    - Vide les lignes 8-156 (valeurs + styles), supprime les merges concernés.
    - Insère une ligne d'entête de catégorie + N lignes de données par catégorie.
    - Remplit uniquement colonnes A (Code), B (Libellé), C (Used '□' par défaut).
      Les autres colonnes (D-O) restent vides — données absentes des 4 tables AKN
      fournies (cf. CLAUDE.md "Tables potentiellement manquantes").
    """
    from openpyxl.styles import Alignment, Border, Side

    print(f"[5/5 b] Injection données AKN dans onglet '{MAIN_SHEET}'…")
    ws = wb[MAIN_SHEET]

    # 1. Mettre à jour le titre G3 ("FR" → "AKN")
    for r in range(1, HEADER_ROW_END + 1):
        for c in range(1, MAIN_COL_COUNT + 1):
            cell = ws.cell(row=r, column=c)
            if cell.value and isinstance(cell.value, str) and "Absences/Présences Catalogue" in cell.value:
                cell.value = cell.value.replace("FR Absences", "AKN Absences")

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
            # Colonnes J-O : laissées vides (métier) avec fond jaune cohérent
            for col in range(10, 16):
                cd = ws.cell(row=cur_row, column=col)
                cd.fill = data_fill
                cd.border = blank_border
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


def main() -> None:
    print(f"=== generate_wtc_absences.py v{APP_VERSION} ===")
    print(f"Template : {GFK_TEMPLATE.name}")
    print(f"Cible    : {OUTPUT.name}")

    # 1. Charger le template (.xlsx pré-converti, ou conversion .xls si nécessaire sous Linux)
    wb = load_template(GFK_TEMPLATE, GFK_XLS_LEGACY)

    # 2. Remplacer les images (logos NGA → logo Strada)
    n_imgs = replace_logos(wb, LOGO_STRADA)

    # 3. Patcher les couleurs (mauve NGA → vert Strada)
    n_fill, n_font = patch_colors(wb)

    # 4. Charger les données AKN
    akn_data = load_akn_data()

    # 5a. Onglet AKN_Data (vue à plat de référence)
    add_akn_data_sheet(wb, akn_data)

    # 5b. Injecter les données AKN dans l'onglet principal
    n_inj = populate_main_sheet(wb, akn_data)

    # 6. Sauvegarder
    print(f"[6/6] Sauvegarde → {OUTPUT.name}")
    wb.save(OUTPUT)

    # Nettoyer le dossier temporaire (cas conversion .xls fallback)
    shutil.rmtree(TMP_DIR, ignore_errors=True)

    print()
    print(f"=== Terminé : {n_imgs} images, {n_fill} fills, {n_font} fontes, "
          f"{len(akn_data)} catégories AKN ({n_inj} lignes injectées) ===")
    print(f"Sortie : {OUTPUT}")


if __name__ == "__main__":
    main()
