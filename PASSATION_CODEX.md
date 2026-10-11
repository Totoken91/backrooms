# Passation — Hors Plan (Backrooms Level 0), Godot 4.6 web

**Reprise du 11 octobre 2026 :** voir
[le diagnostic et les corrections de lumière](docs/LIGHTING_DIAGNOSTIC_2026-10-11.md).
La piste RGBA8 ci-dessous n'est pas la cause principale du bleu perdu : les
conversions du rendu et une passe d'ajustement neutre l'écrasaient à l'affichage.

Document de reprise pour Codex. État au commit qui ajoute ce fichier (branche
`main`). Tout ce qui suit a été vérifié en local ; les chiffres viennent des
outils de mesure décrits plus bas.

---

## 1. Règles à respecter (non négociables)

- **Ne jamais `git push` sans demander à Kenny.** Chaque push sur `main`
  déclenche le build web (GitHub Action) puis le déploiement Vercel. Commits
  locaux : libres.
- Le dépôt GitHub `Totoken91/backrooms` est **public** : ne jamais y committer
  les images de référence (captures Kane Pixels, images de Kenny), ni de
  secret.
- Ne jamais publier sur le site « GPT Sites » ni demander ses clés (consigne
  du projet d'origine). Ne pas modifier la copie Codex `work/backrooms` ni les
  archives.
- Kenny est artiste et très exigeant : il juge à l'œil, veut un rendu
  **indiscernable des références** (Kane Pixels / USER-LUMIERE). Méthode qui
  marche avec lui : **mesurer** (contre Cycles et les références) plutôt
  qu'improviser, montrer des captures, réponses courtes. Il veut des **zones
  noires** (elles font peur) mais **pas de shading cassé** dans la pénombre.
- Il ne veut pas qu'on tourne dans le vide : les captures doivent passer par
  `tools/capture.sh` (jamais de fenêtre Godot bloquée, voir §5).

## 2. Ce qu'est le projet

Jeu d'exploration Backrooms « Level 0 » infini, généré par graine, jouable dans
le navigateur. Godot **4.6**, rendu **Compatibility** (WebGL2), export Web sans
threads. Déployé par Vercel depuis `build/web` sur `main` (le CI commite le
build avec `[skip ci]`).

- URL de prod : `https://backrooms-sable-five.vercel.app` (la protection
  Vercel « Require login » a été traitée côté compte de Kenny).
- Binaire Godot : `C:/Users/kenny/Documents/Codex/2026-10-09/files-mentioned-by-the-user-les/work/tools/godot-4.6/Godot_v4.6-stable_win64_console.exe`
- Blender (vérité terrain Cycles) : `C:/Program Files/Blender Foundation/Blender 4.2/blender.exe`
- Captures et données de travail (hors dépôt) : `C:/Users/kenny/projects/backrooms-captures`

## 3. Architecture

### Monde
- `scripts/world/level_world.gd` — `LevelWorld` : cellules de 2,5 m, chunks de
  16 cellules (40 m). `HEIGHT = 3.2` (plafond), `TILE = CELL/3` (dalles de
  plafond 0,833 m), `PANEL = TILE` (néons carrés sans cadre, centrés dans leur
  cellule, grille régulière ; trous selon `light_density` > 0,34 et 8 %
  manquants). `cell_boxes`, `cell_fixtures`, `floor_height`/`ceiling_height`
  (crochets pour la génération, constants pour l'instant), `panels_off`
  (néons éteints), `geo_test` (géométrie de test : toits de conduit à 1,3 m et
  sols surélevés de 0,5 m dans 1 cellule sur 6).
- `scripts/world/compositions.gd` — salle C01 (pièce désaxée) à l'origine ;
  néons sur la grille monde.
- `scripts/world/span_map.gd` — **représentation 3D** : pour chaque colonne de
  0,125 m, jusqu'à 4 intervalles de hauteur pleins (sol, plafond, murs,
  linteaux, dalles, toits de conduit), en deux images RGBAH. C'est la base de
  tout le calcul de lumière.
- `scripts/world/chunk.gd` — maillage, collisions, néons (MultiMesh), AO de
  contact (seulement les boîtes pleine hauteur). Sol/plafond émis sauf si une
  boîte **pleine hauteur** couvre la cellule.

### Lumière (le gros du travail)
Calcul GPU en jeu, par chunk, dans un SubViewport (canvas shaders, 8 bandes =
une par frame pour éviter les saccades), relu puis stocké dans des
**Texture2DArray** (un jeu de couches par emplacement de chunk = coordonnées
modulo 7, `slot_chunk` dit quel chunk occupe un emplacement).

- `scripts/game/light_baker.gd` — `LightBaker` : passe directe (5 tuiles),
  deux passes de rebond (« gather »), débruitage (`bake_filter`), cache des
  `SpanMap`. Radiance des néons = 12 (convention Cycles : force d'émission =
  radiance). `higher_bounces = 1.7` (facteur des rebonds au-delà du 2ᵉ).
- `scripts/game/world_streamer.gd` — chargement des chunks, ordre des calculs
  (direct → 1ʳᵉ passe → 2ᵉ passe ; `relight` après une extinction), envoi des
  couches (`_upload`), `light_at`, `map_values`.
- Couches par emplacement (`MAPS = 11`) : 0-3 directe (sol + murs à 3 hauteurs
  × 4 orientations ; tuile 3 contient aussi la part des 3 groupes de
  clignotement), **4 = espace de la colonne** (hauteur sol/plafond encodées
  16 bits), 5-7 première passe de rebond (sol/plafond/murs), 8-10 rebond
  affiché (2ᵉ passe, sinon 1ʳᵉ).
- Shaders :
  - `shaders/bake_direct.gdshader` — lumière directe, visibilité 3D par
    hauteur de réception, 3×3 échantillons par néon, groupes de clignotement.
  - `shaders/bake_indirect.gdshader` — rebonds : 16×6 rayons pivotés par
    texel, marche 3D dans les intervalles (faces de mur, plafonds, dessous de
    linteau, dessus de dalle).
  - `shaders/bake_filter.gdshader` — débruitage qui ne traverse pas les murs
    (ne touche pas la tuile 4).
  - `shaders/surface.gdshader` — affichage (unshaded) :
    `ALBEDO = to_srgb((albedo·(1-F) + F) · (directe + rebond) · contact / π)`.
  - Includes : `spans.gdshaderinc` (intervalles, `visible`, `column_gap`,
    `occupied`), `gap.gdshaderinc` (hauteurs de mesure des murs relatives à
    l'espace de la colonne, profil de mur log-quadratique, encodage 16 bits),
    `light_maps.gdshaderinc` (lecture des Texture2DArray).
- `scripts/game/panel_lights.gd` — 3 groupes de clignotement (circuits),
  `group_power` publié chaque frame aux matériaux, `switch_off(f)`.

### Pièges découverts (à ne pas refaire)
- **Compatibility lit `ALBEDO` comme du sRGB** et n'applique pas de décodage
  sRGB aux textures (`drivers/gles3/shaders/scene.glsl`, `SHADER_IS_SRGB`) :
  on décode/encode à la main (`to_linear`/`to_srgb`).
- **Pas de rendu 2D HDR en Compatibility** : les SubViewports sont en RGBA8.
  D'où l'encodage `sqrt(E / e_max)` (e_max 6, i_max 2) et l'abandon des sondes
  DDGI (accumulation temporelle impossible en 8 bits).
- **Le filtrage est un état de texture** en Compatibility : lier la même
  texture à deux uniforms (nearest + linear) met tout en nearest → bandes
  verticales. La carte d'espace (couche 4) est lue au centre du texel avec le
  filtre linéaire.
- Canvas shaders du baker : `render_mode blend_disabled` (sinon l'alpha, qui
  porte des données, multiplie le RGB).
- `return` interdit dans `fragment()` des shaders Godot.
- GDScript : `var x :=` sur une valeur non typée → erreur de parse ; les
  lambdas capturent par valeur ; les PackedArray sont copy-on-write.
- Blender résout les chemins relatifs ailleurs : `render_scene.py` passe la
  sortie en absolu.

## 4. Plan lumière et où on en est

Plan validé avec Kenny (environnements colossaux, murs horizontaux, couloirs où
il faut s'accroupir, autres levels plus tard) :

1. **Fait** — représentation 3D (`SpanMap`), tracé 3D, bandes, Texture2DArray.
2. **Fait** — groupes de clignotement qui assombrissent vraiment la lumière,
   extinction d'un néon (F8 en debug) avec recalcul de zone sans flash.
3. **En cours** — à la place des sondes DDGI (impossibles proprement en 8 bits,
   voir §3), **cartes relatives à l'espace de chaque colonne** :
   - fait : couche 4 (sol/plafond par colonne), hauteurs de mesure des murs
     relatives à l'espace, récepteurs de rebond dans l'espace de la colonne,
     `occupied` = colonne sans espace libre, maillage sol/plafond et AO
     corrigés pour les boîtes partielles, plus de bandes verticales ;
   - **problème ouvert (prioritaire)** : dans les zones peu éclairées, le
     rebond est sous-estimé. Mesures sur la scène de test `geotest` :
     - à rebonds égaux, la **première passe seule** donne 0,71 (vue dim0) et
       **0,21** (vue dim3, zone sombre) de Cycles limité à 1 rebond ;
     - la portée des rayons (16 → 40 m) n'y change rien ; le facteur
       `higher_bounces` non plus ;
     - indice : dans dim3 le **bleu du rebond tombe à 0** (rapport b/r 0,00
       contre ~0,27 dans Cycles) → suspect : quantification 8 bits des petites
       valeurs (encodage sqrt, i_max 2, et/ou e_max 6 des cartes directes lues
       aux points d'impact), ou carte directe des murs trop faible à
       l'impact. À vérifier en premier : dumper les valeurs aux points d'impact
       (`dump`), essayer un i_max/e_max plus petit ou un encodage log.
   - à faire ensuite : couche « étage 2 » (mezzanines) quand la génération en
     aura besoin ; plafonds plus hauts que `HEIGHT` (le maillage suppose
     encore H pour les murs pleine hauteur).
4. **À faire** — grandes distances / espaces colossaux (cascades, portée des
   rayons > marge de 10 m du `SpanMap`).

Autres constats : la scène est un peu plus lumineuse depuis les néons de
0,83 m et le plafond de 3,2 m (non recalibré sur USER-LUMIERE) ; le plafond
reste ~5-10 % sous Cycles ; pics de frame pendant le chargement ≈ 29 ms max /
19 ms p95 (bake en bandes).

## 5. Outils et commandes

Toutes les commandes depuis `C:/Users/kenny/projects/backrooms` (bash).

- **Captures sans jamais bloquer** (arrêt à la première erreur de script ou de
  shader, délai max `MAX_S`, fenêtre hors écran, ferme bien la fenêtre
  « Hors Plan ») :
  ```
  MAX_S=240 RES=720x540 sh tools/capture.sh seed=2 shots=entry,reveal,interior,east out=C:/Users/kenny/projects/backrooms-captures tag=-x
  ```
  Options utiles du jeu (`--` user args, ou `?k=v` dans l'URL web) :
  `seed`, `view`, `debug`, `at=x,z,yaw[,pitch]`, `pitch=`, `shots`, `out`,
  `tag`, `tune=param:val,...` (paramètres des matériaux, `env.<prop>`),
  `raw` (tonemap linéaire, pour mesurer), `export_scene=fichier.json`,
  `scout=N` (+`scout_any`, `scout_r=`) points de vue dans le labyrinthe,
  `flicker=v` (force les groupes), `off` (éteint le néon devant puis attend),
  `skate`, `geotest`, `dump`.
  Vues debug (`tune=debug_view:N`) : 6 albédo, 8 directe E/π, 9 rebond E/π,
  10 première passe seule.
- **Vérité Cycles** : `sh tools/render-truth.sh scene.json tag [vues...]`
  (beauty `truth-<tag>-<vue>.png` + passes diffuses JSON). Option `bounces`
  dans `render_scene.py` pour limiter les rebonds.
- **Mesure jeu vs Cycles** :
  `node tools/measure-gi.cjs direct.png indirect.png passes.json`
  (directe et rebond par zone 3×3, rapports) ; `tools/compare-ref.cjs`
  (planche côte à côte + stats) ; `tools/contact-sheet.cjs` (planche).
  Zones 3×3 : `../backrooms-captures/zones9.txt`.
- Tests : `godot --headless --path . --script res://tests/test_world.gd`
  (doit afficher `PASS: world`). Import après ajout de classes :
  `godot --headless --path . --import`.
- Données de référence actuelles : `scene-s2d.json` + `truth-s2d-*` /
  `passes-s2d-*` (disposition actuelle, seed 2) ; `scene-geo.json` +
  `truth-geo-*`, `passes-geo-*`, `passes-geo1b-*` (1 rebond), `passes-geo2b-*`
  (2 rebonds) pour la géométrie de test.

## 6. En jeu (pour Kenny)

ZQSD/WASD, souris, Maj sprint, **K skate** (Maj boost, S frein), **F3 debug**
(FPS, graphe, graine, position, lumière, calculs en attente…), **F7** vues
lumière, **F8** éteindre le néon proche, Échap pause.

## 7. Prochaines actions conseillées

1. Résoudre la sous-estimation du rebond en zone sombre (§4) avec les outils
   de mesure, valider sur `geotest` puis sur `s2d`.
2. Retirer ou garder derrière une option les vues de debug ajoutées, puis
   commit ; demander à Kenny avant tout push.
3. Recalibrer la luminosité générale sur USER-LUMIERE si Kenny le demande
   (images de référence : `C:/Users/kenny/Documents/Codex/2026-10-09/as-x20/outputs/level0-references/images/`).
4. Étape 4 (espaces colossaux) puis la génération (C02+).
