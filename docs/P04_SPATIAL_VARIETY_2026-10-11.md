# P04 — Tailles, formes et ramifications

P04 devient le départ par défaut ; P03 et les pilotes antérieurs restent
sélectionnables avec `composition=...`. Aucun push ni déploiement.

## Composition

Six modules occupent deux colonnes et trois rangées dans le site existant
27,5 × 27,5 m. La surface des modules est 25 × 25 m, avec une marge de raccord
au sud et à l’est. Cinq répartitions de largeur : 7,5/17,5, 10/15, 12,5/12,5,
15/10 et 17,5/7,5 m. Une rangée fait 10 m, les autres 7,5 m ; la rangée profonde
est choisie par graine. Dimensions et hauteurs sont alignées sur les cellules
2,5 m du plafond ; les empreintes restent exprimées au pas 0,125 m.

Les familles enfilade, piliers et retour sont conservées. Trois empreintes
complètent le jeu : pièce en L masquant son prolongement, galerie en T avec
branche de 1,75 m, carrefour en croix avec noyau élargi. Ce sont des unions
de surfaces libres, avec de vrais coins pleins, et non des pièces rectangulaires
avec des objets décoratifs. Chaque composition contient les six familles,
mélangées par graine. L et croix ont un plafond à 2,2 m, T et pièces ordinaires
à 3,2 m, piliers à 4,8 m. Plancher plat inchangé.

Les ports gardent leur contrat de 1,75 m et leurs ancrages. La compression
peut rapprocher une cloison intérieure d’un port : `make_shaped` réserve donc
un vestibule court et enlève uniquement les morceaux de cloison qui mordent
dessus. Les anciennes recettes `make` / `make_sized` restent intactes pour
préserver les pilotes. Les ouvertures inutilisées restent fermées.

## Graphe

`SpatialAssembler` mélange les sept arêtes possibles de la grille et construit
un arbre couvrant par fusion de composantes. Si cet arbre est une simple chaîne ou si toutes ses feuilles donnent sur une sortie,
il est remplacé par un peigne dont le côté varie : une vraie impasse sans sortie
vers le labyrinthe et au moins un embranchement
est garanti. Zéro, une ou deux arêtes restantes sont ajoutées pour former des
boucles. Les arbres ont des impasses ; le graphe avec toutes les boucles peut
ne pas en avoir. Trois sorties vers le labyrinthe utilisent ses cellules impaires.

Le résultat et les variantes sont déterministes, indépendants de l’ordre des
chunks. Le rapport expose chaque famille, forme, dimension, origine, hauteur
et lien. Le nombre de modules et leur arrangement macro restent bornés à cette
grille : cette étape augmente la variété à l’intérieur du site, pas encore le
nombre ou la distribution des sites dans le monde streamé.

## Vérification

`test_spatial_assembly.gd` : 98 graines, 13 graphes distincts observés,
cinq répartitions de largeur, trois de profondeur et trois nombres de boucles.
BFS indépendant avec rayon joueur de 0,3 m : tous les points de vue et sorties
accessibles ; traversée de chaque port ; ports inutilisés pleins ; coins des
empreintes réellement solides ; panneaux hors murs et aux bonnes altitudes.
Déterminisme vérifié après consultation d’un chunk distant. Meshes réels de
quatre graines : fermeture des hauts de raccords et passage libre à hauteur d’œil.
Les premiers essais ont détecté des cloisons comprimées devant certains ports ;
la réservation des vestibules corrige ce défaut et l’audit passe.

SpanMap inclut P04 dans son oracle indépendant : 1 843 200 colonnes au total,
avec égalité du raster découpé et du raster complet. Les shaders d’éclairage,
le bloom et la lampe ne sont pas modifiés dans cette étape.

Captures artistiques hors dépôt, sans `raw` :
`seed=99 composition=P04 shots=entry,enfilade,pillars,bend,tee,cross flicker=1 msaa=4`.
Toujours lancer les exécutions natives avec le watchdog `tools/capture.sh`.

Les onze suites de régression passent : spatial_assembly, varied_assembly,
assembly, promenade, world, variable_ceiling, span_maps, flashlight,
light_transport, light_pipeline et streaming. Après ajout de la garantie
d’impasse sans sortie, l’audit P04 de 98 graines passe à nouveau (13 graphes).
Six vues natives seed99 inspectées, bakes terminés, sans erreurs de rendu.
Ces captures ne constituent pas un nouveau benchmark de performances.
Export release Web local vérifié à 1280×720, seed99 / enfilade : 99 bakes
terminés, zéro attente, console sans erreur ni avertissement, rendu normal
avec bloom. Onglet et serveur temporaires fermés. Aucun test interactif
de souris ni nouveau benchmark Web revendiqué dans cette étape.

## Suite

Distribuer plusieurs réservations dans les chunks, avec budgets de densité et
règles de voisinage ; transmettre leurs plafonds/ports au streaming et à SpanMap.
Puis varier l’organisation macro au-delà de cette grille. Préserver des séquences
lisibles de compression, révélation, respiration et embranchement plutôt que
multiplier au hasard les ouvertures.
