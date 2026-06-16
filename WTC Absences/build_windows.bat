@echo off
REM ====================================================================
REM  build_windows.bat - Genere l'executable Windows du Wagetype Catalog
REM  Absence (interface HRO) via PyInstaller, a partir de "WTC Absences.spec".
REM
REM  A LANCER SUR UNE MACHINE WINDOWS (PyInstaller ne cross-compile pas
REM  depuis Linux). Python 3.9+ doit etre dans le PATH.
REM
REM  Resultat : dist\WTC Absences.exe  (fichier unique, autonome, avec icone).
REM
REM  Le .spec embarque le template, le mapping 'numeros_vs_unites' et app.ico,
REM  et regle l'icone du .exe. L'icone de la barre des taches est posee au
REM  runtime par wtc_absences_gui.py (iconbitmap + AppUserModelID).
REM ====================================================================

cd /d "%~dp0"

REM --- venv + dependances + PyInstaller (cree au 1er lancement) ---
if not exist ".venv\Scripts\python.exe" (
    echo [build] Creation du virtualenv .venv\...
    python -m venv .venv
)
echo [build] Installation des dependances...
.venv\Scripts\python.exe -m pip install --quiet --upgrade pip
.venv\Scripts\pip.exe install --quiet -r requirements.txt
.venv\Scripts\pip.exe install --quiet pyinstaller

REM --- Nettoyage des builds precedents ---
if exist "build" rmdir /s /q "build"
if exist "dist" rmdir /s /q "dist"

REM --- Construction depuis le .spec ---
echo [build] PyInstaller...
.venv\Scripts\pyinstaller.exe --noconfirm "WTC Absences.spec"

if errorlevel 1 (
    echo.
    echo [build] ECHEC. Voir les messages ci-dessus.
    pause
    exit /b 1
)

echo.
echo [build] OK -^> dist\WTC Absences.exe
echo [build] (copiable tel quel sur n'importe quel Windows 10/11)
pause
