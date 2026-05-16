@echo off
REM Lance le générateur du Wagetype Catalog Absences sous Windows
REM Crée le venv au premier lancement, sinon réutilise.

cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [run.bat] Creation du virtualenv .venv\...
    python -m venv .venv
    .venv\Scripts\python.exe -m pip install --quiet --upgrade pip
    .venv\Scripts\pip.exe install --quiet -r requirements.txt
)

.venv\Scripts\python.exe generate_wtc_absences.py %*
