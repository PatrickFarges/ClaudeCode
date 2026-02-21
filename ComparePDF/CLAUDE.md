# ComparePDF

Application desktop Python 3 / Tkinter qui compare deux PDF de bulletins de paie (PRE vs POST) et génère un rapport Excel coloré des écarts.

## Lancer

```bash
pip install pypdf openpyxl
python Compare_PDF_V4.py
```

## Architecture (fichier unique `Compare_PDF_V4.py`, ~800 lignes)

- **Lignes 1-30 :** Config couleurs hex pour l'export Excel (PRE/POST/DELTA)
- **Lignes 31-154 :** Logique métier — extraction texte PDF groupé par matricule, parsing nombres FR (`1.234,56-` style SAP), calcul deltas
- **Lignes 156-252 :** Moteur de comparaison — parsing flexible (2 regex: avec/sans code rubrique), classification SUPPRIME/AJOUTE/IMPACT BRUT/RECALCUL
- **Lignes 254-403 :** Génération Excel — en-têtes multi-niveaux, sections colorées, regroupement par matricule
- **Lignes 408-762 :** Classe GUI `ComparePDFApp` — sélection fichiers, comparaison threadée, barre de progression
- **Lignes 767-800 :** Point d'entrée avec vérification dépendances

## Concepts métier

- Matricule : ID salarié (4-10 chiffres), regex : `(?:Matricule|Matr\.|Pers\.No\.)\s*[:.]?\s*(\d{4,10})`
- Ligne de paie : CODE (4 car.) + LIBELLE + VALEURS (Base, Tx Sal, Mt Sal, Tx Pat, Mt Pat)
- Format numérique français : virgule = décimale, point = milliers, `-` en fin = négatif
- "Mode détaillé" : affiche les RECALCUL pour régularisations rétroactives (occurrence > 1)

## Notes

- **GitHub dédié :** `https://github.com/PatrickFarges/ComparePDF` — repo séparé, synchronisé via `git subtree push --prefix=ComparePDF`
