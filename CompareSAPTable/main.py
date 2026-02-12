"""Compare SAP Tables & PCR Schemas – Python / Tkinter rewrite.
GUI with drag-and-drop, Options.ini compatibility, Excel output.

Usage:
    pip install xlsxwriter
    pip install tkinterdnd2   # optional, for drag-and-drop
    python main.py
"""

import os
import sys
import re as _re
import time
import configparser
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from typing import List, Dict, Any, Optional

import sys
_HAS_DND = sys.platform == 'win32'

from comparator import (
    get_changes, get_table_name, trie_change, colorize_change,
    NO_KEYCUT_VALUE, SCHEME_LENGTH,
)
from excel_writer import ComparisonResult, write_excel

# ---------------------------------------------------------------------------
#  Configuration (reads the same Options.ini as the Pascal version)
# ---------------------------------------------------------------------------

def _find_ini() -> str:
    """Locate Options.ini next to the script, or in ComparePCRandTables/."""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, 'Options.ini'),
        os.path.join(here, 'ComparePCRandTables', 'Options.ini'),
    ]
    for p in candidates:
        if os.path.isfile(p):
            return p
    return candidates[0]  # will be created on save


def load_config(ini_path: str) -> Dict[str, Any]:
    """Read Options.ini and return a flat config dict."""
    cfg: Dict[str, Any] = {}
    cp = configparser.ConfigParser(strict=False)

    if os.path.isfile(ini_path):
        with open(ini_path, 'r', encoding='utf-8', errors='replace') as fh:
            raw = fh.read().replace(':=', '=')
        # configparser keeps section names case-sensitive; lowercase them
        # so all our lookups work uniformly.
        raw = _re.sub(r'^\[([^\]]+)\]', lambda m: f'[{m.group(1).lower()}]',
                       raw, flags=_re.MULTILINE)
        cp.read_string(raw)

    def gi(sec, key, default=0):
        try:
            return cp.getint(sec.lower(), key.lower())
        except (configparser.Error, ValueError):
            return default

    def gs(sec, key, default=''):
        try:
            return cp.get(sec.lower(), key.lower())
        except configparser.Error:
            return default

    def gb(sec, key, default=False):
        try:
            val = cp.get(sec.lower(), key.lower())
            return val.strip().lower() not in ('0', 'false', 'no', '')
        except configparser.Error:
            return default

    # [DeleteFileNamePart]
    n = gi('deletefilenamepart', 'num', 0)
    parts: List[str] = []
    for i in range(1, n + 1):
        p = gs('deletefilenamepart', str(i))
        if p:
            parts.append(p)
    cfg['parts_to_delete'] = parts

    # [TableCutNumber]
    cfg['table_keycuts'] = {}
    if cp.has_section('tablecutnumber'):
        for key in cp.options('tablecutnumber'):
            try:
                cfg['table_keycuts'][key] = int(cp.get('tablecutnumber', key))
            except ValueError:
                pass

    # [GeneriqueFiles]
    cfg['generique_files'] = {}
    if cp.has_section('generiquefiles'):
        for key in cp.options('generiquefiles'):
            try:
                cfg['generique_files'][key] = int(cp.get('generiquefiles', key))
            except ValueError:
                pass

    # [GenOptions]
    cfg['auto_save'] = gb('genoptions', 'automaticsave', False)
    cfg['affiche_pit'] = gb('genoptions', 'displaypitifidentical', False)
    cfg['use_value_for_scheme'] = gb('genoptions', 'usevalueforscheme', False)
    cfg['key_value_for_schema'] = gi('genoptions', 'keyvalueforschema', 9)
    cfg['override_all_key'] = gb('genoptions', 'overideallkey', False)
    cfg['value_override'] = gi('genoptions', 'valueoveride', 4)

    # [ColorDifference]
    cfg['diff_color'] = gs('colordifference', 'fontcolor', 'red')
    if not cfg['diff_color'].startswith('#'):
        color_map = {'red': '#FF0000', 'blue': '#0000FF', 'green': '#008000'}
        cfg['diff_color'] = color_map.get(cfg['diff_color'].lower(), '#FF0000')

    # [TableHead]
    cfg['row1'] = gs('tablehead', 'row1', 'Table')
    cfg['row2'] = gs('tablehead', 'row2', 'Value Before HRSP')
    cfg['row3'] = gs('tablehead', 'row3', 'Value After HRSP')
    cfg['row4'] = gs('tablehead', 'row4', 'Transport and comments')

    # [TableAnalys]  header_bg in BGR
    bgr = gi('tableanalys', 'backcolor', 0x00008CFF)
    r, g, b = bgr & 0xFF, (bgr >> 8) & 0xFF, (bgr >> 16) & 0xFF
    cfg['table_bg'] = f'#{r:02X}{g:02X}{b:02X}'

    # Main header (hard-coded in Pascal: $008B2268)
    cfg['header_bg'] = '#68228B'
    cfg['header_fg'] = '#FFFFFF'

    # [StandardFont]
    cfg['font_name'] = gs('standardfont', 'fontname', 'Calibri')
    cfg['font_size'] = gi('standardfont', 'fontsize', 11)

    cfg['ini_path'] = ini_path
    return cfg


