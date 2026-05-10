# WagetypeCatalog

Projet de catalogage des rubriques de paie SAP EuHReka. Données sources et fichier Excel consolidé, issu d'un projet originel en Free Pascal/Lazarus.

## Projet originel (Free Pascal / Lazarus)

- **Répertoire (legacy Windows)** : `D:\Projets\Lazarus\CreateWTCatalog\` — non remonté sur le poste Linux actuel
- **Exécutable** : `WTCatalog.exe` — application Windows avec wizard, options, gestion multi-langues (FR/ES/IT/PT/EN). Pour le faire tourner sous Linux : recompiler les sources Pascal avec Lazarus Linux, ou exécuter via Wine/Bottles.
- **Sources Pascal** : `wtc_mainform.pas` (form principal), `unt_wizard.pas` (assistant), `unt_options.pas` (config), `unt_about.pas` (à propos), `unt_missingcol.pas` (colonnes manquantes), `unt_arraystr.pas` (utilitaires string), `stringgridutil.pas` (grille)
- **Formulaires Lazarus** : `.lfm` associés à chaque unité
- **Projet Lazarus** : `WTCatalog.lpi` / `.lpr`
- **Config** : `OptionsWTC.ini`
- **Documentation** : `Manual for CreateWTCatalog.pdf/.pptx`, `Instructions.rtf`, `Files needed for CreateWTCatalog.pdf`
- **Headers Excel** : `HeaderFR.xls`, `HeaderES.xls`, `HeaderIT.xls`, `HeaderPT.xls`, `HeaderEN.xls`
- **Backup** : sous-dossier `backup/` avec copie des sources

## Structure des fichiers Header (templates Excel)

Les fichiers `Header**.xls` sont les templates sur lesquels le catalogue est construit. `**` = code langue (FR/ES/IT/PT/EN).

### Onglets (5 par fichier)

| Onglet FR | Description |
|-----------|-------------|
| **WageType Catalog** | Catalogue principal des rubriques |
| **Rubrique -> Cpt symbolique** | Mapping rubrique → compte symbolique |
| **Cpt symbolique -> Cpt Globaux** | Mapping compte symbolique → compte global (GL) |
| **Rubrique -> Cpt Globaux** | Mapping rubrique → compte global (raccourci direct) |
| **Parameter** | Listes de valeurs (Tax, Freq, Sign, etc.) — ne pas modifier |

> Les noms d'onglets sont traduits par langue (ex: ES = "Codigo CC -> Cuenta simbólica", IT = "Voce retrib. -> Conta simb.", etc.)

### Structure de l'onglet WageType Catalog

- **Lignes 1-5** : zone logo/titre (anciennement logo Alight en .png collé)
- **Ligne 6** : en-têtes de sections (Rubriques EuHReka | Saisie dans infotype | Impact paie | Impact Post paie | Attributs Spécifiques Pays)
- **Ligne 7** : en-têtes de colonnes détaillés
- **Ligne 8** : première ligne de données = en-tête de section rubriques, commence par `(/xxx)` + "Rubriques standard"
- **Ligne 9+** : rubriques de paie (ex: `/001`, `/002`, etc.)

### Colonnes (onglet WageType Catalog, version FR = 50 colonnes)

| Cols | Section | Contenu |
|------|---------|---------|
| 1-2 | Rubriques | Code rubrique, libellé |
| 3-9 | Saisie infotype | Utilisé, calcul auto, IT 0008/0014/0015/2010, autres IT |
| 10-16 | Impact paie | Imposable, auto/ponctuel/récurrent, formule, paiement/déduction, montant/nombre, unité, prorata |
| 18-21 | Impact post-paie | Affichage bulletin, position, ventilation compta, spécificités états |
| 23-45 | Bases de cotisation | Rubriques `/xxx` (ex: /101 Total Brut, /102 URSSAF, etc.) — 23 codes pour FR |
| 46-49 | **Colonnes spécifiques pays** | Varient selon la langue (voir ci-dessous) |
| 50 | Commentaires | Commentaires additionnels |

### Colonnes spécifiques par pays (les plus à droite)

- **FR** (cols 46-49) : ~~Brut coefficient FILLON, Brut abattu FILLON, Brut reconstitué FILLON~~ → **à remplacer par RGDU** (remplacement de FILLON depuis 2026), CICE
- **ES** (cols 47-52) : Salaire brut, Variables fixes, Variables variables, Avantages, Revenus irréguliers, Commentaires
- **IT** (cols 41-52) : Règles comptables/enregistrement spécifiques au système RT italien
- **PT** (cols 45-52) : Règles de transfert, stockage, accumulation
- **EN** (cols 46-49) : Identique à FR (Fillon/CICE) — **même remplacement RGDU à appliquer**

> **IMPORTANT** : Le nombre de colonnes et de codes `/xxx` varie par pays (FR/EN=50 cols, ES/IT/PT=52 cols)

## Branding

- **Ancien** : Alight (logo `LogoAlight.png` collé dans les lignes 1-5 du fichier output)
- **Nouveau** : **STRADA** — couleur corporate = vert légèrement sombre. Le logo et les couleurs du fichier output doivent refléter STRADA, pas Alight

## Contenu (répertoire local)

- **`WageType_Catalog original.xlsx`** : exemple d'output complet (version FR, ~4087 rubriques, 5 onglets) — sert de référence pour le format attendu
- **`WageType_Catalog_EuHReka_GROUPED.xlsx`** : catalogue consolidé et groupé des wage types
- **`Tables pour creer le Wagetype Catalog/`** : ~25 fichiers texte de tables SAP sources (T512T = catalogue rubriques ~12K lignes, T52C0 = mapping paie→compta ~69K lignes, T030 = config codes ~13K lignes, Y00BA_TAB_* = mappings comptes symboliques/comptables)

## Pipeline de données

Rubriques (T512T/T512W) → Comptes symboliques (Y00BA_TAB_FISADF/FISAAC) → Comptes comptables (T52C0/T52C1) → Grand Livre FI
