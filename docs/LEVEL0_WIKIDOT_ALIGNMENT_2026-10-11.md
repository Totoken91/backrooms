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

## État du prototype, constat technique

P05 distribue des ensembles de six modules. Les piliers existent mais ne forment
pas encore de vastes champs. Les zones faiblement éclairées sont actuellement
issues de la densité des néons : elles ne constituent pas un profil complet
d'architecture et d'acoustique. Les arches, fosses et pièces rouges ne sont
pas implémentées. Les volumes restent alignés sur les axes, le sol jouable
est plat et les caches reconstruisent exactement la même géométrie.

## Plan proposé pour nos prochaines étapes

Les choix ci-dessous sont des décisions de jeu à valider par essais, pas des
fréquences, dimensions ou probabilités imposées par le wiki.

1. Remplacer le mélange systématique des six modules par des profils de sites.
   Commencer par deux essais contrôlés : galerie à arches et champ de piliers.
   Donner à chaque profil une silhouette, un rythme, des vues QA et un rapport
   de génération distincts. Mesurer la répétition sur plusieurs graines.
   Élargir ensuite les réservations au-delà d'un seul chunk pour les grands champs.

2. Pour les arches, développer une géométrie de voûte réelle. Le système de
   volumes/collisions/ombres doit décrire cette courbure de manière cohérente ;
   un mesh visuel au-dessus d'une collision rectangulaire ne suffit pas.
   Tester le dégagement joueur et la lampe à travers chaque ouverture.
   Conserver ces lieux comme repères persistants dans notre future simulation.

3. Ajouter un profil de zone noire avec contrôle explicite de ses sources
   lumineuses et sonores, en conservant la propagation physique venant du bord
   éclairé et de la lampe. La survie dans l'obscurité doit rester lisible.
   Les matières et reliefs éventuels feront l'objet d'un audit séparé.

4. Introduire les fosses après un véritable support de surfaces de sol absentes,
   parois verticales, gravité, collisions et chute. Une texture noire sur un sol
   plein serait un faux danger. Réserver des chemins de contournement et tester
   leurs largeurs ; ne pas inventer une destination certaine à la chute.

5. Prototyper les pièces rouges dans une scène isolée avant distribution :
   définir les avertissements visibles, le seuil d'engagement et l'enfermement.
   Ne pas ajouter un piège fatal aléatoire au P05 existant sans ces règles.

6. Traiter la réorganisation comme une couche d'état au-dessus de la graine :
   graine de base + états/révisions des sites. Ne jamais la confondre avec
   l'éviction du cache ni modifier un espace observé ou occupé. Tester d'abord
   une transformation contrôlée hors champ, collisions et bakes compris.
   L'identité persistante actuelle reste une garantie technique utile ; elle
   n'est pas encore une simulation complète du phénomène décrit.

## Conséquences pour la vision générale

Le monde habité et les bases restent des objectifs pour les autres niveaux.
Ne pas peupler ce Level 0 de PNJ ou de monstres ordinaires pour créer du danger.
La survie, l'orientation et l'architecture peuvent porter sa tension.
Garder séparés les rendus de référence artistiques et les règles de cette page :
Kane Pixels nous aide visuellement, mais n'est pas notre source Wikidot.

Le prochain travail conseillé porte sur les profils architecturaux et un pilote
d'arches, avant les dangers irréversibles. Cette lecture ne modifie pas le jeu.
Aucun push ni déploiement.