def save_config_option(ini_path: str, section: str, key: str, value: str):
    """Write a single value back to Options.ini."""
    cp = configparser.ConfigParser()
    if os.path.isfile(ini_path):
        with open(ini_path, 'r', encoding='utf-8', errors='replace') as fh:
            raw = fh.read().replace(':=', '=')
        cp.read_string(raw)
    sec = section.lower()
    if not cp.has_section(sec):
        cp.add_section(sec)
    cp.set(sec, key.lower(), str(value))
    with open(ini_path, 'w', encoding='utf-8') as fh:
        cp.write(fh)


# ---------------------------------------------------------------------------
#  KeyCut resolution (same logic as Pascal ExecCompareTableClick)
# ---------------------------------------------------------------------------

def resolve_keycut(table_name: str, is_pcr: bool, cfg: Dict[str, Any]) -> int:
    kc = NO_KEYCUT_VALUE

    if is_pcr:
        if cfg['use_value_for_scheme']:
            kc = cfg['key_value_for_schema']
        else:
            kc = cfg['table_keycuts'].get('pcr', NO_KEYCUT_VALUE)
    else:
        kc = cfg['table_keycuts'].get(table_name.lower(), NO_KEYCUT_VALUE)

    if kc == NO_KEYCUT_VALUE:
        for gen_key, gen_val in cfg['generique_files'].items():
            if gen_key in table_name.lower():
                kc = gen_val
                break

    if cfg['override_all_key']:
        kc = cfg['value_override']

    return kc


# ---------------------------------------------------------------------------
#  Comparison orchestrator
# ---------------------------------------------------------------------------

