"""
wtc_absences_gui.py — Interface graphique HRO du Wagetype Catalog Absence.

Destinée à un utilisateur non technique (HRO avec notions informatiques de base).
Elle permet de :
  1. choisir le DOSSIER contenant les tables SAP (T554S/T/C/E, T511, T512T…) ;
  2. choisir le DOSSIER de sortie et le NOM du fichier .xlsx à créer ;
  3. (réservé) cocher "fichier WTC antérieur à réviser" — sans effet pour le
     moment (le code de reprise des colonnes manuelles HRO viendra plus tard) ;
  4. lancer la génération et suivre le journal.

Toute la logique métier vit dans generate_wtc_absences.py : la GUI ne fait que
construire la config (build_dir_config) et appeler generate_from_config(), en
capturant la sortie texte pour l'afficher.

Toolkit : Tkinter (bibliothèque standard Python). Aucune dépendance
supplémentaire. Sur Windows, Tkinter est livré avec Python. Sur Linux, il faut
le paquet système : `sudo apt install python3-tk`.

Lancement :
    python wtc_absences_gui.py        (ou ./run.sh / run.bat)

APP_VERSION : voir generate_wtc_absences.APP_VERSION (logique partagée).
"""
from __future__ import annotations

import io
import queue
import subprocess
import sys
import threading
import traceback
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox
    from tkinter.scrolledtext import ScrolledText
except ModuleNotFoundError:  # pragma: no cover - dépend de l'environnement
    sys.stderr.write(
        "Tkinter introuvable. Sous Linux : sudo apt install python3-tk\n"
        "Sous Windows : réinstaller Python en cochant 'tcl/tk and IDLE'.\n"
    )
    raise

import generate_wtc_absences as gen

# Palette Strada (cohérente avec le catalogue généré)
STRADA_DARK = "#084028"
STRADA_MED = "#207F4F"
STRADA_LIGHT = "#18D878"
BG = "#f4f6f5"

DEFAULT_OUTPUT_NAME = "Wagetype Catalog Absence.xlsx"


def _open_folder(folder: Path) -> None:
    """Ouvre un dossier dans l'explorateur de fichiers (multiplateforme)."""
    folder = str(folder)
    try:
        if sys.platform.startswith("win"):
            import os
            os.startfile(folder)  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", folder])
        else:
            subprocess.Popen(["xdg-open", folder])
    except Exception:
        pass


class _QueueWriter(io.TextIOBase):
    """Fichier-like qui pousse chaque écriture dans une file (thread → GUI)."""

    def __init__(self, q: "queue.Queue[str]"):
        self._q = q

    def write(self, s: str) -> int:
        if s:
            self._q.put(s)
        return len(s)

    def flush(self) -> None:  # noqa: D401 - interface fichier
        pass


class WtcAbsencesApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Générateur Wagetype Catalog Absence — Strada")
        self.root.configure(bg=BG)
        self.root.minsize(760, 620)

        self._log_queue: "queue.Queue[str]" = queue.Queue()
        self._worker: threading.Thread | None = None
        self._last_output: Path | None = None

        self.var_input = tk.StringVar()
        self.var_outdir = tk.StringVar()
        self.var_outname = tk.StringVar(value=DEFAULT_OUTPUT_NAME)
        self.var_revise = tk.BooleanVar(value=False)
        self.var_prevfile = tk.StringVar()

        self._build_ui()
        self.root.after(100, self._drain_log)

    # ---- Construction de l'interface --------------------------------------

    def _build_ui(self) -> None:
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TButton", padding=6)
        style.configure("Accent.TButton", foreground="white",
                        background=STRADA_MED, padding=8, font=("Sans", 10, "bold"))
        style.map("Accent.TButton", background=[("active", STRADA_DARK)])

        # Bandeau titre
        header = tk.Frame(self.root, bg=STRADA_DARK)
        header.pack(fill="x")
        tk.Label(header, text="Wagetype Catalog Absence",
                 bg=STRADA_DARK, fg="white",
                 font=("Sans", 16, "bold")).pack(side="left", padx=16, pady=12)
        tk.Label(header, text=f"v{gen.APP_VERSION}",
                 bg=STRADA_DARK, fg=STRADA_LIGHT,
                 font=("Sans", 10)).pack(side="left", pady=12)

        body = tk.Frame(self.root, bg=BG, padx=16, pady=12)
        body.pack(fill="both", expand=True)
        body.columnconfigure(1, weight=1)
        row = 0

        # 1) Dossier des tables SAP
        tk.Label(body, text="1. Dossier des tables SAP", bg=BG,
                 font=("Sans", 10, "bold")).grid(row=row, column=0, columnspan=3,
                                                 sticky="w", pady=(0, 2))
        row += 1
        tk.Label(body, text="Dossier :", bg=BG).grid(row=row, column=0, sticky="e", padx=(0, 6))
        ttk.Entry(body, textvariable=self.var_input).grid(row=row, column=1, sticky="ew")
        ttk.Button(body, text="Parcourir…",
                   command=self._pick_input).grid(row=row, column=2, padx=(6, 0))
        row += 1
        self.lbl_detect = tk.Label(body, text="(choisissez le dossier contenant T554S, T554T, "
                                              "T554C, T554E, T511, T512T…)",
                                   bg=BG, fg="#666", justify="left", anchor="w")
        self.lbl_detect.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(2, 12))
        row += 1

        # 2) Sortie
        tk.Label(body, text="2. Fichier de sortie (.xlsx)", bg=BG,
                 font=("Sans", 10, "bold")).grid(row=row, column=0, columnspan=3,
                                                 sticky="w", pady=(0, 2))
        row += 1
        tk.Label(body, text="Dossier :", bg=BG).grid(row=row, column=0, sticky="e", padx=(0, 6))
        ttk.Entry(body, textvariable=self.var_outdir).grid(row=row, column=1, sticky="ew")
        ttk.Button(body, text="Parcourir…",
                   command=self._pick_outdir).grid(row=row, column=2, padx=(6, 0))
        row += 1
        tk.Label(body, text="Nom :", bg=BG).grid(row=row, column=0, sticky="e", padx=(0, 6))
        ttk.Entry(body, textvariable=self.var_outname).grid(row=row, column=1, sticky="ew", pady=(4, 12))
        row += 1

        # 3) Case réservée — révision d'un fichier antérieur (sans effet)
        tk.Label(body, text="3. Révision (à venir)", bg=BG,
                 font=("Sans", 10, "bold")).grid(row=row, column=0, columnspan=3,
                                                 sticky="w", pady=(0, 2))
        row += 1
        self.chk_revise = ttk.Checkbutton(
            body,
            text="Il existe un fichier Wagetype Catalog antérieur qui doit être révisé",
            variable=self.var_revise, command=self._toggle_revise)
        self.chk_revise.grid(row=row, column=0, columnspan=3, sticky="w")
        row += 1
        tk.Label(body, text="(fonction à venir : reprise des colonnes remplies manuellement "
                            "par l'HRO — sans effet pour le moment)",
                 bg=BG, fg="#999", font=("Sans", 8, "italic")).grid(
            row=row, column=0, columnspan=3, sticky="w")
        row += 1
        tk.Label(body, text="Fichier antérieur :", bg=BG).grid(row=row, column=0, sticky="e", padx=(0, 6))
        self.ent_prevfile = ttk.Entry(body, textvariable=self.var_prevfile, state="disabled")
        self.ent_prevfile.grid(row=row, column=1, sticky="ew", pady=(4, 12))
        self.btn_prevfile = ttk.Button(body, text="Parcourir…", state="disabled",
                                       command=self._pick_prevfile)
        self.btn_prevfile.grid(row=row, column=2, padx=(6, 0), pady=(4, 12))
        row += 1

        # 4) Bouton générer
        self.btn_generate = ttk.Button(body, text="Générer le catalogue",
                                       style="Accent.TButton", command=self._on_generate)
        self.btn_generate.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(0, 10))
        row += 1

        # 5) Journal
        tk.Label(body, text="Journal", bg=BG,
                 font=("Sans", 10, "bold")).grid(row=row, column=0, columnspan=3, sticky="w")
        row += 1
        body.rowconfigure(row, weight=1)
        self.txt_log = ScrolledText(body, height=12, wrap="word", state="disabled",
                                    font=("monospace", 9), bg="#0f1a14", fg="#cfe8d8")
        self.txt_log.grid(row=row, column=0, columnspan=3, sticky="nsew")
        row += 1

        # Barre de statut + ouvrir dossier
        bar = tk.Frame(self.root, bg=BG, padx=16, pady=6)
        bar.pack(fill="x")
        self.lbl_status = tk.Label(bar, text="Prêt.", bg=BG, fg="#444", anchor="w")
        self.lbl_status.pack(side="left")
        self.btn_open = ttk.Button(bar, text="Ouvrir le dossier de sortie",
                                   command=self._open_output, state="disabled")
        self.btn_open.pack(side="right")

    # ---- Sélecteurs -------------------------------------------------------

    def _pick_input(self) -> None:
        d = filedialog.askdirectory(title="Dossier des tables SAP")
        if d:
            self.var_input.set(d)
            if not self.var_outdir.get():
                self.var_outdir.set(d)
            self._refresh_detection()

    def _pick_outdir(self) -> None:
        d = filedialog.askdirectory(title="Dossier de sortie")
        if d:
            self.var_outdir.set(d)

    def _pick_prevfile(self) -> None:
        f = filedialog.askopenfilename(
            title="Fichier Wagetype Catalog antérieur",
            filetypes=[("Classeur Excel", "*.xlsx"), ("Tous", "*.*")])
        if f:
            self.var_prevfile.set(f)

    def _toggle_revise(self) -> None:
        state = "normal" if self.var_revise.get() else "disabled"
        self.ent_prevfile.configure(state=state)
        self.btn_prevfile.configure(state=state)

    # ---- Détection des tables --------------------------------------------

    def _refresh_detection(self) -> None:
        d = self.var_input.get().strip()
        if not d or not Path(d).is_dir():
            self.lbl_detect.configure(text="Dossier invalide.", fg="#b00")
            return
        found = gen.scan_tables_dir(d)
        req = gen.REQUIRED_DIR_TABLES
        rec = gen.RECOMMENDED_DIR_TABLES
        missing_req = [t for t in req if t not in found]
        missing_rec = [t for t in rec if t not in found]
        present = ", ".join(t for t in (req + rec + gen.OPTIONAL_DIR_TABLES) if t in found)
        lines = [f"Tables détectées : {present or 'aucune'}"]
        if missing_req:
            lines.append(f"⚠ MANQUANTES (obligatoires) : {', '.join(missing_req)}")
            color = "#b00"
        elif missing_rec:
            lines.append(f"ℹ T554E absente → repli sur les 11 classes standard.")
            color = "#a60"
        else:
            lines.append("✓ Toutes les tables nécessaires sont présentes.")
            color = STRADA_MED
        self.lbl_detect.configure(text="\n".join(lines), fg=color)

    # ---- Génération -------------------------------------------------------

    def _on_generate(self) -> None:
        if self._worker and self._worker.is_alive():
            return
        input_dir = self.var_input.get().strip()
        outdir = self.var_outdir.get().strip()
        name = self.var_outname.get().strip()

        if not input_dir or not Path(input_dir).is_dir():
            messagebox.showerror("Erreur", "Choisissez un dossier de tables SAP valide.")
            return
        found = gen.scan_tables_dir(input_dir)
        missing = [t for t in gen.REQUIRED_DIR_TABLES if t not in found]
        if missing:
            messagebox.showerror(
                "Tables manquantes",
                "Le dossier ne contient pas toutes les tables obligatoires.\n"
                f"Manquantes : {', '.join(missing)}")
            return
        if not outdir or not Path(outdir).is_dir():
            messagebox.showerror("Erreur", "Choisissez un dossier de sortie valide.")
            return
        if not name:
            messagebox.showerror("Erreur", "Indiquez un nom de fichier de sortie.")
            return
        if not name.lower().endswith(".xlsx"):
            name += ".xlsx"
            self.var_outname.set(name)

        output_path = Path(outdir) / name
        if output_path.exists():
            if not messagebox.askyesno("Écraser ?",
                                       f"Le fichier existe déjà :\n{output_path}\n\nL'écraser ?"):
                return

        self._last_output = output_path
        self.btn_generate.configure(state="disabled")
        self.btn_open.configure(state="disabled")
        self._set_status("Génération en cours…")
        self._clear_log()

        if self.var_revise.get():
            self._log("ℹ Révision d'un fichier antérieur demandée : fonctionnalité à venir "
                      "(ignorée pour le moment).\n")

        cfg = gen.build_dir_config(input_dir, output_path,
                                   revise_previous=self.var_revise.get())
        self._worker = threading.Thread(target=self._run_generation, args=(cfg,), daemon=True)
        self._worker.start()

    def _run_generation(self, cfg: dict) -> None:
        """Exécuté dans un thread : redirige stdout vers la file et génère."""
        old_stdout = sys.stdout
        sys.stdout = _QueueWriter(self._log_queue)
        try:
            stats = gen.generate_from_config(cfg)
            self._log_queue.put(("__DONE__", stats))
        except Exception:
            self._log_queue.put("\n--- ERREUR ---\n" + traceback.format_exc())
            self._log_queue.put(("__FAIL__", None))
        finally:
            sys.stdout = old_stdout

    # ---- Journal (drainage de la file, thread-safe via after) -------------

    def _drain_log(self) -> None:
        try:
            while True:
                item = self._log_queue.get_nowait()
                if isinstance(item, tuple):
                    tag, payload = item
                    if tag == "__DONE__":
                        self._on_done(payload)
                    elif tag == "__FAIL__":
                        self._on_fail()
                else:
                    self._log(item)
        except queue.Empty:
            pass
        self.root.after(100, self._drain_log)

    def _on_done(self, stats: dict) -> None:
        self.btn_generate.configure(state="normal")
        self.btn_open.configure(state="normal")
        cats = stats.get("categories", "?")
        rows = stats.get("rows", "?")
        cal = stats.get("calendar", "?")
        self._set_status(f"Terminé : {cats} catégories, {rows} lignes, "
                         f"{cal} codes calendrier. → {self._last_output}")
        messagebox.showinfo("Terminé",
                            f"Catalogue généré avec succès.\n\n"
                            f"{cats} catégories, {rows} lignes d'absence, "
                            f"{cal} codes calendrier.\n\n"
                            f"{self._last_output}")

    def _on_fail(self) -> None:
        self.btn_generate.configure(state="normal")
        self._set_status("Échec de la génération — voir le journal.")
        messagebox.showerror("Échec", "La génération a échoué. Consultez le journal pour le détail.")

    def _open_output(self) -> None:
        if self._last_output:
            _open_folder(self._last_output.parent)

    # ---- Utilitaires log/statut ------------------------------------------

    def _log(self, text: str) -> None:
        self.txt_log.configure(state="normal")
        self.txt_log.insert("end", text)
        self.txt_log.see("end")
        self.txt_log.configure(state="disabled")

    def _clear_log(self) -> None:
        self.txt_log.configure(state="normal")
        self.txt_log.delete("1.0", "end")
        self.txt_log.configure(state="disabled")

    def _set_status(self, text: str) -> None:
        self.lbl_status.configure(text=text)


def main() -> None:
    # Windows : définir un AppUserModelID explicite AVANT toute fenêtre, sinon la
    # barre des tâches regroupe l'app sous l'icône générique de Python/Tk au lieu
    # de la nôtre. Sans effet (et silencieux) hors Windows.
    if sys.platform.startswith("win"):
        try:
            import ctypes
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
                "Strada.WTCAbsences")
        except Exception:
            pass

    root = tk.Tk()

    # Icône de la fenêtre + barre des tâches. `default=` l'applique aussi aux
    # boîtes de dialogue. gen.ROOT pointe vers le dossier des ressources (ou
    # sys._MEIPASS dans l'exe PyInstaller, où app.ico est embarqué via --add-data).
    # iconbitmap attend un .ico (OK sous Windows ; peut échouer sous Linux en dev
    # → try/except sans conséquence).
    try:
        ico = gen.ROOT / "app.ico"
        if ico.exists():
            root.iconbitmap(default=str(ico))
    except Exception:
        pass

    WtcAbsencesApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
