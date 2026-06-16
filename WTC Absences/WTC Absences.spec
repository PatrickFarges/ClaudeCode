# -*- mode: python ; coding: utf-8 -*-
#
# Spec PyInstaller du Wagetype Catalog Absence (interface HRO).
# Lancer le build via build_windows.bat (sur Windows) ou :
#     pyinstaller --noconfirm "WTC Absences.spec"
#
# Le .spec est lu en UTF-8 par Python : c'est ce qui permet d'embarquer
# proprement le fichier de données 'numeros_vs_unités' (avec accent), ce que
# --add-data dans un .bat gérerait mal (code page Windows).
#
# Fichiers de données embarqués (extraits dans sys._MEIPASS au runtime, retrouvés
# via gen._resource_root()) :
#   - WTCA reference.xlsx : le template de référence (lu par le générateur)
#   - numeros_vs_unités   : mapping code unité de temps -> libellé (cols F/I/L)
#   - app.ico             : icône de la fenêtre / barre des tâches (runtime)
# (logo_strada.png n'est PAS embarqué : le rebranding n'est plus appliqué.)

a = Analysis(
    ['wtc_absences_gui.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('WTCA reference.xlsx', '.'),
        ('numeros_vs_unités', '.'),
        ('app.ico', '.'),
    ],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='WTC Absences',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,          # --windowed : pas de console derrière la GUI
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['app.ico'],       # icône du .exe (Explorateur / exe épinglé)
)
