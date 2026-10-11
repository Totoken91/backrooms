# P06 — Profils architecturaux, pilote de champ de piliers

11 octobre 2026. Arches exclues à la demande de Kenny.

## Composition

Le mode par défaut devient P06. Il conserve les réservations P05 : un propriétaire
par district de 80 × 80 m, site de 27,5 × 27,5 m dans un chunk de 40 m,
avec circulation classique autour. Le départ présente toujours un champ de
piliers. Chaque site distant choisit par hachage entre ce profil (1/3) et
les ensembles ramifiés SpatialAssembler (2/3). Ces proportions sont des choix
de prototype, pas des statistiques du lore.

Le champ comporte 25 ou 36 colonnes carrées de 0,75 ou 1 m de côté,
espacées de 5 ou 4 m. Un passage de 1,75 m de large ouvre sur la trame.
Son plafond monte de 2,2 à 4,8 m après 2,5 m de progression. Trois sorties
rejoignent les cellules impaires du labyrinthe ; la sortie sud est décalée
pour conserver le dégagement du joueur dans les quatre variantes de trame.
Les panneaux restent sur la grille de dalles existante, filtrés contre les
volumes, à la hauteur effective de leur cellule. Le bloom est conservé.

## Architecture et limites

SiteProfiles produit une recette Compositions ; aucun second système de mesh,
collision ou ombre n'est ajouté. LevelWorld choisit le profil et conserve ses
métadonnées dans le rapport de site. Les clés incluent la graine et le propriétaire.
Les plafonds passent dans les métadonnées GPU streamées existantes.

Les champs restent bornés à un chunk. Cette étape donne une identité distincte
aux espaces, elle ne réalise pas encore des étendues gigantesques ni leur
réorganisation hors regard. Le sol reste plat ; pas de fosses ni de pièce rouge.
P07 doit d'abord définir propriété, découpage et budgets multi-chunks.

## Reproduction

Paramètres du jeu : composition=P06 seed=99 view=pillars flicker=1.
Vues : entry, reveal, pillars, return. site=cx,cz sélectionne un site distant.
P05 et toutes les compositions antérieures restent disponibles explicitement.

## Vérification

test_site_profiles : 72 sites sur huit graines, dont 30 champs, deux espacements
et deux largeurs. BFS indépendant au rayon du joueur, vues et sorties,
collisions des piliers, ordre des requêtes, retour après éviction, mesh réel
fermant le changement de plafond tout en laissant passer le joueur.

test_span_maps inclut deux scènes P06 : comparaison exhaustive de 2 764 800
colonnes au total, avec une construction indépendante par appartenance aux volumes.
test_streaming vérifie le reset P05 vers P06 et les hauteurs effectivement lues
par le shader GPU. Les audits antérieurs restent inclus dans la régression.

Quatorze suites natives passent. Quatre vues normales avec bloom inspectées.
Export Web local vérifié : 49 chunks, 99 bakes, zéro calcul en attente,
console sans avertissement ni erreur. À 1280 × 720, mesure ponctuelle après bake :
p50 14,4 ms, p95 19,1 ms ; ce constat ne vaut pas benchmark de déplacement.

Images et exports locaux restent hors dépôt public. Aucun push ni déploiement.
