# P05 — Réservations distribuées

## Résultat

P05 devient la composition par défaut. Les familles de P04 se découvrent désormais
pendant l'exploration. Chaque secteur de 2 × 2 chunks (80 × 80 m) contient
exactement une réservation de 27,5 × 27,5 m, dont le propriétaire varie par graine.
Le secteur initial impose (0, 0). Budget : 25 % des chunks, environ 11,8 % de
la surface du monde. Ce budget spatial ne garantit pas une distance de marche.

Les sites restent à 5 m des bords nord/ouest et 7,5 m des bords sud/est de leur
chunk. Deux sites voisins sont séparés par au moins 12,5 m de labyrinthe.
Les trois sorties de chaque site rejoignent des cellules impaires accessibles.
La circulation et les contrats aux bords des chunks restent intacts.

## Architecture

LevelWorld.reservation_rect décrit le placement sans construire les salles.
reservation_at matérialise paresseusement volumes, plafonds, panneaux, vues
et rapport, sans dépendre de l'ordre des meshes ou des bakes. Les canaux P05
incluent les coordonnées du propriétaire. Les coordonnées négatives utilisent
floor. Les IDs distants portent un préfixe propriétaire ; une extinction ne
touche donc pas un panneau homologue d'un autre site.

Le cache des réservations est élagué avec le monde, sauf le départ conservé.
Les données se reconstruisent à l'identique au retour. Les panneaux éteints
restent dans panels_off. C01 à P04 conservent leurs canaux de génération.

WorldStreamer publie les métadonnées de plafond dans une texture array de
49 couches de 16 × 16 cellules en RGBAF (~196 Kio bruts). Upload uniquement
à la prise de slot ; publication du propriétaire après les données et
invalidation au reset. Le shader rejette les slots d'un autre chunk.
Les bakes gardent les métadonnées locales de SpanMap ; la lampe utilise
les mêmes volumes.

Texture2DArray.get_layer_data peut écrêter les floats sur Compatibility :
les tests contrôlent donc les hauteurs par le vrai shader, normalisées
entre 0 et 1 pour la lecture, et non par une relecture brute des floats.

## Vérifications ciblées

Audit de 72 réservations / huit graines, positives et négatives. BFS indépendant
au pas de 25 cm et rayon de 30 cm sur le chunk complet : vues, sorties,
contrats de bord et dégagement aux traversées. Budget par secteur,
déterminisme après requêtes distantes et éviction/retour, IDs uniques,
extinction conservée. Meshes réels de trois sites distants : raccords hauts
fermés et passages libres à hauteur d'œil.

Lecture GPU des hauteurs 2,2/3,2/4,8 m : propriétaires négatifs/positifs,
réaffectation à sept chunks et reset. Ordonnanceur avec bakes retardés :
rendu shader des 256 cellules par chunk après déplacements, retour,
extinctions pendant un bake et changement de graine.

## Reproduire

Passer par tools/capture.sh, sans raw pour les captures artistiques :

    seed=99 composition=P05 site=-2,-1 view=entry shots=entry,enfilade,pillars flicker=1 msaa=4
    seed=99 composition=P05 site=3,1 view=bend shots=bend,tee,cross flicker=1 msaa=4

site=cx,cz sélectionne les vues QA d'une réservation existante ; il ne modifie
ni la génération ni le départ normal. Ne pas choisir un chunk sans réservation.

## Limites et suite

Cette étape distribue l'assembleur P04 : chaque ensemble garde sa grille
de six modules et ses six familles, avec tailles, ordre et graphe variables.
Cela peut devenir reconnaissable. Prochaine étape : profils de sites et
organisations macro différentes, puis réservations sur plusieurs chunks.
Pas encore de gouffres, étages ou volumes colossaux. Aucun push ni déploiement.

## Régressions et captures

Treize suites natives passent : distributed_sites, spatial_assembly,
varied_assembly, assembly, promenade, world, variable_ceiling, span_maps,
flashlight, light_transport, light_pipeline, streaming, lighting_regressions.
L'oracle SpanMap couvre maintenant 2 304 000 colonnes, dont deux sites P05 distants.
Après le nettoyage des anciens champs de site unique, distributed_sites,
spatial_assembly et world ont été exécutées à nouveau avec succès.

Six vues natives seed99 inspectées dans les sites (-2,-1) et (3,1), bakes terminés,
rendu normal avec bloom. Captures et journaux dans backrooms-captures/p05 et
backrooms-captures/p05-*.log, hors dépôt public. Il ne s'agit pas d'un benchmark
répété de performances. Export release Web local réussi.

Web local à 1280 × 720, seed99 / site (-2,-1) / entry : 111 bakes terminés,
zéro attente, console sans erreur ni avertissement. Plafond, volumes et éclairage
réfléchi contrôlés après stabilisation. Onglet et serveur temporaires fermés.
Aucun nouveau test interactif de souris ni benchmark Web répété revendiqué.

## Référence de lore pour la suite

Voir [l'alignement Wikidot](LEVEL0_WIKIDOT_ALIGNMENT_2026-10-11.md), demandé par
Kenny après P05. Les prochains profils et leurs règles doivent suivre ce plan.
