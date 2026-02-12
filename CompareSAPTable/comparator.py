"""Core comparison engine for SAP table and PCR schema files.
Faithfully replicates the logic from compare_file.pas / analyseprepost.pas.
"""

import os
import re
from typing import List, Tuple, Dict

SCHEME_LENGTH = 4
MIN_SCORE = -10000
NO_KEYCUT_VALUE = 5000


# ---------------------------------------------------------------------------
#  Utilities
# ---------------------------------------------------------------------------

def normalize_line(line: str) -> str:
    """Tabs to single space, compress runs of spaces, strip."""
    result = line.replace('\t', ' ')
    result = re.sub(r' {2,}', ' ', result)
    return result.strip()


def is_a_date(text: str) -> bool:
    """True when *text* starts with dd.mm.yyyy (SAP date format)."""
    text = text.strip()
    if not text or not text[0].isdigit():
        return False
    first_word = text.split()[0]
    if len(first_word) < 10:
        return False
    return text[2] == '.' and text[5] == '.'


def read_file_lines(filepath: str) -> List[str]:
    """Read with encoding fall-back (UTF-8 -> Latin-1 -> CP1252)."""
    for enc in ('utf-8-sig', 'utf-8', 'latin-1', 'cp1252'):
        try:
            with open(filepath, 'r', encoding=enc) as fh:
                return fh.readlines()
        except (UnicodeDecodeError, UnicodeError):
            continue
    with open(filepath, 'r', encoding='utf-8', errors='replace') as fh:
        return fh.readlines()


def get_table_name(filename: str, parts_to_delete: List[str]) -> str:
    """Extract SAP table name from *filename*, stripping known suffixes."""
    name = os.path.splitext(os.path.basename(filename))[0]
    if parts_to_delete:
        for part in parts_to_delete:
            pos = name.find(part)
            if pos > 0:
                return name[:pos]
    return name


def del_space(text: str) -> str:
    return text.replace(' ', '')


def get_reference_str(text: str, pos: int) -> str:
    """First *pos* characters with all spaces removed."""
    return del_space(text)[:pos]


# ---------------------------------------------------------------------------
#  PIT schema helpers
# ---------------------------------------------------------------------------

def is_a_pit(text: str) -> bool:
    """PIT lines have a space at the 5th character (1-indexed)."""
    return len(text) >= 5 and text[4] == ' '


def pit_identical(pre: str, post: str) -> bool:
    """Two PIT lines are 'identical' when only their line-number differs
    (characters 5-8, 1-indexed)."""
    if not (is_a_pit(pre) and is_a_pit(post)):
        return False
    pre_key = pre[:4] + (pre[8:] if len(pre) > 8 else '')
    post_key = post[:4] + (post[8:] if len(post) > 8 else '')
    return pre_key == post_key


def scheme_reference(text: str, keycut: int) -> str:
    cutter = SCHEME_LENGTH if is_a_pit(text) else keycut
    return del_space(text)[:cutter]


# ---------------------------------------------------------------------------
#  Step 1 – diff: lines unique to each side
# ---------------------------------------------------------------------------

def get_changes(pre_file: str, post_file: str) -> Tuple[List[str], List[str], bool]:
    """Load, normalise, deduplicate, return (pre_only, post_only, same_size)."""
    pre_raw = read_file_lines(pre_file)
    post_raw = read_file_lines(post_file)
    same_size = len(pre_raw) == len(post_raw)

    pre_norm = [normalize_line(l) for l in pre_raw]
    post_norm = [normalize_line(l) for l in post_raw]

    pre_set = set(pre_norm)
    post_set = set(post_norm)

    pre_changed = sorted(
        l for l in pre_set if l and l not in post_set and not is_a_date(l))
    post_changed = sorted(
        l for l in post_set if l and l not in pre_set and not is_a_date(l))
    return pre_changed, post_changed, same_size


# ---------------------------------------------------------------------------
#  Step 2 – scoring (similarity between two lines)
# ---------------------------------------------------------------------------

def get_score(source: str, to_compare: str, keycut: int) -> int:
    source = re.sub(r' {2,}', ' ', source)
    to_compare = re.sub(r' {2,}', ' ', to_compare)

    if is_a_pit(source) and is_a_pit(to_compare):
        source = source[8:] if len(source) > 8 else ''
        to_compare = to_compare[8:] if len(to_compare) > 8 else ''

    if not source or not to_compare:
        return -200
    if len(source) < keycut or len(to_compare) < keycut:
        return -200

    result = min(len(source), len(to_compare)) - max(len(source), len(to_compare))

    eff = min(keycut, len(source), len(to_compare))
    for i in range(eff):
        pi = i + 1
        if source[i] == to_compare[i]:
            result += pi * pi
        else:
            result -= 50 + (keycut - pi) * keycut

    str_s = source[keycut:]
    str_t = to_compare[keycut:]
    words_s = str_s.split()
    words_t = str_t.split()
    for i in range(len(source.split())):
        ts = words_s[i] if i < len(words_s) else ''
        tt = words_t[i] if i < len(words_t) else ''
        if not ts or not tt:
            break
        if ts == tt:
            result += (i + 1) + len(ts)
        elif ts in str_t:
            result += len(ts)
    return result


