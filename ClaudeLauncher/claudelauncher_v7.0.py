#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ClaudeLauncher V7.0 - Style Steam/Playnite
Nouveautés V7.0 :
- Auto-sélection + mémorisation de l'onglet actif
- Tags / Mots-clés pour organiser les programmes
- Carrousel d'images personnalisées (local + URL)
- Fix Unicode console Windows cp1252
"""

import sys
import os
import io
import json
import html
import winreg
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Set
from urllib.parse import quote
import string
import re
import time
from datetime import datetime
import hashlib

# Fix Unicode console output on Windows cp1252
if sys.stdout and hasattr(sys.stdout, 'encoding') and sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QListWidget, QLabel, QTabWidget, QPushButton, QSplitter,
    QListWidgetItem, QTextEdit, QMessageBox, QMenu, QFileDialog,
    QInputDialog, QLineEdit, QSpinBox, QDialog, QDialogButtonBox
)
from PyQt6.QtCore import Qt, QSize, QThread, pyqtSignal, QTimer
from PyQt6.QtGui import QPixmap, QIcon, QFont, QAction, QCursor

try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False


class ImageDownloader(QThread):
    """Thread pour télécharger les images de jeux depuis SteamGridDB"""
    image_downloaded = pyqtSignal(str, bytes)  # game_name, image_data
    download_failed = pyqtSignal(str)  # game_name
    
    def __init__(self, game_name: str, api_key: Optional[str] = None):
        super().__init__()
        self.game_name = game_name
        self.api_key = api_key
        self.cache_dir = Path.home() / ".claudelauncher" / "images"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
    
    def run(self):
        """Télécharge l'image depuis SteamGridDB"""
        if not REQUESTS_AVAILABLE:
            print("Module 'requests' non disponible")
            self.download_failed.emit(self.game_name)
            return
        
        try:
            # Vérifier le cache local d'abord
            cache_file = self._get_cache_file()
            if cache_file.exists():
                with open(cache_file, 'rb') as f:
                    self.image_downloaded.emit(self.game_name, f.read())
                return
            
            # Télécharger depuis SteamGridDB
            if self.api_key:
                # Avec clé API (meilleure qualité)
                image_data = self._download_with_api()
            else:
                # Sans clé API (recherche publique limitée)
                image_data = self._download_without_api()
            
            if image_data:
                # Sauvegarder dans le cache
                with open(cache_file, 'wb') as f:
                    f.write(image_data)
                
                self.image_downloaded.emit(self.game_name, image_data)
            else:
                self.download_failed.emit(self.game_name)
                
        except Exception as e:
            print(f"Erreur téléchargement image {self.game_name}: {e}")
            self.download_failed.emit(self.game_name)
    
    def _get_cache_file(self) -> Path:
        """Retourne le chemin du fichier cache"""
        # Utiliser un hash du nom pour éviter les caractères invalides
        name_hash = hashlib.md5(self.game_name.lower().encode()).hexdigest()[:16]
        safe_name = self._sanitize_filename(self.game_name)
        return self.cache_dir / f"{safe_name}_{name_hash}.jpg"
    
    def _download_with_api(self) -> Optional[bytes]:
        """Télécharge avec clé API SteamGridDB"""
        try:
            headers = {"Authorization": f"Bearer {self.api_key}"}
            
            # Essayer plusieurs variantes du nom
            search_terms = self._get_search_variants(self.game_name)
            
            print(f"\n[SteamGridDB] Recherche pour: {self.game_name}")
            print(f"[SteamGridDB] Clé API: {self.api_key[:20]}...{self.api_key[-10:]}")
            print(f"[SteamGridDB] Variantes à essayer: {search_terms}")
            
            game_id = None
            used_term = None
            
            # Essayer chaque variante jusqu'à trouver un résultat
            for term in search_terms:
                print(f"[SteamGridDB] Essai avec: {term}")
                
                # IMPORTANT : Le terme doit être URL-encodé et dans le PATH, pas en query param !
                encoded_term = quote(term)
                search_url = f"https://www.steamgriddb.com/api/v2/search/autocomplete/{encoded_term}"
                
                print(f"[SteamGridDB] URL: {search_url}")
                
                response = requests.get(search_url, headers=headers, timeout=10)
                
                if response.status_code != 200:
                    print(f"[SteamGridDB] Erreur recherche (status {response.status_code})")
                    print(f"[SteamGridDB] Réponse: {response.text[:200]}")
                    continue
                
                results = response.json().get('data', [])
                print(f"[SteamGridDB] Trouvé {len(results)} résultat(s)")
                
                if results:
                    game_id = results[0]['id']
                    used_term = term
                    print(f"[SteamGridDB] ✅ Trouvé ! ID: {game_id}, Nom: {results[0].get('name', 'N/A')}")
                    break
            
            if not game_id:
                print(f"[SteamGridDB] ❌ Aucun résultat pour toutes les variantes")
                return None
            
            # 2. Récupérer les images "hero" (bannières larges)
            print(f"[SteamGridDB] Téléchargement des images pour ID {game_id}...")
            images_url = f"https://www.steamgriddb.com/api/v2/heroes/game/{game_id}"
            response = requests.get(images_url, headers=headers, timeout=10)
            
            if response.status_code != 200:
                print(f"[SteamGridDB] Erreur images (status {response.status_code})")
                return None
            
            images = response.json().get('data', [])
            print(f"[SteamGridDB] Trouvé {len(images)} image(s)")
            
            if not images:
                print(f"[SteamGridDB] ❌ Pas d'images 'hero' disponibles")
                # Essayer avec des grids à la place
                print(f"[SteamGridDB] Essai avec des 'grids'...")
                images_url = f"https://www.steamgriddb.com/api/v2/grids/game/{game_id}"
                response = requests.get(images_url, headers=headers, timeout=10)
                
                if response.status_code == 200:
                    images = response.json().get('data', [])
                    print(f"[SteamGridDB] Trouvé {len(images)} grid(s)")
                
                if not images:
                    return None
            
            # 3. Télécharger la première image
            image_url = images[0]['url']
            print(f"[SteamGridDB] Téléchargement de l'image depuis: {image_url[:50]}...")
            image_response = requests.get(image_url, timeout=15)
            
            if image_response.status_code == 200:
                print(f"[SteamGridDB] ✅ Image téléchargée ! ({len(image_response.content)} bytes)")
                return image_response.content
            else:
                print(f"[SteamGridDB] Erreur téléchargement image (status {image_response.status_code})")
            
        except Exception as e:
            print(f"[SteamGridDB] Erreur API: {e}")
            import traceback
            traceback.print_exc()
        
        return None
    
    def _get_search_variants(self, game_name: str) -> List[str]:
        """Génère des variantes du nom de jeu pour la recherche"""
        variants = [game_name]
        
        # Nettoyer le nom de base
        clean_name = game_name.strip()
        
        # Variantes communes
        # Enlever/ajouter des suffixes courants
        suffixes_to_try = [
            ' Online',
            ' Online Edition',
            ' Remastered',
            ' Special Edition',
            ' Game of the Year Edition',
            ' GOTY',
            ' Definitive Edition',
            ' Enhanced Edition',
            ' Deluxe Edition',
            ' Complete Edition',
            ' Ultimate Edition',
            ' Director\'s Cut',
        ]
        
        # Ajouter les variantes avec suffixes
        for suffix in suffixes_to_try:
            if not clean_name.endswith(suffix):
                variants.append(clean_name + suffix)
            else:
                # Si le nom contient déjà le suffixe, essayer sans
                variants.append(clean_name.replace(suffix, '').strip())
        
        # Enlever les numéros de version (ex: "Game 2" → "Game")
        if clean_name[-1].isdigit():
            base = clean_name.rstrip('0123456789').strip()
            if base and base != clean_name:
                variants.append(base)
        
        # Enlever les sous-titres après ":" 
        if ':' in clean_name:
            main_title = clean_name.split(':')[0].strip()
            variants.append(main_title)
        
        # Enlever les parenthèses et leur contenu
        if '(' in clean_name:
            without_parens = re.sub(r'\([^)]*\)', '', clean_name).strip()
            variants.append(without_parens)
        
        # Dédupliquer en gardant l'ordre
        seen = set()
        unique_variants = []
        for v in variants:
            v_lower = v.lower()
            if v_lower not in seen and v:
                seen.add(v_lower)
                unique_variants.append(v)
        
        return unique_variants
    
    def _download_without_api(self) -> Optional[bytes]:
        """Télécharge sans clé API (méthode alternative)"""
        # Sans clé API, on utilise une recherche Google Images simplifiée
        # ou on retourne None pour que l'utilisateur ajoute une clé API
        
        # Pour l'instant, on retourne None
        # L'utilisateur devra ajouter une clé API gratuite pour avoir les images
        print(f"Pas de clé API - image non téléchargée pour: {self.game_name}")
        return None
    
    def _sanitize_filename(self, filename: str) -> str:
        """Nettoie un nom de fichier"""
        # Garder seulement les caractères alphanumériques et espaces/tirets
        safe = "".join(c for c in filename if c.isalnum() or c in (' ', '-', '_'))
        return safe.strip()[:50]  # Max 50 caractères


class CustomImageDownloader(QThread):
    """Thread pour télécharger une image personnalisée depuis une URL"""
    image_downloaded = pyqtSignal(str, bytes)  # source_url, image_data
    download_failed = pyqtSignal(str)  # source_url

    def __init__(self, source_url: str):
        super().__init__()
        self.source_url = source_url
        self.cache_dir = Path.home() / ".claudelauncher" / "images"
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def run(self):
        try:
            # Check cache first
            url_hash = hashlib.md5(self.source_url.encode()).hexdigest()
            cache_file = self.cache_dir / f"custom_{url_hash}.jpg"
            if cache_file.exists():
                with open(cache_file, 'rb') as f:
                    self.image_downloaded.emit(self.source_url, f.read())
                return

            if not REQUESTS_AVAILABLE:
                self.download_failed.emit(self.source_url)
                return

            response = requests.get(self.source_url, timeout=15)
            if response.status_code == 200 and response.content:
                with open(cache_file, 'wb') as f:
                    f.write(response.content)
                self.image_downloaded.emit(self.source_url, response.content)
            else:
                self.download_failed.emit(self.source_url)
        except Exception as e:
            print(f"Erreur téléchargement image custom {self.source_url}: {e}")
            self.download_failed.emit(self.source_url)


