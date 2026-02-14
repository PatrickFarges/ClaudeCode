#!/usr/bin/env python3
"""
HRSP File Comparator - Final POC
Supports both regular tables and PCR schemas (Payroll schemas)
"""

import sys
import configparser
from pathlib import Path
from typing import List, Tuple, Dict, Set
import xlsxwriter
import time


class HRSPComparer:
    """Main comparison engine with intelligent matching"""
    
    def __init__(self, config_file: str = "Options.ini"):
        self.config = configparser.ConfigParser(strict=False)
        self.config.read(config_file)
        self.suffixes_to_remove = self._load_suffixes()
        self.keycut_map = self._load_keycuts()
        
    def _load_suffixes(self) -> List[str]:
        """Load file name suffixes to remove from config"""
        suffixes = []
        if 'DeleteFileNamePart' in self.config:
            section = self.config['DeleteFileNamePart']
            num = int(section.get('Num', 0))
            for i in range(1, num + 1):
                suffix = section.get(str(i), '')
                if suffix:
                    suffixes.append(suffix)
        print(f"✓ Loaded {len(suffixes)} suffixes to remove")
        return suffixes
    
    def _load_keycuts(self) -> Dict[str, int]:
        """Load keycut values for each table"""
        keycuts = {}
        if 'TableCutNumber' in self.config:
            for key, value in self.config['TableCutNumber'].items():
                try:
                    keycuts[key.upper()] = int(value)
                except ValueError:
                    pass
        print(f"✓ Loaded {len(keycuts)} keycut definitions")
        return keycuts
    
    def extract_table_name(self, filename: str) -> str:
        """Extract real table name by removing known suffixes"""
        name = Path(filename).stem
        for suffix in self.suffixes_to_remove:
            if suffix in name:
                name = name.replace(suffix, '')
        return name
    
    def is_pcr_file(self, filename: str) -> bool:
        """Check if file is a PCR (Payroll Schema) file"""
        name_lower = filename.lower()
        return 'schema' in name_lower or 'pcr' in name_lower
    
    def get_keycut(self, table_name: str) -> int:
        """Get keycut value for a table (default 9 if not found)"""
        return self.keycut_map.get(table_name.upper(), 9)
    
    def remove_whitespace(self, line: str) -> str:
        """Remove all spaces and tabs from line"""
        return line.replace(' ', '').replace('\t', '')
    
    def extract_key(self, line: str, keycut: int) -> str:
        """Extract key from line (first N characters without spaces/tabs)"""
        clean = self.remove_whitespace(line)
        return clean[:keycut]
    
    def deduplicate(self, lines: List[str]) -> List[str]:
        """
        Remove duplicate lines while preserving order
        CRITICAL for PCR files which often have 2-4 identical copies of the same rule
        """
        seen = set()
        result = []
        duplicates_removed = 0
        
        for line in lines:
            if line not in seen:
                seen.add(line)
                result.append(line)
            else:
                duplicates_removed += 1
        
        if duplicates_removed > 0:
            print(f"    Removed {duplicates_removed} duplicate lines")
        
        return result
    
    def calculate_similarity(self, line1: str, line2: str, keycut: int) -> int:
        """
        Calculate similarity score between two lines
        Based on Pascal GetScore algorithm
        
        Higher score = more similar
        """
        # Normalize spaces (like DelSpace1 in Pascal)
        source = ' '.join(line1.split())
        to_compare = ' '.join(line2.split())
        
        # Empty lines check
        if not source or not to_compare:
            return -200
        
        # Length check
        if len(source) < keycut or len(to_compare) < keycut:
            return -200
        
        # Score starts with length difference penalty
        a_min = min(len(source), len(to_compare))
        a_max = max(len(source), len(to_compare))
        result = a_min - a_max  # Negative penalty for length difference
        
        # PHASE 1: Character-by-character comparison in KeyCut zone (VERY IMPORTANT!)
        # First N characters are the key and weigh heavily
        for i in range(keycut):
            if source[i] == to_compare[i]:
                # Bonus: quadratic weight (1², 2², 3², ... 9²)
                result += (i + 1) * (i + 1)
            else:
                # BIG penalty: earlier chars have bigger penalty
                penalty = 50 + (keycut - i) * keycut
                result -= penalty
        
        # PHASE 2: Word-by-word comparison AFTER KeyCut zone
        # Extract text after keycut
        str_s = source[keycut:] if len(source) > keycut else ''
        str_t = to_compare[keycut:] if len(to_compare) > keycut else ''
        
        if not str_s or not str_t:
            return result
        
        # Split into words
        words_s = str_s.split()
        words_t = str_t.split()
        
        # Compare words at same position
        for i in range(len(words_s)):
            temp_s = words_s[i]
            temp_t = words_t[i] if i < len(words_t) else ''
            
            if not temp_s or not temp_t:
                break
            
            if temp_s == temp_t:
                # Same word at same position: bonus = position + word length
                result += (i + 1) + len(temp_s)
            elif temp_s in str_t:
                # Word exists but at different position: bonus = word length
                result += len(temp_s)
        
        return result
    
    def match_groups(self, pre_group: List[str], post_group: List[str], 
                     keycut: int) -> List[Tuple[str, str]]:
        """
        Match lines in PRE and POST groups using similarity scoring
        GLOBAL GREEDY matching (like Pascal FillScheme):
        - Calculate ALL scores ONCE (like FillArrayScoring)
        - Sort by best score
        - Take best scores that don't conflict (greedy)
        
        Returns list of (pre_line, post_line) tuples
        """
        if not pre_group and not post_group:
            return []
        
        if not pre_group:
            return [('', post) for post in post_group]
        
        if not post_group:
            return [(pre, '') for pre in pre_group]
        
        # Calculate ALL scores ONCE (like Pascal FillArrayScoring)
        scores = []
        for i, pre_line in enumerate(pre_group):
            for j, post_line in enumerate(post_group):
                score = self.calculate_similarity(pre_line, post_line, keycut)
                scores.append((score, i, j))
        
        # Sort by best score first (like Pascal MeilleurScore)
        scores.sort(reverse=True, key=lambda x: x[0])
        
        # Greedy matching: take best scores that don't conflict
        used_pre = set()
        used_post = set()
        matches_with_pos = []  # Store (post_position, pre_line, post_line)
        
        for score, i, j in scores:
            # Only match if both are still available AND score is reasonable
            if i not in used_pre and j not in used_post and score > -100:
                matches_with_pos.append((j, pre_group[i], post_group[j]))  # j = POST position
                used_pre.add(i)
                used_post.add(j)
        
        # Sort by POST position (like Pascal TempMinor[CibleLine])
        matches_with_pos.sort(key=lambda x: x[0])
        matches = [(pre, post) for _, pre, post in matches_with_pos]
        
        # Add unmatched PRE lines (deleted) - at the end
        for i, pre_line in enumerate(pre_group):
            if i not in used_pre:
                matches.append((pre_line, ''))
        
        # Add unmatched POST lines (added) - at their position
        for j, post_line in enumerate(post_group):
            if j not in used_post:
                # Insert at correct position
                inserted = False
                for idx, (post_pos, _, _) in enumerate(matches_with_pos):
                    if j < post_pos:
                        matches.insert(idx, ('', post_line))
                        inserted = True
                        break
                if not inserted:
                    matches.append(('', post_line))
        
        return matches
    
    def extract_rule_name(self, line: str) -> str:
        """
        Extract rule name from PCR line (first 4 characters after removing spaces/tabs)
        Examples: ")6RS", "FIN0", "H0WP", etc.
        """
        clean = self.remove_whitespace(line)
        return clean[:4] if len(clean) >= 4 else clean
    
    def compare_files(self, pre_file: Path, post_file: Path) -> Tuple[str, Dict[str, List[Tuple[str, str]]], bool]:
        """
        Compare two files with intelligent matching
        Returns (table_name, differences, is_pcr)
        """
        table_name = self.extract_table_name(pre_file.name)
        is_pcr = self.is_pcr_file(pre_file.name)
        keycut = self.get_keycut(table_name)
        
        file_type = "PCR Schema" if is_pcr else "Table"
        print(f"\n  📄 {file_type}: {table_name} (keycut={keycut})")
        
        # Read files (skip header line)
        with open(pre_file, 'r', encoding='utf-8', errors='ignore') as f:
            pre_lines = [line.rstrip() for line in f.readlines()[1:] if line.strip()]
        
        with open(post_file, 'r', encoding='utf-8', errors='ignore') as f:
            post_lines = [line.rstrip() for line in f.readlines()[1:] if line.strip()]
        
        print(f"    Read {len(pre_lines)} PRE lines, {len(post_lines)} POST lines")
        
        # STEP 1: Deduplicate (CRITICAL for PCR files!)
        pre_clean = self.deduplicate(pre_lines)
        post_clean = self.deduplicate(post_lines)
        
        # STEP 2: Group by key
        pre_groups = {}
        for line in pre_clean:
            key = self.extract_key(line, keycut)
            if key not in pre_groups:
                pre_groups[key] = []
            pre_groups[key].append(line)
        
        post_groups = {}
        for line in post_clean:
            key = self.extract_key(line, keycut)
            if key not in post_groups:
                post_groups[key] = []
            post_groups[key].append(line)
        
        print(f"    Grouped into {len(pre_groups)} PRE groups, {len(post_groups)} POST groups")
        
        # STEP 3: Match and compare groups
        all_differences = []
        all_keys = sorted(set(list(pre_groups.keys()) + list(post_groups.keys())))
        
        total_iterations = 0
        
        for key in all_keys:
            pre_group = pre_groups.get(key, [])
            post_group = post_groups.get(key, [])
            
            # CRITICAL FIX: Remove identical lines BEFORE matching (like Pascal)
            # Normalize for comparison
            pre_normalized = [' '.join(line.split()) for line in pre_group]
            post_normalized = [' '.join(line.split()) for line in post_group]
            
            # Find and remove identical lines
            pre_to_match = []
            post_to_match = []
            
            for i, pre_line in enumerate(pre_group):
                # Check if this exact line exists in POST
                if pre_normalized[i] not in post_normalized:
                    pre_to_match.append(pre_line)
            
            for j, post_line in enumerate(post_group):
                # Check if this exact line exists in PRE
                if post_normalized[j] not in pre_normalized:
                    post_to_match.append(post_line)
            
            # Count iterations for performance tracking
            iterations = len(pre_to_match) * len(post_to_match)
            total_iterations += iterations
            
            # Match lines within group (only non-identical lines)
            matches = self.match_groups(pre_to_match, post_to_match, keycut)
            
            # Add all matches to differences (they're already filtered)
            all_differences.extend(matches)
        
        print(f"    💡 Total iterations: {total_iterations:,}")
        print(f"    ✅ Found {len(all_differences)} differences")
        
        # STEP 5: For PCR files, group by rule name (4 chars)
        if is_pcr:
            grouped_by_rule = {}
            for pre_line, post_line in all_differences:
                # Extract rule name from the line that exists
                line_to_use = pre_line if pre_line else post_line
                rule_name = self.extract_rule_name(line_to_use)
                
                if rule_name not in grouped_by_rule:
                    grouped_by_rule[rule_name] = []
                grouped_by_rule[rule_name].append((pre_line, post_line))
            
            print(f"    📋 Grouped into {len(grouped_by_rule)} rules")
            return table_name, grouped_by_rule, is_pcr
        else:
            # For regular tables, return as single group
            return table_name, {"": all_differences}, is_pcr
    
    def compare_directories(self, pre_dir: Path, post_dir: Path) -> List[Tuple[str, Dict[str, List[Tuple[str, str]]], bool]]:
        """Compare all matching files in two directories"""
        results = []
        
        pre_files = {self.extract_table_name(f.name): f 
                     for f in pre_dir.glob('*.txt')}
        post_files = {self.extract_table_name(f.name): f 
                      for f in post_dir.glob('*.txt')}
        
        common_tables = set(pre_files.keys()) & set(post_files.keys())
        
        print(f"\n📊 Found {len(pre_files)} PRE files, {len(post_files)} POST files")
        print(f"📊 Common files to compare: {len(common_tables)}")
        
        total_start = time.time()
        
        for table_name in sorted(common_tables):
            pre_file = pre_files[table_name]
            post_file = post_files[table_name]
            
            start_time = time.time()
            table_name, grouped_differences, is_pcr = self.compare_files(pre_file, post_file)
            elapsed = time.time() - start_time
            
            # Count total differences
            total_diffs = sum(len(diffs) for diffs in grouped_differences.values())
            
            if total_diffs > 0:
                results.append((table_name, grouped_differences, is_pcr))
                print(f"    ⏱️  Time: {elapsed:.3f}s")
            else:
                print(f"    ⏭️  Identical (skipped)")
        
        total_elapsed = time.time() - total_start
        print(f"\n⏱️  Total comparison time: {total_elapsed:.2f}s")
        
        return results


