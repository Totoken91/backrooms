# C02 pilote — compression puis ouverture, 11 octobre 2026

Travail local. Aucun push ni déploiement.

## Composition jouable

Le lancement du jeu choisit désormais C02 comme composition de départ. Elle
occupe la même réservation de 17,5 × 17,5 m que C01 et possède trois sorties
reliées au labyrinthe classique. Le passage d'entrée mesure 1,75 m de large,
7,5 m de long et 2,2 m sous plafond. Il débouche sur une pièce de 12,5 × 8,75 m,
haute de 4,8 m. Un retour de cloison masque une partie de sa profondeur et impose
un détour. Aucun mobilier, entité ou système de survie n'est ajouté.

Le plan peut être retourné horizontalement selon la graine ; certains panneaux
sont omis. C'est une composition finie avec variantes, pas encore un assemblage
procédural de familles. Les zones ordinaires conservent leur plafond à 3,2 m.

- Jeu : C02 par défaut, ou `?composition=C01` pour le témoin précédent.
- Données : `LevelWorld.new(seed, "C02")`; le constructeur sans deuxième
  argument conserve C01 pour les outils et tests historiques.
- Version C02 : `level0-godot.2-C02`, utilisée par les canaux de hasard et
  affichée avec la graine. C01 garde sa version et ses résultats précédents.
- Vues : `entry`, `reveal`, `interior`, `east` dans les deux compositions.

## Hauteurs cohérentes

`LevelWorld.ceiling_height` résout les régions de plafond sur la trame de
2,5 m. Les changements de hauteur coïncident donc avec la grille des dalles.
Le maillage, les panneaux, SpanMap, les métadonnées de lumière et l'export
interrogent cette même description.

`LevelWorld.ceiling_steps` produit les faces verticales des différences de
hauteur. Le côté haut en est propriétaire ; les empreintes des murs pleine
hauteur masquent les portions couvertes. Le jeu et l'export partagent ces
faces, au lieu de laisser un trou derrière un changement de plafond.
Les panneaux utilisent leur altitude propre et remplacent leurs dalles ; les
collisions murales ne sont plus tronquées à l'ancien plafond global.
Le critère de pleine hauteur de l'occlusion de contact suit aussi le plafond local.

Les hauteurs structurelles sont séparées du premier espace libre de SpanMap :
un conduit bas ne devient pas le plafond structurel, ni le plan des sources
lumineuses. Une petite texture RGBAF à la résolution des cellules fournit le
plan local des émetteurs au profil des murs et la hauteur de classification
plafond/dessous de linteau au gather. Pas de cible de rendu flottante : ces
textures de données sont seulement échantillonnées, y compris dans WebGL2.

Une carte de 60 m couvre 24 × 24 cellules : 9 216 octets supplémentaires CPU,
plus autant pour sa texture GPU. Huit entrées représentent environ 144 Kio
CPU+GPU, hors allocations du pilote. La texture du site sur les matériaux
fait 7 × 7 × 16 = 784 octets. Le layout de lumière reste à 11 couches par slot.

## Validation

- `test_variable_ceiling.gd` : huit graines, deux orientations, traversée
  libre du corps entre entrée et révélation, trois sorties accessibles par
  parcours de grille au rayon 0,3 m. Toutes les vues ont leur dégagement.
- Le même test interroge le vrai mesh par segments : plafonds à 2,2 et 4,8 m,
  face verticale fermée à la transition. Il contrôle les altitudes des panneaux
  MultiMesh, la hauteur des collisions, les spans et la lecture des métadonnées
  structurelles sur CPU puis sur GPU, y compris hors de leur région.
- `test_span_maps.gd` : C02 ajouté à l'oracle, 921 600 colonnes au total ;
  raster synchrone/réparti identique, cache borné et isolé par monde.
- `test_world.gd`, `test_streaming.gd`, `test_light_transport.gd` et
  `test_light_pipeline.gd` : PASS.
- Témoin C01 : seed99 entry/reveal et seed2 geotest dim3, quinze images au total
  (final, albédo, direct, indirect, premier rebond), identiques pixel par pixel
  aux captures `gather-three-maps` précédentes.
- C02 seed99 : captures entrée, révélation, intérieur et allée est inspectées.
  Attentes terminées. Trois vues de la version finale avec arrêt propre sont
  conservées sous le tag `c02-final-drained`.
- Export Web release local : réussi. Navigateur IAB, seed99 reveal, 1280×720 :
  99 passes terminées, zéro attente, aucune erreur ni alerte console. Contrôle
  fonctionnel, sans benchmark ni mesure du mouvement à la souris. Onglet et
  serveur temporaires fermés après validation.
- Export de scène : trois hauteurs, altitudes des panneaux et quatre faces de
  transition. Le lecteur Blender accepte l'ancien format de panneaux à cinq
  valeurs et le nouveau à six. Rendu Cycles de contrôle 96×72, un échantillon,
  un rebond effectué : simple validation du pipeline, pas comparaison physique
  de qualité. Le script d'audit des récepteurs comprend aussi les plafonds locaux.

Les captures/export de développement arrêtent désormais la programmation des
jobs avant de quitter. Les captures laissent finir la passe suspendue ; l'export
ne lance pas de bake inutile. Cela évite les messages de ressources encore en
cours lors d'une sortie au milieu d'un calcul d'arrière-plan.

Tous les médias, scènes et journaux restent dans
`C:/Users/kenny/projects/backrooms-captures`, hors dépôt public.

## Limites et suite

Le sol reste plat, sans mezzanine ni puits. Les changements de plafond sont
alignés aux cellules ; le découpage vertical des faces doit être étendu avant
des voisinages avec couvertures partielles complexes. Les matériaux de surface
utilisent la petite carte du site fini : distribuer ces métadonnées devient
nécessaire avant des compositions à hauteur variable partout dans le monde.

Le modèle de lumière garde ses trois mesures directes et une seule hauteur
indirecte pour les murs. Un mélange d'émetteurs de hauteurs différentes demeure
une approximation du profil vertical. La portée et les marges ne changent pas ;
ce lot n'autorise pas encore les halls colossaux. Aucun gain de fluidité ni
égalité avec Cycles n'est revendiqué pour C02.

Suite utile : enrichir la promenade avec une enfilade et une salle à piliers,
valider leurs vues d'entrée/révélation/intérieur, puis traiter les contrats de
raccord et leur assemblage par graine. Garder les compositions lisibles et
les moments de vide ; ne pas semer des changements de hauteur cellule par cellule.

## Reproduire

Toujours passer par `tools/capture.sh` et garder les sorties hors dépôt :

```sh
GODOT_SCRIPT=res://tests/test_variable_ceiling.gd sh tools/capture.sh
sh tools/capture.sh seed=99 shots=entry,reveal,interior raw flicker=1 msaa=4 out=<hors-depot> tag=-c02
sh tools/capture.sh seed=99 composition=C01 shots=entry,reveal raw flicker=1 msaa=4 layers out=<hors-depot> tag=-c01-controle
sh tools/capture.sh seed=99 export_scene=<hors-depot>/scene-c02.json
```
