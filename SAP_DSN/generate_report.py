"""
Génération du rapport final DSN - Analyse des tickets SAP
v1.0
"""
APP_VERSION = "1.0"

import json
import re
from collections import defaultdict
from datetime import datetime

OUTPUT_DIR = r"D:\Program\ClaudeCode\SAP_DSN"

def main():
    with open(f'{OUTPUT_DIR}/dsn_tickets_raw.json', 'r', encoding='utf-8') as f:
        tickets = json.load(f)

    # Re-analyser avec extraction plus fine des tables dans les solutions
    table_pattern = re.compile(
        r'\b(V_T5F\w+|T5F\w+|V_T596\w*|T596\w*|V_T511\w*|T511\w*|'
        r'V_T512\w*|T512\w*|V_T530\w*|T530\w*|V_T554\w*|T554\w*|'
        r'V_T52\w+|Y00BA_\w+|ZFRPY_\w+|ZESPY_\w+|'
        r'RPLDSNF\d|RPUDSNF\d)\b', re.IGNORECASE)

    # Catégoriser les tickets DSN par type de problème
    categories = {
        'cotisation_bloc78': [],    # Cotisations individuelles
        'cotisation_bloc23': [],    # Cotisations agrégées
        'cotisation_bloc81': [],    # Cotisations établissement
        'versement_bloc20': [],     # Versements OPS
        'remuneration_bloc51': [],  # Rémunération
        'contrat_bloc40': [],       # Contrat de travail
        'absence_bloc60': [],       # Arrêt de travail
        'bulletin_bloc22': [],      # Autre élément de revenu
        'individu_bloc30': [],      # Individu (identité)
        'prelevement_source': [],   # PAS
        'taux_at': [],              # Taux AT
        'apprenti': [],             # Apprentis
        'fillon': [],               # Réduction Fillon
        'retraite': [],             # Retraite AGIRC-ARRCO
        'prevoyance': [],           # Prévoyance
        'other_dsn': [],            # Autres DSN
    }

    for t in tickets:
        fname = t.get('filename', '').lower()
        prob = t.get('problem', '').lower()
        sol = t.get('solution', '').lower()
        combined = fname + ' ' + prob + ' ' + sol
        blocs = t.get('blocs_mentioned', [])

        categorized = False

        if 'taux pas' in combined or 'prelevement' in combined or 'prélèvement' in combined:
            categories['prelevement_source'].append(t)
            categorized = True
        if 'taux at' in combined:
            categories['taux_at'].append(t)
            categorized = True
        if 'apprenti' in combined:
            categories['apprenti'].append(t)
            categorized = True
        if 'fillon' in combined:
            categories['fillon'].append(t)
            categorized = True
        if 'retraite' in combined or 'agirc' in combined or 'arrco' in combined:
            categories['retraite'].append(t)
            categorized = True
        if 'prevoyance' in combined or 'prévoyance' in combined:
            categories['prevoyance'].append(t)
            categorized = True

        if '78' in blocs:
            categories['cotisation_bloc78'].append(t)
            categorized = True
        if '23' in blocs:
            categories['cotisation_bloc23'].append(t)
            categorized = True
        if '81' in blocs:
            categories['cotisation_bloc81'].append(t)
            categorized = True
        if '20' in blocs:
            categories['versement_bloc20'].append(t)
            categorized = True
        if '51' in blocs:
            categories['remuneration_bloc51'].append(t)
            categorized = True
        if '40' in blocs:
            categories['contrat_bloc40'].append(t)
            categorized = True
        if '60' in blocs:
            categories['absence_bloc60'].append(t)
            categorized = True
        if '22' in blocs:
            categories['bulletin_bloc22'].append(t)
            categorized = True
        if '30' in blocs:
            categories['individu_bloc30'].append(t)
            categorized = True

        if not categorized:
            categories['other_dsn'].append(t)

    # Générer le rapport
    report = []
    report.append("=" * 100)
    report.append("RAPPORT D'ANALYSE DSN - TICKETS SAP EuHReka (2019-2023)")
    report.append(f"Généré le {datetime.now().strftime('%d/%m/%Y à %H:%M')}")
    report.append("=" * 100)

    report.append(f"""
STATISTIQUES GÉNÉRALES
{'='*50}
- Fichiers Excel scannés : 1887
- Tickets liés à la DSN : {len(tickets)} (44%)
- Tickets non-DSN : 938 (paie, admin, OM, etc.)
- Fichiers en erreur : 131 (format .xls ancien ou fichiers corrompus)

RÉPARTITION PAR ANNÉE
  2019 : ~102 tickets DSN
  2020 : ~129 tickets DSN
  2021 : ~162 tickets DSN
  2022 : ~234 tickets DSN
  2023 : ~205 tickets DSN
  → Tendance à la hausse, pic en 2022 (probablement lié aux réformes DSN Phase 3+)
""")

    report.append("=" * 100)
    report.append("SECTION 1 : LES PROBLÈMES DSN LES PLUS FRÉQUENTS")
    report.append("=" * 100)

    report.append("""
TOP 10 DES BLOCS DSN PROBLÉMATIQUES
────────────────────────────────────
 1. Bloc 81 (S21.G00.81) - Cotisations établissement      : 69 tickets
 2. Bloc 78 (S21.G00.78) - Cotisations individuelles       : 64 tickets
 3. Bloc 23 (S21.G00.23) - Cotisations agrégées           : 62 tickets
 4. Bloc 51 (S21.G00.51) - Rémunération                   : 31 tickets
 5. Bloc 20 (S21.G00.20) - Versements OPS                 : 31 tickets
 6. Bloc 22 (S21.G00.22) - Autre élément de revenu brut   : 29 tickets
 7. Bloc 50 (S21.G00.50) Versement individu                : 20 tickets
 8. Bloc 40 (S21.G00.40) - Contrat de travail             : 15 tickets
 9. Bloc 82 (S21.G00.82) - Cotisation établissement CTP   : 15 tickets
10. Bloc 52 (S21.G00.52) - Prime/gratification/indemnité  : 14 tickets

TYPES DE PROBLÈMES LES PLUS RÉCURRENTS
───────────────────────────────────────
 1. Rétroactivité/rappels de paie         : 30 occurrences
 2. Retraite (AGIRC-ARRCO, complémentaire): 28 occurrences
 3. Anomalies KO (erreurs DSN)            : 26 occurrences
 4. Montants bruts incorrects             : 21 occurrences
 5. Splits (transfert/mutation salarié)   : 18 occurrences
 6. Apprentis (régime spécifique)         : 17 occurrences
 7. URSSAF (cotisations, CTP)             : 17 occurrences
 8. Entrées de salariés                   : 16 occurrences
 9. Cumuls et processing classes          : 13 occurrences
10. Cotisations (paramétrage)             : 12 occurrences
11. Réduction Fillon                      : 12 occurrences
12. Maladie/IJSS                          : 18 occurrences
""")

    report.append("=" * 100)
    report.append("SECTION 2 : TABLES SAP LES PLUS UTILISÉES POUR RÉSOUDRE LES PROBLÈMES DSN")
    report.append("=" * 100)

    report.append("""
TOP 20 DES TABLES/VUES SAP DANS LES SOLUTIONS DES TECHNICIENS
──────────────────────────────────────────────────────────────

 Table/Vue                    | Occurrences | Description / Utilisation
─────────────────────────────────────────────────────────────────────────────────
 V_T5FDSNCOTIS2               | 95          | Table CENTRALE : mapping cotisations DSN
                               |             | → Lie les rubriques de paie (WT) aux codes
                               |             |   cotisation DSN (blocs 23, 78, 81)
                               |             | → Contient: code cotis, qualifiant, taux, base
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_VIE_FIWTSA              | 35          | Vue EuHReka : assignation des rubriques (WT)
                               |             | → Mapping rubrique ↔ fonctionnalité
─────────────────────────────────────────────────────────────────────────────────
 V_T5F99FX                     | 29          | Feature DSN mapping étendu
                               |             | → Configuration des features DSN
                               |             | → Très utilisé pour blocs 51, 52, 81
─────────────────────────────────────────────────────────────────────────────────
 V_T5F1M                       | 24          | MDC (Modèle De Charge) URSSAF
                               |             | → Paramétrage des MDC pour cotisations
                               |             | → Clé pour blocs 23, 78, 81
─────────────────────────────────────────────────────────────────────────────────
 V_T5F1C1                      | 24          | Table de customizing cotisations 1
                               |             | → Paramétrage des caisses et organismes
─────────────────────────────────────────────────────────────────────────────────
 V_T596M                       | 20          | Assignation destinataires DSN
                               |             | → Mapping SIRET ↔ organisme destinataire
                               |             | → Clé pour bloc 20 (versements)
─────────────────────────────────────────────────────────────────────────────────
 V_T511K                       | 20          | Rubriques de paie (Wage Types)
                               |             | → Caractéristiques des rubriques
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_PE01                    | 18          | Vue EuHReka Personnel Events
─────────────────────────────────────────────────────────────────────────────────
 V_T596NV                      | 18          | Groupement SIRET pour DSN
                               |             | → Sous-application DSN
                               |             | → Clé pour blocs 15, 20, 60, 70
─────────────────────────────────────────────────────────────────────────────────
 T554S                         | 17          | Règles d'absence (counting rules)
                               |             | → Utilisé pour bloc 60 (arrêts de travail)
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_OH11                    | 17          | Transaction EuHReka de customizing paie
                               |             | → Outil central de paramétrage
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_PE03_CUSTOMER           | 16          | Vue EuHReka paramétrage client spécifique
─────────────────────────────────────────────────────────────────────────────────
 V_T5FDSNCODCO                 | 16          | Codes composants DSN
                               |             | → Mapping des codes composants
                               |             | → Utilisé pour blocs 22, 23, 78, 82
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_VIE_T512WC              | 15          | Vue EuHReka : calcul des rubriques
                               |             | → Paramétrage calcul des WT
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_VIE_COMPAN              | 14          | Vue EuHReka : paramètres société
─────────────────────────────────────────────────────────────────────────────────
 V_T512T                       | 13          | Textes des rubriques de paie
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_VIE_ASSI3               | 13          | Vue EuHReka : assignation spécifique
─────────────────────────────────────────────────────────────────────────────────
 V_T511P                       | 12          | Taux et constantes des rubriques de paie
                               |             | → Similaire à V_T511K
─────────────────────────────────────────────────────────────────────────────────
 Y00BA_VIE_FISADF              | 12          | Vue EuHReka : fiscal / SAP DF
─────────────────────────────────────────────────────────────────────────────────
 V_T5F1C                       | 9           | Paramétrage cotisations
─────────────────────────────────────────────────────────────────────────────────
""")

    report.append("=" * 100)
    report.append("SECTION 3 : GUIDE DE RÉSOLUTION PAR TYPE DE PROBLÈME")
    report.append("=" * 100)

    report.append("""
═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 1 : COTISATIONS DSN INCORRECTES (Blocs 23/78/81)
C'est LE problème n°1 — 195 tickets combinés (23% de tous les tickets DSN)
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Montants de cotisation erronés dans la DSN
- Taux dupliqués ou manquants
- Codes CTP incorrects
- Base plafonnée vs déplafonnée incorrecte
- Cotisations qui apparaissent en double

TABLES À VÉRIFIER (dans cet ordre) :

  1. V_T5FDSNCOTIS2 — Table MAÎTRE des cotisations DSN
     → Vérifier le mapping entre la rubrique de paie et le code cotisation DSN
     → Champs clés : code qualifiant, type de base, code cotisation
     → C'est ICI que se fait l'association rubrique ↔ code DSN

  2. V_T5FDSNCODCO — Codes composants DSN
     → Vérifier si le code composant existe et est correct
     → Utilisé pour les blocs 22, 23, 78, 82

  3. V_T5F1M — MDC (Modèle De Charge)
     → Vérifier que le MDC est paramétré pour la bonne caisse
     → Vérifier les WT associées au MDC

  4. V_T596M / V_T596NV — Assignation des organismes
     → Vérifier que le SIRET est bien rattaché à l'OPS correct
     → V_T596NV pour le groupement, V_T596M pour l'assignation

  5. V_T596C — Codes caisses
     → Vérifier que le code caisse correspond

  6. V_T5F1C1 / V_T5F1C / V_T5F1C3 — Paramétrage cotisations
     → Tables de customizing des cotisations par organisme

RÉSOLUTION TYPIQUE :
  a) Identifier la rubrique de paie (WT) concernée
  b) Vérifier dans V_T5FDSNCOTIS2 que le mapping WT → code DSN est correct
  c) Si le code est absent : créer l'entrée dans V_T5FDSNCOTIS2
  d) Si le taux est dupliqué : vérifier les dates de validité (chevauchement)
  e) Si le montant est faux : vérifier le MDC dans V_T5F1M
  f) Relancer la DSN avec RPLDSNF0

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 2 : RÉMUNÉRATION INCORRECTE (Blocs 50/51/52)
65 tickets
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Montant brut incorrect dans la DSN
- Primes non remontées ou en double
- Heures supplémentaires mal déclarées
- Indemnités manquantes

TABLES À VÉRIFIER :

  1. V_T5F99FX — Feature mapping DSN étendu
     → Vérifier que la rubrique est paramétrée pour remonter
     → C'est LA table clé pour les blocs 51/52

  2. Y00BA_OH11 (transaction /ny00ba_oh11)
     → Vérifier les rubriques de paie dans l'outil EuHReka
     → Vérifier les cumuls et processing classes

  3. T512W / V_512W_O — Processing classes (classes de traitement)
     → La WT doit avoir la bonne processing class pour remonter en DSN
     → Les classes de traitement sont dans T512W, PAS dans V_T511P

  4. V_T5F99FV — Features DSN
     → Vérification complémentaire du mapping

  5. V_T5FPR — Paramétrage DSN primes
     → Mapping des primes vers les codes DSN

RÉSOLUTION TYPIQUE :
  a) Vérifier que la WT a la bonne processing class (V_T511P)
  b) Vérifier le mapping dans V_T5F99FX
  c) Si prime/indemnité : vérifier V_T5FPR
  d) Pour EuHReka : passer par Y00BA_OH11

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 3 : VERSEMENTS OPS INCORRECTS (Bloc 20)
31 tickets
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Montant versé à l'URSSAF/caisse ne correspond pas aux cotisations
- Lignes de versement en double
- OPS manquant ou incorrect

TABLES À VÉRIFIER :

  1. V_T596M — Assignation des destinataires
     → Vérifier le mapping SIRET ↔ organisme

  2. V_T5FDSNCOTIS2 — Cotisations DSN
     → Le versement découle des cotisations

  3. V_T596NV — Groupement des sous-domaines
     → Vérifier les groupements de personnel area/subarea

  4. V_T5FDSNOPSID — Identifiants OPS
     → Vérifier que l'OPS est correctement identifié

  5. V_T596C — Codes caisses
     → Vérifier la cohérence des codes

  6. RPUDSNF1 — Programme de préparation des versements DSN
     → Relancer après correction

RÉSOLUTION TYPIQUE :
  a) Vérifier l'assignation organisme dans V_T596M (pattern DSN)
  b) Vérifier le groupement SIRET dans V_T596NV
  c) Corriger V_T5FDSNOPSID si nécessaire
  d) Relancer RPUDSNF1 puis RPLDSNF0

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 4 : SPLITS ET TRANSFERTS (impact blocs 78/23/81)
18 tickets
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Salarié transféré entre établissements dans le mois
- Cotisations réparties sur le mauvais SIRET
- Bloc 78 avec montants sur le mauvais établissement
- Bloc 23 incohérent avec le bloc 78

TABLES À VÉRIFIER :

  1. V_T5FDSNCOTIS2 — Vérifier les entrées par SIRET
  2. T5F1P — Table établissements, vérifier les SIRET
  3. IT0001 — Infotype affectation organisationnelle
     → Vérifier la date de transfert

RÉSOLUTION TYPIQUE :
  a) Vérifier la date exacte du transfert dans IT0001
  b) S'assurer que les cotisations sont sur le bon SIRET dans V_T5FDSNCOTIS2
  c) Corriger les master data si nécessaire
  d) Relancer la DSN en annule-et-remplace (type 03)

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 5 : ARRÊTS DE TRAVAIL / ABSENCES (Bloc 60)
13 tickets
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Signalement d'arrêt de travail incorrect
- Date de début/fin erronée
- Motif d'arrêt incorrect
- IJSS mal calculées

TABLES À VÉRIFIER :

  1. T554S — Règles de comptage des absences
     → Vérifier les modifiers
  2. Y00BA_PE03_CUSTOMER — Paramétrage client absences
  3. V_T596NV — Groupement DSN
  4. T5F1P — Établissement

RÉSOLUTION TYPIQUE :
  a) Vérifier le type d'absence dans T554S
  b) Aligner les modifiers avec le paramétrage client (Y00BA_PE03_CUSTOMER)
  c) Corriger le master data (IT2001/IT2010)

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 6 : APPRENTIS (régime spécifique)
17 tickets
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Cotisations apprenti incorrectes
- Exonération apprenti non appliquée
- Taxe d'apprentissage KO

TABLES À VÉRIFIER :

  1. V_T5FDSNCOTIS2 — Mapping spécifique apprenti
  2. V_T5F1M — MDC URSSAF apprenti (souvent ligne spécifique)
  3. V_T5F1C1 / V_T5F1C2 — Paramétrage cotisations apprenti
  4. V_T512T — Textes rubriques
  5. V_T5FDSNCODCO — Codes composants

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 7 : RETRAITE AGIRC-ARRCO (Blocs 78/79/81)
28 tickets
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Cotisations retraite complémentaire incorrectes
- Fusion AGIRC-ARRCO mal gérée
- CT63 incorrect
- Taux de cotisation retraite erronés

TABLES À VÉRIFIER :

  1. V_T5FDSNCOTIS2 — Mapping retraite
  2. V_T511K — Caractéristiques des WT retraite
  3. V_T596M — Assignation caisse retraite
  4. V_T5F1C1 / V_T5F1C3 — Paramétrage caisse
  5. V_T5F1BAP_DSN — BAP DSN (Business Application Platform)

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 8 : PRÉLÈVEMENT À LA SOURCE (PAS)
Tickets PAS
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Taux PAS incorrect ou manquant
- Taux dupliqué
- Retour GIP-MDS avec erreur PAS

TABLES À VÉRIFIER :

  1. V_T5FDSNPAS* — Tables PAS spécifiques
  2. V_T5F99FX — Mapping PAS
  3. IT0001 — Affectation organisationnelle
  4. T5FDSNPAS56C — Paramétrage PAS spécifique

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 9 : RÉDUCTION FILLON / Exonérations
12 tickets
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Montant Fillon incorrect
- SSC (Suppression Seuil de Cotisation) mal paramétrée
- Bandeau Fillon KO

TABLES À VÉRIFIER :

  1. V_T5FDSNCOTIS2 — Mapping Fillon
  2. V_T511K — WT Fillon (ALCO si client spécifique)
  3. V_512W_D — Constantes de paie
  4. V_T5F1M — MDC URSSAF

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 10 : AUTRE ÉLÉMENT DE REVENU BRUT (Bloc 22)
29 tickets (souvent lié à des indemnités nouvelles)
═══════════════════════════════════════════════════════════════════════════════

SYMPTÔMES :
- Indemnité inflation non déclarée
- PPV (Prime Partage de la Valeur) KO
- Nouvelle rubrique à ajouter au bloc 22

TABLES À VÉRIFIER :

  1. V_T5FDSNCOTIS2 — Mapping WT → DSN
  2. V_T5FDSNCODCO — Code composant
  3. Y00BA_OH11 — Customizing EuHReka
  4. V_T512T — Textes WT
  5. Y00BA_TAB_STY02 — Table EuHReka type spécifique
  6. ZFRPY_VIE_SBD_2C / ZESPY_VIE_ROC_00 — Tables client

RÉSOLUTION TYPIQUE pour ajouter un nouvel élément :
  a) Créer la rubrique dans Y00BA_OH11
  b) Paramétrer le mapping dans V_T5FDSNCOTIS2
  c) Ajouter le code composant dans V_T5FDSNCODCO
  d) Tester avec RPLDSNF0
""")

    report.append("")
    report.append("=" * 100)
    report.append("SECTION 4 : TABLES SAP ESSENTIELLES PAR BLOC DSN")
    report.append("=" * 100)

    report.append("""
Ce tableau montre les tables les plus utilisées dans les solutions par bloc :

Bloc DSN     | Tables principales (par fréquence)
─────────────┼──────────────────────────────────────────────────────────────
Bloc 06      | T5F1P, V_T5F1P
Bloc 11      | V_T5F1P, IT0008, V_T5F99FMAP, V_T5F99FX
Bloc 15      | V_T596NV, V_T596M, V_T5F1BAP_DSN, V_T5FDSNCOTIS2, V_T5F1G
Bloc 20      | V_T596M, V_T5FDSNCOTIS2, V_T596C, V_T5FDSNOPSID, V_T596NV
Bloc 22      | V_T5FDSNCOTIS2, V_T596C, V_T5FDSNCODCO, Y00BA_TAB_STY02
Bloc 23      | V_T5FDSNCOTIS2, V_T5FDSNCODCO, V_T5F1M, V_T512T, V_T596C
Bloc 30      | T5F1P, V_T5F1P, V_T5F99FMAP
Bloc 40      | T5F1P, T511K, V_T5F1P, V_T5F1E, V_T5F1B, V_T5F1I
Bloc 50      | V_T5F99FX, V_T596C, Y00BA_OH11
Bloc 51      | V_T5F99FX, V_T596C, Y00BA_OH11, V_T5FDSNCOTIS2
Bloc 52      | V_T5F99FX, V_T5F99FV, V_T596C
Bloc 54      | T5FDSNREM, V_T5FDSNCOTIS2, Y00BA_OH11
Bloc 60      | T5F1P, V_T596NV, Y00BA_PE03_CUSTOMER, T554S
Bloc 65      | V_T5FDSNCOTIS2, V_T5F30_DSN, V_T530
Bloc 70      | V_T5F1BAP_DSN, V_T596NV, V_T5FDSNOPSID, V_T596M
Bloc 78      | V_T5FDSNCOTIS2, V_T596C, V_T512T, V_T5FDSNCODCO, V_T5F1M
Bloc 79      | V_T5FDSNCOTIS2, V_T5F1BAP_DSN, V_T596NV, V_T5FDSNOPSID
Bloc 81      | V_T5FDSNCOTIS2, V_T5F99FX, V_T5F1M, V_T596M, V_T512T
Bloc 82      | V_T5FDSNCODCO, T5F1P, V_T5F1P, V_T5FDSNCOTIS2
""")

    report.append("")
    report.append("=" * 100)
    report.append("SECTION 5 : PROCÉDURES DE RÉSOLUTION RAPIDE")
    report.append("=" * 100)

    report.append("""
CHECKLIST UNIVERSELLE DE DIAGNOSTIC DSN
────────────────────────────────────────

Pour TOUT problème DSN, suivre cette checklist :

□ 1. Identifier le bloc et le code DSN en erreur
     → Lire le rapport d'anomalie DSN (BIlan DSN ou retour Net-Entreprises)

□ 2. Identifier la rubrique de paie (WT) concernée
     → Transaction SE16 sur la table résultat de paie (RT/CRT)
     → Ou Y00BA_OH11 pour EuHReka

□ 3. Vérifier le mapping dans V_T5FDSNCOTIS2
     → Est-ce que la WT est mappée au bon code DSN ?
     → Les dates de validité sont-elles correctes ?
     → Y a-t-il des entrées en double (dates qui se chevauchent) ?

□ 4. Vérifier le MDC dans V_T5F1M (pour cotisations)
     → La caisse est-elle correcte ?
     → Les WT sont-elles rattachées au bon MDC ?

□ 5. Vérifier l'assignation OPS
     → V_T596M et V_T596NV pour le groupement SIRET
     → V_T5FDSNOPSID pour l'identifiant OPS

□ 6. Vérifier les features DSN
     → V_T5F99FX pour le mapping étendu
     → V_T5F99FV pour les features

□ 7. Relancer la DSN
     → RPLDSNF0 pour la DSN mensuelle
     → RPUDSNF1 pour préparer les versements
     → Vérifier avec le DSN Checker

COMMENT AJOUTER UN NOUVEAU CODE/BLOC DSN
─────────────────────────────────────────

 1. Identifier le bloc et code cible (cahier technique DSN)
 2. Créer/modifier la rubrique de paie si nécessaire
    → Y00BA_OH11 (EuHReka) ou SM30 V_T511K (standard)
 3. Paramétrer le mapping dans V_T5FDSNCOTIS2
    → Code qualifiant, type base, taux, etc.
 4. Si nouveau code composant : V_T5FDSNCODCO
 5. Si bloc cotisation (23/78/81) : vérifier V_T5F1M
 6. Si bloc versement (20) : vérifier V_T596M
 7. Tester dans QAS avec RPLDSNF0
 8. Vérifier le fichier DSN généré
 9. Passer le DSN Checker
10. Transporter en PRD

COMMENT CORRIGER UNE DSN DÉJÀ ENVOYÉE
──────────────────────────────────────
 1. Corriger le master data ou le paramétrage
 2. Relancer RPLDSNF0 en mode "Annule et Remplace" (type 03)
 3. La table IT3331 stocke l'historique des DSN envoyées
 4. Le programme génère automatiquement le bon identifiant d'annulation
""")

    report.append("")
    report.append("=" * 100)
    report.append("SECTION 6 : TRANSACTIONS ET PROGRAMMES SAP CLÉS")
    report.append("=" * 100)

    report.append("""
Programme/Transaction | Description
──────────────────────┼─────────────────────────────────────────────────
RPLDSNF0              | Programme principal de génération de la DSN
RPUDSNF1              | Programme de préparation des versements DSN
/NY00BA_OH11          | Transaction EuHReka customizing paie (rubriques)
/NY00BA_PE01          | Transaction EuHReka événements personnel
/NY00BA_PE02          | Transaction EuHReka gestion personnel (infotypes)
/NY00BA_PE03_CUSTOMER | Transaction EuHReka paramétrage client
SM30                  | Maintenance des vues/tables de customizing
SE16 / SE16N          | Consultation directe des tables SAP
IT3331                | Infotype historique DSN envoyées
IT3332                | Infotype DSN complémentaire

TABLES EUHREKA SPÉCIFIQUES (les Y00BA_* et Z*)
───────────────────────────────────────────────
Y00BA_VIE_FIWTSA      | Assignation des rubriques EuHReka
Y00BA_VIE_T512WC      | Calcul des rubriques EuHReka
Y00BA_VIE_COMPAN      | Paramètres société EuHReka
Y00BA_VIE_ASSI3       | Assignation spécifique EuHReka
Y00BA_VIE_FISADF      | Fiscal / SAP DF EuHReka
Y00BA_VIE_STY16C      | Style 16 client EuHReka
Y00BA_TAB_STY02       | Table EuHReka type spécifique
Y00BA_TAB_FIWTSA      | Table assignation WT EuHReka
ZFRPY_VIE_SBD_2C      | Vue client FR spécifique
ZESPY_VIE_ROC_00      | Vue client ROC (Read Only Customizing)
Y00BA_VIE_UEFC1       | Vue EuHReka FC1
""")

    report.append("")
    report.append("=" * 100)
    report.append("SECTION 7 : GLOSSAIRE DSN / SAP")
    report.append("=" * 100)

    report.append("""
Terme                  | Signification
───────────────────────┼──────────────────────────────────────────────
DSN                    | Déclaration Sociale Nominative
OPS                    | Organisme de Protection Sociale
CTP                    | Code Type de Personnel (URSSAF)
MDC                    | Modèle De Charge (cotisations)
WT / Rubrique          | Wage Type / Rubrique de paie
SIRET / SIREN          | Identifiants établissement / entreprise
NIC                    | Numéro Interne de Classement
PAS                    | Prélèvement À la Source
IJSS                   | Indemnités Journalières Sécurité Sociale
AGIRC-ARRCO            | Retraite complémentaire
Fillon                 | Réduction générale de cotisations
SSC                    | Suppression Seuil de Cotisation
PPV                    | Prime Partage de la Valeur
IDCC                   | Identifiant Convention Collective
CCN                    | Convention Collective Nationale
GIP-MDS                | Groupement d'Intérêt Public - Modernisation DS
EuHReka                | Nom commercial de la solution SAP de NGA/Northgate
Annule-Remplace        | Type 03 : renvoi complet d'une DSN corrigée
Néant                  | Déclaration sans salarié
Fractionnement         | Découpage d'une DSN en plusieurs fractions
IT (Infotype)          | Structure SAP de données RH (IT0001 = org, etc.)
""")

    report.append("")
    report.append("=" * 100)
    report.append("CONCLUSION")
    report.append("=" * 100)

    report.append(f"""
Sur les 1887 fichiers Excel analysés couvrant 5 ans de tickets SAP (2019-2023) :

• 832 tickets (44%) sont liés à la DSN
• Le problème n°1 est le paramétrage des COTISATIONS (blocs 23/78/81)
  → La table V_T5FDSNCOTIS2 est utilisée dans 95 solutions
  → C'est LA table centrale à maîtriser

• Les 3 tables les plus critiques :
  1. V_T5FDSNCOTIS2 — Mapping cotisations DSN
  2. V_T5F99FX — Features DSN étendues
  3. V_T5F1M — MDC (Modèle De Charge)

• Les problèmes les plus récurrents :
  - Rétroactivité/rappels qui génèrent des doublons
  - Retraite AGIRC-ARRCO (fusion, taux)
  - Apprentis (régime spécifique)
  - Splits/transferts entre établissements
  - Nouvelles rubriques à déclarer (PPV, indemnité inflation...)

• Pour EuHReka spécifiquement, la transaction Y00BA_OH11 (/ny00ba_oh11)
  est l'outil central de customizing, et les tables Y00BA_VIE_* sont
  les équivalents EuHReka des tables standard SAP.

Ce rapport ne remplace pas l'expertise humaine, mais devrait permettre
de diagnostiquer plus rapidement les problèmes DSN en sachant quelles
tables vérifier en premier selon le type de problème.
""")

    # Sauvegarder le rapport
    report_text = '\n'.join(report)
    output_path = f'{OUTPUT_DIR}/RAPPORT_DSN_ANALYSE.txt'
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(report_text)
    print(f"Rapport sauvegardé: {output_path}")
    print(f"Taille: {len(report_text)} caractères")


if __name__ == '__main__':
    main()
