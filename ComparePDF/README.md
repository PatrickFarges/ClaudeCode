# ComparePDF - Comparateur de Bulletins de Paie

Application desktop Python / Tkinter qui compare deux PDF de bulletins de paie (PRE vs POST) et produit un rapport Excel des ecarts.

Concue pour les equipes RH/Paie SAP, elle detecte automatiquement les rubriques ajoutees, supprimees ou modifiees, matricule par matricule.

![Python](https://img.shields.io/badge/Python-3.8+-blue) ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey)

## Fonctionnalites

- Extraction automatique du texte PDF et regroupement par matricule
- Parsing des formats numeriques SAP/francais (`1.234,56-`)
- Classification des ecarts : **SUPPRIME**, **AJOUTE**, **IMPACT BRUT**, **RECALCUL**
- Calcul des deltas par composante (Base, Tx Sal, Mt Sal, Tx Pat, Mt Pat)
- Rapport Excel colore avec en-tetes fusionnes PRE / POST / DELTA
- Mode detaille pour afficher les recalculs retroactifs
- Detection des PDF scannes (sans texte extractible)
- Interface graphique avec barre de progression

## Installation

```bash
pip install pypdf openpyxl
```

## Utilisation

```bash
python Compare_PDF_V4.py
```

1. Cliquer sur **Ouvrir fichier PRE** pour selectionner le bulletin avant modification
2. Cliquer sur **Ouvrir fichier POST** pour selectionner le bulletin apres modification
3. Cocher **Mode DETAILLE** si souhaite (affiche les recalculs retroactifs)
4. Cliquer sur **Lancer la comparaison**
5. Choisir l'emplacement du fichier Excel de sortie

## Rapport Excel

Le rapport genere contient pour chaque matricule avec ecarts :

| Section | Couleur | Description |
|---------|---------|-------------|
| SUPPRIME | Rouge clair | Rubrique presente en PRE mais absente en POST |
| AJOUTE | Vert clair | Rubrique absente en PRE mais presente en POST |
| IMPACT BRUT | Jaune | Rubrique contenant "BRUT" ou "GROSS" avec valeurs differentes |
| RECALCUL | Jaune pale | Autre rubrique modifiee (mode detaille uniquement) |

Chaque ligne affiche les 5 composantes (Base, Tx Sal, Mt Sal, Tx Pat, Mt Pat) en PRE, POST et DELTA.

## Concepts metier

- **Matricule** : identifiant salarie (4 a 10 chiffres), detecte via `Matricule`, `Matr.` ou `Pers.No.`
- **Format numerique SAP** : virgule = decimale, point = milliers, `-` en fin = negatif
- **Occurrence** : une rubrique apparaissant plusieurs fois indique une regularisation retroactive

## Dependances

- [pypdf](https://pypi.org/project/pypdf/) - extraction de texte PDF
- [openpyxl](https://pypi.org/project/openpyxl/) - generation de fichiers Excel
- tkinter - interface graphique (inclus avec Python)
