# P07 — Champs de piliers sur quatre chunks

11 octobre 2026. Développement local, aucun push ni déploiement.
Les arches demeurent exclues.

## Contrat spatial

Le mode P07 remplace P06 par défaut et conserve les compositions précédentes.
Chaque district de 2 × 2 chunks (80 × 80 m) choisit une seule réservation :
un champ de 72,5 × 72,5 m sur ses quatre chunks, ou un parcours SpatialAssembler
de 27,5 × 27,5 m dans un membre du district. Le départ est toujours un grand
champ ; les districts distants choisissent le grand champ avec une probabilité
hachée de 1/3. Dimensions et fréquences sont des choix de jeu, pas des données
statistiques du wiki.

Le champ contient 196 ou 289 piliers réguliers, espacés de 5 ou 4 m,
de 0,75 ou 1 m de côté. Hauteur 4,8 m, entrée à 2,2 m. Les panneaux restent
sur la grille de dalles de 2,5 m ; ils suivent la hauteur et évitent les volumes.
La surface réservée est presque sept fois celle du pilote P06. Ce n'est pas
encore une étendue kilométrique ou une architecture qui se réorganise.

## Propriété, fragmentation et circulation

LevelWorld._district_layout décrit propriétaire et bounds globaux en cellules.
reservation_rect retourne seulement leur intersection locale avec un chunk.
reservation_at retourne le même dictionnaire pour les quatre membres, sans
copier le champ et sans alias de cache supplémentaires.

Les volumes sont résolus une seule fois puis coupés aux plans de chunks.
Chaque fragment possède son ID et reste dans son chunk ; l'index mondial
permet au mesher de supprimer les faces internes entre fragments adjacents.
Cela évite les faces coplanaires en double et permet de décharger un chunk sans
emporter la collision de son voisin. Les plafonds, SpanMap, bakes, lampe et AO
interrogent cette même description, indépendamment des meshes chargés.
Les panneaux sont indexés par leur cellule mondiale et ne sont instanciés
que dans un chunk. Leur identité et leur extinction restent liées au propriétaire.

Le cadre externe conserve une circulation de labyrinthe. Les sorties tombent
sur ses cellules impaires. Lorsque la réservation couvre le départ historique
(1,1), le labyrinthe commence dans une cellule impaire libre de sa périphérie.
Les limites internes entre les quatre chunks ne créent aucune nouvelle paroi.

## Coût et durée de vie

La première version utilisait un raster uniforme de 580 × 580 quanta et un
pic mesuré de 124,64 ms pour construire un propriétaire. Elle est remplacée par
Compositions.resolve_rectangles : coordonnées compressées aux bords exacts
des rectangles, même union de passages et mêmes superpositions de solides.
Le petit grid est non uniforme et ses axes sont fournis dans grid_axes ;
site_grid_axes expose la convention au départ. Les anciens modes conservent
leur raster uniforme. Après compression et mutualisation des préfixes de hash,
les deux audits des 72 districts mesurent des pics de 12,931 et 24,294 ms
(mesures locales variables, pas une garantie matérielle). Le grid d’un grand champ reste sous 3 000 octets ;
le maximum global de 48 400 octets vient des petits sites historiques. Ne pas interpréter le grid P07 comme un bitmap à pas fixe.

Les décisions de panneaux du grand champ utilisent un canal de trous partagé
puis un hash de cellule. Le préfixe du hash des graines de panneaux est calculé
une seule fois ; le résultat reste identique au channel complet pour les
compositions historiques. Aucun canal ne dépend de l'ordre des requêtes.

L'élagage teste l'intersection du champ complet avec la zone conservée, et non
la distance à son seul propriétaire. Un coin encore utile ne peut ainsi perdre
ses métadonnées parce que le propriétaire a quitté le rayon. Les contrats de
districts sont élagués aussi. Le départ reste retenu comme auparavant.
Le streaming garde 49 slots de lumière actifs et les mêmes tableaux GPU ;
la marge de rétention de géométrie existante peut conserver jusqu’à 81 chunks.
les champs ne créent pas de textures géantes par réservation.

