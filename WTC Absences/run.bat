@echo off
REM Lance l'interface graphique HRO du Wagetype Catalog Absence sous Windows.
REM Cree le venv au premier lancement, sinon reutilise.
REM Generateur en ligne de commande : .venv\Scripts\python.exe generate_wtc_absences.py --client ABV

cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [run.bat] Creation du virtualenv .venv\...
    python -m venv .venv
    .venv\Scripts\python.exe -m pip install --quiet --upgrade pip
    .venv\Scripts\pip.exe install --quiet -r requirements.txt
)

REM Tkinter est livre avec Python sous Windows (aucune installation systeme requise).
.venv\Scripts\python.exe wtc_absences_gui.py %*
