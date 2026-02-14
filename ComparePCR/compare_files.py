#!/usr/bin/env python3
"""
HRSP File Comparator - Version ULTRA SIMPLE
Compare 2 fichiers directement - c'est tout !
"""

import sys
from pathlib import Path
import time

# Vérifier les arguments
if len(sys.argv) < 3:
    print("""
╔════════════════════════════════════════════════════════════════╗
║          HRSP File Comparator - Version Simple                ║
╚════════════════════════════════════════════════════════════════╝

Usage:
  python compare_files.py PRE_Schema.txt POST_Schema.txt
  python compare_files.py PRE_Schema.txt POST_Schema.txt resultat.xlsx

C'est tout ! 🎯
    """)
    sys.exit(1)

pre_file = Path(sys.argv[1])
post_file = Path(sys.argv[2])
output_file = sys.argv[3] if len(sys.argv) > 3 else "comparison_result.xlsx"

# Vérifier que les fichiers existent
if not pre_file.exists():
    print(f"❌ Erreur: '{pre_file}' introuvable!")
    sys.exit(1)

if not post_file.exists():
    print(f"❌ Erreur: '{post_file}' introuvable!")
    sys.exit(1)

if not Path("Options.ini").exists():
    print("❌ Erreur: 'Options.ini' introuvable!")
    sys.exit(1)

# Importer les modules nécessaires
sys.path.insert(0, str(Path(__file__).parent))

try:
    from hrsp_compare_final import HRSPComparer, ExcelGenerator
except ImportError:
    print("❌ Erreur: Fichier 'hrsp_compare_final.py' introuvable!")
    print("   Téléchargez aussi ce fichier depuis les outputs.")
    sys.exit(1)

print(f"""
╔════════════════════════════════════════════════════════════════╗
║          HRSP File Comparator - Comparaison en cours          ║
╚════════════════════════════════════════════════════════════════╝

📄 Fichier PRE  : {pre_file.name}
📄 Fichier POST : {post_file.name}
📊 Output       : {output_file}
""")

# Créer le comparateur
comparer = HRSPComparer("Options.ini")

# Extraire infos
table_name = comparer.extract_table_name(pre_file.name)
is_pcr = comparer.is_pcr_file(pre_file.name)
keycut = comparer.get_keycut(table_name)

file_type = "PCR Schema" if is_pcr else "Table"
print(f"  📄 {file_type}: {table_name} (keycut={keycut})")

# Lire les fichiers
with open(pre_file, 'r', encoding='utf-8', errors='ignore') as f:
    pre_lines = [line.rstrip() for line in f.readlines()[1:] if line.strip()]

with open(post_file, 'r', encoding='utf-8', errors='ignore') as f:
    post_lines = [line.rstrip() for line in f.readlines()[1:] if line.strip()]

print(f"    📊 Read {len(pre_lines)} PRE lines, {len(post_lines)} POST lines")

# Dédupliquer
pre_clean = comparer.deduplicate(pre_lines)
post_clean = comparer.deduplicate(post_lines)

# Grouper par clé
pre_groups = {}
for line in pre_clean:
    key = comparer.extract_key(line, keycut)
    if key not in pre_groups:
        pre_groups[key] = []
    pre_groups[key].append(line)

post_groups = {}
for line in post_clean:
    key = comparer.extract_key(line, keycut)
    if key not in post_groups:
        post_groups[key] = []
    post_groups[key].append(line)

print(f"    📋 Grouped into {len(pre_groups)} PRE groups, {len(post_groups)} POST groups")

# Comparer les groupes
all_differences = []
all_keys = sorted(set(list(pre_groups.keys()) + list(post_groups.keys())))

total_iterations = 0
start_time = time.time()

for key in all_keys:
    pre_group = pre_groups.get(key, [])
    post_group = post_groups.get(key, [])
    
    # Éliminer les lignes identiques AVANT matching
    pre_normalized = [' '.join(line.split()) for line in pre_group]
    post_normalized = [' '.join(line.split()) for line in post_group]
    
    pre_to_match = []
    post_to_match = []
    
    for i, pre_line in enumerate(pre_group):
        if pre_normalized[i] not in post_normalized:
            pre_to_match.append(pre_line)
    
    for j, post_line in enumerate(post_group):
        if post_normalized[j] not in pre_normalized:
            post_to_match.append(post_line)
    
    iterations = len(pre_to_match) * len(post_to_match)
    total_iterations += iterations
    
    # Matcher les lignes
    matches = comparer.match_groups(pre_to_match, post_to_match, keycut)
    all_differences.extend(matches)

elapsed = time.time() - start_time

print(f"    💡 Total iterations: {total_iterations:,}")
print(f"    ✅ Found {len(all_differences)} differences")
print(f"    ⏱️  Time: {elapsed:.2f}s")

# Grouper par règle pour PCR
if is_pcr:
    grouped_by_rule = {}
    for pre_line, post_line in all_differences:
        line_to_use = pre_line if pre_line else post_line
        rule_name = comparer.extract_rule_name(line_to_use)
        
        if rule_name not in grouped_by_rule:
            grouped_by_rule[rule_name] = []
        grouped_by_rule[rule_name].append((pre_line, post_line))
    
    print(f"    📋 Grouped into {len(grouped_by_rule)} rules")
    differences_dict = grouped_by_rule
else:
    differences_dict = {"": all_differences}

total_diffs = len(all_differences)

if total_diffs == 0:
    print(f"\n✅ Aucune différence trouvée!")
    sys.exit(0)

# Générer Excel
print(f"\n📝 Génération du fichier Excel...")
excel_gen = ExcelGenerator(output_file)
results = [(table_name, differences_dict, is_pcr)]
excel_gen.save(results)

print(f"""
╔════════════════════════════════════════════════════════════════╗
║                    ✅ Comparaison terminée !                   ║
╚════════════════════════════════════════════════════════════════╝

📊 Résultat      : {output_file}
🔍 Différences   : {total_diffs} lignes
⏱️  Temps        : {elapsed:.2f}s

Ouvrez le fichier Excel pour voir les détails ! 🎉
""")
