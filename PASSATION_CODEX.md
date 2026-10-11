# Passation — Hors Plan (Backrooms Level 0), Godot 4.6 web

**Alignement lore Level 0 :** [lecture Wikidot et plan](docs/LEVEL0_WIKIDOT_ALIGNMENT_2026-10-11.md).
La page fournie par Kenny devient la référence de lore pour le prototype.
Kenny a exclu les arches. Voir la feuille de route consolidée
[DEVELOPMENT_ROADMAP](docs/DEVELOPMENT_ROADMAP.md) : profils à piliers,
multi-chunks, zones noires, fosses, pièces rouges, puis réorganisation.
Ne pas confondre cache déterministe et future réorganisation hors observation.
Aucun push sans accord de Kenny.

**P06 — profils de sites :** [architecture et audits](docs/P06_SITE_PROFILES_2026-10-11.md).
Mode par défaut P06 : champ régulier de 25/36 piliers au départ, alternant avec
les ensembles ramifiés à distance. Passage bas 2,2 m vers plafond 4,8 m,
trames de 4/5 m, trois sorties avec dégagement du joueur. Aucun système d'arches.
Quatorze suites natives passent ; 72 sites, dont 30 champs, audités sur huit graines.
Oracle SpanMap étendu à 2 764 800 colonnes et reset GPU P05 vers P06 contrôlé.
Quatre captures natives avec bloom inspectées ; Web local : 99 bakes, zéro
attente, console propre. Les champs restent bornés à
27,5 m : P07 doit étendre les réservations à plusieurs chunks. Aucun push.

**P05 — réservations distribuées :** [architecture et validation](docs/P05_DISTRIBUTED_RESERVATIONS_2026-10-11.md).
Composition P05 conservée explicitement : un site de six modules par secteur de
80 × 80 m ; placement et variantes par graine, cache élagué, IDs de néons
uniques et extinction conservée au retour. Trois sorties vers la circulation
classique. Métadonnées de plafond GPU distribuées dans les 49 slots de streaming,
avec contrôle du propriétaire ; SpanMap/bakes/lampe suivent les volumes distants.
72 réservations auditées, treize suites passent (oracle SpanMap 2 304 000 colonnes).
Six captures natives de sites distants inspectées, bloom conservé, zéro attente.
Web local distant : 111 bakes, zéro attente, console propre, rendu contrôlé.
Les ensembles gardent la grille P04 : suite, profils et organisations macro
variées, puis réservations sur plusieurs chunks. Aucun push ni déploiement.

**Correctifs éclairage et rebonds de lampe :** [reproduction, causes et validation](docs/LIGHTING_ARTIFACTS_AND_FLASHLIGHT_BOUNCE_2026-10-11.md).
Graine utilisateur 1601967012 : coupure murale corrigée par reconstruction des
hauteurs avant interpolation ; PCF corrigé par plan récepteur pour les stries.
Lampe : cœur/halo plus large et quatre patches réfléchis avec atlas occulté,
actualisés à 15 Hz maximum, sans readback ni rebake. Test GPU 96 récepteurs rasants,
rebond avant/derrière cloison et continuité aux plafonds variables passé.
Douze suites natives passent ; coin sombre et performances Web vérifiés.
Sources/éclairage artistique conservés. Aucun push ni déploiement de ce correctif.

**P04 : tailles, formes et ramifications :** [architecture et audits](docs/P04_SPATIAL_VARIETY_2026-10-11.md).
Départ P04 : six familles dont L, T et croix, cinq répartitions de largeur,
trois de profondeur ; arbre ramifié et zéro à deux boucles. 98 graines / 13
graphes observés, accès aux vues/sorties et rayon joueur contrôlés.
Onze suites passent ; captures normales et Web local (99 bakes, console propre)
inspectés. P03 reste sélectionnable. Site encore borné : prochaine étape, réservations
et métadonnées distribuées dans les chunks. Aucun push ni déploiement.

**P03 et lampe v3 intégrés :** [architecture et validation](docs/FLASHLIGHT_AND_P03_2026-10-11.md).
Départ P03 : modules de tailles différentes, trois graphes et une alcôve basse
en impasse (cinq modules bornés). Lampe sous la caméra, F, éteinte par défaut ;
faisceau et ombres GPU raccordés au shader personnalisé, modèle lié à Player.light.
Dix suites natives passent ; P03 contrôlé sur 66 graines / 55 variantes.
Web local rendu/performance validés ; F vérifié en natif (pointer lock Chromium
refusé dans le navigateur automatisé, test F Web non concluant).
Sources du pack conservées sous `.gdignore`, provenance runtime documentée.
Bloom conservé. Suite : réservations/métadonnées distribuées dans le streaming.
Aucun push ni déploiement.