# ---------------------------------------------------------------------------
#  Step 3a – schema (PCR) matching
# ---------------------------------------------------------------------------

def _delete_same_pit(minor: list, major: list):
    """Remove PIT-identical pairs in-place."""
    rm_mi, rm_ma = set(), set()
    for i, m in enumerate(minor):
        for j, M in enumerate(major):
            if j not in rm_ma and pit_identical(m, M):
                rm_mi.add(i)
                rm_ma.add(j)
                break
    for i in sorted(rm_mi, reverse=True):
        minor.pop(i)
    for j in sorted(rm_ma, reverse=True):
        major.pop(j)


def fill_scheme(minor_in: List[str], major_in: List[str],
                keycut: int, affiche_pit: bool) -> Tuple[List[str], List[str]]:
    """Greedy best-score matching of *minor* lines into *major* slots.
    Returns aligned (minor, major) of equal length."""
    minor = list(minor_in)
    major = list(major_in)

    if not minor:
        return [''] * len(major), list(major)

    if minor and is_a_pit(minor[0]) and not affiche_pit:
        _delete_same_pit(minor, major)

    if not minor:
        return [''] * len(major), list(major)
    if not major:
        return list(minor), [''] * len(minor)

    temp_minor = [''] * len(major)

    while True:
        minor = [m for m in minor if m]
        if not minor:
            break

        scores: List[Tuple[int, int, int, str]] = []

        for i in range(len(minor)):
            m_line = minor[i]
            m_ref = scheme_reference(m_line, keycut)
            pit_matched = False

            for j in range(len(major)):
                if temp_minor[j]:
                    continue
                if is_a_pit(m_line) and is_a_pit(major[j]):
                    if pit_identical(m_line, major[j]):
                        temp_minor[j] = m_line
                        minor[i] = ''
                        scores.clear()
                        pit_matched = True
                        break
                    else:
                        sc = get_score(m_line, major[j], keycut)
                        scores.append((sc, i, j, m_line))
                else:
                    M_ref = scheme_reference(major[j], keycut) if major[j] else ''
                    if m_ref and m_ref == M_ref:
                        sc = get_score(m_line, major[j], keycut)
                        scores.append((sc, i, j, m_line))

            if pit_matched:
                break  # restart while-loop

        minor = [m for m in minor if m]
        if not minor:
            break

        if not scores:
            for m_line in minor:
                m_ref = scheme_reference(m_line, keycut)
                insert_pos = -1
                for k in range(len(major)):
                    if get_reference_str(major[k], keycut) == m_ref:
                        insert_pos = k
                if insert_pos >= 0:
                    temp_minor.insert(insert_pos + 1, m_line)
                    major.insert(insert_pos + 1, '')
                else:
                    temp_minor.append(m_line)
                    major.append('')
            break
        else:
            best = max(scores, key=lambda x: x[0])
            _, _, best_j, best_str = best
            temp_minor[best_j] = best_str
            for idx in range(len(minor)):
                if minor[idx] == best_str:
                    minor[idx] = ''
                    break

    return temp_minor, major


def process_schema(pre_changed: List[str], post_changed: List[str],
                   keycut: int, affiche_pit: bool) -> Tuple[List[str], List[str]]:
    """Group by schema name (first 4 chars), match within each group."""
    schema_set: set = set()
    for line in pre_changed:
        if line and not is_a_date(line):
            schema_set.add(line[:SCHEME_LENGTH])
    for line in post_changed:
        if line and not is_a_date(line):
            schema_set.add(line[:SCHEME_LENGTH])
    if not schema_set:
        return [], []

    pre_by: Dict[str, List[str]] = {}
    post_by: Dict[str, List[str]] = {}
    for line in pre_changed:
        if line:
            pre_by.setdefault(line[:SCHEME_LENGTH], []).append(line)
    for line in post_changed:
        if line:
            post_by.setdefault(line[:SCHEME_LENGTH], []).append(line)

    res_pre, res_post = [], []
    for schema in sorted(schema_set):
        pg = pre_by.get(schema, [])
        qg = post_by.get(schema, [])
        if len(pg) <= len(qg):
            am, aM = fill_scheme(pg, qg, keycut, affiche_pit)
            ap, aq = am, aM
        else:
            am, aM = fill_scheme(qg, pg, keycut, affiche_pit)
            ap, aq = aM, am
        for p, q in zip(ap, aq):
            if affiche_pit or not pit_identical(p, q):
                res_pre.append(p)
                res_post.append(q)
    return res_pre, res_post


