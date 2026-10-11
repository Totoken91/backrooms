# Préparation de lumière et pauses — 11 octobre 2026

Travail local uniquement, sans push ni déploiement. Suite des diagnostics
de lumière et de raccords. Captures et profils JSON dans
`C:/Users/kenny/projects/backrooms-captures`, hors dépôt public.

## Cause mesurée et correction

Sur seed 2, geotest, vue exacte `at=13.75,-8.75,2.03936660010186` :
102 préparations de SpanMap synchrones coûtent 24 504 ms CPU cumulés ; la plus
lente bloque 325,145 ms. Les attentes de rendu ne sont pas comptées dans ce
temps. Le cache de huit cartes ne peut garder toute la région pendant les
trois passes : les reconstructions restent fréquentes.

Le raster parcourt désormais des rectangles de colonnes aux intervalles
constants, découpés sur les projections des boîtes, au lieu d'allouer et de
fusionner les mêmes intervalles pour chaque colonne. Les tests stricts au
centre des colonnes restent identiques. La préparation en jeu cède aussi la
main entre cellules, avec un budget de 3 ms. Ce budget est souple : une cellule
et l'allocation des images restent indivisibles.

Mesures après correction : tranches CPU SpanMap au maximum 3,096 ms sur la
capture finale geotest ; 3,084 ms sur seed 99 classique. Cela ne constitue pas
une garantie de temps de frame global.

Le cache est maintenant lié à l'instance du monde et au mode geotest, avec
éviction LRU et huit entrées maximum. Auparavant une nouvelle graine pouvait
réutiliser la géométrie de l'ancienne aux mêmes coordonnées. Les deux textures
GPU d'une carte sont conservées avec son entrée, puis libérées à l'éviction.
Les cartes CPU et GPU restent en mémoire ensemble, donc le cache consomme plus
de mémoire qu'avant ; sa capacité n'a pas augmenté.

Autres réductions de pics :

- Le filtre de lumière se dessine en huit bandes au lieu d'une passe complète.
- La tuile des hauteurs et les tuiles inutilisées évitent les boucles du filtre.
- La passe directe évite le calcul de radiance pour la tuile des hauteurs.
- La construction des meshes vérifie son budget après chaque cellule, plutôt
  qu'après une ligne entière. L'initialisation `warm()` reste synchrone.

## Validation

- `tests/test_span_maps.gd` : 691 200 colonnes comparées octet par octet à un
  oracle évaluant les boîtes au centre de chaque colonne ; géométrie classique,
  conduits/dalles, C01, coordonnées positives et négatives. Versions synchrone
  et répartie identiques ; changement de monde/mode et capacité du cache testés.
- `tests/test_world.gd` : PASS sur 12 graines.
- `tests/test_light_transport.gd` : PASS GPU, couleurs faibles, sélection des
  couches, raccords et slots obsolètes.
- Capture premier rebond geotest : **zéro canal modifié** avant/après toutes
  les optimisations. Même résultat pour seed 99 entry en rendu normal MSAA 4×,
  comparé à l'audit précédent.
- Export Web release local réussi. Vérification IAB, seed 99 entry, 1280×720,
  MSAA par défaut : 99 passes terminées, zéro calcul restant, aucune erreur
  ni alerte console. Environ 50 FPS à la fin de ce contrôle ponctuel ; ce n'est
  pas un benchmark comparatif. Onglet et serveur local fermés après le test.

Profils natifs finaux pendant le calcul : geotest p50 6,462 ms, p95 18,057 ms,
max 69,314 ms ; seed 99 p50 6,199 ms, p95 21,913 ms, max 68,332 ms. Des pics
subsistent donc. Les attentes d'une bande incluent le GPU, les autres tâches
de la frame et son cadencement ; ce ne sont pas des chronométrages GPU isolés.
La relecture des textures coûte encore jusqu'à 11–14 ms dans ces essais.

Attention : le profil initial utilisait `delta`, que le moteur peut borner.
Les profils finaux mesurent le temps mural entre callbacks. Ne pas annoncer
une réduction du maximum global à partir de ces deux séries incompatibles.
`build_ms` est un total CPU, pas une pause ; `build_slice_cpu_max_ms` mesure
les tranches de streaming et exclut `warm()` (corrigé après les captures).

## Nouvelle mesure contre Cycles

Vue geotest dim3, raw, MSAA 0, mêmes coordonnées et éclairage figé :
capture directe fraîche `godot-s2-at-direct-current.png`, premier rebond
`godot-s2-at-perf-final.png`, référence `passes-geo1b-dim3-passes.json`.

Moyenne géométrique jeu/Cycles sur les neuf régions : **direct 1,03 ; indirect
0,79**. Le direct des régions hautes est à 0,87–0,91 ; celui des régions
basses à 1,07–1,23. Un multiplicateur global ne corrigerait pas ce profil.
Le premier rebond reste particulièrement faible dans le haut droit (0,62).
Radiance, albédo et multiplicateur des rebonds supérieurs n'ont pas changé.

Prochaine investigation lumière : transport du premier rebond, notamment la
lecture du direct aux points d'impact et son profil de hauteur. Ces mesures
n'isolent pas encore une cause unique et ne prouvent pas une correction du
déficit indirect. Prochaine optimisation : relectures GPU et pics de rendu,
puis mesures dans le navigateur ; les chiffres ci-dessus sont natifs.

## Reproduire

Ajouter `profile` à une capture écrit un JSON à côté du PNG. Il contient les
temps CPU et les attentes par phase, plus les quantiles de temps mural des
frames pendant le calcul. Les données ne sont collectées que pour ces captures
(les statistiques agrégées du baker restent disponibles en mémoire).

```sh
GODOT_SCRIPT=res://tests/test_span_maps.gd sh tools/capture.sh
GODOT_SCRIPT=res://tests/test_light_transport.gd sh tools/capture.sh
sh tools/capture.sh seed=2 geotest at=13.75,-8.75,2.03936660010186 shots=at raw flicker=1 msaa=0 tune=debug_view:10 profile out=<dossier-hors-depot>
```

Ne jamais lancer deux captures natives simultanément. Aucun fichier de
référence ni export de travail ne doit entrer dans le dépôt public.
