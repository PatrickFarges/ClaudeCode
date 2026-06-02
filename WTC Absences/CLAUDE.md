# WTC Absences

Génération du **Wagetype Catalog Absences** (catalogue des rubriques d'absences) pour SAP EuHReka, à l'image du **Wagetype Catalog** mais pour les absences.

## Objectif

Produire un fichier Excel à partir du template Strada `WTCA reference.xlsx` (déjà
brandé, structure finalisée), en y injectant les données d'un client (AKN, ABV, …
ou un dossier de tables choisi par l'HRO) :
1. Récupérant les données depuis les tables SAP du client (T554S/T/C/E, T511, T512T)
2. Vidant les données d'exemple du template et injectant celles du client
3. Conservant tel quel le branding Strada (logo + couleurs) et les onglets

> **Depuis v1.3.0** le template de référence est `WTCA reference.xlsx` (déjà aux
> couleurs/logo Strada, bloc des 11 classes d'absences P→Z en place, onglets dans
> l'ordre voulu). L'ancienne stratégie « copier GFK + rebrander NGA→Strada » est
> **abandonnée** : plus aucun `replace_logos`/`patch_colors` dans le flux. Les
> fonctions de rebranding restent dans le code (réserve) mais ne sont plus appelées.

## Fichiers du projet

| Fichier | Rôle |
|---------|------|
| `WTCA reference.xlsx` | **Template de référence actuel (v1.3.0+)** — Strada finalisé : logo + couleurs, 11 classes P→Z, listes déroulantes, 5 onglets (`Absences-Présences` / `Parameter` masqué / `Wagetype Catalog Absence_Data` / `Calendrier` / `Aide remplissage`). Données d'exemple à vider/remplacer. |
| `<dossier client>/` (ex. `ABV/`) | **Dumps de tables SAP du client** : `T554S/T/C/E`, `T511`, `T512T` (+ `T512W`, `T508A`, `Y00BA_TAB_COMPAN`). Dossier choisi par l'HRO dans la GUI. **Jamais commit** (gitignore — Pat les régénère depuis SAP à la demande). |
| `logo_strada.png` | Logo Strada (496×103 px, vert foncé `#084028`) — inséré au runtime |
| `numeros_vs_unités` | Table de correspondance code → unité de temps (`001=Heures`, `010=Jours`…). **Lue au runtime** par le générateur (cols F/I/L). |

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

## Stratégie de génération (v1.3.0)

Flux de `generate_from_config(cfg)` :
1. **Charger** le template `WTCA reference.xlsx` (déjà brandé, aucun rebranding).
2. **Charger les données client** (`load_client_data`) : T554S + T554T (GrSdP, langue F)
   puis enrichissement cols D-L via T554C → T512T + T511 ; classes via T554E
   (`load_t554e`, repli sur les 11 classes standard si absente).
3. **Peupler en place** l'onglet `Wagetype Catalog Absence_Data` (vue à plat,
   position conservée — vidé puis réécrit).
4. **Injecter** dans l'onglet principal (`populate_main_sheet`) : vide les données
   d'exemple (lignes 8-232), réécrit par catégorie `(0Xxx)`, puis **ré-applique les
   listes déroulantes** du template aux vraies lignes (col C=Used, F/I=unité,
   L=Heure/Jour, P→Z=■/□ ; TH/TJ ignorées car `#REF!`).
5. **Sauvegarder** vers le fichier de sortie (garde-fou : refuse d'écraser le template).

### Compléments restant manuels (non auto)
- "Used" (col C), "Formule de calcul" (M), "Taux horaire/jour" (N/O) = paramétrage métier.
- ⚠ Les listes déroulantes **TH** (col N) et **TJ** (col O) sont mortes dans le template :
  leurs named ranges pointent sur `#REF!` depuis la suppression de l'onglet
  "Taux de valorisation". À recréer côté template (source de liste + repointage)
  si l'HRO veut ces menus déroulants.

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
| `openpyxl` | ≥ 3.1 | Lecture/écriture des fichiers `.xlsx` (template `WTCA reference` + tables client + sortie) |
| `Pillow` | ≥ 10.0 | Manipulation d'images (logo Strada, requis par openpyxl pour `XLImage`) |

> Plus de dépendance LibreOffice côté Windows : le template `WTCA reference.xlsx` est commit dans le projet, prêt à l'emploi.

#### Libs dev (optionnelles)

Listées dans `requirements-dev.txt` :
- `xlrd==2.0.1` — lecture des `.xls` historiques (debug uniquement ; les anciens modèles GFK ne sont plus dans le repo)
- `pdfplumber` — inspection de PDF (les captures `Absence WageType Catalog Standardized.pdf` ne sont plus dans le repo)

## Conventions

- Python 3.9+ + `.venv/` local
- Tous les libellés / commentaires en français
- Numérotation : `APP_VERSION` à incrémenter dans le script à chaque modif + changelog en docstring
- Logo + couleurs Strada : `logo_strada.png`, `#084028` (foncé) / `#207F4F` (moyen) / `#18D878` (clair)