## Audits et reproduction

- test_multi_chunk_sites : 72 districts / huit graines, propriétaires partagés,
  196/289 piliers, coordonnées négatives, volumes bornés par chunk, panneaux
  uniques, BFS indépendant au pas 0,25 m avec rayon joueur 0,3 m, vues et sorties,
  ordre des requêtes, éviction/retour et caches bornés. Un audit ciblé conserve
  le propriétaire lorsque seul son coin opposé reste dans la zone utile.
  Les graines de panneaux historiques sont comparées au hash complet initial.
- Quatre variantes du grand champ : géométrie et sélection des panneaux comparées
  exactement au résolveur dense conservé comme oracle.
- Quatre meshes réels sur un pilier au croisement : aucune face interne sur les
  deux plans de coupe, une seule face extérieure, traversées libres entre piliers.
- test_streaming : reset vers P07, traversées dans les deux directions, positions
  négatives, réutilisation des slots sept chunks plus loin et retour ; vérification
  des hauteurs réellement lues par le shader GPU.
- test_span_maps : deux zones P07 traversant des limites de chunks, comparées par
  appartenance indépendante aux volumes ; 3 225 600 colonnes au total.

QA : composition=P07 seed=99. Vues pillars, depth, seam_west, seam_east,
seam_north, seam_south ; site=cx,cz accepte n'importe quel membre d'un champ.
Captures normales avec bloom, images et exports conservés hors dépôt public.
La capture attend désormais une échéance monotone de 120 s par vue au lieu de
4 000 frames, afin qu'un rendu rapide n'écourte pas un bake encore actif.
Le watchdog externe continue à borner la durée du processus et à fermer la fenêtre.

## Validation visuelle native

Quinze suites natives passent. Six vues normales avec bloom inspectées, avant
et après les deux plans de raccord. La vue depth est centrée dans une allée
dérivée de l'espacement, afin de ne pas photographier un pilier à bout portant.
Tous les clichés sont pris avec zéro bake en attente. En capture 720 × 540,
mesure ponctuelle de la vue depth stabilisée : 126 FPS. Pendant ses bakes :
p50 8,50 ms, p95 21,27 ms, p99 36,20 ms ; le premier calcul complet attend
environ 46 s. Les grands champs ouverts coûtent plus de bakes que les petites
pièces cloisonnées ; ces chiffres ne sont ni un benchmark souris ni une garantie
60 FPS sur toute machine. Slices CPU de construction observées jusqu'à 11,35 ms.

## Validation Web locale

Export release hors dépôt, ouvert dans le navigateur à 1280 × 720 sur seed=99,
view=depth. Rendu de la trame et bloom contrôlés après 112 bakes, zéro attente,
62 chunks de géométrie retenus pour 49 slots de lumière, environ 190 Mo de VRAM
selon le compteur Godot. Console sans erreur ni avertissement. Le calcul initial
Web est sensiblement plus lent que le natif ; les statistiques pendant cette
phase ne décrivent pas le rendu stabilisé. Une fois les calculs terminés,
les relevés Web de cette vue restent à 26–33 FPS, p50 25–35 ms et p95 41–54 ms.
Un essai sans overlay debug n'a pas montré d'amélioration. Le rendu est correct,
mais le budget de 60 FPS n'est pas atteint dans ce test. La cause CPU/GPU reste
à isoler par un benchmark comparatif contrôlé ; ne pas attribuer ce coût à un
sous-système sans mesure.

## Suite

Priorité avant P08 : profiler et optimiser les grands champs sur Web, en conservant
le bloom et la géométrie validée.

P08 : profils explicites de zones noires, architecture et acoustique cohérentes,
transitions conservant la lumière provenant du bord et usage utile de la lampe.
Les fosses, la gravité/chute et les pièces rouges restent des étapes séparées.
