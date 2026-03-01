"""
Fusion des deux sources de tickets DSN et génération du rapport unifié
v1.0
"""
APP_VERSION = "1.0"

import json
import re
from collections import defaultdict
from datetime import datetime

OUTPUT_DIR = r"D:\Program\ClaudeCode\SAP_DSN"


def load_tickets(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def main():
    # Charger les deux sources
    tickets_julio = load_tickets(f'{OUTPUT_DIR}/dsn_tickets_raw.json')
    tickets_clients = load_tickets(f'{OUTPUT_DIR}/dsn_tickets_clients_raw.json')

    # Fusionner en ajoutant la source
    for t in tickets_julio:
        t['source'] = 'Julio (par année)'
    for t in tickets_clients:
        t['source'] = 'SAP Ticket (par client)'

    all_tickets = tickets_julio + tickets_clients

    # Dédupliquer par nom de fichier (certains tickets peuvent apparaître dans les deux)
    seen = set()
    unique_tickets = []
    dupes = 0
    for t in all_tickets:
        fname = t['filename']
        if fname not in seen:
            seen.add(fname)
            unique_tickets.append(t)
        else:
            dupes += 1

    print(f"Source 1 (Julio/année) : {len(tickets_julio)} tickets DSN")
    print(f"Source 2 (SAP/client)  : {len(tickets_clients)} tickets DSN")
    print(f"Doublons éliminés      : {dupes}")
    print(f"Total unique           : {len(unique_tickets)}")

    # Sauvegarder le JSON fusionné
    with open(f'{OUTPUT_DIR}/dsn_tickets_ALL.json', 'w', encoding='utf-8') as f:
        json.dump(unique_tickets, f, ensure_ascii=False, indent=2, default=str)

    # === ANALYSE COMPLÈTE ===
    table_pattern = re.compile(
        r'\b(V_T5F\w+|T5F\w+|V_T596\w*|T596\w*|V_T511\w*|T511\w*|'
        r'V_T512\w*|T512\w*|V_T530\w*|T530\w*|V_T554\w*|T554\w*|'
        r'V_T52\w+|Y00BA_\w+|ZFRPY_\w+|ZESPY_\w+|'
        r'RPLDSNF\d|RPUDSNF\d)\b', re.IGNORECASE)

    bloc_counter = defaultdict(int)
    table_counter = defaultdict(int)
    code_counter = defaultdict(int)
    problems_by_bloc = defaultdict(list)
    tickets_by_year = defaultdict(int)
    tickets_by_client = defaultdict(int)
    problem_keywords = defaultdict(int)
    tables_per_bloc = defaultdict(lambda: defaultdict(int))

    problem_kw_list = [
        'taux at', 'taux pas', 'taux dupliqu', 'cotisation', 'quotit',
        'erreur', 'ko', 'anomali', 'manquant', 'doublon', 'split',
        'transfer', 'mutation', 'retro', 'rappel', 'r.gularisa',
        'apprenti', 'temps partiel', 'cdd', 'sortie', 'entr.e',
        'handicap', 'prevoyance', 'retraite', 'fillon', 'urssaf',
        'fractionn', 'annule', 'remplace', 'n.ant',
        'net social', 'net imposable', 'brut', 'plafond',
        'csg', 'crds', 'ijss', 'arr.t', 'maladie', 'maternit',
        'ccn', 'idcc', 'convention', 'bulletin',
        'cumul', 'processing class', 'classe de cumul',
        'stagiaire', 'ppv', 'prime partage',
    ]

    for t in unique_tickets:
        # Année
        for year in ['2019', '2020', '2021', '2022', '2023', '2024']:
            if year in t.get('file', ''):
                tickets_by_year[year] += 1
                break

        # Client
        client = t.get('client', '')
        if client:
            tickets_by_client[client] += 1

        # Blocs
        for bloc in t.get('blocs_mentioned', []):
            bloc_counter[bloc] += 1
            if t.get('problem') or t.get('solution'):
                problems_by_bloc[bloc].append({
                    'file': t['filename'],
                    'client': t.get('client', ''),
                    'problem': (t.get('problem', '') or '')[:500],
                    'solution': (t.get('solution', '') or '')[:500],
                })

        # Tables
        for table in t.get('tables_mentioned', []):
            table_counter[table] += 1

        # Codes DSN
        for code in t.get('dsn_codes', []):
            code_counter[code] += 1

        # Tables dans la solution
        sol = t.get('solution', '') or ''
        found_tables = table_pattern.findall(sol)
        blocs = t.get('blocs_mentioned', [])
        for tbl in found_tables:
            tbl_upper = tbl.upper().replace('/N', '')
            for bloc in blocs:
                tables_per_bloc[bloc][tbl_upper] += 1

        # Mots-clés problème
        combined_lower = (t.get('problem', '') + ' ' + t.get('solution', '') + ' ' + t.get('filename', '')).lower()
        for kw in problem_kw_list:
            if re.search(kw, combined_lower):
                problem_keywords[kw] += 1

    # === GÉNÉRATION DU RAPPORT UNIFIÉ ===
    r = []
    r.append("=" * 100)
    r.append("RAPPORT D'ANALYSE DSN UNIFIÉ - TICKETS SAP EuHReka (2019-2023)")
    r.append(f"Généré le {datetime.now().strftime('%d/%m/%Y à %H:%M')}")
    r.append("Sources : Tickets Julio (par année) + SAP Tickets (par client)")
    r.append("=" * 100)

    r.append(f"""
STATISTIQUES GÉNÉRALES
{'='*50}
- Source 1 (Julio, par année)  : 1887 fichiers scannés → 832 tickets DSN
- Source 2 (SAP, par client)   : 1271 fichiers scannés → 920 tickets DSN
- Total fichiers scannés       : 3158
- Doublons éliminés            : {dupes}
- TOTAL TICKETS DSN UNIQUES    : {len(unique_tickets)}

RÉPARTITION PAR ANNÉE (quand identifiable)
""")
    for year in sorted(tickets_by_year.keys()):
        r.append(f"  {year} : {tickets_by_year[year]} tickets DSN")

    r.append(f"""
RÉPARTITION PAR CLIENT (source 2)
""")
    for client, count in sorted(tickets_by_client.items(), key=lambda x: x[1], reverse=True):
        if client:
            r.append(f"  {client:20s}: {count} tickets DSN")

    r.append("")
    r.append("=" * 100)
    r.append("SECTION 1 : LES PROBLÈMES DSN LES PLUS FRÉQUENTS")
    r.append("=" * 100)

    r.append("""
TOP 15 DES BLOCS DSN PROBLÉMATIQUES
────────────────────────────────────""")
    for i, (bloc, count) in enumerate(sorted(bloc_counter.items(), key=lambda x: x[1], reverse=True)[:15], 1):
        r.append(f" {i:2d}. Bloc {bloc:3s}: {count} tickets")

    r.append("""
TYPES DE PROBLÈMES LES PLUS RÉCURRENTS
───────────────────────────────────────""")
    for i, (kw, count) in enumerate(sorted(problem_keywords.items(), key=lambda x: x[1], reverse=True)[:20], 1):
        r.append(f" {i:2d}. {kw:30s}: {count} occurrences")

    r.append("")
    r.append("=" * 100)
    r.append("SECTION 2 : TABLES SAP LES PLUS UTILISÉES POUR RÉSOUDRE LES PROBLÈMES DSN")
    r.append("=" * 100)

    # Tables dans les solutions uniquement
    solution_tables = defaultdict(int)
    for t in unique_tickets:
        sol = t.get('solution', '') or ''
        found = table_pattern.findall(sol)
        for tbl in found:
            tbl_upper = tbl.upper().replace('/N', '')
            solution_tables[tbl_upper] += 1

    table_descriptions = {
        'V_T5FDSNCOTIS2': 'Table CENTRALE : mapping cotisations DSN\n'
                          '                               |             | → Lie les rubriques de paie (WT) aux codes\n'
                          '                               |             |   cotisation DSN (blocs 23, 78, 81)',
        'Y00BA_VIE_FIWTSA': 'Vue EuHReka : assignation des rubriques (WT)',
        'V_T5F99FX': 'Feature DSN mapping étendu (blocs 51, 52, 81)',
        'V_T5F1M': 'MDC (Modèle De Charge) URSSAF\n'
                   '                               |             | → Clé pour blocs 23, 78, 81',
        'V_T5F1C1': 'Table de customizing cotisations 1',
        'V_T596M': 'Assignation destinataires DSN (SIRET → OPS)',
        'V_T511K': 'Rubriques de paie (Wage Types) - caractéristiques',
        'Y00BA_PE01': 'Vue EuHReka Personnel Events',
        'V_T596NV': 'Groupement SIRET pour DSN (blocs 15, 20, 60, 70)',
        'T554S': 'Règles d\'absence / counting rules (bloc 60)',
        'Y00BA_OH11': 'Transaction EuHReka customizing paie central',
        'Y00BA_PE03_CUSTOMER': 'Vue EuHReka paramétrage client spécifique',
        'V_T5FDSNCODCO': 'Codes composants DSN (blocs 22, 23, 78, 82)',
        'Y00BA_VIE_T512WC': 'Vue EuHReka : calcul des rubriques',
        'Y00BA_VIE_COMPAN': 'Vue EuHReka : paramètres société',
        'V_T512T': 'Textes des rubriques de paie',
        'Y00BA_VIE_ASSI3': 'Vue EuHReka : assignation spécifique',
        'V_T511P': 'Taux et constantes des rubriques (similaire V_T511K)',
        'Y00BA_VIE_FISADF': 'Vue EuHReka : fiscal / SAP DF',
        'V_T5F1C': 'Paramétrage cotisations',
        'V_T554C': 'Règles de comptage absences',
        'V_T52EL': 'Éléments de paie',
        'V_T596C': 'Codes caisses',
        'V_T5F1C3': 'Paramétrage cotisations 3',
        'V_T5F1H': 'Paramétrage établissement H',
        'V_T5FDSNMTOMC': 'Mapping montant DSN',
        'V_T5F99FMAP': 'Feature mapping DSN',
        'V_T5F1BAP_DSN': 'BAP DSN (Business Application Platform)',
        'V_T5FDSNPAVAL': 'Paramétrage PAS validation',
        'V_T5F1G': 'Paramétrage groupement cotisations',
    }

    r.append("""
TOP 25 DES TABLES/VUES SAP DANS LES SOLUTIONS DES TECHNICIENS
──────────────────────────────────────────────────────────────

 Table/Vue                    | Occurrences | Description
─────────────────────────────────────────────────────────────────────────────────""")
    for tbl, count in sorted(solution_tables.items(), key=lambda x: x[1], reverse=True)[:25]:
        desc = table_descriptions.get(tbl, '')
        r.append(f" {tbl:30s}| {count:4d}        | {desc}")
        r.append("─────────────────────────────────────────────────────────────────────────────────")

    r.append("")
    r.append("=" * 100)
    r.append("SECTION 3 : GUIDE DE RÉSOLUTION PAR TYPE DE PROBLÈME")
    r.append("=" * 100)

    # Compter les tickets par catégorie de problème pour le rapport
    cat_counts = {}
    cat_counts['cotis_78_23_81'] = bloc_counter.get('78', 0) + bloc_counter.get('23', 0) + bloc_counter.get('81', 0)
    cat_counts['remun_50_51_52'] = bloc_counter.get('50', 0) + bloc_counter.get('51', 0) + bloc_counter.get('52', 0)
    cat_counts['versement_20'] = bloc_counter.get('20', 0)
    cat_counts['contrat_40'] = bloc_counter.get('40', 0)
    cat_counts['absence_60'] = bloc_counter.get('60', 0)
    cat_counts['bloc_22'] = bloc_counter.get('22', 0)

    r.append(f"""
═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 1 : COTISATIONS DSN INCORRECTES (Blocs 23/78/81)
C'est LE problème n°1 — {cat_counts['cotis_78_23_81']} tickets combinés
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
{cat_counts['remun_50_51_52']} tickets
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
  a) Vérifier que la WT a la bonne processing class (T512W / V_512W_O)
  b) Vérifier le mapping dans V_T5F99FX
  c) Si prime/indemnité : vérifier V_T5FPR
  d) Pour EuHReka : passer par Y00BA_OH11

═══════════════════════════════════════════════════════════════════════════════
PROBLÈME 3 : VERSEMENTS OPS INCORRECTS (Bloc 20)
{cat_counts['versement_20']} tickets
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
{cat_counts['absence_60']} tickets
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
{cat_counts['bloc_22']} tickets (souvent lié à des indemnités nouvelles)
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

    r.append("")
    r.append("=" * 100)
    r.append("SECTION 4 : TABLES SAP ESSENTIELLES PAR BLOC DSN")
    r.append("=" * 100)

    r.append("""
Ce tableau montre les tables les plus utilisées dans les solutions par bloc :

Bloc DSN     | Tables principales (par fréquence)
─────────────┼──────────────────────────────────────────────────────────────""")
    for bloc in sorted(tables_per_bloc.keys(), key=lambda x: int(x) if x.isdigit() else 999):
        tables = sorted(tables_per_bloc[bloc].items(), key=lambda x: x[1], reverse=True)[:8]
        if tables:
            table_str = ', '.join(f'{t}({c})' for t, c in tables)
            r.append(f"Bloc {bloc:3s}     | {table_str}")

    r.append("")
    r.append("=" * 100)
    r.append("SECTION 5 : PROCÉDURES DE RÉSOLUTION RAPIDE")
    r.append("=" * 100)

    r.append("""
CHECKLIST UNIVERSELLE DE DIAGNOSTIC DSN
────────────────────────────────────────

Pour TOUT problème DSN, suivre cette checklist :

□ 1. Identifier le bloc et le code DSN en erreur
     → Lire le rapport d'anomalie DSN (Bilan DSN ou retour Net-Entreprises)

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

□ 7. Vérifier les processing classes
     → T512W / V_512W_O pour les classes de traitement des WT

□ 8. Relancer la DSN
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

    r.append("")
    r.append("=" * 100)
    r.append("SECTION 6 : TRANSACTIONS ET PROGRAMMES SAP CLÉS")
    r.append("=" * 100)

    r.append("""
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

    r.append("")
    r.append("=" * 100)
    r.append("SECTION 7 : GLOSSAIRE DSN / SAP")
    r.append("=" * 100)

    r.append("""
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

    r.append("")
    r.append("=" * 100)
    r.append("CONCLUSION")
    r.append("=" * 100)

    r.append(f"""
Sur les 3158 fichiers Excel analysés couvrant 2 sources de tickets SAP (2019-2023) :

• {len(unique_tickets)} tickets DSN uniques identifiés (après dédoublonnage)
  - Source Julio (par année) : 832 tickets
  - Source SAP (par client)  : 920 tickets

• Clients les plus impactés par les problèmes DSN :""")
    for client, count in sorted(tickets_by_client.items(), key=lambda x: x[1], reverse=True)[:5]:
        if client:
            r.append(f"  - {client}: {count} tickets")

    r.append(f"""
• Le problème n°1 reste le paramétrage des COTISATIONS (blocs 23/78/81)
  → La table V_T5FDSNCOTIS2 est LA table centrale à maîtriser

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

• Processing classes : elles se trouvent dans T512W / V_512W_O
  (section "Class. traitement / valeur"), PAS dans V_T511P.

Ce rapport ne remplace pas l'expertise humaine, mais devrait permettre
de diagnostiquer plus rapidement les problèmes DSN en sachant quelles
tables vérifier en premier selon le type de problème.
""")

    # Sauvegarder le rapport
    report_text = '\n'.join(r)
    output_path = f'{OUTPUT_DIR}/RAPPORT_DSN_ANALYSE.txt'
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(report_text)
    print(f"\nRapport unifié sauvegardé: {output_path}")
    print(f"Taille: {len(report_text)} caractères")


if __name__ == '__main__':
    main()