# ---------------------------------------------------------------------------
#  Step 3b – table matching (non-PCR)
# ---------------------------------------------------------------------------

def valid_string(a: str, b: str) -> bool:
    if a == b:
        return False
    if not a and not b:
        return False
    at, bt = a.strip(), b.strip()
    if is_a_date(at) and not b:
        return False
    if is_a_date(bt) and not a:
        return False
    if is_a_date(at) and is_a_date(bt):
        return False
    return True


def _match_by_key(valid_pos: int, source: List[str],
                  target: List[str]) -> Tuple[List[str], List[str]]:
    """Match *source* against *target* on the first *valid_pos* characters."""
    src_temp, tgt_temp = [], []
    used = [False] * len(target)

    for src_line in source:
        src_ref = get_reference_str(src_line, valid_pos)
        matched = False
        if src_ref:
            for j, tgt_line in enumerate(target):
                if used[j]:
                    continue
                if src_ref == get_reference_str(tgt_line, valid_pos):
                    src_temp.append(src_line)
                    tgt_temp.append(tgt_line)
                    used[j] = True
                    matched = True
                    break
        if not matched:
            src_temp.append(src_line)
            tgt_temp.append('')

    for j, tgt_line in enumerate(target):
        if not used[j]:
            src_temp.append('')
            tgt_temp.append(tgt_line)
    return src_temp, tgt_temp


def trie_change(keycut: int, pre_changed: List[str], post_changed: List[str],
                is_pcr: bool, affiche_pit: bool,
                same_size: bool) -> Tuple[List[str], List[str]]:
    """Sort / match PRE vs POST, return aligned equal-length lists."""
    if is_pcr:
        return process_schema(pre_changed, post_changed, keycut, affiche_pit)

    if len(pre_changed) > len(post_changed):
        pre_t, post_t = _match_by_key(keycut, pre_changed, post_changed)
    else:
        post_t, pre_t = _match_by_key(keycut, post_changed, pre_changed)

    rp, rq = [], []
    for p, q in zip(pre_t, post_t):
        if valid_string(p, q):
            rp.append(p)
            rq.append(q)
    return rp, rq


# ---------------------------------------------------------------------------
#  Step 4 – word-level colourisation
# ---------------------------------------------------------------------------

def _word_elsewhere(word: str, text: str, start: int, approx: int) -> bool:
    words = text.split()
    for i in range(max(0, min(approx, start)), len(words)):
        if words[i] == word:
            return True
    return False


def colorize_change(pre_str: str, post_str: str,
                    valid_pos: int) -> Tuple[list, list]:
    """Return (pre_segs, post_segs) each being [(word, is_red), ...]."""
    if not pre_str or not pre_str.strip() or not post_str or not post_str.strip():
        return [(pre_str, False)], [(post_str, False)]

    pw = pre_str.split()
    qw = post_str.split()

    # Same word count → simple comparison
    if len(pw) == len(qw):
        ps = [(w, w != qw[i]) for i, w in enumerate(pw)]
        qs = [(w, w != pw[i]) for i, w in enumerate(qw)]
        return ps, qs

    # Different lengths – skip key portion, then mark differences
    total = max(len(pw), len(qw))
    ps, qs = [], []
    char_cnt, k = 0, 0
    for i in range(total):
        w = pw[i] if i < len(pw) else ''
        if w:
            char_cnt += len(w)
        if char_cnt <= valid_pos:
            if i < len(pw):
                ps.append((pw[i], False))
            if i < len(qw):
                qs.append((qw[i], False))
            k = i + 1
        else:
            break

    color_hit = False
    diff = abs(len(pw) - len(qw))
    for i in range(k, total):
        p = pw[i] if i < len(pw) else ''
        q = qw[i] if i < len(qw) else ''
        if p != q:
            if p and _word_elsewhere(p, post_str, k, max(0, i - diff)):
                ps.append((p, False))
            elif p:
                color_hit = True
                ps.append((p, True))
            if q and _word_elsewhere(q, pre_str, k, max(0, i - diff)):
                qs.append((q, False))
            elif q:
                color_hit = True
                qs.append((q, True))
        else:
            if p:
                ps.append((p, False))
            if q:
                qs.append((q, False))

    if not color_hit and len(pw) != len(qw):
        mn = min(len(pw), len(qw))
        if len(pw) > len(qw):
            ps = [(w, i >= mn) for i, w in enumerate(pw)]
        else:
            qs = [(w, i >= mn) for i, w in enumerate(qw)]

    return ps, qs