def run_comparison(pre_path: str, post_path: str,
                   cfg: Dict[str, Any],
                   log_fn=None) -> List[ComparisonResult]:
    """Run the full comparison pipeline.  Returns results for Excel."""

    def log(msg):
        if log_fn:
            log_fn(msg)

    is_file_mode = os.path.isfile(pre_path) and os.path.isfile(post_path)
    is_dir_mode = os.path.isdir(pre_path) and os.path.isdir(post_path)

    if not is_file_mode and not is_dir_mode:
        raise ValueError("PRE and POST must both be files or both be directories.")

    # Build file pairs
    pairs: List[tuple] = []
    if is_file_mode:
        pairs.append((pre_path, post_path))
    else:
        pre_files = {}
        post_files = {}
        for root, _, files in os.walk(pre_path):
            for f in files:
                pre_files[f.lower()] = os.path.join(root, f)
        for root, _, files in os.walk(post_path):
            for f in files:
                post_files[f.lower()] = os.path.join(root, f)
        log(f"{len(pre_files)} files in Pre")
        log(f"{len(post_files)} files in Post")
        common = sorted(set(pre_files) & set(post_files))
        for fname in common:
            pairs.append((pre_files[fname], post_files[fname]))

    results: List[ComparisonResult] = []
    parts_del = cfg['parts_to_delete']

    for pre_f, post_f in pairs:
        table_name = get_table_name(pre_f, parts_del)
        log(f"=Analyse {table_name}=")
        t0 = time.time()

        pre_changed, post_changed, same_size = get_changes(pre_f, post_f)

        if not pre_changed and not post_changed:
            log("No changes found")
            log(f"Time: {time.time() - t0:.3f} sec.")
            continue

        is_pcr = 'schema' in table_name.lower()
        keycut = resolve_keycut(table_name, is_pcr, cfg)

        pre_res, post_res = trie_change(
            keycut, pre_changed, post_changed,
            is_pcr, cfg['affiche_pit'], same_size)

        # For non-PCR with large keycut + same size: reset keycut for coloring
        if not is_pcr and keycut > 100 and same_size and len(pre_res) == len(post_res):
            keycut = 0

        if pre_res:
            results.append(ComparisonResult(table_name, pre_res, post_res, is_pcr, keycut))
            log(f"{len(pre_res)} difference(s)")
        else:
            log("No changes found")

        log(f"Time: {time.time() - t0:.3f} sec.")

    return results


# ---------------------------------------------------------------------------
#  Options dialog
# ---------------------------------------------------------------------------