class ExcelGenerator:
    """Generate Excel with Rich Text using xlsxwriter"""
    
    def __init__(self, filename: str):
        self.workbook = xlsxwriter.Workbook(filename)
        self.worksheet = self.workbook.add_worksheet('Comparisons')
        self.current_row = 0
        
        # Set column widths
        self.worksheet.set_column(0, 0, 15)
        self.worksheet.set_column(1, 1, 80)
        self.worksheet.set_column(2, 2, 80)
        self.worksheet.set_column(3, 3, 30)
        
        # Define formats
        self.header_fmt = self.workbook.add_format({
            'bg_color': '#68228B',
            'font_color': 'white',
            'bold': True,
        })
        
        self.table_fmt = self.workbook.add_format({
            'bg_color': '#FF8C00',
            'font_color': '#FF0000',
            'bold': True,
        })
        
        # Format for PCR rule headers (orange background, larger font)
        self.rule_fmt = self.workbook.add_format({
            'bg_color': '#FF8C00',  # Orange
            'font_color': '#000000',  # Black text
            'bold': True,
            'font_size': 12,  # Larger font
        })
        
        self.red_fmt = self.workbook.add_format({'color': '#FF0000'})
        self.black_fmt = self.workbook.add_format({'color': '#000000'})
    
    def write_header(self):
        """Write header row"""
        headers = ['Table', 'Value Before HRSP', 'Value After HRSP', 'Transport and comments']
        for col, header in enumerate(headers):
            self.worksheet.write(self.current_row, col, header, self.header_fmt)
        self.current_row += 1
    
    def write_table(self, table_name: str, grouped_differences: Dict[str, List[Tuple[str, str]]], is_pcr: bool):
        """Write a table with all its differences, grouped by rule for PCR"""
        # Table name row
        for col in range(4):
            value = table_name if col == 0 else ""
            self.worksheet.write(self.current_row, col, value, self.table_fmt)
        self.current_row += 1
        
        # For PCR: write rule header before each group
        # For tables: write all differences without headers
        if is_pcr:
            for rule_name in sorted(grouped_differences.keys()):
                differences = grouped_differences[rule_name]
                
                # Write rule header (orange row with rule name)
                for col in range(4):
                    value = rule_name if col == 0 else ""
                    self.worksheet.write(self.current_row, col, value, self.rule_fmt)
                self.current_row += 1
                
                # Write differences for this rule
                self._write_differences(differences)
        else:
            # Regular table: single group with empty key
            differences = grouped_differences.get("", [])
            self._write_differences(differences)
    
    def _write_differences(self, differences: List[Tuple[str, str]]):
        """Write difference lines (helper method)"""
        for pre_line, post_line in differences:
            # Column A (empty)
            self.worksheet.write(self.current_row, 0, "")
            
            # Column B (PRE)
            if pre_line and post_line:
                # Both exist and different - use rich text (BLACK + RED for differences)
                rich_pre = self.create_rich_text(pre_line, post_line)
                if rich_pre and len(rich_pre) > 2:  # xlsxwriter needs 3+ elements
                    self.worksheet.write_rich_string(self.current_row, 1, *rich_pre)
                else:
                    # Fallback for single-word lines: write in black
                    self.worksheet.write(self.current_row, 1, pre_line, self.black_fmt)
            elif pre_line:
                # Only PRE (deleted) - BLACK (not red!)
                self.worksheet.write(self.current_row, 1, pre_line, self.black_fmt)
            else:
                # Empty cell
                self.worksheet.write(self.current_row, 1, "")
            
            # Column C (POST)
            if post_line and pre_line:
                # Both exist and different - use rich text (BLACK + RED for differences)
                rich_post = self.create_rich_text(post_line, pre_line)
                if rich_post and len(rich_post) > 2:  # xlsxwriter needs 3+ elements
                    self.worksheet.write_rich_string(self.current_row, 2, *rich_post)
                else:
                    # Fallback for single-word lines: write in black
                    self.worksheet.write(self.current_row, 2, post_line, self.black_fmt)
            elif post_line:
                # Only POST (added) - BLACK (not red!)
                self.worksheet.write(self.current_row, 2, post_line, self.black_fmt)
            else:
                # Empty cell
                self.worksheet.write(self.current_row, 2, "")
            
            # Column D (comments)
            self.worksheet.write(self.current_row, 3, " ")
            
            self.current_row += 1
    
    def create_rich_text(self, line: str, other_line: str):
        """
        Create rich text array for xlsxwriter
        Format: [format1, text1, format2, text2, ...]
        BLACK for identical parts, RED for different parts
        
        CRITICAL: Loop only on words that EXIST in the current line
        """
        # Split by whitespace to get words
        words = line.split()
        other_words = other_line.split()
        
        result = []
        
        # Compare word by word - ONLY for words in current line
        for i, word in enumerate(words):
            # Get corresponding word from other line (empty if doesn't exist)
            other_word = other_words[i] if i < len(other_words) else ''
            
            # Determine if this word is different
            is_different = (word != other_word)
            
            # Choose format
            fmt = self.red_fmt if is_different else self.black_fmt
            
            # Add space separator if not first word
            if i > 0:
                result.append(fmt)
                result.append(' ')
            
            # Add format + word
            result.append(fmt)
            result.append(word)
        
        # xlsxwriter needs at least one format+text pair
        return result if len(result) >= 2 else None
    
    def save(self, results: List[Tuple[str, Dict[str, List[Tuple[str, str]]], bool]]):
        """Write all results and close workbook"""
        print(f"\n📝 Generating Excel file...")
        
        self.write_header()
        
        for table_name, grouped_differences, is_pcr in results:
            self.write_table(table_name, grouped_differences, is_pcr)
        
        self.workbook.close()
        
        tables_count = len(results)
        pcr_count = sum(1 for _, _, is_pcr in results if is_pcr)
        table_count = tables_count - pcr_count
        
        print(f"✅ Saved with {tables_count} items:")
        print(f"   - {table_count} tables")
        print(f"   - {pcr_count} PCR schemas")


def main():
    if len(sys.argv) != 3:
        print("Usage: python hrsp_compare_final.py <PRE_DIR> <POST_DIR>")
        print("\nExample:")
        print("  python hrsp_compare_final.py ./data/PRE ./data/POST")
        sys.exit(1)
    
    pre_dir = Path(sys.argv[1])
    post_dir = Path(sys.argv[2])
    
    if not pre_dir.is_dir() or not post_dir.is_dir():
        print(f"❌ Error: Invalid directories")
        sys.exit(1)
    
    print("=" * 70)
    print("🦀 HRSP File Comparator - Final POC")
    print("    Python version with PCR support")
    print("=" * 70)
    
    comparer = HRSPComparer()
    results = comparer.compare_directories(pre_dir, post_dir)
    
    if results:
        generator = ExcelGenerator("comparison_final.xlsx")
        generator.save(results)
        print(f"\n✅ Done! Output: comparison_final.xlsx")
    else:
        print("\n✅ No differences found")


if __name__ == "__main__":
    main()