**P02 : premier assemblage par graine :** [familles, contrats et validation](docs/P02_ASSEMBLY_2026-10-11.md).
Nouveau départ : quatre familles indépendantes (enfilade, piliers, retour,
vide), mélangées dans quatre slots et reliées en boucle. Entrée basse et trois
sorties vers le labyrinthe. `RoomFamilies` décrit les ports ;
`PromenadeAssembler` les raccorde et agrège les données pour le résolveur commun.
34 graines / 18 ordres observés ; huit suites passées, vrais meshes des raccords
hauts/bas vérifiés. Captures natives normales seed99/7 avec bloom inspectées.
Web local : 99 passes, zéro attente, console propre ; onglet/serveur fermés.
P01 reste accessible avec `composition=P01`. P02 est un assembleur borné :
cycle et dimensions fixes, pas encore des familles partout dans les chunks.
Suite : tailles et graphes variés, puis réservations/métadonnées distribuées.
Aucun push ni déploiement.

**Captures visuelles :** ne pas passer `raw` pour présenter le jeu. Ce mode
de mesure désactive le bloom, le tonemap et l’exposition artistique. Le bloom
reste actif par défaut ; confirmé sur `godot-s99-pillars-p01-bloom-default.png`
hors dépôt. Réserver `raw` aux comparaisons quantitatives.

**P01 : enfilades et salle à piliers jouables :** [plan, architecture et validation](docs/P01_PROMENADE_2026-10-11.md).
Nouveau départ : passage bas → seuils décalés → salle à neuf piliers, deux
liaisons formant une boucle et trois sorties vers le labyrinthe. Réservation
27,5 × 27,5 m, plafonds 2,2 / 3,2 / 4,8 m. `LevelWorld.site` décrit désormais
la réservation de l'instance ; C01/C02 gardent leur site, versions et canaux.
Sept suites passées ; cinq vues natives inspectées. Web local : 99 passes,
zéro attente, console propre ; onglet/serveur temporaires fermés.
P01 reste un parcours fixe (néons/labyrinthe varient par graine), pas un
assembleur procédural. Suite : contrats de raccord puis assemblage par graine.
Aucun push ni déploiement.

**C02 jouable et plafonds variables :** [composition pilote, architecture et validation](docs/C02_VARIABLE_CEILINGS_2026-10-11.md).
Le jeu démarre désormais dans un passage à 2,2 m ouvrant sur une pièce à 4,8 m.
Trois sorties vers le labyrinthe ; variantes miroir/néons par graine. Panneaux,
meshes, collisions murales, spans, shaders et export utilisent les hauteurs locales.
C01 reste accessible avec `composition=C01` ; quinze images de contrôle identiques.
Six suites passées, Web local 99 passes/zéro attente/console propre. Pilote fini :
pas encore d'assemblage infini des familles, de mezzanine ni d'espace colossal.
Aucun push ni déploiement.

**Chargement et extinction :** [validation ciblée et invalidation des passes suspendues](docs/STREAMING_VALIDATION_2026-10-11.md).
Extinction pendant une passe : résultat périmé désormais rejeté par révision,
monde et propriétaire. Test ordonnanceur avec slots GPU, coordonnées négatives,
retour après éviction et changement de graine passé. Captures réelles seed99/7 :
retours identiques pixel par pixel ; extinction c260 achevée. Suites GPU passées.
Pics toujours présents ; pas de gain de fluidité revendiqué, ni de nouvelle
validation Web. Suite : volumes à hauteur variable et compositions.
Aucun push ni déploiement.

**Lectures du gather :** [trois cartes utiles par impact de mur](docs/GATHER_MAP_READS_2026-10-11.md).
Quatre lectures de cartes réduites à trois selon l'orientation du mur ; énergies
et rendu conservés. Oracle GPU des quatre orientations passé. Deux profils
natifs restent proches de la référence : ne pas annoncer de gain global de FPS.
Quinze captures identiques pixel par pixel ; suites GPU et Web local validés
(99 passes, zéro attente, console propre).
Aucun push ni déploiement.

**Calcul direct allégé :** [récepteurs utiles et mesures répétées](docs/DIRECT_RECEIVER_COST_2026-10-11.md).
Visibilités calculées seulement pour les hauteurs stockées dans chaque tuile,
avec conservation des fallbacks. Seed99 p95 natif ~28 vers ~19 ms sur deux
exécutions ; pics isolés encore présents. Seize bandes testées et écartées
par défaut (bake plus long). Diagnostics `light_bands=4|8|16` et profils enrichis.
Quinze captures identiques ; suites GPU passées ; Web local 99 passes, zéro
attente, console propre.
Aucun push ni déploiement.