class OptionsDialog(tk.Toplevel):
    def __init__(self, parent, cfg: Dict[str, Any]):
        super().__init__(parent)
        self.cfg = cfg
        self.title("Options")
        self.geometry("440x560")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        self._build()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build(self):
        c = self.cfg
        pad = dict(padx=8, pady=3)

        # --- General frame ---
        gf = ttk.LabelFrame(self, text="General")
        gf.pack(fill='x', **pad)

        row0 = ttk.Frame(gf)
        row0.pack(fill='x', **pad)
        self.chk_val_scheme = tk.BooleanVar(value=c['use_value_for_scheme'])
        ttk.Checkbutton(row0, text="Use this Key value for Schema:",
                        variable=self.chk_val_scheme,
                        command=self._save_opts).pack(side='left')
        self.spin_schema = tk.IntVar(value=c['key_value_for_schema'])
        ttk.Spinbox(row0, from_=1, to=9999, width=6,
                     textvariable=self.spin_schema,
                     command=self._save_opts).pack(side='left', padx=4)

        row1 = ttk.Frame(gf)
        row1.pack(fill='x', **pad)
        self.chk_override = tk.BooleanVar(value=c['override_all_key'])
        ttk.Checkbutton(row1, text="Override ALL Key with this value:",
                        variable=self.chk_override,
                        command=self._save_opts).pack(side='left')
        self.spin_override = tk.IntVar(value=c['value_override'])
        ttk.Spinbox(row1, from_=1, to=9999, width=6,
                     textvariable=self.spin_override,
                     command=self._save_opts).pack(side='left', padx=4)

        row2 = ttk.Frame(gf)
        row2.pack(fill='x', **pad)
        self.chk_auto = tk.BooleanVar(value=c['auto_save'])
        ttk.Checkbutton(row2, text='Save file and clear automatically after "Execute"',
                        variable=self.chk_auto,
                        command=self._save_opts).pack(side='left')

        row3 = ttk.Frame(gf)
        row3.pack(fill='x', **pad)
        self.chk_pit = tk.BooleanVar(value=c['affiche_pit'])
        ttk.Checkbutton(row3, text="Show PIT Scheme with same text but different line numbers",
                        variable=self.chk_pit,
                        command=self._save_opts).pack(side='left')

        # --- Key-value table ---
        ttk.Label(self, text="Key value for files").pack(anchor='w', padx=8, pady=(8, 0))

        tf = ttk.Frame(self)
        tf.pack(fill='both', expand=True, padx=8, pady=4)

        cols = ('table', 'keycut')
        self.tree = ttk.Treeview(tf, columns=cols, show='headings', height=14)
        self.tree.heading('table', text='Table File Name')
        self.tree.heading('keycut', text='Key Value')
        self.tree.column('table', width=280)
        self.tree.column('keycut', width=80)
        sb = ttk.Scrollbar(tf, orient='vertical', command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side='left', fill='both', expand=True)
        sb.pack(side='right', fill='y')

        for tname, kval in sorted(self.cfg['table_keycuts'].items()):
            self.tree.insert('', 'end', values=(tname.upper(), kval))

        # --- Buttons ---
        bf = ttk.Frame(self)
        bf.pack(fill='x', padx=8, pady=6)
        ttk.Button(bf, text="Delete Selected", command=self._delete_key).pack(side='left')
        ttk.Button(bf, text="Add...", command=self._add_key).pack(side='left', padx=8)
        ttk.Button(bf, text="Close", command=self._on_close).pack(side='right')

    def _save_opts(self, *_):
        c = self.cfg
        c['use_value_for_scheme'] = self.chk_val_scheme.get()
        c['key_value_for_schema'] = self.spin_schema.get()
        c['override_all_key'] = self.chk_override.get()
        c['value_override'] = self.spin_override.get()
        c['auto_save'] = self.chk_auto.get()
        c['affiche_pit'] = self.chk_pit.get()

    def _delete_key(self):
        sel = self.tree.selection()
        if not sel:
            return
        item = sel[0]
        vals = self.tree.item(item, 'values')
        tname = vals[0].lower()
        self.tree.delete(item)
        self.cfg['table_keycuts'].pop(tname, None)

    def _add_key(self):
        dlg = tk.Toplevel(self)
        dlg.title("Add table key")
        dlg.geometry("340x120")
        dlg.transient(self)
        dlg.grab_set()

        ttk.Label(dlg, text="Table name:").grid(row=0, column=0, padx=8, pady=8, sticky='w')
        ent = ttk.Entry(dlg, width=20)
        ent.grid(row=0, column=1, padx=4, pady=8)

        ttk.Label(dlg, text="Key value:").grid(row=1, column=0, padx=8, sticky='w')
        sp = tk.IntVar(value=10)
        ttk.Spinbox(dlg, from_=1, to=9999, width=8, textvariable=sp).grid(row=1, column=1, padx=4, sticky='w')

        def _ok():
            n = ent.get().strip()
            v = sp.get()
            if not n:
                messagebox.showwarning("Warning", "Table name cannot be empty", parent=dlg)
                return
            self.cfg['table_keycuts'][n.lower()] = v
            self.tree.insert('', 'end', values=(n.upper(), v))
            dlg.destroy()

        ttk.Button(dlg, text="Add", command=_ok).grid(row=2, column=0, columnspan=2, pady=12)

    def _on_close(self):
        self._save_opts()
        self.destroy()


# ---------------------------------------------------------------------------
#  Main application
# ---------------------------------------------------------------------------

