# Lampe v3 et P03 — 11 octobre 2026

## Lampe intégrée

Le pack fourni est conservé intégralement dans `assets/3d/source/flashlight_v3/`.
Son `.gdignore` exclut les sources des imports et de l’export Godot. Le runtime
est dans `assets/flashlight/`, avec provenance et empreinte SHA256 du ZIP.
Le modèle compte 5 952 triangles. Les textures 1024² intégrées au GLB sont
réutilisées depuis les matériaux importés : aucune deuxième copie externe
n’est chargée. La rugosité Metal Plate 02 de Rob Tuytel / Poly Haven est CC0,
selon le README du pack ; le reste est l’asset fourni par Kenny.

Rig sous Camera3D, position locale `(0.16, -0.16, -0.18)` m. F bascule la lampe,
éteinte à chaque nouvelle exploration. Une indication discrète rappelle F.
Le mouvement du modèle est limité à 1,5 mm en marche, sans oscillation au repos.
Le corps noir conserve ses textures et utilise `Player.light` pour son éclairage
manuel, avec une réflexion de plafond approximative. La lentille transparente
est également modulée par cette lumière. Aucun SpotLight3D natif ni ombre native.

Le faisceau est ajouté en linéaire dans le shader unshaded du niveau avant le
rendu artistique. Un viewport canvas 128² trace les occultations dans SpanMap
(mêmes volumes que le bake), sans lecture GPU ni recalcul des néons.
Portée 18 m, demi-angle environ 26°, atténuation et bord progressifs.
Quatre échantillons PCF adoucissent les ombres. Carte spatiale de 60 m à pas
0,125 m, reconstruite de façon découpée lors du changement de secteur de 10 m.
Les résultats asynchrones périmés sont rejetés au changement de monde. Un rayon
physique ramène l’émetteur devant un mur proche pour empêcher la lampe de passer
à travers. Le viewport d’ombre ne se redessine que si la pose change.

Limites actuelles : approximation discrète des contours (128² / 0,125 m),
réflexion du modèle approximative, pas de rebond indirect de la lampe ni de
cône volumétrique. Les tests portent sur les surfaces et les obstacles réels.
Le bloom des néons reste actif ; aucune capture de présentation n’utilise `raw`.

## P03 : dimensions et embranchements

P03 est désormais le départ par défaut. Dans la réservation de 27,5 × 27,5 m,
les quatre familles de P02 sont distribuées dans des modules de largeur 10 ou
15 m et de profondeur 10 m. L’intérieur s’adapte sur la grille de 0,125 m ;
les ports gardent leur largeur et leurs ancrages. Un cinquième module de
7,5 m de profondeur et plafond à 2,2 m forme une alcôve en impasse.

Trois graphes déterministes : boucle avec branche, ou deux variantes d’arbre
avec embranchement. Les raccords inutilisés restent fermés. Trois sorties
rejoignent toujours le labyrinthe, les planchers restent à zéro et les panneaux
suivent les plafonds locaux. C01, C02, P01 et P02 restent sélectionnables.
Le rapport de composition expose les dimensions des modules et les liens.
Ce pilote reste borné à cinq modules ; la prochaine étape est de distribuer
les réservations et métadonnées dans le monde streamé.

## Validation native

Dix suites passent : flashlight, varied_assembly, assembly, promenade, world,
variable_ceiling, span_maps, light_transport, light_pipeline et streaming.
P03 : 66 graines, 55 variantes observées, trois graphes et deux répartitions
de tailles ; BFS indépendant avec rayon joueur, traversées de tous les ports,
fermeture des ports retirés, plafond/panneaux et vrais meshes sur quatre graines.
SpanMap : 1 612 800 colonnes contrôlées. Tests GPU de la lampe : mur mince,
sol, plafond, rayon parallèle, occlusion avant/après mur et rejet hors cône.
Captures normales natives seed99 : entry, return, pillars et alcove inspectées.

Benchmark natif seed99 / alcove, 720×540, MSAA4 : quatre blocs ABBA avec
modèle présent et même trajectoire de caméra, 30 images de chauffe puis 180
mesurées par bloc. Médianes éteinte 6,899 / 6,924 ms ; allumée 6,917 / 6,915 ms.
P95 éteinte 10,037 / 8,981 ms ; allumée 13,188 / 9,522 ms. Un appel de dessin
et deux triangles supplémentaires pendant le mouvement. Ce sont des temps
d’image complets, pas des timestamps GPU ; la synchronisation native peut
masquer un surcoût. Ne pas extrapoler à toutes les machines.

## Validation Web locale

Export release Web réussi, sources sous `.gdignore` absentes du pack.
Même scène alcove seed99, 1280×720 : médianes ABBA éteinte 23,7 / 25,6 ms,
allumée 25,3 / 29,1 ms ; P95 44,3 / 44,4 ms contre 45,1 / 47,7 ms.
88 appels contre 89 pendant le mouvement. Zéro mise à jour de la carte d’ombre
sur 30 images au repos avec lampe allumée, après quatre images de stabilisation.
99 bakes terminés, zéro attente ; modèle et faisceau visibles, bloom conservé.
Aucune erreur de script/shader. L’entrée dans le jeu a toutefois déclenché
une erreur Chromium UnknownError de pointer lock dans le navigateur automatisé :
le test interactif F y est donc non concluant. Le vrai handler Player a été
contrôlé en natif : allumer, ignorer la répétition, éteindre, ignorer hors jeu.
L’onglet et le serveur localhost temporaires sont fermés. Le test Web présente
un surcoût mesurable modéré ; il ne prouve pas une fluidité sur tous les PC.

## Reproduction

Utiliser le watchdog `tools/capture.sh` pour toute exécution native.
Exemple : `seed=99 view=alcove flashlight=1 flicker=1 shots=alcove out=...`.
`bench_flashlight=1` lance les blocs ABBA après stabilisation des bakes ;
`viewmodel=0` masque le modèle pour comparaison. `raw` reste réservé aux mesures.
Captures, export local et logs sont hors dépôt dans `backrooms-captures`.
Aucun push ni déploiement.
