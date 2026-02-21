# CompareSAPTable

Application desktop Python 3 / Tkinter de comparaison de tables SAP et de schémas de paie (PCR). Réécriture complète depuis Free Pascal/Lazarus (PCRandTables v0.92b) vers Python, avec gain de performance majeur (~2 secondes au lieu de ~15 pour traiter toutes les tables). Compare deux ensembles de fichiers texte (PRE vs POST) et génère un rapport Excel avec les différences, les mots modifiés étant surlignés en rouge.

## Lancer

```bash
pip install xlsxwriter
python main.py
```

**Dépendances :** xlsxwriter (obligatoire)

## Architecture (4 fichiers Python, ~1700 lignes)

- **`main.py` (~824 lignes) :** GUI Tkinter + orchestration
  - Classe `CompareSAPApp(tk.Tk)` : fenêtre principale 1280x720, toolbar (Execute/Save As/Clear/Options/About), champs PRE/POST avec Browse, grille 3 colonnes synchronisées (Table | Before | After) avec scrollbar partagée, panneau stats à droite
  - Classe `OptionsDialog(tk.Toplevel)` : config KeyValue pour schemas, override global, auto-save, affichage PIT, gestion des keycuts par table (ajout/suppression)
  - `load_config()` / `save_config_option()` : lecture/écriture `Options.ini` (compatible avec le format Pascal original, `:=` → `=`)
  - `resolve_keycut()` : résolution du nombre de caractères clé selon la table (TableCutNumber → GeneriqueFiles → override global)
  - `run_comparison()` : pipeline complet — mode fichier ou dossier, appariement par nom de fichier, extraction nom de table, comparaison, tri, colorisation
- **`comparator.py` (~442 lignes) :** Moteur de comparaison (portage fidèle de `compare_file.pas`)
  - `get_changes()` : chargement avec fallback encodage (UTF-8 → Latin-1 → CP1252), normalisation, dédoublonnage par set, exclusion des dates SAP
  - `get_score()` : scoring de similarité entre deux lignes — pondération quadratique sur les N premiers caractères (keycut), bonus mots communs après le keycut
  - `fill_scheme()` : matching greedy pour schémas PCR — groupement par nom de règle (4 premiers car.), gestion PIT (lignes avec numéro de ligne différent mais contenu identique), insertion/ajout des lignes non matchées
  - `_match_by_key()` : matching pour tables non-PCR — appariement par clé (N premiers caractères sans espaces)
  - `colorize_change()` : colorisation mot-par-mot — comparaison positionnelle, détection de mots déplacés (`_word_elsewhere`), gestion des longueurs différentes
- **`excel_writer.py` (~186 lignes) :** Export XLSX via xlsxwriter
  - Classe `ComparisonResult` : conteneur (table_name, pre_lines, post_lines, is_pcr, keycut)
  - `write_excel()` : en-tête configurable (Table | Before | After | Comments), sous-en-têtes par table/schéma en orange, texte riche `write_rich_string()` pour les mots différents en rouge
- **`win_dnd.py` (~244 lignes) :** Drag-and-drop natif Windows sans dépendance externe
  - Trampoline en code machine x64 pur (VirtualAlloc PAGE_EXECUTE_READWRITE) qui intercepte `WM_DROPFILES` sans toucher au GIL Python
  - Polling toutes les 50ms via `tk.after()` depuis le thread principal — lecture sûre du handle HDROP stocké en mémoire partagée
  - Gestion UIPI (ChangeWindowMessageFilterEx) pour les processus élevés

## Données de test incluses

- `PRE_Tables/` et `POST_Tables/` : ~85 fichiers de tables SAP (T030, T510, T512T, T512W, T5F*, Y00BA_TAB_*, V_T5F*, etc.)
- `PRE_Schema.txt` et `POST_Schema.txt` : schémas de paie complets (~4.6 Mo chacun)

## Config (`Options.ini`, ~270 lignes)

- `[DeleteFileNamePart]` : 8 suffixes à supprimer des noms de fichiers (_DP9_BEFORE, _ED5_AFTER, etc.)
- `[TableCutNumber]` : ~85 tables avec leur keycut spécifique (PCR=9, T030=17, T510=10, CSKS=63, etc.) — valeur 1000 = comparer la ligne entière
- `[GeneriqueFiles]` : keycuts génériques par pattern de nom (Generique=10, RunPosting=19, Results=8, etc.)
- `[GenOptions]` : auto-save, affichage PIT identiques, override global des keycuts
- `[ColorDifference]` : couleur des différences (rouge par défaut)
- `[StandardFont]` : police Calibri 11pt

## Présentation du résultat

- Colonne A : nom de la table SAP (ou nom de la règle PCR sur 4 caractères)
- Colonne B : lignes supprimées/modifiées (version PRE), mots changés en rouge
- Colonne C : lignes ajoutées/modifiées (version POST), mots changés en rouge
- Colonne D : commentaires / transports (à remplir manuellement)

## Historique

Réécriture de `ComparePCRandTables/PCRandTables.exe` (Free Pascal/Lazarus, v0.92b, ~2048 lignes Pascal dans `compare_file.pas` + `analyseprepost.pas`) en Python. Le code source Pascal original et l'exécutable sont conservés dans le sous-dossier `ComparePCRandTables/`.