class CompareSAPApp(tk.Tk):
    TITLE = 'Compare HRSP Files v1.0 (Python)'

    def __init__(self):
        super().__init__()
        self.title(self.TITLE)
        self.geometry('1280x720')
        self.minsize(800, 500)

        self.ini_path = _find_ini()
        self.cfg = load_config(self.ini_path)
        self.results: List[ComparisonResult] = []

        self._build_ui()
        self._try_enable_dnd()

    # ----- UI construction --------------------------------------------------

    def _build_ui(self):
        self._build_toolbar()
        self._build_inputs()
        self._build_main_area()
        self._build_statusbar()

    def _build_toolbar(self):
        tb = ttk.Frame(self, padding=4)
        tb.pack(fill='x')
        ttk.Button(tb, text="Execute", command=self.execute, width=10).pack(side='left', padx=2)
        ttk.Button(tb, text="Save As", command=self.save_as, width=10).pack(side='left', padx=2)
        ttk.Button(tb, text="Clear", command=self.clear_all, width=10).pack(side='left', padx=2)
        ttk.Separator(tb, orient='vertical').pack(side='left', fill='y', padx=6)
        ttk.Button(tb, text="Options", command=self.show_options, width=10).pack(side='left', padx=2)
        ttk.Button(tb, text="About", command=self.show_about, width=10).pack(side='left', padx=2)

    def _build_inputs(self):
        frm = ttk.Frame(self, padding=(8, 4))
        frm.pack(fill='x')

        ttk.Label(frm, text="PRE:").grid(row=0, column=0, sticky='w')
        self.pre_var = tk.StringVar()
        pre_ent = ttk.Entry(frm, textvariable=self.pre_var, width=90)
        pre_ent.grid(row=0, column=1, padx=4, sticky='ew')
        ttk.Button(frm, text="Browse...", command=self._browse_pre, width=10).grid(row=0, column=2, padx=2)

        ttk.Label(frm, text="POST:").grid(row=1, column=0, sticky='w')
        self.post_var = tk.StringVar()
        post_ent = ttk.Entry(frm, textvariable=self.post_var, width=90)
        post_ent.grid(row=1, column=1, padx=4, sticky='ew')
        ttk.Button(frm, text="Browse...", command=self._browse_post, width=10).grid(row=1, column=2, padx=2)

        frm.columnconfigure(1, weight=1)

    def _build_main_area(self):
        pw = ttk.PanedWindow(self, orient='horizontal')
        pw.pack(fill='both', expand=True, padx=4, pady=4)

        # Left: results grid (3 synchronized Text widgets)
        left = ttk.Frame(pw)
        pw.add(left, weight=4)

        self.drop_label = ttk.Label(
            left, text="Drag-and-drop PRE file/directory here, or use Browse",
            anchor='center', font=('Segoe UI', 14), foreground='#888888')
        self.drop_label.pack(fill='both', expand=True)

        grid_frame = ttk.Frame(left)
        self.grid_frame = grid_frame  # shown after execute

        # Column headers
        hdr_frame = tk.Frame(grid_frame)
        hdr_frame.pack(fill='x')
        hdr_font = ('Segoe UI', 10, 'bold')
        hdr_bg = '#68228B'
        hdr_fg = '#FFFFFF'
        # Scrollbar placeholder on right (pack first so it takes priority)
        tk.Label(hdr_frame, text='', width=2, bg=hdr_bg,
                 borderwidth=1, relief='solid').pack(side='right', fill='y')
        tk.Label(hdr_frame, text='Table', font=hdr_font, width=16,
                 bg=hdr_bg, fg=hdr_fg, anchor='w', padx=4,
                 borderwidth=1, relief='solid').pack(side='left', fill='y')
        tk.Label(hdr_frame, text='Value Before HRSP', font=hdr_font,
                 bg=hdr_bg, fg=hdr_fg, anchor='w', padx=4,
                 borderwidth=1, relief='solid').pack(side='left', fill='both', expand=True)
        tk.Label(hdr_frame, text='Value After HRSP', font=hdr_font,
                 bg=hdr_bg, fg=hdr_fg, anchor='w', padx=4,
                 borderwidth=1, relief='solid').pack(side='left', fill='both', expand=True)

        # Text columns area
        text_frame = tk.Frame(grid_frame)
        text_frame.pack(fill='both', expand=True)

        grid_font = ('Consolas', 10)

        # Table name column (narrow)
        self.col_table = tk.Text(text_frame, width=16, font=grid_font,
                                 wrap='none', state='disabled', cursor='arrow',
                                 borderwidth=1, relief='solid', padx=2)
        self.col_table.pack(side='left', fill='y')

        # Before column
        self.col_before = tk.Text(text_frame, font=grid_font, wrap='none',
                                  state='disabled', cursor='arrow',
                                  borderwidth=1, relief='solid', padx=2)
        self.col_before.pack(side='left', fill='both', expand=True)

        # After column
        self.col_after = tk.Text(text_frame, font=grid_font, wrap='none',
                                 state='disabled', cursor='arrow',
                                 borderwidth=1, relief='solid', padx=2)
        self.col_after.pack(side='left', fill='both', expand=True)

        # Shared vertical scrollbar
        self._grid_vsb = ttk.Scrollbar(text_frame, orient='vertical',
                                       command=self._on_grid_scroll)
        self._grid_vsb.pack(side='right', fill='y')

        # All three columns report scroll position; only col_before drives the scrollbar
        self.col_before.configure(yscrollcommand=self._on_col_yscroll)

        # Configure tags for all three columns
        for w in (self.col_table, self.col_before, self.col_after):
            w.tag_configure('red', foreground='#FF0000')
            w.tag_configure('header', background='#FF8C00', foreground='black')
            w.tag_configure('deleted', background='#FFE0E0')
            w.tag_configure('added', background='#E0FFE0')
            w.tag_configure('changed', background='#FFFFF0')
            # Bind mousewheel for synchronized scrolling
            w.bind('<MouseWheel>', self._on_grid_mousewheel)
            w.bind('<Button-4>', self._on_grid_mousewheel)
            w.bind('<Button-5>', self._on_grid_mousewheel)

        # Right: stats
        right = ttk.Frame(pw)
        pw.add(right, weight=1)

        ttk.Label(right, text="Stats and messages", font=('Segoe UI', 9, 'bold')).pack(anchor='w')
        self.stats_text = tk.Text(right, width=36, wrap='word', state='disabled',
                                  font=('Consolas', 9))
        self.stats_text.pack(fill='both', expand=True)

    # ----- Grid scrolling synchronization -----------------------------------

    def _on_grid_scroll(self, *args):
        """Scrollbar drives all three columns."""
        self.col_table.yview(*args)
        self.col_before.yview(*args)
        self.col_after.yview(*args)

    def _on_col_yscroll(self, first, last):
        """Any column scroll updates scrollbar + syncs others."""
        self._grid_vsb.set(first, last)
        self.col_table.yview_moveto(first)
        self.col_after.yview_moveto(first)

    def _on_grid_mousewheel(self, event):
        """Synchronized mousewheel scrolling."""
        if event.num == 4:
            delta = -3
        elif event.num == 5:
            delta = 3
        else:
            delta = int(-1 * (event.delta / 120))
        self.col_table.yview_scroll(delta, 'units')
        self.col_before.yview_scroll(delta, 'units')
        self.col_after.yview_scroll(delta, 'units')
        return 'break'

    def _build_statusbar(self):
        self.status_var = tk.StringVar(value="Ready")
        sb = ttk.Label(self, textvariable=self.status_var, relief='sunken', anchor='w', padding=4)
        sb.pack(fill='x', side='bottom')

    # ----- Drag-and-drop ----------------------------------------------------

    def _try_enable_dnd(self):
        """Enable native Windows drag-and-drop."""
        if not _HAS_DND:
            return
        try:
            from win_dnd import hook_dropfiles
            hook_dropfiles(self, self._on_drop_files)
        except Exception:
            pass  # DnD not available, user uses Browse buttons

    def _on_drop_files(self, files: List[str]):
        """Handle dropped files/directories."""
        if not files:
            return
        path = files[0]
        if not self.pre_var.get():
            self.pre_var.set(path)
            if os.path.isdir(path):
                self.drop_label.configure(text="Now drag the POST directory here")
            else:
                self.drop_label.configure(text="Now drag the POST file here")
        elif not self.post_var.get():
            self.post_var.set(path)
            self.drop_label.configure(text='Click "Execute" to compare')

    # ----- Actions -----------------------------------------------------------

    def _browse_pre(self):
        p = filedialog.askdirectory(title="Select PRE directory")
        if not p:
            p = filedialog.askopenfilename(title="Select PRE file")
        if p:
            self.pre_var.set(p)

    def _browse_post(self):
        p = filedialog.askdirectory(title="Select POST directory")
        if not p:
            p = filedialog.askopenfilename(title="Select POST file")
        if p:
            self.post_var.set(p)

    def _log(self, msg: str):
        self.stats_text.configure(state='normal')
        self.stats_text.insert('end', msg + '\n')
        self.stats_text.see('end')
        self.stats_text.configure(state='disabled')
        self.update_idletasks()

    def execute(self):
        pre = self.pre_var.get().strip()
        post = self.post_var.get().strip()
        if not pre:
            messagebox.showwarning("Warning", "PRE file or directory missing")
            return
        if not post:
            messagebox.showwarning("Warning", "POST file or directory missing")
            return

        # Reload config in case Options were changed
        self.cfg = load_config(self.ini_path)

        self.stats_text.configure(state='normal')
        self.stats_text.delete('1.0', 'end')
        self.stats_text.configure(state='disabled')
        for w in (self.col_table, self.col_before, self.col_after):
            w.configure(state='normal')
            w.delete('1.0', 'end')
            w.configure(state='disabled')

        # Show grid, hide drop label
        self.drop_label.pack_forget()
        self.grid_frame.pack(fill='both', expand=True)

        self.status_var.set("Analysis in progress...")
        self.config(cursor='watch')
        self.update_idletasks()

        t_global = time.time()
        try:
            self.results = run_comparison(pre, post, self.cfg, log_fn=self._log)
        except Exception as exc:
            messagebox.showerror("Error", str(exc))
            self.config(cursor='')
            self.status_var.set("Error")
            return

        # Fill grid
        for w in (self.col_table, self.col_before, self.col_after):
            w.configure(state='normal')
        for res in self.results:
            if res.is_pcr:
                self._fill_grid_pcr(res)
            else:
                self._fill_grid_table(res)
        for w in (self.col_table, self.col_before, self.col_after):
            w.configure(state='disabled')

        elapsed = time.time() - t_global
        n_files = len(self.results)
        self.status_var.set(f"Global time: {elapsed:.3f} sec.  Tables with changes: {n_files}")
        self.config(cursor='')

        # Auto-save
        if self.cfg['auto_save'] and self.results:
            self._auto_save(pre, post)

    # ----- Grid filling (Text widgets with red highlighting) ----------------

    def _insert_grid_line(self, table_text: str, before_text: str,
                          after_text: str, row_tag: str,
                          pre_segs: list = None, post_segs: list = None):
        """Insert one row across all three Text columns."""
        # Table column
        self.col_table.insert('end', table_text + '\n', row_tag)

        # Before column
        if pre_segs:
            self._insert_colored(self.col_before, pre_segs, row_tag)
        else:
            self.col_before.insert('end', before_text + '\n', row_tag)

        # After column
        if post_segs:
            self._insert_colored(self.col_after, post_segs, row_tag)
        else:
            self.col_after.insert('end', after_text + '\n', row_tag)

    @staticmethod
    def _insert_colored(widget: tk.Text, segments: list, row_tag: str):
        """Insert a line with per-word red highlighting, then newline."""
        for i, (word, is_red) in enumerate(segments):
            prefix = ' ' if i > 0 else ''
            if is_red:
                widget.insert('end', prefix + word, ('red', row_tag))
            else:
                widget.insert('end', prefix + word, row_tag)
        widget.insert('end', '\n', row_tag)

    def _fill_grid_table(self, res: ComparisonResult):
        """Fill grid rows for a non-PCR table result."""
        # Table header row
        self._insert_grid_line(res.table_name, '', '', 'header')

        kc = res.keycut
        for p, q in zip(res.pre_lines, res.post_lines):
            if not p:
                self._insert_grid_line('', '', q, 'added')
            elif not q:
                self._insert_grid_line('', p, '', 'deleted')
            else:
                pre_segs, post_segs = colorize_change(p, q, kc)
                self._insert_grid_line('', '', '', 'changed',
                                       pre_segs=pre_segs, post_segs=post_segs)

    def _fill_grid_pcr(self, res: ComparisonResult):
        """Fill grid rows for a PCR schema result."""
        cur_schema = ''
        kc = res.keycut
        for p, q in zip(res.pre_lines, res.post_lines):
            name = (p[:4] if p else q[:4]) if (p or q) else ''
            if name and name != cur_schema:
                self._insert_grid_line(name, '', '', 'header')
                cur_schema = name

            if not p:
                self._insert_grid_line('', '', q, 'added')
            elif not q:
                self._insert_grid_line('', p, '', 'deleted')
            else:
                pre_segs, post_segs = colorize_change(p, q, kc)
                self._insert_grid_line('', '', '', 'changed',
                                       pre_segs=pre_segs, post_segs=post_segs)

    def _auto_save(self, pre: str, post: str):
        if os.path.isdir(post):
            out = post.rstrip('/\\') + '.xlsx'
        else:
            out = os.path.splitext(post)[0] + '.xlsx'
        try:
            write_excel(out, self.results, self.cfg)
            self._log(f'Saved to {out}')
            self.status_var.set(f'File "{out}" saved.')
        except Exception as exc:
            messagebox.showerror("Save error", str(exc))

    def save_as(self):
        if not self.results:
            messagebox.showinfo("Info", "Nothing to save. Run Execute first.")
            return
        path = filedialog.asksaveasfilename(
            title="Save comparison as",
            defaultextension='.xlsx',
            filetypes=[
                ('Excel 2007+', '*.xlsx'),
                ('All files', '*.*'),
            ])
        if not path:
            return
        self.config(cursor='watch')
        self.update_idletasks()
        try:
            write_excel(path, self.results, self.cfg)
            messagebox.showinfo("Saved", f"File saved:\n{path}")
        except Exception as exc:
            messagebox.showerror("Error", str(exc))
        finally:
            self.config(cursor='')

    def clear_all(self):
        self.pre_var.set('')
        self.post_var.set('')
        self.results.clear()
        for w in (self.col_table, self.col_before, self.col_after):
            w.configure(state='normal')
            w.delete('1.0', 'end')
            w.configure(state='disabled')
        self.stats_text.configure(state='normal')
        self.stats_text.delete('1.0', 'end')
        self.stats_text.configure(state='disabled')
        self.grid_frame.pack_forget()
        self.drop_label.pack(fill='both', expand=True)
        self.drop_label.configure(text="Drag-and-drop PRE file/directory here, or use Browse")
        self.status_var.set("Ready")

    def show_options(self):
        OptionsDialog(self, self.cfg)

    def show_about(self):
        messagebox.showinfo(
            "About",
            "Compare HRSP Files v1.0\n"
            "Python rewrite of PCRandTables v0.92b\n\n"
            "Compares SAP tables and PCR schemas\n"
            "between PRE and POST versions.\n\n"
            "Outputs differences to Excel (.xlsx)\n"
            "with colour-highlighted changes."
        )


# ---------------------------------------------------------------------------
#  Entry point
# ---------------------------------------------------------------------------

def main():
    app = CompareSAPApp()
    app.mainloop()


if __name__ == '__main__':
    main()
