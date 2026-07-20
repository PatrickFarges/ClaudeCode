# SAP_Onenote

Base de connaissance SAP EuHReka (tickets résolus + procédures) rendue **interrogeable par cloclo/Claude** — un **RAG local**. Deux sources dans la même base : les 7 notebooks OneNote (`.one`, ~1,7 Go) **+** les ~1500 dossiers Test Evidence (phase 2, faite le 2026-07-20).

## But (pivot 2026-07-18)

L'ancien livrable `sap_onenote_index.xlsx` (Excel de liens) a été **abandonné** : il ne faisait rien gagner (il fallait encore cliquer/lire), alors que OneNote a déjà sa recherche plein-texte. Ce qui manquait vraiment : que **cloclo** puisse consulter cette connaissance SAP (absente de ses poids) **en < 1 s, sans saturer son contexte**.

→ **RAG** (Retrieval-Augmented Generation) : un CLI qui, sur une requête, renvoie seulement les quelques pages pertinentes (titre, N° ticket, client, section, extrait, lien OneNote, [phase 2] chemin evidence). Je pioche l'essentiel et je réponds ; je ne charge jamais les Go.

## RAG — utilisation (le nouveau cœur du projet)

**Interroger** (c'est CE que cloclo lance quand Pat pose une question SAP) :

```bash
./rag/ask "net social corning"                 # top pages + extraits
./rag/ask "allegement retraite" --client RECKITT -k 5
./rag/ask "IJSS subrogation maladie" --json     # sortie structurée (agents)
```

La base vit sur le NVMe Samsung : `/media/red/Samsung2TB/SAP_KB/sap_kb.db` (39 Mo, tient en cache RAM → réponses instantanées). Override possible via `$SAP_KB_DB`.

**Reconstruire** l'index :

```bash
source .venv/bin/activate       # venv : stdlib + openpyxl + xlrd (lecture Excel evidence)
python rag/kb_build.py          # rebuild COMPLET : tous les .one + Test Evidence, ~3-4 min
python rag/kb_build.py --no-onenote   # refresh evidence seul (garde onenote), ~1 min
python rag/kb_build.py --no-evidence  # onenote seul (rebuild complet des .one)
```

`--evidence-root` (ou `$EVIDENCE_ROOT`) pour pointer une autre arbo Test Evidence.

### Archi RAG

- **Stockage** : SQLite + **FTS5** natif (zéro dépendance, BM25, requêtes en ms). Recherche par mots-clés (mieux adaptée que le sémantique aux tokens SAP : T511K, CTP 717, CS0…, MDC, PEX) et **100 % local** (données clients confidentielles, rien vers une API externe).
- **Extraction `.one` sous Linux SANS OneNote** : `rag/onenote_extract.py`. On lit le texte au niveau **octet** via `strings` (UTF-16LE pour les titres/français + 8-bit pour les blocs anglais), on filtre le bruit binaire, puis on segmente en pages avec les **titres du CSV comme ancres**.
  - ⚠️ pyOneNote a été **abandonné** : il plante sur les 2 fichiers clés (`NotImplementedError 'ArrayOfPropertyValues'` 0x10 sur Utility.one ; `AttributeError 'data'` sur Tickets résolus 1,25 Go). La méthode `strings` ne plante jamais.
  - Limitation connue : attribution page↔contenu imparfaite (l'ordre octet titre/corps du `.one` n'est pas linéaire) + résidu de bruit binaire dans certains extraits. Sans impact sur la recherche ; à polir.
- **Extraction Test Evidence (phase 2)** : `rag/evidence_extract.py`. Arbo `/media/red/Samsung2TB/SAP_KB/TestEvidence/` (~4,2 Go, structure hétérogène : dossiers par client ET par année/date — sans importance). **1 doc = le fichier Excel le plus récent (mtime) de chaque répertoire** contenant directement des Excel (1482 répertoires-tickets). On en extrait le texte de 3 onglets, par valeur décroissante :
  1. **"Change Logs"** → CE QUI A ÉTÉ MODIFIÉ (tables/transactions/rubriques SAP). L'essentiel.
  2. **"Analyse"** → l'analyse faite par l'AMO avant la modif.
  3. **"Analyse HRO"** → l'analyse du problème par HRO (contexte : pourquoi le ticket).
  - Métadonnées : N° ticket (CS/CHG/INC/DFCT) du nom de dossier/fichier, client (dossier racine → code `XXXFR` → "Customer Name" du formulaire), tables SAP, `Change Reason` du "Test Evidence Form". Sans onglet cible (formulaires DFCT/INC purs) → fallback sur les onglets formulaire (recherche par N° ticket OK quand même).
  - Lecture robuste : `.xlsx/.xlsm` via **openpyxl**, `.xls` via **xlrd**, bascule auto sur l'autre moteur (exports SAP à mauvaise extension). ~16 fichiers illisibles (OLE2 chiffrés / .xls-HTML SAP) → ignorés.
  - Limitation connue : un dossier regroupant plusieurs tickets distincts (rare, surtout dans l'arbo par date) ne garde que le plus récent — les autres tickets du dossier sont perdus. Conforme à la règle "le plus récent Excel de chaque répertoire".
- **Build** : `rag/kb_build.py` — ingère onenote **et** evidence, enrichit (N° tickets, tables, client), indexe. `--no-onenote` / `--no-evidence` pour builds partiels.
- **Requête** : `rag/kb.py` (wrapper `rag/ask`) — FTS5/BM25 + snippet + filtres `--client/--section/--source` (`--source evidence` pour ne cibler que les Test Evidence), sortie texte ou `--json`.

### État (build 2026-07-20)

**2720 docs** au total dans `sap_kb.db` :
- **onenote = 1254** pages (967 avec N° ticket, 1252 avec lien OneNote). Répartition : Tickets résolus 926, Utility 158, To Do 112, PCC 47, ABAP 7, PCR 4.
- **evidence = 1466** dossiers Test Evidence (1386 avec N° ticket = 93 %, 1254 avec onglet Change Log ; 16 illisibles ignorés).

→ Objectif phase 2 atteint : une requête par N° ticket (ex. `CS0236151`) renvoie **à la fois** la page OneNote (la discussion/résolution) **et** le Test Evidence (le détail des tables/transactions modifiées).

---

## [LEGACY] Ancien index Excel `sap_onenote_index.xlsx`

> Conservé pour référence. Remplacé par le RAG ci-dessus.

Reliait chaque ticket résolu (CSxxxxxxx / CHGxxxxxxx) à son dossier evidence et sa page OneNote (lien `onenote:///` cliquable).

## Sortie : `sap_onenote_index.xlsx`

Excel à 4 onglets :

| Onglet | Contenu |
|--------|---------|
| **Stats** | Couverture globale + répartition par client |
| **Tickets** | 1 ligne par dossier evidence, hyperliens vers dossier Windows ET page OneNote |
| **OneNote orphelins** | Pages OneNote avec un ID mais sans dossier evidence (anciens tickets) |
| **OneNote sans ID** | Pages OneNote sans CSxxx/CHGxxx (annotations, procédures, nav SAP) |

Stats actuelles (1ère exécution 2026-05-01) :
- 587 dossiers evidence (424 CS + 163 CHG)
- 1526 pages OneNote utiles (après filtre)
- **508 tickets matchés** entre les deux mondes (couverture 86,5 %)
- 573 pages OneNote orphelines (résolus avant l'archivage local)
- 445 pages OneNote sans ID (annotations à conserver)

## Pipeline en 3 étapes

### 1. `scan_evidence.py` — Scan des dossiers Test Evidence

Walk récursif de `E:\Dossier Manuel (CV, taf, dev etc)\NGA\OLD\Tickets\` :
- Détecte les dossiers `<ID> - <description>` à n'importe quelle profondeur
- Détecte aussi les fichiers Excel "orphelins" (sans dossier dédié) qui contiennent un ID
- Sortie : `evidence_scan.csv`

### 2. `dump_onenote.ps1` + `scan_onenote.py` — Scan OneNote

Le COM OneNote ne se laisse pas piloter proprement par pywin32 (typelib pas exploitable côté Python). On délègue à PowerShell :

- `dump_onenote.ps1` se connecte à OneNote, dump la hiérarchie complète + un CSV `onenote_pages.csv` avec hyperliens cliquables
- `scan_onenote.py` lit ce CSV, applique les filtres (skip "Notes rapides", "email important", "Bordel en attente", "Info personnel"), extrait les IDs CS/CHG des titres
- Sortie : `onenote_scan.csv`

`scan_onenote.py` lance le PowerShell auto si `onenote_pages.csv` n'existe pas. Pour forcer un nouveau dump : `python scan_onenote.py --refresh`.

**Pré-requis** : OneNote desktop installé et le notebook ouvert.

### 3. `build_index.py` — Excel maître

Joint les deux CSV sur l'ID, génère `sap_onenote_index.xlsx` avec hyperliens cliquables (openpyxl).

## Lancer (ordre)

```bash
# Setup une fois :
cd /mnt/Raid4Tb/Program/ClaudeCode/SAP_Onenote
python3 -m venv .venv
source .venv/bin/activate
pip install openpyxl

# Pipeline :
python scan_evidence.py
python scan_onenote.py        # dump auto si besoin
python build_index.py
```

Ou pour forcer un re-dump OneNote (si tu as ajouté/modifié des pages) :

```bash
python scan_onenote.py --refresh
python build_index.py
```

**Limitation Linux :** OneNote desktop n'existe pas sous Linux, donc `dump_onenote.ps1` (PowerShell + COM) ne tourne pas nativement. Solutions :
- Garder le dump OneNote sous Windows (lancer `dump_onenote.ps1` côté Windows, copier `onenote_pages.csv` sur le poste Linux)
- Ou utiliser PowerShell Core (`pwsh`) côté Linux mais sans accès à COM → ne fonctionnera pas pour OneNote
- Pour `scan_evidence.py` + `build_index.py` (qui ne touchent pas COM), tout marche sous Linux à condition que les chemins `E:\Dossier Manuel...` soient remontés (voir section suivante).

## Structure de données

### Tickets (IDs)

Deux formats coexistent :
- **Anciens** : `CHG0563104` (10 chiffres après le préfixe)
- **Récents (depuis ~2023)** : `CS0514848` (7 chiffres après le préfixe)

### Test Evidence — arborescence type

```
E:\Dossier Manuel (CV, taf, dev etc)\NGA\OLD\Tickets\
├── <CLIENT> (LEO PHARMA, RECKITT, CORNING, ...)
│   ├── 2025/
│   │   └── CS0514848 - RKTFR - Mapping to be done.../
│   │       ├── CS0514848 - <description>.xlsx        ← onglet "Change Logs"
│   │       └── ...
│   └── 2020-2024/
│       └── CHG0563104 - LEO - .../
```

L'onglet **"Change Logs"** dans l'Excel principal contient les modifications faites par AMO pour résoudre le ticket. Les autres onglets ne sont pas utiles.

### OneNote — sections traitées

- `Tickets résolus` (1052 pages) — la mine d'or
- `Utility` (253 pages)
- `To Do` (157 pages)
- `PCC` (52 pages)
- `ABAP` (8 pages)
- `PCR` (4 pages)

Sections **ignorées** : `email important`, `Notes rapides`, `Bordel en attente`, `Info personnel`.

## Fichiers

| Fichier | Rôle |
|---------|------|
| `scan_evidence.py` | Scan des dossiers Test Evidence |
| `dump_onenote.ps1` | Dump OneNote via COM PowerShell |
| `scan_onenote.py` | Wrapper Python : lance PS1 + enrichit le CSV |
| `build_index.py` | Cross-référence + génération Excel |
| `evidence_scan.csv` | Intermédiaire : 1 ligne par dossier ticket |
| `onenote_pages.csv` | Intermédiaire brut : sortie PowerShell |
| `onenote_scan.csv` | Intermédiaire enrichi : pages filtrées + IDs |
| `onenote_hierarchy.xml` | Dump XML brut OneNote (pour debug) |
| `sap_onenote_index.xlsx` | **Sortie finale** : index Excel cliquable |
| `OneNote/` | Les 7 fichiers `.one` (~2 Go) — copie locale du notebook |

## Notes techniques

- **OneNote 2016+** : ProgID = `OneNote.Application.15`, TypeLib GUID `{0EA692EE-BB50-4E3C-AEF0-356D91732725}`
- **CLSID Application** : `{D7FAC39E-7FF1-49AA-98CF-A1DDD316337E}`
- **CLSID IApplication** : `{452AC71A-B655-4967-A208-A4CC39DD7949}`
- **HierarchyScope.hsPages** = 4
- **DispID GetHierarchy** = 1610743808 ; **GetHyperlinkToObject** = 1610743823
- pywin32 n'arrive pas à instancier ces interfaces (`Bibliothèque non inscrite` malgré l'enregistrement). PowerShell COM s'en sort sans broncher → on a choisi cette voie.

## Évolutions possibles

- ~~Extraire l'onglet "Change Logs" de chaque Excel evidence~~ → **fait (phase 2, 2026-07-20)**, cf. `rag/evidence_extract.py`
- OCR/vision des screenshots des Test Evidence : beaucoup de config réelle est dans les captures d'écran (Pre/Post-Change), invisible au texte
- Récupérer les tickets perdus quand un dossier regroupe plusieurs tickets distincts (indexer tous les Excel du dossier, pas seulement le plus récent)
- Les ~16 Excel illisibles (OLE2 chiffrés, exports SAP en .xls-HTML) : convertir via LibreOffice headless (`soffice --convert-to xlsx`)
- UI tkinter pour browser l'index sans passer par Excel
