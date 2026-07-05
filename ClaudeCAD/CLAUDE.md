# ClaudeCAD

Projet d'application de type "ARC+ like" dans le même style que la version des années 1990, début 2000.

## Vue d'ensemble

Outil de **dessin architectural basique** (filaire 2D/3D), dans l'esprit d'ARC+ première génération :
sobre, rapide, **pensé 3D dès l'origine** (et non la 3D bricolée par-dessus du 2D comme l'AutoCAD de
l'époque). Look rétro années 90 / début 2000 assumé : barres d'outils, ligne de commande, dessin filaire
noir sur fond clair, pas de fioritures.

**Pas un moteur de rendu photoréaliste.** L'image de synthèse réaliste est déléguée aux outils d'IA
externes qui partent des dessins filaires de l'architecte. ClaudeCAD ne produit que le **dessin technique**.

## Cahier des charges fonctionnel

Primitives volontairement minimales :

- **Lignes** et **arcs** uniquement (segments droits + arcs de cercle). Pas de splines, pas de NURBS, pas de surfaces.
- **Espace 3D natif** : tout point a (x, y, z). Caméra orbit/pan/zoom. Notion de **plan de travail** déplaçable
  (l'innovation ARC+ : dessiner une toiture ou un pan incliné sans se battre avec le « plan XY de base »).
- **Lignes d'aide / de construction** : la signature d'ARC+. Ce sont des lignes comme les autres mais
  affichées en **pointillé gris** (vs noir plein pour le dessin final), servant de **support d'accrochage**.
  Effaçables **toutes d'un coup** par une seule commande.
- **Accrochage (snap)** : extrémités, milieux, intersections, centres/quadrants d'arcs, perpendiculaire,
  tangente. C'est le cœur métier — à écrire nous-mêmes quel que soit le socle technique.
- **Raccords** propres entre sections de lignes/arcs en 2D comme en 3D (jonctions exactes aux points d'accroche).
- **Saisie numérique précise** des coordonnées (clavier + ligne de commande).
- **Calques** (layers) et gestion couleur/épaisseur/style de trait.
- Interface **en français**.

Nice-to-have (pas bloquant) : import/export **DXF** (échange standard entre architectes).

## Pile technique

**Validé le 2026-06-03.** Socle = chrome Qt riche + projection 3D maison (NumPy float64),
rendu filaire 2D via QPainter. Pas de moteur de jeu.

| Couche | Choix | Rôle |
|--------|-------|------|
| **Langage** | **Python 3** (`/usr/bin/python3`, venv `.venv/` par projet) | tout le code applicatif |
| **Chrome / UI** | **PySide6 (Qt 6)** | fenêtre, menus, ligne de commande, dialogues, calques, raccourcis — le look rétro CAD 90s/2000s |
| **Viewport** | **`QWidget` + `QPainter`** | rendu filaire 2D (pointillé gris ↔ noir plein, antialiasing, texte) ; redessin **sur événement**, pas en boucle |
| **Caméra / projection** | **NumPy float64** maison (`camera.py`) | projection orthographique 3D→2D ; vue XY par défaut, azimuth/elevation prêts pour la 3D |
| **Modèle géométrique** | **NumPy float64** | points/lignes/arcs en double précision (pas de perte float32) |
| **Interop** | **`ezdxf`** | lecture **et** écriture DXF (échange standard architectes) |

**Choix du rendu — QPainter plutôt que moderngl/OpenGL (décidé le 2026-06-04, début de l'implémentation).**
Pour un CAD **filaire pur, sans ombrage ni rendu réaliste** (cf. cahier des charges), QPainter est plus léger
et plus sûr que monter un contexte OpenGL : pointillés/couleurs/antialiasing/texte sont natifs, zéro shader.
La projection 3D→2D reste maison en NumPy float64 (donc 3D-natif côté modèle). C'est l'option la plus fidèle
au « pas de bazooka » de Pat. **Voie d'évolution GPU si besoin** (très gros dessins ou effets) : passer le
viewport en `QOpenGLWidget` + `moderngl` sans toucher au modèle ni à la caméra — l'archi est découplée pour ça.

**Pourquoi pas Godot** (le « bazooka ») : rendu *frame-based* (chauffe pour rien sur un dessin statique),
float32 par défaut, tout l'attirail jeu inutile — et la logique CAD (snapping, lignes de construction, plans
de travail) reste à écrire de toute façon.
**Pourquoi pas le canvas OS pur** : pas d'UI/chrome, et toute la pile 3D à réécrire à la main de toute façon
(c'est ce qu'on fait, mais Qt nous donne fenêtre + chrome + QPainter par-dessus).

Stack déjà éprouvée chez nous : `ClaudeLauncher` (PyQt6) et `ClaudeCraft/scripts/structure_viewer.py` (PyQt6).

## Lancer

```bash
./run.sh                 # crée le venv + installe les deps au 1er lancement, puis lance main.py
```

Ou à la main :

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt   # 1re fois
.venv/bin/python main.py                                             # lancement
```

Sous Linux, le double-clic sur un `.py` ne lance rien (contrairement à Windows) : utiliser `run.sh`
(bit exécutable requis : `chmod +x run.sh`). Qt 6 peut réclamer `sudo apt install libxcb-cursor0`.

Tests : `.venv/bin/python tests/test_camera.py` (maths caméra, headless) et
`QT_QPA_PLATFORM=offscreen .venv/bin/python tests/smoke.py` (fenêtre + rendu + .cca, headless).

## Structure du code (v0.1)

```
main.py                 point d'entrée (.venv/bin/python main.py)
claudecad/
  __init__.py           APP_VERSION + changelog (incrémenter à chaque modif !)
  app.py                amorçage QApplication
  main_window.py        fenêtre : canvas + barre basse (ligne de commande | coords XYZ) + menu Fichier
  canvas.py             CadCanvas (QWidget/QPainter) : rendu, zoom molette, pan [CTRL]+clic ou bouton milieu, lignes d'aide infinies
  camera.py             Camera : projection ortho 3D float64, zoom-vers-curseur, pan, cadrage nouveau projet
  document.py           Document + HelpLine + lecture/écriture .cca
tests/                  test_camera.py (headless) + smoke.py (Qt offscreen)
```

## Contrôles (v0.1)

- **Zoom / dézoom** : molette, centré sur le curseur (molette avant = zoom avant ; `WHEEL_INVERT` pour inverser).
- **Pan** (panoramique, déplace les coordonnées du dessin) : **[CTRL] + clic gauche** maintenu, ou **bouton du milieu**.
  - ⚠️ On évite **[ALT]** : sous Cinnamon, le WM capte `Alt+glisser` pour déplacer les fenêtres (réglage
    `org.cinnamon.desktop.wm.preferences mouse-button-modifier` = `<Alt>`), donc l'événement n'atteint jamais
    le canvas. CTRL/SHIFT passent. Modifieur réglable via `PAN_MODIFIER` dans `canvas.py`.

## Format de fichier `.cca`

JSON. L'en-tête **commence par l'identifiant magique** `"magic": "ClaudeCAD"` (reconnaissance certaine du
type de fichier — refus avec message clair à l'ouverture sinon ; les .cca 0.1.x sans magic restent acceptés),
puis la **version** de l'app créatrice, l'**état caméra 3D complet** (pour rouvrir la vue à l'identique,
y compris en vue iso ou future perspective : `projection` + `center` monde + `scale` + `azimuth`/`elevation`
— indépendant de la taille de fenêtre), les **réglages de travail** `settings` (unité, couleurs
fond/aide/trait, épaisseur, police, calque courant — restaurés à l'ouverture, rien à reconfigurer ; les clés
absentes d'un vieux fichier reprennent les défauts `DEFAULT_SETTINGS` de `document.py`, donc le format peut
grossir sans casser l'existant), puis les lignes d'aide et les entités. L'état caméra est **réécrit à la
fermeture** de l'app (dernier zoom/vue).

```json
{ "magic": "ClaudeCAD",
  "claudecad_version": "0.1.2",
  "camera": { "projection": "ortho", "center": [x,y,z], "scale": 40.0, "azimuth": 0.0, "elevation": 0.0 },
  "settings": { "unit": "m", "background_color": "#ffffff", "help_line_color": "#b4b4b4",
                "line_color": "#000000", "line_width": 1.0,
                "font_family": "monospace", "font_size": 10, "current_layer": "0" },
  "help_lines": [ {"point":[0,0,0],"direction":[1,0,0]}, {"point":[0,0,0],"direction":[0,1,0]} ],
  "entities": [] }
```

> Extension `.cca` : utilisée par quelques logiciels **legacy/niche** (Clickteam Fusion 1.5, archives cc:Mail,
> MacCaption…) — aucun présent/actif sous Linux Mint, donc libre pour nous. Si on veut du 100 % unique
> plus tard : `.ccad` est dispo.

> **Commande de lancement :** à figer ici quand le squelette (`main.py` + venv) existera.

## Code historique à récupérer (priorité haute)

Pat possède un **ancien projet ARC+ like en Turbo Pascal** (~35 ans). Il contient déjà les **calculs de base**
qui représenteraient ~90 % du travail métier qu'on n'aura alors **pas** à réécrire :

- **Raccords d'arcs tangents** : jonctions **lisses** entre tronçons d'arcs/lignes, sans « cassure » aux
  jointures (continuité tangentielle / C1) — utilisé pour des **toboggans 3D smooth** et des **bassins complexes**.
- **Calcul de surface** d'un bassin fermé délimité par des arcs et lignes (projets d'aqua-center).

À porter Turbo Pascal → Python/NumPy dès que Pat retrouve les sources. **Ne pas réimplémenter ces formules à
l'aveugle avant de les avoir vues** — le savoir-faire est dans ce code.

## Système de commandes (conception — à implémenter)

Toutes les commandes commencent par `/` (ex. `/pan 20 34` = déplacer le dessin de +20 u en X et +34 u en Y ;
négatif = sens inverse). Cible : **200+ commandes** à terme.

**Architecture retenue : registre de commandes** (table de dispatch), PAS un gros `switch`/`case` unique.
L'idée mentale reste celle de Pat (une entrée par commande → son code), mais en plus scalable :
- `commands/` : une classe `Command` de base (`name`, `aliases`, `usage`, `help`, `category`, `undoable`,
  `execute(ctx, args)`), un registre (dict `name`→`Command` + alias), un dispatcher. Commandes groupées
  par fichier de catégorie (`view.py`, `draw.py`, `walls.py`, …), auto-enregistrées à l'import.
- Dispatcher : enlève le `/`, découpe nom + args, résout les alias, **valide les args typés** (entier / réel /
  coordonnée / texte / option) avec message d'usage en cas d'erreur, puis exécute avec un objet `Context`
  (document, canvas, calque courant, unité, sélection, helpers `ctx.echo / ctx.error / ctx.redraw`).
- `/help` **auto-généré** depuis le registre (200 commandes = impossible à maintenir à la main).
- **Undo/redo prévu dès le départ** : toute commande modifiant le document enregistre une opération réversible
  (très coûteux à rétro-fitter sur 200 commandes après coup).
- **Parseur de coordonnées** extensible (convention CAD) : absolu `x,y`, relatif `@dx,dy`, polaire `@d<a`.
- Branchement : le hook existe déjà (`MainWindow._on_command`).

**Unité** : le modèle géométrique reste en float64 « sans unité » ; une unité document (mm/cm/m) ne pilote que
l'**affichage** et le **parsing** des commandes (cf. `$INSUNITS` DXF). Spécification d'unité à fournir par Pat.

**Murs** : sous-système paramétrique dédié (axe + épaisseur + hauteur + **nettoyage des angles / jonctions en T**)
— le point fort « archi » d'ARC+, pas de simples lignes. Module `walls.py` séparé. Les raccords d'arcs tangents
du code Turbo Pascal historique pourront alimenter les murs courbes.

## Principes d'architecture (indépendants du socle retenu)

- **Modèle géométrique en double précision (float64)**, découplé du rendu. Le rendu ne reçoit que des
  coordonnées projetées/locales (technique de l'**origine flottante** : convertir en float32 au dernier
  moment, relatif à une origine locale, pour ne pas perdre la précision sur de grandes coordonnées).
- Le **snapping**, les **lignes de construction** et les **plans de travail** sont du code métier maison.
  Aucun framework ne les fournit clé en main — le socle ne sert qu'à : fenêtre + contexte de dessin +
  rendu de lignes + entrées + chrome UI.
- Arc stocké en **centre + rayon + angles** (exact), tesselé en polyligne **uniquement au moment du rendu**.

## Références d'inspiration (open source)

- **SolveSpace** — CAD paramétrique 2D/3D, noyau géométrique maison minuscule, démarre en ~1 s, <30 Mo.
  Preuve qu'un CAD filaire 3D n'a **pas** besoin d'un moteur lourd.
- **LibreCAD / QCAD** — CAD 2D en C++/Qt, DXF/DWG. Référence pour le chrome UI et l'interop DXF.
