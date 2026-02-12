"""Excel output for SAP table / PCR comparison results.
Uses xlsxwriter for .xlsx with rich-text (red) difference highlighting.
"""

import xlsxwriter
from typing import List, Tuple, Dict, Any
from comparator import colorize_change, SCHEME_LENGTH


def _bgr_to_hex(bgr: int) -> str:
    """Convert Delphi $00BBGGRR integer to '#RRGGBB' string."""
    r = bgr & 0xFF
    g = (bgr >> 8) & 0xFF
    b = (bgr >> 16) & 0xFF
    return f'#{r:02X}{g:02X}{b:02X}'


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

class ComparisonResult:
    """One table's worth of aligned PRE/POST differences."""
    __slots__ = ('table_name', 'pre_lines', 'post_lines', 'is_pcr', 'keycut')

    def __init__(self, table_name: str, pre_lines: List[str],
                 post_lines: List[str], is_pcr: bool, keycut: int):
        self.table_name = table_name
        self.pre_lines = pre_lines
        self.post_lines = post_lines
        self.is_pcr = is_pcr
        self.keycut = keycut


def _segments_to_rich(wb: xlsxwriter.Workbook, segments: List[Tuple[str, bool]],
                      base_fmt: xlsxwriter.format.Format,
                      red_fmt: xlsxwriter.format.Format) -> list:
    """Convert [(word, is_red), ...] to xlsxwriter write_rich_string args."""
    parts: list = []
    for word, is_red in segments:
        if not word:
            continue
        fmt = red_fmt if is_red else base_fmt
        if parts:
            parts.append(fmt)
            parts.append(' ' + word)
        else:
            parts.append(fmt)
            parts.append(word)
    return parts


def _write_cell(ws, row: int, col: int, segments: List[Tuple[str, bool]],
                wb: xlsxwriter.Workbook,
                base_fmt: xlsxwriter.format.Format,
                red_fmt: xlsxwriter.format.Format):
    """Write a cell: plain string if no red, rich string otherwise."""
    has_red = any(is_red for _, is_red in segments)
    text = ' '.join(w for w, _ in segments)

    if not has_red or not text.strip():
        ws.write_string(row, col, text, base_fmt)
        return

    parts = _segments_to_rich(wb, segments, base_fmt, red_fmt)
    # xlsxwriter requires at least 3 args (fmt, str, fmt, str) for rich strings
    if len(parts) >= 4:
        try:
            ws.write_rich_string(row, col, *parts)
        except Exception:
            ws.write_string(row, col, text, base_fmt)
    else:
        ws.write_string(row, col, text, base_fmt)


def _html_unescape(text: str) -> str:
    """Replace &lt; back to < (Pascal RemplaceSupInf did the opposite)."""
    return text.replace('&lt;', '<').replace('&gt;', '>')


def write_excel(filepath: str, results: List[ComparisonResult],
                cfg: Dict[str, Any]):
    """Write all comparison results to an Excel .xlsx file."""
    wb = xlsxwriter.Workbook(filepath, {'strings_to_urls': False})
    ws = wb.add_worksheet('Comparison')

    # --- formats ---
    font_name = cfg.get('font_name', 'Calibri')
    font_size = cfg.get('font_size', 11)

    header_bg = cfg.get('header_bg', '#68228B')
    header_fg = cfg.get('header_fg', '#FFFFFF')
    table_bg = cfg.get('table_bg', '#FF8C00')
    diff_color = cfg.get('diff_color', '#FF0000')

    hdr_fmt = wb.add_format({
        'bold': True, 'font_size': 12, 'font_name': font_name,
        'bg_color': header_bg, 'font_color': header_fg,
        'border': 1, 'text_wrap': False,
    })
    tbl_fmt = wb.add_format({
        'bold': True, 'font_size': 12, 'font_name': font_name,
        'bg_color': table_bg, 'font_color': '#000000',
        'border': 1,
    })
    base_fmt = wb.add_format({
        'font_size': font_size, 'font_name': font_name,
        'text_wrap': False, 'valign': 'top',
    })
    red_fmt = wb.add_format({
        'font_size': font_size, 'font_name': font_name,
        'font_color': diff_color, 'text_wrap': False, 'valign': 'top',
    })
    empty_fmt = wb.add_format({'font_size': font_size, 'font_name': font_name})

    # --- column widths (characters) ---
    ws.set_column(0, 0, 18)   # Table
    ws.set_column(1, 1, 65)   # Before
    ws.set_column(2, 2, 65)   # After
    ws.set_column(3, 3, 30)   # Comments

    # --- header row ---
    row1 = cfg.get('row1', 'Table')
    row2 = cfg.get('row2', 'Value Before HRSP')
    row3 = cfg.get('row3', 'Value After HRSP')
    row4 = cfg.get('row4', 'Transport and comments')
    ws.write_string(0, 0, row1, hdr_fmt)
    ws.write_string(0, 1, row2, hdr_fmt)
    ws.write_string(0, 2, row3, hdr_fmt)
    ws.write_string(0, 3, row4, hdr_fmt)

    cur = 1  # current row

    for res in results:
        if not res.pre_lines:
            continue

        if res.is_pcr:
            cur = _write_pcr(wb, ws, cur, res, tbl_fmt, base_fmt, red_fmt, empty_fmt)
        else:
            # Table header
            ws.write_string(cur, 0, res.table_name, tbl_fmt)
            ws.write_string(cur, 1, '', tbl_fmt)
            ws.write_string(cur, 2, '', tbl_fmt)
            ws.write_string(cur, 3, '', tbl_fmt)
            cur += 1

            kc = res.keycut
            for pre_line, post_line in zip(res.pre_lines, res.post_lines):
                pre_segs, post_segs = colorize_change(pre_line, post_line, kc)
                _write_cell(ws, cur, 1, pre_segs, wb, base_fmt, red_fmt)
                _write_cell(ws, cur, 2, post_segs, wb, base_fmt, red_fmt)
                ws.write_string(cur, 3, '', empty_fmt)
                cur += 1

    try:
        wb.close()
    except Exception as exc:
        raise RuntimeError(f"Cannot save Excel: {exc}") from exc


def _write_pcr(wb, ws, cur: int, res: ComparisonResult,
               tbl_fmt, base_fmt, red_fmt, empty_fmt) -> int:
    """Write PCR schema results with sub-headers per schema ID."""
    current_schema = ''
    kc = res.keycut
    for pre_line, post_line in zip(res.pre_lines, res.post_lines):
        name = (pre_line[:4] if pre_line else post_line[:4]) if (pre_line or post_line) else ''
        if name and name != current_schema:
            ws.write_string(cur, 0, name, tbl_fmt)
            ws.write_string(cur, 1, '', tbl_fmt)
            ws.write_string(cur, 2, '', tbl_fmt)
            ws.write_string(cur, 3, '', tbl_fmt)
            current_schema = name
            cur += 1

        if not pre_line or not post_line:
            ws.write_string(cur, 1, pre_line or '', base_fmt)
            ws.write_string(cur, 2, post_line or '', base_fmt)
        else:
            pre_segs, post_segs = colorize_change(pre_line, post_line, kc)
            _write_cell(ws, cur, 1, pre_segs, wb, base_fmt, red_fmt)
            _write_cell(ws, cur, 2, post_segs, wb, base_fmt, red_fmt)
        ws.write_string(cur, 3, '', empty_fmt)
        cur += 1
    return cur