class ProgramScanner(QThread):
    """Thread pour scanner les programmes"""
    finished = pyqtSignal(list)
    progress = pyqtSignal(str)
    
    def __init__(self, custom_folders: List[str] = None):
        super().__init__()
        self.cache_dir = Path.home() / ".claudelauncher" / "cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.custom_folders = custom_folders or []
        self.steam_games = set()
        self.epic_games = set()
        
    def run(self):
        """Scanne les programmes installés"""
        programs = []
        
        self.progress.emit("Scan des bibliothèques Steam...")
        self._parse_steam_library()
        
        self.progress.emit("Scan des bibliothèques Epic Games...")
        self._parse_epic_library()
        
        self.progress.emit("Scan du registre Windows...")
        programs.extend(self._scan_registry())
        
        self.progress.emit("Scan des disques pour les jeux...")
        programs.extend(self._scan_all_drives_for_games())
        
        if self.custom_folders:
            self.progress.emit("Scan des dossiers personnalisés...")
            programs.extend(self._scan_custom_folders())
        
        unique_programs = self._deduplicate(programs)
        
        self.progress.emit(f"Trouvé {len(unique_programs)} programmes")
        self.finished.emit(unique_programs)
    
    def _parse_steam_library(self):
        """Parse les fichiers .acf de Steam"""
        steam_paths = [
            Path("C:/Program Files (x86)/Steam"),
            Path("C:/Program Files/Steam"),
        ]
        
        for steam_path in steam_paths:
            steamapps = steam_path / "steamapps"
            if not steamapps.exists():
                continue
            
            library_folders = [steamapps]
            libraryfolders_vdf = steamapps / "libraryfolders.vdf"
            
            if libraryfolders_vdf.exists():
                try:
                    with open(libraryfolders_vdf, 'r', encoding='utf-8') as f:
                        content = f.read()
                        paths = re.findall(r'"path"\s+"([^"]+)"', content)
                        for path in paths:
                            lib_path = Path(path) / "steamapps"
                            if lib_path.exists():
                                library_folders.append(lib_path)
                except Exception:
                    pass
            
            for lib_folder in library_folders:
                for acf_file in lib_folder.glob("appmanifest_*.acf"):
                    try:
                        with open(acf_file, 'r', encoding='utf-8') as f:
                            content = f.read()
                            name_match = re.search(r'"name"\s+"([^"]+)"', content)
                            if name_match:
                                game_name = name_match.group(1)
                                self.steam_games.add(game_name.lower())
                    except Exception:
                        continue
    
    def _parse_epic_library(self):
        """Parse les manifests Epic Games"""
        epic_manifests = Path.home() / "AppData/Local/EpicGamesLauncher/Saved/Data/Manifests"
        
        if not epic_manifests.exists():
            return
        
        for manifest_file in epic_manifests.glob("*.item"):
            try:
                with open(manifest_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    game_name = data.get('DisplayName', '')
                    if game_name:
                        self.epic_games.add(game_name.lower())
            except Exception:
                continue
    
    def _scan_all_drives_for_games(self) -> List[Dict]:
        """Scanne TOUS les disques"""
        programs = []
        
        available_drives = [f"{d}:\\" for d in string.ascii_uppercase if os.path.exists(f"{d}:\\")]
        
        for drive in available_drives:
            self.progress.emit(f"Scan du disque {drive}...")
            
            game_folders = [
                Path(drive) / "Program Files (x86)/Steam/steamapps/common",
                Path(drive) / "Program Files/Steam/steamapps/common",
                Path(drive) / "Program Files/Epic Games",
                Path(drive) / "Games",
                Path(drive) / "Jeux",
            ]
            
            for folder in game_folders:
                if not folder.exists():
                    continue
                
                try:
                    for game_dir in folder.iterdir():
                        if not game_dir.is_dir():
                            continue
                        
                        exe_files = list(game_dir.glob("*.exe"))
                        if exe_files:
                            if self._looks_like_game_folder(game_dir):
                                main_exe = self._find_main_exe(exe_files, game_dir)
                                
                                programs.append({
                                    'name': game_dir.name,
                                    'path': str(main_exe),
                                    'publisher': "Inconnu",
                                    'version': "N/A",
                                    'install_date': "N/A",
                                    'type': 'game'
                                })
                except Exception:
                    continue
            
            try:
                for item in Path(drive).iterdir():
                    if not item.is_dir():
                        continue
                    
                    if item.name.lower() in ['windows', 'program files', 'program files (x86)', 
                                             'programdata', '$recycle.bin', 'system volume information']:
                        continue
                    
                    if self._looks_like_game_folder(item):
                        exe_files = list(item.glob("*.exe"))
                        if exe_files:
                            main_exe = self._find_main_exe(exe_files, item)
                            
                            programs.append({
                                'name': item.name,
                                'path': str(main_exe),
                                'publisher': "Inconnu",
                                'version': "N/A",
                                'install_date': "N/A",
                                'type': 'game'
                            })
            except Exception:
                continue
        
        return programs
    
    def _looks_like_game_folder(self, folder: Path) -> bool:
        """Vérifie si un dossier ressemble à un jeu"""
        game_indicators = [
            'data', 'assets', 'content', 'resources', 'textures',
            'sounds', 'music', 'models', 'levels', 'maps',
            'bin', 'game', 'engine', 'plugins', 'mods'
        ]
        
        try:
            subfolder_names = [f.name.lower() for f in folder.iterdir() if f.is_dir()]
            matches = sum(1 for indicator in game_indicators if indicator in subfolder_names)
            return matches >= 2
        except Exception:
            return False
    
    def _find_main_exe(self, exe_files: List[Path], folder: Path) -> Path:
        """Trouve le .exe principal"""
        ignore_patterns = [
            'unins', 'uninst', 'uninstall', 'setup', 'install',
            'updater', 'update', 'launcher', 'crash', 'report',
            'config', 'settings', 'editor'
        ]
        
        filtered_exes = []
        for exe in exe_files:
            exe_name_lower = exe.stem.lower()
            if not any(pattern in exe_name_lower for pattern in ignore_patterns):
                filtered_exes.append(exe)
        
        if filtered_exes:
            folder_name_lower = folder.name.lower()
            for exe in filtered_exes:
                if exe.stem.lower() in folder_name_lower or folder_name_lower in exe.stem.lower():
                    return exe
            return filtered_exes[0]
        
        return exe_files[0]
    
    def _scan_custom_folders(self) -> List[Dict]:
        """Scanne les dossiers custom"""
        programs = []
        
        for folder_path in self.custom_folders:
            folder = Path(folder_path)
            if not folder.exists() or not folder.is_dir():
                continue
            
            exe_files = list(folder.glob("*.exe"))
            if exe_files:
                main_exe = self._find_main_exe(exe_files, folder)
                
                programs.append({
                    'name': folder.name,
                    'path': str(main_exe),
                    'publisher': "Custom",
                    'version': "N/A",
                    'install_date': "N/A",
                    'type': 'game'
                })
        
        return programs
    
    def _scan_registry(self) -> List[Dict]:
        """Scanne le registre Windows"""
        programs = []
        registry_paths = [
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
            (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
        ]
        
        for hkey, path in registry_paths:
            try:
                key = winreg.OpenKey(hkey, path)
                for i in range(winreg.QueryInfoKey(key)[0]):
                    try:
                        subkey_name = winreg.EnumKey(key, i)
                        subkey = winreg.OpenKey(key, subkey_name)
                        
                        name = self._read_registry_value(subkey, "DisplayName")
                        exe_path = self._read_registry_value(subkey, "DisplayIcon") or \
                                  self._read_registry_value(subkey, "InstallLocation")
                        publisher = self._read_registry_value(subkey, "Publisher")
                        version = self._read_registry_value(subkey, "DisplayVersion")
                        install_date = self._read_registry_value(subkey, "InstallDate")
                        
                        if name and exe_path:
                            exe_path = self._fix_ico_path(exe_path)
                            prog_type = self._determine_type(name, exe_path, publisher)
                            
                            programs.append({
                                'name': name,
                                'path': exe_path,
                                'publisher': publisher or "Inconnu",
                                'version': version or "N/A",
                                'install_date': self._format_date(install_date),
                                'type': prog_type
                            })
                        
                        winreg.CloseKey(subkey)
                    except Exception:
                        continue
                winreg.CloseKey(key)
            except Exception:
                continue
        
        return programs
    
    def _fix_ico_path(self, path: str) -> str:
        """Corrige un chemin .ico"""
        path = path.strip('"').split(',')[0]
        
        if path.lower().endswith('.ico'):
            ico_path = Path(path)
            if ico_path.exists():
                folder = ico_path.parent
                exe_name = ico_path.stem + ".exe"
                exe_path = folder / exe_name
                
                if exe_path.exists():
                    return str(exe_path)
                
                exe_files = list(folder.glob("*.exe"))
                if exe_files:
                    return str(exe_files[0])
        
        return path
    
    def _determine_type(self, name: str, path: str, publisher: str) -> str:
        """Détermine le type"""
        name_lower = name.lower()
        publisher_lower = (publisher or "").lower()
        path_lower = path.lower()
        
        strict_blacklist = [
            'redistributable', 'runtime', 'redist', 'vcredist', 'directx',
            'net framework', '.net', 'java', 'jre', 'jdk',
            'editor', 'pdf', 'reader', 'viewer', 'player',
            'tweaker', 'optimizer', 'cleaner', 'booster', 'tuner',
            'driver', 'update', 'utility', 'tool', 'helper',
            'antivirus', 'security', 'firewall', 'backup',
            'uninstall', 'setup', 'installer',
            'browser', 'chrome', 'firefox', 'edge', 'opera',
            'outlook', 'thunderbird', 'mail',
            'office', 'word', 'excel', 'powerpoint', 'onenote',
            'visual studio', 'python', 'node', 'npm', 'git',
            'compiler', 'debugger', 'sdk'
        ]
        
        if any(black in name_lower or black in publisher_lower for black in strict_blacklist):
            return 'app'
        
        if name_lower in self.steam_games or name_lower in self.epic_games:
            return 'game'
        
        game_path_keywords = ['steam', 'epic', 'games', 'ubisoft', 'ea', 'riot', 
                              'blizzard', 'rockstar', 'gog']
        if any(keyword in path_lower for keyword in game_path_keywords):
            return 'game'
        
        game_publishers = ['valve', 'ubisoft', 'electronic arts', 'ea games', 'riot', 
                          'blizzard', 'rockstar', 'bethesda', 'square enix', '2k games',
                          'sega', 'capcom', 'cd projekt', 'activision', 'take-two',
                          'bandai', 'namco', 'konami', 'fromsoft', 'fromsoftware']
        if any(pub in publisher_lower for pub in game_publishers):
            return 'game'
        
        game_name_keywords = ['game', 'launcher', 'client']
        if any(keyword in name_lower for keyword in game_name_keywords):
            return 'game'
        
        return 'app'
    
    def _format_date(self, date_str: Optional[str]) -> str:
        """Formate une date"""
        if not date_str or date_str == "N/A":
            return "N/A"
        
        try:
            if len(date_str) == 8:
                year = date_str[0:4]
                month = date_str[4:6]
                day = date_str[6:8]
                return f"{day}/{month}/{year}"
        except Exception:
            pass
        
        return date_str
    
    def _read_registry_value(self, key, value_name: str) -> Optional[str]:
        """Lit une valeur du registre"""
        try:
            value, _ = winreg.QueryValueEx(key, value_name)
            return str(value) if value else None
        except Exception:
            return None
    
    def _deduplicate(self, programs: List[Dict]) -> List[Dict]:
        """Supprime les doublons"""
        seen = set()
        unique = []
        
        for prog in programs:
            key = (prog['name'].lower(), prog['path'].lower())
            if key not in seen:
                seen.add(key)
                unique.append(prog)
        
        return unique


class ClaudeLauncher(QMainWindow):
    """Fenêtre principale"""
    
    def __init__(self):
        super().__init__()
        self.programs = []
        self.current_program = None
        self.custom_folders = self._load_custom_folders()
        self.user_overrides = self._load_overrides()
        self.custom_exes = self._load_custom_exes()
        self.custom_args = self._load_custom_args()
        self.favorites = self._load_favorites()
        self.launch_stats = self._load_launch_stats()
        self.custom_tab_names = self._load_custom_tab_names()
        self.custom_program_names = self._load_custom_program_names()
        self.steamgrid_api_key = self._load_api_key()  # NOUVEAU V6
        self.active_downloaders = []  # NOUVEAU V6 - garder référence des threads
        self.hidden_programs = self._load_hidden_programs()  # NOUVEAU V6.4
        self.last_tab_index = self._load_last_tab()  # NOUVEAU V7.0
        self.custom_tags = self._load_custom_tags()  # NOUVEAU V7.0
        self.custom_images = self._load_custom_images()  # NOUVEAU V7.0
        self.bundled_images = self._scan_bundled_images()  # NOUVEAU V8.0 - images locales
        self.carousel_timer = QTimer()  # NOUVEAU V7.0
        self.carousel_timer.timeout.connect(self._show_next_carousel_image)
        self.carousel_index = 0
        self.carousel_pixmaps = []
        self.carousel_active = False
        self.active_custom_downloaders = []
        self.init_ui()
        self.scan_programs()
    
    def _load_custom_folders(self) -> List[str]:
        """Charge les dossiers custom"""
        custom_file = Path.home() / ".claudelauncher" / "custom_folders.json"
        if custom_file.exists():
            try:
                with open(custom_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return []
    
    def _save_custom_folders(self):
        """Sauvegarde les dossiers custom"""
        custom_file = Path.home() / ".claudelauncher" / "custom_folders.json"
        custom_file.parent.mkdir(parents=True, exist_ok=True)
        with open(custom_file, 'w', encoding='utf-8') as f:
            json.dump(self.custom_folders, f, indent=2)
    
    def _load_overrides(self) -> Dict[str, str]:
        """Charge les overrides"""
        override_file = Path.home() / ".claudelauncher" / "overrides.json"
        if override_file.exists():
            try:
                with open(override_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}
    
    def _save_overrides(self):
        """Sauvegarde les overrides"""
        override_file = Path.home() / ".claudelauncher" / "overrides.json"
        override_file.parent.mkdir(parents=True, exist_ok=True)
        with open(override_file, 'w', encoding='utf-8') as f:
            json.dump(self.user_overrides, f, indent=2)
    
    def _load_custom_exes(self) -> Dict[str, str]:
        """Charge les chemins exe modifiés"""
        exe_file = Path.home() / ".claudelauncher" / "custom_exes.json"
        if exe_file.exists():
            try:
                with open(exe_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}
    
    def _save_custom_exes(self):
        """Sauvegarde les chemins exe"""
        exe_file = Path.home() / ".claudelauncher" / "custom_exes.json"
        exe_file.parent.mkdir(parents=True, exist_ok=True)
        with open(exe_file, 'w', encoding='utf-8') as f:
            json.dump(self.custom_exes, f, indent=2)
    
    def _load_custom_args(self) -> Dict[str, str]:
        """Charge les arguments custom"""
        args_file = Path.home() / ".claudelauncher" / "custom_args.json"
        if args_file.exists():
            try:
                with open(args_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}
    
    def _save_custom_args(self):
        """Sauvegarde les arguments"""
        args_file = Path.home() / ".claudelauncher" / "custom_args.json"
        args_file.parent.mkdir(parents=True, exist_ok=True)
        with open(args_file, 'w', encoding='utf-8') as f:
            json.dump(self.custom_args, f, indent=2)
    
    def _load_favorites(self) -> Set[str]:
        """Charge les favoris"""
        fav_file = Path.home() / ".claudelauncher" / "favorites.json"
        if fav_file.exists():
            try:
                with open(fav_file, 'r', encoding='utf-8') as f:
                    return set(json.load(f))
            except Exception:
                pass
        return set()
    
    def _save_favorites(self):
        """Sauvegarde les favoris"""
        fav_file = Path.home() / ".claudelauncher" / "favorites.json"
        fav_file.parent.mkdir(parents=True, exist_ok=True)
        with open(fav_file, 'w', encoding='utf-8') as f:
            json.dump(list(self.favorites), f, indent=2)
    
    def _load_launch_stats(self) -> Dict[str, int]:
        """Charge les stats de lancement"""
        stats_file = Path.home() / ".claudelauncher" / "launch_stats.json"
        if stats_file.exists():
            try:
                with open(stats_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}
    
    def _save_launch_stats(self):
        """Sauvegarde les stats"""
        stats_file = Path.home() / ".claudelauncher" / "launch_stats.json"
        stats_file.parent.mkdir(parents=True, exist_ok=True)
        with open(stats_file, 'w', encoding='utf-8') as f:
            json.dump(self.launch_stats, f, indent=2)
    
    def _load_custom_tab_names(self) -> Dict[str, str]:
        """Charge les noms personnalisés des onglets"""
        tab_file = Path.home() / ".claudelauncher" / "custom_tab_names.json"
        if tab_file.exists():
            try:
                with open(tab_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}
    
    def _save_custom_tab_names(self):
        """Sauvegarde les noms personnalisés des onglets"""
        tab_file = Path.home() / ".claudelauncher" / "custom_tab_names.json"
        tab_file.parent.mkdir(parents=True, exist_ok=True)
        with open(tab_file, 'w', encoding='utf-8') as f:
            json.dump(self.custom_tab_names, f, indent=2)
    
    def _load_custom_program_names(self) -> Dict[str, str]:
        """Charge les noms personnalisés des programmes"""
        prog_file = Path.home() / ".claudelauncher" / "custom_program_names.json"
        if prog_file.exists():
            try:
                with open(prog_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}
    
    def _save_custom_program_names(self):
        """Sauvegarde les noms personnalisés des programmes"""
        prog_file = Path.home() / ".claudelauncher" / "custom_program_names.json"
        prog_file.parent.mkdir(parents=True, exist_ok=True)
        with open(prog_file, 'w', encoding='utf-8') as f:
            json.dump(self.custom_program_names, f, indent=2)
    
    def _load_api_key(self) -> Optional[str]:
        """Charge la clé API SteamGridDB"""
        api_file = Path.home() / ".claudelauncher" / "api_keys.json"
        if api_file.exists():
            try:
                with open(api_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    return data.get('steamgriddb')
            except Exception:
                pass
        return None
    
    def _load_hidden_programs(self) -> Set[str]:
        """Charge les programmes masqués"""
        hidden_file = Path.home() / ".claudelauncher" / "hidden_programs.json"
        if hidden_file.exists():
            try:
                with open(hidden_file, 'r', encoding='utf-8') as f:
                    return set(json.load(f))
            except Exception:
                pass
        return set()
    
    def _save_hidden_programs(self):
        """Sauvegarde les programmes masqués"""
        hidden_file = Path.home() / ".claudelauncher" / "hidden_programs.json"
        hidden_file.parent.mkdir(parents=True, exist_ok=True)
        with open(hidden_file, 'w', encoding='utf-8') as f:
            json.dump(list(self.hidden_programs), f, indent=2)
    
    # === V7.0: Last tab persistence ===
    def _load_last_tab(self) -> int:
        tab_file = Path.home() / ".claudelauncher" / "last_tab.json"
        if tab_file.exists():
            try:
                with open(tab_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    return data.get('last_tab_index', 0)
            except Exception:
                pass
        return 0

    def _save_last_tab(self):
        tab_file = Path.home() / ".claudelauncher" / "last_tab.json"
        tab_file.parent.mkdir(parents=True, exist_ok=True)
        with open(tab_file, 'w', encoding='utf-8') as f:
            json.dump({'last_tab_index': self.last_tab_index}, f, indent=2)

    # === V7.0: Custom tags ===
    def _load_custom_tags(self) -> Dict[str, List[str]]:
        tags_file = Path.home() / ".claudelauncher" / "custom_tags.json"
        if tags_file.exists():
            try:
                with open(tags_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _save_custom_tags(self):
        tags_file = Path.home() / ".claudelauncher" / "custom_tags.json"
        tags_file.parent.mkdir(parents=True, exist_ok=True)
        with open(tags_file, 'w', encoding='utf-8') as f:
            json.dump(self.custom_tags, f, indent=2, ensure_ascii=False)

    # === V7.0: Custom images ===
    def _load_custom_images(self) -> Dict:
        images_file = Path.home() / ".claudelauncher" / "custom_images.json"
        if images_file.exists():
            try:
                with open(images_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _save_custom_images(self):
        images_file = Path.home() / ".claudelauncher" / "custom_images.json"
        images_file.parent.mkdir(parents=True, exist_ok=True)
        with open(images_file, 'w', encoding='utf-8') as f:
            json.dump(self.custom_images, f, indent=2, ensure_ascii=False)

    # === V8.0: Bundled images (dossier images/) ===
    def _scan_bundled_images(self) -> Dict[str, list]:
        """Scanne le dossier images/ et construit un index nom → chemins d'images.

        Utilise manifest.json pour indexer aussi par nom réel du jeu/app
        (ex: dossier 'Grinn' indexé aussi sous 'skyrim special edition').
        """
        images_dir = Path(__file__).parent / "images"
        bundled = {}
        if not images_dir.exists():
            return bundled

        # Charger le manifest pour les noms réels
        manifest_path = images_dir / "manifest.json"
        manifest = {}
        if manifest_path.exists():
            try:
                with open(manifest_path, 'r', encoding='utf-8') as f:
                    manifest = json.load(f)
            except Exception:
                pass

        for folder in images_dir.iterdir():
            if not folder.is_dir():
                continue
            images = sorted([
                str(f) for f in folder.iterdir()
                if f.suffix.lower() in ('.jpg', '.jpeg', '.png', '.bmp', '.webp')
            ])
            if not images:
                continue

            folder_name = folder.name
            # Indexer par nom de dossier (lowercase)
            bundled[folder_name.lower()] = images

            # Indexer aussi par real_name depuis le manifest
            entry = manifest.get(folder_name, {})
            real_name = entry.get("real_name", "")
            if real_name:
                # Extraire le nom principal (avant parenthèses)
                core_name = re.sub(r'\s*\(.*?\)', '', real_name).strip()
                core_lower = core_name.lower()
                if core_lower != folder_name.lower() and core_lower not in bundled:
                    bundled[core_lower] = images

        print(f"[Bundled Images] {len(bundled)} entrées indexées depuis {images_dir}")
        return bundled

    def _find_bundled_images(self, prog_key: str) -> list:
        """Trouve les images bundled pour un programme par matching intelligent.

        Stratégies de matching (en ordre de priorité) :
        1. Match exact (case-insensitive)
        2. Le nom du dossier est un préfixe du nom du programme
        3. Tous les mots du dossier sont présents dans le nom du programme
        """
        if not self.bundled_images:
            return []

        # 1. Match exact
        if prog_key in self.bundled_images:
            return self.bundled_images[prog_key]

        # 2 & 3. Matching par préfixe et mots communs
        best_match = None
        best_score = 0

        for folder_key, images in self.bundled_images.items():
            score = 0

            # Préfixe : le programme commence par le nom du dossier
            if prog_key.startswith(folder_key + " ") or prog_key.startswith(folder_key + "-"):
                score = len(folder_key) * 2  # pondérer par longueur du match

            # Mots communs : tous les mots du dossier sont dans le nom du programme
            if score == 0:
                folder_words = set(folder_key.replace('-', ' ').replace(':', '').split())
                prog_words = set(prog_key.replace('-', ' ').replace(':', '').split())
                if folder_words and len(folder_words) >= 2 and folder_words.issubset(prog_words):
                    score = len(folder_words)

            if score > best_score:
                best_score = score
                best_match = images

        return best_match or []

    def _start_bundled_carousel(self, prog_key: str, image_paths: list):
        """Démarre le carrousel avec les images bundled du dossier images/"""
        self._stop_carousel()
        self.carousel_pixmaps = []
        self.carousel_index = 0
        self.carousel_active = True

        for path in image_paths:
            pixmap = QPixmap(path)
            if not pixmap.isNull():
                self.carousel_pixmaps.append(pixmap)

        if self.carousel_pixmaps:
            self._display_carousel_pixmap(self.carousel_pixmaps[0])
            if len(self.carousel_pixmaps) > 1:
                self.carousel_timer.start(5000)  # 5 secondes par défaut

    def _increment_launch_count(self, prog_name: str):
        """Incrémente le compteur de lancement"""
        prog_key = prog_name.lower()
        self.launch_stats[prog_key] = self.launch_stats.get(prog_key, 0) + 1
        self._save_launch_stats()
        self.populate_most_used()
    
    def init_ui(self):
        """Initialise l'interface"""
        self.setWindowTitle("ClaudeLauncher V7.0 🏷️")
        self.setMinimumSize(1200, 700)
        
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        
        # Boutons
        buttons_layout = QHBoxLayout()
        
        refresh_btn = QPushButton("🔄 Rafraîchir")
        refresh_btn.clicked.connect(self.scan_programs)
        refresh_btn.setMaximumWidth(150)
        buttons_layout.addWidget(refresh_btn)
        
        add_folder_btn = QPushButton("📁 Ajouter un dossier")
        add_folder_btn.clicked.connect(self.add_custom_folder)
        add_folder_btn.setMaximumWidth(180)
        buttons_layout.addWidget(add_folder_btn)
        
        # NOUVEAU V6: Bouton pour ajouter clé API
        api_btn = QPushButton("🔑 Clé API SteamGridDB")
        api_btn.clicked.connect(self.set_api_key)
        api_btn.setMaximumWidth(200)
        buttons_layout.addWidget(api_btn)
        
        buttons_layout.addStretch()
        
        # Afficher si clé API présente
        self.api_status_label = QLabel()
        self._update_api_status()
        buttons_layout.addWidget(self.api_status_label)
        
        # Créer un widget conteneur pour les boutons avec hauteur fixe
        buttons_widget = QWidget()
        buttons_widget.setLayout(buttons_layout)
        buttons_widget.setMaximumHeight(60)  # V6.4: Hauteur fixe !
        
        main_layout.addWidget(buttons_widget)
        
        # Splitter
        splitter = QSplitter(Qt.Orientation.Horizontal)
        
        # === PARTIE GAUCHE ===
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        
        # V7.0: Barre de recherche
        self.search_bar = QLineEdit()
        self.search_bar.setPlaceholderText("🔍 Rechercher par nom ou tag...")
        self.search_bar.setClearButtonEnabled(True)
        self.search_bar.textChanged.connect(self._filter_lists)
        self.search_bar.setStyleSheet("""
            QLineEdit {
                background-color: #2a2a2a;
                color: #ffffff;
                border: 1px solid #444;
                border-radius: 5px;
                padding: 6px 10px;
                font-size: 11pt;
            }
            QLineEdit:focus {
                border: 1px solid #0078d4;
            }
        """)
        left_layout.addWidget(self.search_bar)

        self.tabs = QTabWidget()
        self.tabs.tabBarDoubleClicked.connect(self.rename_tab)

        # Onglet Jeux
        self.games_list = QListWidget()
        self.games_list.itemDoubleClicked.connect(self.launch_program)
        self.games_list.itemClicked.connect(self.show_program_info)
        self.games_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.games_list.customContextMenuRequested.connect(self.show_context_menu)
        tab_name = self.custom_tab_names.get('games', "🎮 Jeux")
        self.tabs.addTab(self.games_list, tab_name)
        
        # Onglet Applications
        self.apps_list = QListWidget()
        self.apps_list.itemDoubleClicked.connect(self.launch_program)
        self.apps_list.itemClicked.connect(self.show_program_info)
        self.apps_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.apps_list.customContextMenuRequested.connect(self.show_context_menu)
        tab_name = self.custom_tab_names.get('apps', "📦 Applications")
        self.tabs.addTab(self.apps_list, tab_name)
        
        # Onglet Favoris
        self.favorites_list = QListWidget()
        self.favorites_list.itemDoubleClicked.connect(self.launch_program)
        self.favorites_list.itemClicked.connect(self.show_program_info)
        self.favorites_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.favorites_list.customContextMenuRequested.connect(self.show_context_menu)
        tab_name = self.custom_tab_names.get('favorites', "⭐ Favoris")
        self.tabs.addTab(self.favorites_list, tab_name)
        
        # Onglet Plus utilisés
        self.most_used_list = QListWidget()
        self.most_used_list.itemDoubleClicked.connect(self.launch_program)
        self.most_used_list.itemClicked.connect(self.show_program_info)
        self.most_used_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.most_used_list.customContextMenuRequested.connect(self.show_context_menu)
        tab_name = self.custom_tab_names.get('most_used', "🔥 Plus utilisés")
        self.tabs.addTab(self.most_used_list, tab_name)

        self.tabs.currentChanged.connect(self._on_tab_changed)  # V7.0 - après création des 4 onglets

        left_layout.addWidget(self.tabs)
        left_widget.setMinimumWidth(300)
        left_widget.setMaximumWidth(400)
        
        # === PARTIE DROITE ===
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(20, 10, 20, 20)
        
        # Titre
        self.title_label = QLabel("Sélectionnez un programme")
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        self.title_label.setFont(title_font)
        self.title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.title_label.setMaximumHeight(40)
        right_layout.addWidget(self.title_label)
        
        # Image (AMÉLIORÉE V6)
        self.image_label = QLabel()
        self.image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_label.setMinimumSize(600, 300)
        self.image_label.setText("🖼️ Sélectionnez un jeu")
        self.image_label.setWordWrap(True)
        self.image_label.setScaledContents(False)  # Pas de scaling auto
        self.image_label.setStyleSheet("""
            QLabel {
                background-color: #1a1a1a;
                border-radius: 10px;
                color: #888888;
                font-size: 14pt;
                padding: 20px;
            }
        """)
        right_layout.addWidget(self.image_label, stretch=10)  # V6.4: Stretch élevé !
        
        # Boutons d'édition
        edit_layout = QHBoxLayout()
        
        self.edit_exe_btn = QPushButton("✏️ Modifier l'exécutable")
        self.edit_exe_btn.clicked.connect(self.edit_executable)
        self.edit_exe_btn.setEnabled(False)
        edit_layout.addWidget(self.edit_exe_btn)
        
        self.edit_args_btn = QPushButton("⚙️ Arguments")
        self.edit_args_btn.clicked.connect(self.edit_arguments)
        self.edit_args_btn.setEnabled(False)
        edit_layout.addWidget(self.edit_args_btn)
        
        right_layout.addLayout(edit_layout)
        
        # Infos
        self.info_text = QTextEdit()
        self.info_text.setReadOnly(True)
        self.info_text.setMinimumHeight(180)
        self.info_text.setStyleSheet("""
            QTextEdit {
                background-color: #2a2a2a;
                color: #ffffff;
                border: none;
                border-radius: 5px;
                padding: 10px;
                font-size: 11pt;
            }
        """)
        right_layout.addWidget(self.info_text, stretch=1)
        
        splitter.addWidget(left_widget)
        splitter.addWidget(right_widget)
        splitter.setStretchFactor(1, 3)
        
        main_layout.addWidget(splitter)
        
        # Style
        self.setStyleSheet("""
            QMainWindow {
                background-color: #1a1a1a;
            }
            QWidget {
                background-color: #1a1a1a;
                color: #ffffff;
            }
            QListWidget {
                background-color: #2a2a2a;
                border: none;
                padding: 5px;
                font-size: 11pt;
                alternate-background-color: #252525;
            }
            QListWidget::item {
                padding: 8px;
                border-radius: 5px;
            }
            QListWidget::item:hover {
                background-color: #3a3a3a;
            }
            QListWidget::item:selected {
                background-color: #0078d4;
            }
            QTabWidget::pane {
                border: none;
                background-color: #1a1a1a;
            }
            QTabBar::tab {
                background-color: #2a2a2a;
                color: #ffffff;
                padding: 10px 20px;
                margin-right: 2px;
            }
            QTabBar::tab:selected {
                background-color: #0078d4;
            }
            QPushButton {
                background-color: #0078d4;
                color: white;
                border: none;
                padding: 10px;
                border-radius: 5px;
                font-size: 11pt;
            }
            QPushButton:hover {
                background-color: #0086f0;
            }
            QPushButton:disabled {
                background-color: #444444;
                color: #888888;
            }
        """)
        
        # Activer zebra striping
        self.games_list.setAlternatingRowColors(True)
        self.apps_list.setAlternatingRowColors(True)
        self.favorites_list.setAlternatingRowColors(True)
        self.most_used_list.setAlternatingRowColors(True)

        # V7.0: Restaurer le dernier onglet
        if 0 <= self.last_tab_index < self.tabs.count():
            self.tabs.setCurrentIndex(self.last_tab_index)
    
    def _update_api_status(self):
        """Met à jour le statut de la clé API"""
        if self.steamgrid_api_key:
            self.api_status_label.setText("✅ API")
            self.api_status_label.setStyleSheet("color: #00ff00;")
        else:
            self.api_status_label.setText("❌ Pas de clé API")
            self.api_status_label.setStyleSheet("color: #ff8800;")
    
    def set_api_key(self):
        """Permet d'ajouter/modifier la clé API SteamGridDB"""
        text, ok = QInputDialog.getText(
            self,
            "Clé API SteamGridDB",
            "Pour obtenir une clé API gratuite :\n"
            "1. Va sur https://www.steamgriddb.com/\n"
            "2. Crée un compte (gratuit)\n"
            "3. Va dans Profile → Preferences → API\n"
            "4. Génère une clé et colle-la ici :\n",
            QLineEdit.EchoMode.Normal,
            self.steamgrid_api_key or ""
        )
        
        if ok and text.strip():
            # Tester la clé avant de la sauvegarder
            print(f"\n[SteamGridDB] Test de la clé API...")
            if self._test_api_key(text.strip()):
                # Sauvegarder la clé
                api_file = Path.home() / ".claudelauncher" / "api_keys.json"
                api_file.parent.mkdir(parents=True, exist_ok=True)
                
                with open(api_file, 'w', encoding='utf-8') as f:
                    json.dump({'steamgriddb': text.strip()}, f, indent=2)
                
                self.steamgrid_api_key = text.strip()
                self._update_api_status()
                
                QMessageBox.information(
                    self,
                    "Clé API ajoutée",
                    "✅ Clé API SteamGridDB validée et sauvegardée !\n\n"
                    "Les images des jeux seront maintenant téléchargées automatiquement."
                )
            else:
                QMessageBox.warning(
                    self,
                    "Clé API invalide",
                    "❌ La clé API ne fonctionne pas.\n\n"
                    "Vérifications :\n"
                    "• La clé est-elle complète ?\n"
                    "• As-tu bien copié toute la clé ?\n"
                    "• Regarde les logs dans la console pour plus de détails."
                )
    
    def _test_api_key(self, api_key: str) -> bool:
        """Teste si la clé API fonctionne"""
        if not REQUESTS_AVAILABLE:
            print("[SteamGridDB] Module 'requests' non disponible")
            return False
        
        try:
            headers = {"Authorization": f"Bearer {api_key}"}
            
            # Tester avec une recherche simple - IMPORTANT: terme dans le PATH
            search_term = quote("Skyrim")
            search_url = f"https://www.steamgriddb.com/api/v2/search/autocomplete/{search_term}"
            
            print(f"[SteamGridDB] Test URL: {search_url}")
            print(f"[SteamGridDB] Test avec: Skyrim")
            
            response = requests.get(search_url, headers=headers, timeout=10)
            
            print(f"[SteamGridDB] Status: {response.status_code}")
            
            if response.status_code == 200:
                results = response.json().get('data', [])
                print(f"[SteamGridDB] ✅ Clé valide ! Trouvé {len(results)} résultat(s)")
                return True
            elif response.status_code == 401 or response.status_code == 403:
                print(f"[SteamGridDB] ❌ Clé invalide (status {response.status_code})")
                print(f"[SteamGridDB] Réponse: {response.text[:200]}")
                return False
            else:
                print(f"[SteamGridDB] ⚠️ Status inattendu: {response.status_code}")
                print(f"[SteamGridDB] Réponse: {response.text[:200]}")
                # On considère que c'est OK si ce n'est pas une erreur d'auth
                return response.status_code < 500
                
        except Exception as e:
            print(f"[SteamGridDB] Erreur test API: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def add_custom_folder(self):
        """Ajoute un dossier custom"""
        folder = QFileDialog.getExistingDirectory(self, "Sélectionner un dossier de jeu")
        
        if folder and folder not in self.custom_folders:
            self.custom_folders.append(folder)
            self._save_custom_folders()
            self.scan_programs()
    
    def rename_tab(self, index: int):
        """Renomme un onglet"""
        if index == -1:
            return
        
        tab_keys = ['games', 'apps', 'favorites', 'most_used']
        if index >= len(tab_keys):
            return
        
        tab_key = tab_keys[index]
        current_name = self.tabs.tabText(index)
        
        text, ok = QInputDialog.getText(
            self,
            "Renommer l'onglet",
            f"Nouveau nom pour '{current_name}' :",
            QLineEdit.EchoMode.Normal,
            current_name
        )
        
        if ok and text.strip():
            self.custom_tab_names[tab_key] = text.strip()
            self._save_custom_tab_names()
            self.tabs.setTabText(index, text.strip())
            self.title_label.setText(f"✅ Onglet renommé: {text.strip()}")
    
    def edit_executable(self):
        """Modifie l'exécutable"""
        if not self.current_program:
            return
        
        exe_file, _ = QFileDialog.getOpenFileName(
            self,
            "Sélectionner l'exécutable",
            os.path.dirname(self.current_program['path']),
            "Exécutables (*.exe)"
        )
        
        if exe_file:
            prog_name = self.current_program['name'].lower()
            self.custom_exes[prog_name] = exe_file
            self._save_custom_exes()
            self.current_program['path'] = exe_file

            # Propager dans self.programs (comme force_category)
            for p in self.programs:
                if p['name'].lower() == prog_name:
                    p['path'] = exe_file
                    break

            # Mettre à jour les items dans toutes les listes
            for list_widget in [self.games_list, self.apps_list, self.favorites_list, self.most_used_list]:
                for i in range(list_widget.count()):
                    item = list_widget.item(i)
                    item_prog = item.data(Qt.ItemDataRole.UserRole)
                    if item_prog and item_prog.get('name', '').lower() == prog_name:
                        item_prog['path'] = exe_file

            self.show_program_info_direct(self.current_program)
            self.title_label.setText(f"✅ Exe modifié: {os.path.basename(exe_file)}")
    
    def edit_arguments(self):
        """Modifie les arguments"""
        if not self.current_program:
            return
        
        prog_name = self.current_program['name'].lower()
        current_args = self.custom_args.get(prog_name, "")
        
        text, ok = QInputDialog.getText(
            self,
            "Arguments de lancement",
            f"Arguments pour {self.current_program['name']}:\n\n"
            "Exemples:\n"
            "- MO2: --profile \"MonProfile\" --executable \"skse64_loader.exe\"\n"
            "- Steam: -applaunch 377160\n",
            QLineEdit.EchoMode.Normal,
            current_args
        )
        
        if ok:
            if text.strip():
                self.custom_args[prog_name] = text.strip()
            elif prog_name in self.custom_args:
                del self.custom_args[prog_name]
            
            self._save_custom_args()
            self.show_program_info_direct(self.current_program)
            self.title_label.setText("✅ Arguments sauvegardés")
    
    def show_context_menu(self, position):
        """Menu contextuel"""
        sender = self.sender()
        item = sender.itemAt(position)
        
        if not item:
            return
        
        prog = item.data(Qt.ItemDataRole.UserRole)
        
        menu = QMenu()
        
        # Renommer
        rename_action = QAction("✏️ Renommer", self)
        rename_action.triggered.connect(lambda: self.rename_program(prog, item))
        menu.addAction(rename_action)
        
        menu.addSeparator()
        
        # Favoris
        prog_key = prog['name'].lower()
        if prog_key in self.favorites:
            remove_fav_action = QAction("⭐ Retirer des favoris", self)
            remove_fav_action.triggered.connect(lambda: self.toggle_favorite(prog))
            menu.addAction(remove_fav_action)
        else:
            add_fav_action = QAction("⭐ Ajouter aux favoris", self)
            add_fav_action.triggered.connect(lambda: self.toggle_favorite(prog))
            menu.addAction(add_fav_action)
        
        menu.addSeparator()
        
        # Catégorie
        if prog['type'] == 'game':
            force_app_action = QAction("📦 Forcer en Application", self)
            force_app_action.triggered.connect(lambda: self.force_category(prog, 'app'))
            menu.addAction(force_app_action)
        else:
            force_game_action = QAction("🎮 Forcer en Jeu", self)
            force_game_action.triggered.connect(lambda: self.force_category(prog, 'game'))
            menu.addAction(force_game_action)
        
        menu.addSeparator()
        
        # Édition
        edit_exe_action = QAction("✏️ Modifier l'exécutable", self)
        edit_exe_action.triggered.connect(lambda: self.edit_executable_for_prog(prog))
        menu.addAction(edit_exe_action)
        
        edit_args_action = QAction("⚙️ Modifier les arguments", self)
        edit_args_action.triggered.connect(lambda: self.edit_arguments_for_prog(prog))
        menu.addAction(edit_args_action)
        
        menu.addSeparator()

        # NOUVEAU V7.0: Tags
        tags_action = QAction("🏷️ Gérer les tags", self)
        tags_action.triggered.connect(lambda: self.manage_tags(prog))
        menu.addAction(tags_action)

        # NOUVEAU V7.0: Images personnalisées
        images_action = QAction("🖼️ Gérer les images", self)
        images_action.triggered.connect(lambda: self.manage_custom_images(prog))
        menu.addAction(images_action)

        menu.addSeparator()

        # NOUVEAU V6.4: Effacer (masquer)
        hide_action = QAction("🗑️ Effacer", self)
        hide_action.triggered.connect(lambda: self.hide_program(prog))
        menu.addAction(hide_action)
        
        menu.exec(sender.mapToGlobal(position))
    
    def rename_program(self, prog: Dict, item: QListWidgetItem):
        """Renomme un programme"""
        current_name = self.get_display_name(prog)
        
        text, ok = QInputDialog.getText(
            self,
            "Renommer le programme",
            f"Nouveau nom pour '{current_name}' :\n(Le nom original: {prog['name']})",
            QLineEdit.EchoMode.Normal,
            current_name
        )
        
        if ok and text.strip():
            prog_key = prog['name'].lower()
            if text.strip() != prog['name']:
                self.custom_program_names[prog_key] = text.strip()
            elif prog_key in self.custom_program_names:
                del self.custom_program_names[prog_key]
            
            self._save_custom_program_names()
            item.setText(text.strip())
            self.title_label.setText(f"✅ Renommé: {text.strip()}")
    
    def get_display_name(self, prog: Dict) -> str:
        """Retourne le nom à afficher"""
        prog_key = prog['name'].lower()
        return self.custom_program_names.get(prog_key, prog['name'])
    
    def toggle_favorite(self, prog: Dict):
        """Ajoute/retire des favoris"""
        prog_key = prog['name'].lower()
        if prog_key in self.favorites:
            self.favorites.remove(prog_key)
            msg = "Retiré des favoris"
        else:
            self.favorites.add(prog_key)
            msg = "Ajouté aux favoris"
        
        self._save_favorites()
        self.populate_favorites()
        self.title_label.setText(f"✅ {prog['name']} - {msg}")
    
    def edit_executable_for_prog(self, prog: Dict):
        """Modifie l'exe"""
        self.current_program = prog
        self.edit_executable()
    
    def edit_arguments_for_prog(self, prog: Dict):
        """Modifie les arguments"""
        self.current_program = prog
        self.edit_arguments()
    
    def hide_program(self, prog: Dict):
        """Masque un programme de ClaudeLauncher (V6.4)"""
        display_name = self.get_display_name(prog)
        
        reply = QMessageBox.question(
            self,
            "Masquer le programme",
            f"Voulez-vous masquer '{display_name}' de ClaudeLauncher ?\n\n"
            f"⚠️ Le programme ne sera PAS désinstallé de votre système.\n"
            f"Il sera juste caché de la liste.\n\n"
            f"Pour le faire réapparaître, supprimez :\n"
            f"~/.claudelauncher/hidden_programs.json",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.Yes:
            prog_key = prog['name'].lower()
            self.hidden_programs.add(prog_key)
            self._save_hidden_programs()
            
            # Retirer des favoris si présent
            if prog_key in self.favorites:
                self.favorites.remove(prog_key)
                self._save_favorites()
            
            # Retirer des stats si présent
            if prog_key in self.launch_stats:
                del self.launch_stats[prog_key]
                self._save_launch_stats()
            
            # Rafraîchir l'affichage
            self.populate_lists()
            self.title_label.setText(f"✅ {display_name} masqué")
    
    def force_category(self, prog: Dict, new_type: str):
        """Force une catégorie"""
        self.user_overrides[prog['name'].lower()] = new_type
        self._save_overrides()
        
        for p in self.programs:
            if p['name'].lower() == prog['name'].lower():
                p['type'] = new_type
                break
        
        prog['type'] = new_type
        self.populate_lists()
        
        category_name = 'Jeux' if new_type == 'game' else 'Applications'
        self.title_label.setText(f"✅ {prog['name']} → {category_name}")
    
    def scan_programs(self):
        """Lance le scan"""
        self.scanner = ProgramScanner(self.custom_folders)
        self.scanner.finished.connect(self.on_scan_finished)
        self.scanner.progress.connect(self.on_scan_progress)
        self.scanner.start()
        
        self.title_label.setText("Scan en cours...")
    
    def on_scan_progress(self, message: str):
        """Progression"""
        self.title_label.setText(message)
    
    def on_scan_finished(self, programs: List[Dict]):
        """Scan terminé"""
        for prog in programs:
            prog_name_lower = prog['name'].lower()
            if prog_name_lower in self.user_overrides:
                prog['type'] = self.user_overrides[prog_name_lower]
            if prog_name_lower in self.custom_exes:
                prog['path'] = self.custom_exes[prog_name_lower]
        
        self.programs = programs
        self.populate_lists()
        self._auto_select_first_item()  # V7.0

        games_count = sum(1 for p in programs if p['type'] == 'game')
        apps_count = sum(1 for p in programs if p['type'] == 'app')
        self.title_label.setText(f"✅ {games_count} jeux, {apps_count} applications")
    
    def populate_lists(self):
        """Remplit toutes les listes"""
        self.games_list.clear()
        self.apps_list.clear()
        
        for prog in sorted(self.programs, key=lambda x: x['name']):
            # V6.4: Filtrer les programmes masqués
            prog_key = prog['name'].lower()
            if prog_key in self.hidden_programs:
                continue
            
            display_name = self.get_display_name(prog)
            item = QListWidgetItem(display_name)
            item.setData(Qt.ItemDataRole.UserRole, prog)

            # V7.0: Tooltip avec tags
            tags = self.custom_tags.get(prog_key, [])
            if tags:
                item.setToolTip("Tags: " + ", ".join(tags))

            if prog['type'] == 'game':
                self.games_list.addItem(item)
            else:
                self.apps_list.addItem(item)

        self.populate_favorites()
        self.populate_most_used()
    
    def populate_favorites(self):
        """Remplit l'onglet Favoris"""
        self.favorites_list.clear()
        
        for prog in sorted(self.programs, key=lambda x: x['name']):
            prog_key = prog['name'].lower()
            # V6.4: Filtrer les programmes masqués
            if prog_key in self.hidden_programs:
                continue
            
            if prog_key in self.favorites:
                display_name = self.get_display_name(prog)
                item = QListWidgetItem(display_name)
                item.setData(Qt.ItemDataRole.UserRole, prog)
                self.favorites_list.addItem(item)
    
    def populate_most_used(self):
        """Remplit l'onglet Plus utilisés"""
        self.most_used_list.clear()
        
        sorted_stats = sorted(
            self.launch_stats.items(),
            key=lambda x: x[1],
            reverse=True
        )[:7]
        
        for prog_name_lower, count in sorted_stats:
            # V6.4: Filtrer les programmes masqués
            if prog_name_lower in self.hidden_programs:
                continue
            
            for prog in self.programs:
                if prog['name'].lower() == prog_name_lower:
                    display_name = self.get_display_name(prog)
                    item = QListWidgetItem(f"{display_name} ({count}x)")
                    item.setData(Qt.ItemDataRole.UserRole, prog)
                    self.most_used_list.addItem(item)
                    break
    
    def show_program_info(self, item: QListWidgetItem):
        """Affiche les infos"""
        prog = item.data(Qt.ItemDataRole.UserRole)
        self.show_program_info_direct(prog)
    
    def show_program_info_direct(self, prog: Dict):
        """Affiche les infos d'un programme"""
        try:
            self.current_program = prog
            self.edit_exe_btn.setEnabled(True)
            self.edit_args_btn.setEnabled(True)
            
            display_name = self.get_display_name(prog)
            self.title_label.setText(display_name)
            
            exe_exists = os.path.exists(prog['path'])
            exe_status = "✅" if exe_exists else "❌ Introuvable"
            
            prog_key = prog['name'].lower()
            args = self.custom_args.get(prog_key, "")
            args_display = f"<p><b>Arguments :</b> {args}</p>" if args else ""
            
            launch_count = self.launch_stats.get(prog_key, 0)
            is_favorite = "⭐ Favori" if prog_key in self.favorites else ""
            
            name_info = ""
            if display_name != prog['name']:
                name_info = f"<p><b>Nom original :</b> {prog['name']}</p>"
            
            # V7.0: Tags badges
            tags = self.custom_tags.get(prog_key, [])
            tags_html = ""
            if tags:
                tag_colors = ['#e74c3c', '#3498db', '#2ecc71', '#f39c12', '#9b59b6', '#1abc9c', '#e67e22', '#e84393']
                badges = ""
                for i, tag in enumerate(tags):
                    color = tag_colors[i % len(tag_colors)]
                    safe_tag = html.escape(tag)
                    badges += (
                        f'<span style="background-color: {color}; color: white; '
                        f'padding: 2px 8px; border-radius: 10px; font-size: 9pt; '
                        f'margin-right: 4px;">{safe_tag}</span> '
                    )
                tags_html = f"<p><b>Tags :</b> {badges}</p>"

            info_html = f"""
            {name_info}
            <p><b>Éditeur :</b> {prog['publisher']}</p>
            <p><b>Version :</b> {prog['version']}</p>
            <p><b>Date d'installation :</b> {prog['install_date']}</p>
            <p><b>Exécutable :</b> {exe_status}</p>
            <p style="font-size: 9pt; color: #aaa;">{prog['path']}</p>
            {args_display}
            <p><b>Lancements :</b> {launch_count}x {is_favorite}</p>
            <p><b>Type :</b> {'🎮 Jeu' if prog['type'] == 'game' else '📦 Application'}</p>
            {tags_html}
            <p style="color: #888;"><i>Clic droit: renommer, favoris, tags, images</i></p>
            """
            self.info_text.setHtml(info_html)

            # V7.0+V8.0: Priorité images : custom > bundled (images/) > SteamGridDB
            self._stop_carousel()
            if prog_key in self.custom_images and self.custom_images[prog_key].get('images'):
                self._start_carousel(prog_key)
            else:
                bundled = self._find_bundled_images(prog_key)
                if bundled:
                    self._start_bundled_carousel(prog_key, bundled)
                else:
                    # Comportement SteamGridDB original
                    self.load_game_image(display_name, prog['type'])
            
        except Exception as e:
            print(f"Erreur affichage infos: {e}")
            self.title_label.setText(prog.get('name', 'Erreur'))
            self.info_text.setPlainText(f"Erreur: {e}")
    
    def load_game_image(self, game_name: str, prog_type: str):
        """Charge l'image d'un jeu (V6 - VRAIES IMAGES !)"""
        try:
            # Afficher un placeholder en attendant
            self.image_label.clear()
            self.image_label.setText(f"⏳ Chargement de l'image...\n{game_name}")
            self.image_label.setStyleSheet("""
                QLabel {
                    background-color: #2a2a2a;
                    color: #888888;
                    border-radius: 10px;
                    font-size: 14pt;
                    padding: 20px;
                }
            """)
            
            # Ne télécharger que pour les jeux (pas les applications)
            if prog_type != 'game':
                self.image_label.setText(f"📦 {game_name}\n\n(Application)")
                return
            
            # Lancer le téléchargement
            downloader = ImageDownloader(game_name, self.steamgrid_api_key)
            downloader.image_downloaded.connect(self.on_image_downloaded)
            downloader.download_failed.connect(self.on_image_download_failed)
            downloader.start()
            
            # Garder une référence pour éviter le garbage collection
            self.active_downloaders.append(downloader)
            
        except Exception as e:
            print(f"Erreur load_game_image: {e}")
            self.image_label.setText(f"🖼️ {game_name}\n\n(Erreur)")
    
    def on_image_downloaded(self, game_name: str, image_data: bytes):
        """Appelé quand l'image est téléchargée"""
        try:
            # Vérifier que c'est toujours le jeu actuel
            if not self.current_program or self.get_display_name(self.current_program) != game_name:
                return
            
            # Créer le pixmap depuis les données
            pixmap = QPixmap()
            if pixmap.loadFromData(image_data):
                # Redimensionner pour s'adapter au label
                scaled_pixmap = pixmap.scaled(
                    self.image_label.size(),
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation
                )
                
                self.image_label.clear()
                self.image_label.setPixmap(scaled_pixmap)
                self.image_label.setStyleSheet("""
                    QLabel {
                        background-color: #1a1a1a;
                        border-radius: 10px;
                    }
                """)
            else:
                self.on_image_download_failed(game_name)
                
        except Exception as e:
            print(f"Erreur affichage image: {e}")
            self.on_image_download_failed(game_name)
    
    def on_image_download_failed(self, game_name: str):
        """Appelé si le téléchargement échoue"""
        try:
            # Vérifier que c'est toujours le jeu actuel
            if not self.current_program or self.get_display_name(self.current_program) != game_name:
                return
            
            self.image_label.clear()
            
            if not self.steamgrid_api_key:
                # Pas de clé API
                self.image_label.setText(
                    f"🖼️ {game_name}\n\n"
                    "❌ Pas de clé API\n\n"
                    "Clique sur '🔑 Clé API SteamGridDB'\n"
                    "pour ajouter une clé gratuite"
                )
            else:
                # Image non trouvée - donner des suggestions
                self.image_label.setText(
                    f"🖼️ {game_name}\n\n"
                    "❌ Image non trouvée\n\n"
                    "💡 Suggestions :\n"
                    "• Vérifie les logs dans la console\n"
                    "• Renomme le jeu (clic droit)\n"
                    "• Cherche le nom exact sur steamgriddb.com"
                )
            
            self.image_label.setStyleSheet("""
                QLabel {
                    background-color: #2a2a2a;
                    color: #888888;
                    border-radius: 10px;
                    font-size: 11pt;
                    padding: 20px;
                }
            """)
            
        except Exception as e:
            print(f"Erreur affichage échec: {e}")
    
    # ===== V7.0: Tab memorization =====

    def _on_tab_changed(self, index: int):
        """Sauvegarde l'onglet actif et auto-sélectionne le 1er item"""
        self.last_tab_index = index
        self._save_last_tab()
        self._auto_select_first_item()

    def _auto_select_first_item(self):
        """Sélectionne le 1er item de la liste active"""
        current_list = self._get_current_list()
        if current_list and current_list.count() > 0:
            current_list.setCurrentRow(0)
            item = current_list.item(0)
            if item:
                prog = item.data(Qt.ItemDataRole.UserRole)
                if prog:
                    self.show_program_info_direct(prog)

    def _get_current_list(self) -> Optional[QListWidget]:
        """Retourne la QListWidget de l'onglet actif"""
        index = self.tabs.currentIndex()
        lists = [self.games_list, self.apps_list, self.favorites_list, self.most_used_list]
        if 0 <= index < len(lists):
            return lists[index]
        return None

    # ===== V7.0: Tags management =====

    def manage_tags(self, prog: Dict):
        """Ouvre un dialogue pour gérer les tags d'un programme"""
        prog_key = prog['name'].lower()
        display_name = self.get_display_name(prog)
        current_tags = list(self.custom_tags.get(prog_key, []))

        dialog = QDialog(self)
        dialog.setWindowTitle(f"Tags - {display_name}")
        dialog.setMinimumSize(350, 300)
        dialog.setStyleSheet("""
            QDialog { background-color: #1a1a1a; color: #fff; }
            QListWidget { background-color: #2a2a2a; color: #fff; border: none; padding: 5px; }
            QListWidget::item { padding: 5px; }
            QListWidget::item:selected { background-color: #0078d4; }
            QPushButton { background-color: #0078d4; color: white; border: none; padding: 8px 16px; border-radius: 5px; }
            QPushButton:hover { background-color: #0086f0; }
            QLineEdit { background-color: #2a2a2a; color: #fff; border: 1px solid #444; border-radius: 5px; padding: 6px; }
        """)

        layout = QVBoxLayout(dialog)
        layout.addWidget(QLabel(f"Tags pour : {display_name}"))

        tag_list = QListWidget()
        for tag in current_tags:
            tag_list.addItem(tag)
        layout.addWidget(tag_list)

        # Input + buttons
        input_layout = QHBoxLayout()
        tag_input = QLineEdit()
        tag_input.setPlaceholderText("Nouveau tag...")
        input_layout.addWidget(tag_input)

        add_btn = QPushButton("Ajouter")
        def add_tag():
            text = tag_input.text().strip()
            if text and text not in current_tags:
                current_tags.append(text)
                tag_list.addItem(text)
                tag_input.clear()
        add_btn.clicked.connect(add_tag)
        tag_input.returnPressed.connect(add_tag)
        input_layout.addWidget(add_btn)
        layout.addLayout(input_layout)

        remove_btn = QPushButton("Supprimer le tag sélectionné")
        def remove_tag():
            row = tag_list.currentRow()
            if row >= 0:
                current_tags.pop(row)
                tag_list.takeItem(row)
        remove_btn.clicked.connect(remove_tag)
        layout.addWidget(remove_btn)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        layout.addWidget(buttons)

        if dialog.exec() == QDialog.DialogCode.Accepted:
            if current_tags:
                self.custom_tags[prog_key] = current_tags
            elif prog_key in self.custom_tags:
                del self.custom_tags[prog_key]
            self._save_custom_tags()
            self.populate_lists()
            self.show_program_info_direct(prog)
            self.title_label.setText(f"✅ Tags mis à jour pour {display_name}")

    def _filter_lists(self, search_text: str):
        """Filtre tous les onglets par nom ou tag"""
        search_lower = search_text.lower().strip()

        for list_widget in [self.games_list, self.apps_list, self.favorites_list, self.most_used_list]:
            for i in range(list_widget.count()):
                item = list_widget.item(i)
                if not search_lower:
                    item.setHidden(False)
                    continue

                prog = item.data(Qt.ItemDataRole.UserRole)
                if not prog:
                    item.setHidden(True)
                    continue

                prog_key = prog['name'].lower()
                display_name = self.get_display_name(prog).lower()
                tags = self.custom_tags.get(prog_key, [])
                tags_lower = " ".join(t.lower() for t in tags)

                visible = search_lower in display_name or search_lower in tags_lower
                item.setHidden(not visible)

    # ===== V7.0: Custom images carousel =====

    def manage_custom_images(self, prog: Dict):
        """Dialogue pour gérer les images personnalisées d'un programme"""
        prog_key = prog['name'].lower()
        display_name = self.get_display_name(prog)
        current_data = self.custom_images.get(prog_key, {"images": [], "interval": 5})
        current_images = list(current_data.get("images", []))
        current_interval = current_data.get("interval", 5)

        dialog = QDialog(self)
        dialog.setWindowTitle(f"Images - {display_name}")
        dialog.setMinimumSize(450, 400)
        dialog.setStyleSheet("""
            QDialog { background-color: #1a1a1a; color: #fff; }
            QListWidget { background-color: #2a2a2a; color: #fff; border: none; padding: 5px; font-size: 9pt; }
            QListWidget::item { padding: 4px; }
            QListWidget::item:selected { background-color: #0078d4; }
            QPushButton { background-color: #0078d4; color: white; border: none; padding: 8px 16px; border-radius: 5px; }
            QPushButton:hover { background-color: #0086f0; }
            QSpinBox { background-color: #2a2a2a; color: #fff; border: 1px solid #444; border-radius: 5px; padding: 4px; }
            QLabel { color: #fff; }
        """)

        layout = QVBoxLayout(dialog)
        layout.addWidget(QLabel(f"Images pour : {display_name}"))

        image_list = QListWidget()
        for img in current_images:
            image_list.addItem(img)
        layout.addWidget(image_list)

        # Buttons
        btn_layout = QHBoxLayout()

        add_file_btn = QPushButton("📁 Fichier local")
        def add_local_file():
            files, _ = QFileDialog.getOpenFileNames(
                dialog, "Sélectionner des images", "",
                "Images (*.png *.jpg *.jpeg *.bmp *.gif *.webp)"
            )
            for f in files:
                if f not in current_images:
                    current_images.append(f)
                    image_list.addItem(f)
        add_file_btn.clicked.connect(add_local_file)
        btn_layout.addWidget(add_file_btn)

        add_url_btn = QPushButton("🌐 URL")
        def add_url():
            url, ok = QInputDialog.getText(dialog, "Ajouter une URL", "URL de l'image :")
            if ok and url.strip():
                url = url.strip()
                if url not in current_images:
                    current_images.append(url)
                    image_list.addItem(url)
        add_url_btn.clicked.connect(add_url)
        btn_layout.addWidget(add_url_btn)

        remove_btn = QPushButton("🗑️ Supprimer")
        def remove_image():
            row = image_list.currentRow()
            if row >= 0:
                current_images.pop(row)
                image_list.takeItem(row)
        remove_btn.clicked.connect(remove_image)
        btn_layout.addWidget(remove_btn)

        layout.addLayout(btn_layout)

        # Interval spinner
        interval_layout = QHBoxLayout()
        interval_layout.addWidget(QLabel("Intervalle (secondes) :"))
        interval_spin = QSpinBox()
        interval_spin.setRange(1, 60)
        interval_spin.setValue(current_interval)
        interval_layout.addWidget(interval_spin)
        interval_layout.addStretch()
        layout.addLayout(interval_layout)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        layout.addWidget(buttons)

        if dialog.exec() == QDialog.DialogCode.Accepted:
            if current_images:
                self.custom_images[prog_key] = {
                    "images": current_images,
                    "interval": interval_spin.value()
                }
            elif prog_key in self.custom_images:
                del self.custom_images[prog_key]
            self._save_custom_images()
            self.show_program_info_direct(prog)
            self.title_label.setText(f"✅ Images mises à jour pour {display_name}")

    def _start_carousel(self, prog_key: str):
        """Démarre le carrousel d'images personnalisées"""
        self._stop_carousel()

        data = self.custom_images.get(prog_key, {})
        sources = data.get("images", [])
        interval = data.get("interval", 5)

        if not sources:
            return

        self.carousel_pixmaps = []
        self.carousel_index = 0
        self.carousel_active = True

        # Précharger les images
        for source in sources:
            pixmap = self._load_pixmap_from_source(source)
            if pixmap and not pixmap.isNull():
                self.carousel_pixmaps.append(pixmap)

        if self.carousel_pixmaps:
            self._display_carousel_pixmap(self.carousel_pixmaps[0])
            if len(self.carousel_pixmaps) > 1:
                self.carousel_timer.start(interval * 1000)
        else:
            # Try async download for URLs
            self._async_load_carousel(sources, interval)

    def _async_load_carousel(self, sources: list, interval: int):
        """Charge les images du carrousel de manière asynchrone (pour les URLs)"""
        self.carousel_pixmaps = []
        self._carousel_pending_sources = list(sources)
        self._carousel_interval = interval
        self._carousel_loaded_count = 0

        for source in sources:
            if source.startswith(('http://', 'https://')):
                downloader = CustomImageDownloader(source)
                downloader.image_downloaded.connect(self._on_carousel_image_downloaded)
                downloader.download_failed.connect(self._on_carousel_image_failed)
                downloader.start()
                self.active_custom_downloaders.append(downloader)
            else:
                # Local file — try loading
                pixmap = self._load_pixmap_from_source(source)
                if pixmap and not pixmap.isNull():
                    self.carousel_pixmaps.append(pixmap)
                self._carousel_loaded_count += 1

        # If all were local and loaded, start immediately
        if self._carousel_loaded_count == len(sources):
            self._finalize_carousel_load()

    def _on_carousel_image_downloaded(self, source_url: str, image_data: bytes):
        """Callback quand une image du carrousel est téléchargée"""
        if not self.carousel_active:
            return
        pixmap = QPixmap()
        if pixmap.loadFromData(image_data):
            self.carousel_pixmaps.append(pixmap)
        self._carousel_loaded_count += 1
        if self._carousel_loaded_count >= len(self._carousel_pending_sources):
            self._finalize_carousel_load()

    def _on_carousel_image_failed(self, source_url: str):
        """Callback quand le téléchargement d'une image du carrousel échoue"""
        if not self.carousel_active:
            return
        self._carousel_loaded_count += 1
        if self._carousel_loaded_count >= len(self._carousel_pending_sources):
            self._finalize_carousel_load()

    def _finalize_carousel_load(self):
        """Finalise le chargement et démarre le carrousel"""
        if self.carousel_pixmaps:
            self.carousel_index = 0
            self._display_carousel_pixmap(self.carousel_pixmaps[0])
            if len(self.carousel_pixmaps) > 1:
                self.carousel_timer.start(self._carousel_interval * 1000)

    def _stop_carousel(self):
        """Arrête le carrousel"""
        self.carousel_timer.stop()
        self.carousel_pixmaps = []
        self.carousel_index = 0
        self.carousel_active = False

    def _show_next_carousel_image(self):
        """Slot du timer : affiche l'image suivante"""
        if not self.carousel_pixmaps:
            self._stop_carousel()
            return
        self.carousel_index = (self.carousel_index + 1) % len(self.carousel_pixmaps)
        self._display_carousel_pixmap(self.carousel_pixmaps[self.carousel_index])

    def _display_carousel_pixmap(self, pixmap: QPixmap):
        """Affiche un pixmap dans le label image"""
        scaled = pixmap.scaled(
            self.image_label.size(),
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )
        self.image_label.clear()
        self.image_label.setPixmap(scaled)
        self.image_label.setStyleSheet("""
            QLabel {
                background-color: #1a1a1a;
                border-radius: 10px;
            }
        """)

    def _load_pixmap_from_source(self, source: str) -> Optional[QPixmap]:
        """Charge un pixmap depuis un chemin local ou un cache URL"""
        if source.startswith(('http://', 'https://')):
            # Check cache
            url_hash = hashlib.md5(source.encode()).hexdigest()
            cache_file = Path.home() / ".claudelauncher" / "images" / f"custom_{url_hash}.jpg"
            if cache_file.exists():
                pixmap = QPixmap(str(cache_file))
                if not pixmap.isNull():
                    return pixmap
            return None
        else:
            # Local file
            if os.path.exists(source):
                pixmap = QPixmap(source)
                if not pixmap.isNull():
                    return pixmap
            return None

    def launch_program(self, item: QListWidgetItem):
        """Lance le programme"""
        prog = item.data(Qt.ItemDataRole.UserRole)
        
        try:
            path = prog['path']
            
            if not os.path.exists(path):
                reply = QMessageBox.question(
                    self, "Fichier introuvable",
                    f"Le fichier n'existe pas :\n{path}\n\nVoulez-vous choisir un autre exe ?",
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
                )
                
                if reply == QMessageBox.StandardButton.Yes:
                    self.current_program = prog
                    self.edit_executable()
                return
            
            prog_key = prog['name'].lower()
            args = self.custom_args.get(prog_key, "")
            
            # Working directory = dossier de l'exe (V5.4 fix)
            working_dir = os.path.dirname(path)
            
            if path.endswith('.exe'):
                try:
                    if args:
                        subprocess.Popen(f'"{path}" {args}', shell=True, cwd=working_dir)
                    else:
                        subprocess.Popen([path], cwd=working_dir)
                except PermissionError:
                    self._launch_elevated(path, args, working_dir)
            else:
                os.startfile(path)
            
            self._increment_launch_count(prog['name'])
            self.title_label.setText(f"✅ {prog['name']} lancé !")
            
        except Exception as e:
            QMessageBox.critical(self, "Erreur de lancement", 
                f"Impossible de lancer {prog['name']} :\n{str(e)}")
    
    def _launch_elevated(self, path: str, args: str = "", working_dir: str = None):
        """Lance avec élévation"""
        import ctypes
        
        try:
            if not working_dir:
                working_dir = os.path.dirname(path)
            
            ctypes.windll.shell32.ShellExecuteW(
                None, "runas", path, args if args else None, working_dir, 1
            )
        except Exception as e:
            QMessageBox.critical(self, "Erreur d'élévation", 
                f"Impossible de lancer avec admin :\n{str(e)}")


def main():
    app = QApplication(sys.argv)
    launcher = ClaudeLauncher()
    launcher.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
