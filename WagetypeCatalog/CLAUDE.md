# WagetypeCatalog

Projet de catalogage des rubriques de paie SAP EuHReka. Pas de code exécutable — uniquement des données sources et un fichier Excel consolidé.

## Contenu

- **`WageType_Catalog_EuHReka_GROUPED.xlsx`** : catalogue consolidé et groupé des wage types
- **`Tables pour creer le Wagetype Catalog/`** : ~25 fichiers texte de tables SAP sources (T512T = catalogue rubriques ~12K lignes, T52C0 = mapping paie→compta ~69K lignes, T030 = config codes ~13K lignes, Y00BA_TAB_* = mappings comptes symboliques/comptables)

## Pipeline de données

Rubriques (T512T/T512W) → Comptes symboliques (Y00BA_TAB_FISADF/FISAAC) → Comptes comptables (T52C0/T52C1) → Grand Livre FI
