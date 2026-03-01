# SAP_DSN — Analyse des tickets DSN SAP EuHReka

## Vue d'ensemble

Projet d'analyse automatisée de tickets SAP liés à la **DSN** (Déclaration Sociale Nominative) pour identifier les problèmes récurrents, les tables SAP impliquées et les procédures de résolution.

**Résultat principal** : 3158 fichiers Excel scannés → **1558 tickets DSN uniques** identifiés, compilés dans un rapport unifié avec guides de résolution par type de problème.

## Sources de données

| Source | Chemin | Contenu |
|--------|--------|---------|
| Julio (par année) | `E:\Dossier Manuel (CV, taf, dev etc)\NGA\Travail (NGA et autres)\Tous les TE de Julio` | 1887 fichiers, 5 ans (2019-2023), sous-dossiers par mois |
| SAP Ticket (par client) | `E:\Dossier Manuel (CV, taf, dev etc)\NGA\Travail (NGA et autres)\SAP Ticket\SAP Ticket` | 1271 fichiers, 9 clients (Corning, Akzo Nobel, Astellas, Lonza, Leo Pharma, Alcon, Bunge, Abbvie, Reckitt) |

## Fichiers du projet

### Données de référence
| Fichier | Description |
|---------|-------------|
| `DSN_Mapping_SAP.xlsx` | Correspondance blocs/codes DSN ↔ Tables/Infotypes SAP (1396 lignes) |
| `dsn-cahier-technique-2020.pdf` | Cahier technique DSN officiel (description des blocs et codes) |
| `Instructions.txt` | Instructions initiales du projet |
| `processingclass.png` | Screenshot T512W montrant les Processing Classes (classes de traitement) |

### Scripts Python
| Script | Description |
|--------|-------------|
| `scan_dsn_tickets.py` | Scanner source 1 (Julio/année) — détecte les tickets DSN par mots-clés dans le nom de fichier et le contenu |
| `scan_dsn_tickets_clients.py` | Scanner source 2 (SAP Ticket/client) — même logique, adapté à la structure par client |
| `generate_report.py` | Générateur du rapport initial (source 1 seule) — obsolète, remplacé par `merge_and_report.py` |
| `merge_and_report.py` | Fusion des deux sources + génération du rapport unifié final |

### Résultats
| Fichier | Description |
|---------|-------------|
| `RAPPORT_DSN_ANALYSE.txt` | **Rapport unifié final** — 7 sections, guides de résolution, tables par bloc |
| `dsn_tickets_raw.json` | Données brutes des tickets DSN source 1 (832 tickets) |
| `dsn_tickets_clients_raw.json` | Données brutes des tickets DSN source 2 (920 tickets) |
| `dsn_tickets_ALL.json` | Fusion dédoublonnée des deux sources (1558 tickets) |
| `dsn_analysis.json` | Analyse statistique de la source 1 (ancienne, conservée pour référence) |

## Architecture des scripts

### Détection DSN
Les scripts identifient un ticket comme DSN via deux mécanismes :
1. **Nom de fichier** : mots-clés comme `dsn`, `bloc 78`, `taux pas`, `urssaf`, `cotisation`, etc.
2. **Contenu** : scan des onglets Excel pour les mêmes mots-clés + codes DSN (`S21.G00.xx.xxx`)

### Structure des tickets Excel
Les fichiers de tickets ont des formats variables :
- **Format structuré** (majoritaire) : onglets `INC FORM`, `DFCT FORM`, `Test Evidence Form`, `Change Logs`, `Analyse`, `AMO Screeshots QAS`
- **Format libre** : onglets `Sheet1`, `AMO` avec du texte libre

Le contenu exploitable est souvent textuel (pas d'images analysées). Les solutions des techniciens se trouvent dans les onglets `Change Logs`, `AMO`, `Analyse`.

### Extraction des tables SAP
Regex pour capturer les noms de tables/vues : `V_T5F*`, `T5F*`, `V_T596*`, `V_T511*`, `V_T512*`, `Y00BA_*`, `ZFRPY_*`, `ZESPY_*`, `RPLDSNF*`, `RPUDSNF*`

## Terminologie clé

| Terme | Signification |
|-------|---------------|
| DSN | Déclaration Sociale Nominative |
| MDC | Modèle De Charge (PAS "Modèle De Calcul") |
| WT | Wage Type / Rubrique de paie |
| OPS | Organisme de Protection Sociale |
| CTP | Code Type de Personnel (URSSAF) |
| PAS | Prélèvement À la Source |
| EuHReka | Solution SAP de NGA/Northgate (proche SAP standard, quelques tables spécifiques Y00BA_*) |
| Processing Classes | Dans T512W / V_512W_O (PAS dans V_T511P qui contient des taux/constantes) |

## Tables SAP critiques (top 5)

1. **V_T5FDSNCOTIS2** (143 occurrences) — Table MAÎTRE mapping cotisations DSN
2. **Y00BA_VIE_FIWTSA** (54) — Assignation rubriques EuHReka
3. **Y00BA_VIE_ASSI3** (45) — Assignation spécifique EuHReka
4. **V_T511K** (41) — Caractéristiques des rubriques de paie
5. **V_T5F99FX** (37) — Feature DSN mapping étendu

## Dépendances

- Python 3.12 avec `openpyxl` (3.1.5)
- Pas de virtualenv, pas de tests, pas de linting

## Notes

- Les fichiers `.xls` (ancien format Excel) ne sont pas lisibles par openpyxl → comptés en erreurs (131+183)
- RT et CT apparaissent massivement car ce sont les tables résultat de paie, présentes dans quasi tous les tickets — filtrés dans l'analyse des solutions
- Le rapport est en français, les tickets sont un mélange français/anglais/espagnol (techniciens internationaux)
- Si de nouvelles sources de tickets sont disponibles, il suffit de créer un nouveau scanner avec le même pattern et d'ajouter la source dans `merge_and_report.py`
