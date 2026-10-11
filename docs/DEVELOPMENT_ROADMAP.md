# Feuille de route de développement — Hors Plan

Mise à jour : 11 octobre 2026. Référence : LEVEL0_WIKIDOT_ALIGNMENT_2026-10-11.md.
Les arches sont exclues à la demande de Kenny. Aucun push sans son accord.

## Socle terminé, conservé et testé

- Rendu propre, bloom, panneaux alignés ; mouvement libre et sprint.
- Éclairage personnalisé direct/indirect, volumes SpanMap, streaming et caches.
- Corrections des raccords de hauteur et auto-ombres rasantes.
- Lampe v3 : faisceau, occultation, premier rebond approximé et modèle éclairé.
- C01/C02 : compositions pilotes et plafonds variables.
- P01/P02 : parcours puis contrats et assemblage.
- P03/P04 : tailles, formes L/T/croix et graphes ramifiés avec boucles.
- P05 : réservations distribuées, plafonds streamés, déterminisme et éviction.

Ces étapes restent sélectionnables pour les régressions. Ne pas réimplémenter
ce socle en parallèle. La fidélité du transport lumineux reste approximative :
ne pas présenter les quatre patches de lampe comme une GI complète.

## Ordre de travail

| Étape | Objet | Critère de fin | État |
|---|---|---|---|
| P06 | Profils architecturaux distincts | Champ de piliers reconnaissable, alternant avec les parcours resserrés ; connectivité et rendu contrôlés | Pilote validé — voir P06_SITE_PROFILES_2026-10-11.md |
| P07 | Réservations multi-chunks | Champs beaucoup plus vastes sans joints de génération, collisions ni lumière cassés ; budgets mémoire vérifiés | À faire |
| P08 | Zones noires complètes | Profil spatial/acoustique et sources maîtrisées, transitions éclairées naturelles, lampe utile | À faire |
| P09 | Fosses | Vrai sol absent, gravité et chute, volumes et ombres cohérents, chemins testés | À faire |
| P10 | Pièces rouges | Pilote isolé, avertissements et seuil d'engagement définis, piège spatial contrôlé | À faire |
| P11 | Réorganisation hors regard | État distinct du cache, aucun espace observé/occupé modifié, collisions et bakes invalidés ensemble | À faire |
| P12 | Boucle de survie | Ressources, fatigue et orientation au service de ces espaces ; paramètres discutés et mesurés | À concevoir |

P06 commence avec un pilote borné au site P05 : il sert à valider l'identité
architecturale, pas à prétendre avoir déjà des étendues kilométriques.
P07 devra traiter le propriétaire d'une réservation et ses volumes dans plusieurs
chunks avant d'agrandir arbitrairement les rectangles.

## Méthode à chaque étape

Une étape = un comportement jouable, un document d'architecture, des audits
ciblés indépendants, captures normales avec bloom et validation Web locale.
Les images restent hors dépôt public. Utiliser tools/capture.sh pour les jobs
natifs. Signaler les limites et conserver les étapes précédentes.
Ne pas introduire tous les dangers et systèmes de survie dans le même patch.

## Choix actuels

Pas d'arches. Pas de PNJ ou de monstres ordinaires ajoutés au Level 0.
Pas de pièces rouges mortelles distribuées avant un pilote lisible.
La réorganisation ne se déclenche jamais simplement parce qu'un chunk est évincé.
La graine décrit le monde de base ; un futur état de site portera ses changements.
Le monde habité et les bases demeurent des objectifs pour d'autres niveaux.