**Débruitage sur GPU :** [pipeline et mesures](docs/GPU_DENOISE_PIPELINE_2026-10-11.md).
Deux viewports réutilisés ; une seule relecture finale par passe. Seed99 : 198
vers 99 relectures, coût CPU cumulé observé 236 vers 52 ms. Quinze captures
identiques pixel par pixel ; test dédié du pipeline et transport GPU passés.
Web local validé : 99 passes, zéro attente, console propre. Les pics globaux
restent présents. Aucun push ni déploiement.

**Dernière itération :** [essai vertical indirect et optimisation](docs/INDIRECT_HEIGHT_EXPERIMENT_2026-10-11.md).
Trois hauteurs testées puis écartées : ratios premier rebond dim3 0,93 vers 0,89,
dim0 0,88 vers 0,85, avec plus de mémoire. Patch conservé hors dépôt. Le jeu garde
le layout 11 couches. Lectures inutiles supprimées dans le premier gather ;
cinq captures dim3 identiques pixel par pixel. Aucun push.

**Reprise du 11 octobre 2026 :** voir
[le diagnostic et les corrections de lumière](docs/LIGHTING_DIAGNOSTIC_2026-10-11.md).
La piste RGBA8 ci-dessous n'est pas la cause principale du bleu perdu : les
conversions du rendu et une passe d'ajustement neutre l'écrasaient à l'affichage.

**Consolidation suivante :** [audit visuel des raccords et des arêtes](docs/VISUAL_AUDIT_2026-10-11.md).
Filtrage entre chunks corrigé pour lumière et occlusion ; MSAA 4× activé pour
les arêtes fines. Toujours aucun push sans accord de Kenny.

**Fluidité du calcul :** [profil CPU et préparation répartie](docs/STREAMING_DIAGNOSTIC_2026-10-11.md).
Raster des obstacles optimisé et réparti sur les frames ; cache isolé par monde,
textures réutilisées, débruitage en bandes. Rendu avant/après identique sur les
deux vues contrôlées. Mesure directe fraîche dim3 : 1,03 de Cycles ; premier
rebond toujours à 0,79. Les pics GPU/relecture restent à traiter.

**Transport suivant :** [interpolation d'énergie, ombres par hauteur et bandes](docs/LIGHT_TRANSPORT_FOLLOWUP_2026-10-11.md).
Gather en énergie linéaire, visibilité distincte du sol/mur bas, panneaux
intégrés par quadrature symétrique. Dim3 : directe 1,01, premier rebond 0,81
de Cycles ; dim0 : directe 0,82, rebond 0,80. Déficit encore ouvert. Captures
`layers` pour isoler matériau/direct/rebonds. Toujours aucun push.

**Profil vertical suivant :** [reconstruction physique et mesures](docs/WALL_PROFILE_2026-10-11.md).
Haut des murs mieux reconstruit ; dim3 directe 1,02, rebond 0,83 ; dim0
0,82 / 0,81. Approximation moins précise très près des panneaux dans le test
analytique ; déficit indirect encore ouvert. Travail local, aucun push.
**Conservation du gather :** [test uniforme et quadrature normalisée](docs/GATHER_CONSERVATION_2026-10-11.md).
Erreur de lumière uniforme ramenée de 24 à 1/255 encodé. Sur dim3, le rebond
reste à 0,83 de Cycles : déficit principal encore ouvert. `CAPTURE_LOG` conserve
le journal des captures, `profile` imprime leur progression. Aucun push.
**Faces du transport :** [normales d'impact, test de rotation et comparaisons](docs/GATHER_WALL_FACES_2026-10-11.md).
Traversées diagonales : lecture de la vraie face plutôt que préférence X.
Premier rebond dim3 0,83 → 0,93 de Cycles ; dim0 0,81 → 0,88, directe inchangée.
Test GPU des quatre orientations passé. Portée 8 m et hauteur centrale inchangées.
Options QA `direct_reach` / `wall_receiver_fraction`, audit des récepteurs en Python.
Toujours local uniquement, aucun push.
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
  16 cellules (40 m). `HEIGHT = 3.2` (plafond classique ; C02 utilise 2,2/4,8 m), `TILE = CELL/3` (dalles de
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
  `SpanMap`. Deux cibles GPU brut/filtré, une relecture finale par passe.
  Radiance des néons = 12 (convention Cycles : force d'émission =
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
     aura besoin. Plafonds variables : pilote C02 réalisé, voir la mise à jour en tête.
     Diagnostic historique avant C02 : le maillage supposait
     encore H pour les murs pleine hauteur.
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
