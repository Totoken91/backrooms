# Level 0 — Référence Wikidot et décisions de conception

Source lue le 11 octobre 2026 : [Level 0 — Threshold](https://backrooms-wiki.wikidot.com/level-0).
Révision affichée : 50, 6 octobre 2026.
Auteurs : DivineAtlas, DrAkimoto, RobertGoerman. Texte sous CC BY-SA 3.0.
Ce document contient une synthèse courte et un plan original ; aucune image copiée.
La page Wikidot fournie par Kenny fait référence pour le lore de ce prototype.

## Description du wiki, synthèse

- Arches : transitions ou impasses, murs pâles, moquette profonde ; espaces relativement stables.
- Piliers : trames régulières, étendues parfois immenses ; trajets susceptibles de changer.
- Trous : fosses sombres regroupées en grille ; aucun survivant rapporté.
- Zones noires : sans éclairage ni bourdonnement, murs rugueux, sols parfois abaissés et inondés.
- Pièces rouges : espaces déconnectés, enfermement après entrée complète ; avertissements matériels et psychologiques.
- Réorganisation hors observation, isolement entre personnes, entités non confirmées.
- Sortie décrite : traverser une paroi clignotante vers le Level 1.

## Décision de Kenny et ordre de développement

Les arches sont exclues du développement. Le plan exécutable fait référence
à [la feuille de route consolidée](DEVELOPMENT_ROADMAP.md), qui remplace les
propositions initiales. Les fréquences et dimensions choisies sont des paramètres
de jeu à éprouver ; elles ne sont pas imposées par le wiki.

P06 introduit un champ de piliers régulier borné à une réservation P05, alternant
avec les ensembles de pièces resserrées. P07 doit étendre les réservations sur
plusieurs chunks avant de prétendre représenter les grandes étendues décrites.
Viennent ensuite les zones noires, les fosses, les pièces rouges et la
réorganisation hors observation, chacune avec ses propres audits.

## État et limites techniques

Les volumes actuels sont alignés sur les axes. Le sol est plat et la graine
reconstruit exactement la même géométrie après éviction. Les endroits sombres
issus de la densité des néons ne sont pas encore un profil complet de zone noire.
Les fosses exigent du sol absent, une gravité et une chute réelles ; les pièces
rouges nécessitent un pilote lisible avant distribution. La réorganisation sera
une couche d'état distincte du cache, sans modification des lieux observés ou
occupés, avec invalidation cohérente des collisions et de la lumière.

## Conséquences pour la vision générale

Le monde habité et les bases restent des objectifs pour les autres niveaux.
Ne pas peupler ce Level 0 de PNJ ou de monstres ordinaires pour créer du danger.
La survie, l'orientation et l'architecture peuvent porter sa tension.
Garder séparés les rendus de référence artistiques et les règles de cette page :
Kane Pixels nous aide visuellement, mais n'est pas notre source Wikidot.

Aucun push ni déploiement sans accord de Kenny.
