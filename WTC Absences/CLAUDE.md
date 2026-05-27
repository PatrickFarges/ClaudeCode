# WTC Absences

Génération du **Wagetype Catalog Absences** (catalogue des rubriques d'absences) pour SAP EuHReka, à l'image du **Wagetype Catalog** mais pour les absences.

## Objectif

Produire un fichier Excel équivalent à `GFK Original Absence Catalog.xls` (le modèle de référence, créé pour le client GFK) mais pour le client **AKN**, en :
1. Récupérant les données depuis les 4 tables SAP fournies dans `AKN/`
2. Gardant la structure, colonnes, polices, couleurs (jaune/gris/blanc/etc.) du GFK Original
3. **Substituant le branding NGA par STRADA** : logo + couleurs mauves → vertes

## Fichiers du projet

| Fichier | Rôle |
|---------|------|
| `GFK Original Absence Catalog.xls` | **Modèle de référence** — structure et formatage à reproduire (données GFK à NE PAS conserver) |
| `AKN/T554S.XLSX` (+ `.txt`) | Catégories Absences/Présences (subtypes) — table principale |
| `AKN/T554T.XLSX` (+ `.txt`) | Textes multilingues des catégories d'absences |
| `AKN/T554C.XLSX` (+ `.txt`) | Règles de valorisation des absences (lien vers rubriques) |
| `AKN/Y00BA_TAB_COMPAN.XLSX` (+ `.txt`) | Configuration société (mapping Customer Code → GrPay) |
| `GFK/*.XLSX` + `.txt` | Mêmes tables côté GFK — utile comme témoin (pas obligatoire) |
| `absences.xlsx` | Doc STRADA mal structurée — quelques infos sur les modèles maintien |
| `Absence WageType Catalog Standardized.pdf` | Captures d'écran montrant le lien tables ↔ colonnes Excel |
| `logo_strada.png` | Nouveau logo (496×103 px, vert foncé `#084028`) |

## Clés d'identification AKN

| Élément | Valeur |
|---------|--------|
| **Mandant** | `984` |
| **Global Customer Code** | `AKN` |
| **Local Customer Code** | `A06` |
| **GrPay** (Groupe de paie) | `06` |
| **GrSdP** (Groupe subdivisions personnel) | **`6`** — 122 catégories d'absences, données FR disponibles |
| **Code langue FR** | `'F'` (122 lignes en T554T pour GrSdP=6) |

## Architecture des tables SAP

```
T554S (catégories d'absences/présences)
  │  Clé : (GrSdP, CatAbsP, Début/Fin)
  │  Contient : Règle de valorisat., classes, types absence/présence
  │
  ├── T554T (textes par langue)
  │     Clé : (Langue, GrSdP, CatAbsP) → libellé
  │
  └── T554C (règles de valorisation détaillées)
        Clé : (GrPay, Grpe, Règle de valorisat.)
        Contient : rubriques de paiement (jusqu'à 15 par règle), pourcentages
        
Y00BA_TAB_COMPAN (paramétrage société)
  Clé : (GrPay, ID paramètre)
  Mappe le Customer Code (AKN) au GrPay (06)
```

## Structure du fichier Excel cible

### Onglet `Absences-Présences` (principal)

- **156 lignes × ~25 colonnes** (max_col déclaré 256 mais contenu réel ≤ 25)
- **Frozen panes** : D8 (lignes 1-7 + colonnes A-C figées)
- **Police principale** : Arial
- **2 images** : logo NGA (col A) + logo "Human Resources" (col S)

### Mise en forme — couleurs

| Couleur (hex) | Rôle | Action |
|---------------|------|--------|
| `FF660066` | Mauve très foncé (texte titre, font color) | → **vert foncé Strada** `FF084028` |
| `FF993366` | Mauve bordeaux (entêtes colonnes, sections catégorie) | → **vert moyen Strada** `FF207F4F` |
| `FF800080` | Violet (onglets "Taux de valorisation" et "Calendrier") | → **vert clair Strada** `FF18D878` (ou vert moyen) |
| `FFFFFF99` | **Jaune clair** (cellules de données) | ✅ Conserver |
| `FFC0C0C0` | **Gris clair** (entêtes secondaires) | ✅ Conserver |
| `FF969696` | **Gris moyen** (entêtes groupes) | ✅ Conserver |
| `FFCCFFCC` | **Vert très clair** (calendrier) | ✅ Conserver |
| `FFFFCC00` | **Orange** (Sheet1) | ✅ Conserver |
| `FF99CC00` | **Vert pomme** | ✅ Conserver |

### Colonnes de l'onglet principal (A-O au minimum)

| Col | Entête | Source SAP |
|-----|--------|-----------|
| A | Code Absences/Présences | `T554S.CatAbsP` (premier chiffre = catégorie, ex `0100` → ligne "100" dans la catégorie `(01xx)`) |
| B | Libellé Absences | `T554T.Texte` (Langue='F', GrSdP='6') |
| C | Used (■/□) | Manuel/métier — laisser vide ou OFF par défaut |
| D | Rubrique Paiement euHReka | `T554C.Rubrique[Paiement]` via `T554S.Règle de valorisat.` |
| E | Libellé Rubrique paiement | À résoudre via T512T (rubrique → libellé) |
| F | Unité de temps | `T554C` (CLABS / unité) |
| G | Rubrique Paiement (Retenue) | `T554C.Rubrique[Retenue]` |
| H | Libellé Rubrique (Retenue) | T512T |
| I | Unité de temps | idem |
| J-K | Pilotage Paie Nombre/Montant (■/□) | Manuel |
| L | Unité de temps | T554C |
| M | Formule de calcul | Manuel |
| N | Taux horaire | Manuel (ex `TH1`, `TH2`, ref à l'onglet "Taux de valorisation") |
| O | Taux jour | Manuel (ex `TJ1`...`TJ10`) |

### Structure ligne-par-ligne

- **Lignes 1-5** : zone titre + logo
- **Ligne 6** : entête de groupes (Used / Paiement / Retenue / Pilotage Paie)
- **Ligne 7** : entêtes de colonnes détaillées
- **Lignes 8, 16, 36, 86, 107, 152** : entêtes de **catégories** fusionnés `(0Xxx) Nom`
- **Lignes entre** : codes d'absence (CatAbsP) avec leurs libellés

### Autres onglets

| Onglet | Contenu |
|--------|---------|
| `Parameter` | Listes de valeurs (Tax, Freq, Sign, etc.) — **ne pas modifier** |
| `Taux de valorisation` | Codes TH1-TH3, TJ1-TJ10 + formules (Modif char 06VL1-7) |
| `Calendrier` | Codes calendrier (vert clair) |
| `Sheet1` | Notes (orange) |
| `Aide remplissage` | Légendes + captures d'écran |

## Stratégie de génération

### Phase 1 — Squelette (LIVRABLE IMMÉDIAT)
1. Copier `GFK Original Absence Catalog.xls` → `AKN France Absences-Presences Catalogue.xlsx`
2. Remplacer les 2 images du logo par `logo_strada.png`
3. Patcher toutes les couleurs mauves NGA (`FF660066`, `FF993366`, `FF800080`) → palette verte Strada
4. Conserver toutes les données GFK telles quelles (preview du rendu)

### Phase 2 — Données AKN (à valider après Phase 1)
1. Vider les lignes de données (lignes 8-156, hors entêtes catégorie)
2. Pour chaque catégorie `(0Xxx)` :
   - Filtrer T554S sur GrSdP=`6` et CatAbsP commençant par `0X`
   - Joindre T554T (Langue=`F`) pour le libellé
   - Écrire les lignes (Code, Libellé)
   - Optionnel : remplir D/E/F via T554C → T512T

### Phase 3 — Compléments (manuel-assisté)
- Compléter "Used", "Formule de calcul", "Taux horaire/jour" (données métier non auto)
- Vérifier les libellés des rubriques de paiement (besoin de table T512T qui n'est pas fournie pour AKN)

## Tables manquantes pour compléter le fichier

Les 4 tables fournies dans `AKN/` (T554S, T554T, T554C, Y00BA_TAB_COMPAN) permettent de remplir :
- ✅ Col A — Code Absences/Présences (`CatAbsP`)
- ✅ Col B — Libellé Absences (`Texte cat. prés./abs.` langue F)
- ⚠ Col C — Used : checkbox manuelle (`□` par défaut)

Pour remplir le reste, il manque ces tables SAP côté AKN :

| Table | Permet de remplir | Priorité |
|-------|------------------|----------|
| **T512T** | Cols **E + H** (libellés rubriques de paiement euHReka pour Paiement et Retenue) | 🔴 Haute |
| **T512W** | Cols **F + I + L** (unité de temps de chaque rubrique : "Jours de paie", "Jours calendrier", "Jour") | 🟡 Moyenne (peut aussi se déduire de T554C.CLABS) |
| **T508A** ou **T508P** | Onglet `Calendrier` (codes calendrier de paie) | 🟢 Basse (onglet secondaire) |

Les cols D + G (Rubrique Paiement / Retenue) peuvent en théorie se déduire avec les 4 tables actuelles via la jointure :
- `T554S.Règle de valorisat.` → `T554C.Règle de valorisat.` → `T554C.Rubrique[paiement]` ou `T554C.Rubrique[retenue]`

…mais c'est complexe (T554C a 9 sous-blocs CLABS/Payé × 15 blocs DH/Tp/RB/Rubrique répétés). À faire en Phase 2.2 si Pat valide.

Les cols M, N, O (Formule de calcul, Taux horaire, Taux jour) sont du **paramétrage métier** (référence à l'onglet "Taux de valorisation" : TH1-TH3, TJ1-TJ10) et ne sortent d'aucune table SAP — remplissage manuel.

## Interface graphique (HRO)

`wtc_absences_gui.py` — interface Tkinter destinée à un HRO (utilisateur non
technique). Elle ne contient **aucune logique métier** : elle construit une
config via `generate_wtc_absences.build_dir_config()` puis appelle
`generate_from_config()`, en capturant le stdout pour l'afficher dans un journal.

L'HRO renseigne uniquement :
1. **Dossier des tables SAP** (détection auto des fichiers, casse libre — voir
   `scan_tables_dir()`). Obligatoires : T554S, T554T, T554C, T511, T512T.
   Recommandée : T554E (sinon repli sur les 11 classes standard).
2. **Dossier de sortie** + **nom du fichier** `.xlsx`.
3. Case **« fichier WTC antérieur à réviser »** → `cfg['revise_previous']`.
   **Réservée, sans effet pour le moment** : prévue pour reprendre plus tard les
   2-3 colonnes remplies manuellement par l'HRO (ex. Used) depuis l'ancien
   fichier. La place (case + libellé + sélecteur de fichier) est déjà en place.

Les paramètres France (GrSdP=6, GrPay=06, langue=F, pas de filtre Mdt) sont des
**defaults cachés** : l'HRO n'a pas à les connaître.

## Installation et lancement

`./run.sh` (Linux) et `run.bat` (Windows) lancent désormais **l'interface
graphique**. Le générateur en ligne de commande reste accessible pour le dev :

```bash
.venv/bin/python generate_wtc_absences.py --client ABV   # ou --client AKN / --all
```

### Linux (poste de dev)

```bash
./run.sh
```

Crée `.venv/`, installe les libs (`requirements.txt`) et lance la GUI.
⚠ **Tkinter** n'est pas livré avec Python sous Linux : si `run.sh` affiche
qu'il manque, installer une fois le paquet système :

```bash
sudo apt install python3-tk
```

(Inutile de recréer le venv ensuite : il partage la stdlib du Python système.)

### Windows 11 (poste entreprise)

```cmd
run.bat
```

Idem côté Windows (Tkinter est **livré avec Python** → aucune installation
système requise). Le `run.bat` :
1. Crée `.venv\` avec `python -m venv` (Python doit être dans le PATH)
2. Installe les libs depuis `requirements.txt`
3. Lance `wtc_absences_gui.py`

#### Libs Python nécessaires (production)

Listées dans `requirements.txt` — **2 libs au total** :

| Lib | Version | Rôle |
|-----|---------|------|
| `openpyxl` | ≥ 3.1 | Lecture/écriture des fichiers `.xlsx` (template GFK + tables AKN + sortie) |
| `Pillow` | ≥ 10.0 | Manipulation d'images (logo Strada, requis par openpyxl pour `XLImage`) |

> Plus de dépendance LibreOffice côté Windows : le template `GFK Original Absence Catalog.xlsx` est commit dans le projet (pré-converti depuis le `.xls` historique côté Linux).

#### Libs dev (optionnelles)

Listées dans `requirements-dev.txt` :
- `xlrd==2.0.1` — pour lire directement le `.xls` historique GFK (debug uniquement)
- `pdfplumber` — pour inspecter le PDF `Absence WageType Catalog Standardized.pdf`

## Conventions

- Python 3.9+ + `.venv/` local
- Tous les libellés / commentaires en français
- Numérotation : `APP_VERSION` à incrémenter dans le script à chaque modif + changelog en docstring
- Logo + couleurs Strada : `logo_strada.png`, `#084028` (foncé) / `#207F4F` (moyen) / `#18D878` (clair)
