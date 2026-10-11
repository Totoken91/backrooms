# Chargement, retours et extinction pendant un calcul — 11 octobre 2026

Travail local uniquement. Aucun push ni déploiement.

## Défaut reproduit et correction

Une extinction pendant une passe directe pouvait marquer le chunk pour un
recalcul, puis la passe déjà lancée publiait son ancien résultat et avançait
le drapeau à la première passe indirecte. Le nouveau direct était donc sauté.
Le premier essai de `test_streaming.gd` reproduit cette erreur dans
`streaming-before.log`, hors dépôt.

Chaque chunk porte désormais une révision lumière. Une extinction incrémente
les révisions affectées ; les passes suspendues ne publient que si le monde,
l'instance chargée et la révision correspondent encore. Même protection pour
les gathers et après la préparation répartie de l'AO. Une extinction est prise
en compte même si la toute première carte directe n'existe pas encore. Une
nouvelle modification voisine pendant le second gather revient au premier
gather, sans écraser une invalidation directe plus forte.

Une construction de géométrie suspendue vérifie aussi son monde et son
propriétaire avant de publier après une nouvelle exploration. Les opérations
obsolètes terminent leur travail puis sont rejetées ; ce n'est pas une
annulation anticipée du coût GPU. Le compteur `discarded_bakes` est cumulatif.

## Tests ciblés de l'ordonnanceur

`tests/test_streaming.gd` utilise le véritable WorldStreamer et les uploads
Texture2DArray, avec un baker retardé produisant des cartes synthétiques et
une construction de chunks minimale. Il teste :

- extinction pendant la passe directe, pendant son premier calcul et pendant
  le second gather d'un voisin ; résultat ancien rejeté et étape correcte ;
- franchissements en coordonnées négatives et positives ;
- déplacement de sept chunks (réutilisation des slots modulo), puis retour ;
- état d'extinction conservé après déchargement/rechargement ;
- nouvelle graine pendant une passe suspendue ;
- terminaison de l'ordonnanceur, propriétaires et données directes réellement
  présentes dans les slots GPU des 25 chunks centraux.

Ce test isole la logique asynchrone ; il ne vérifie pas la physique du transport
lumineux ni la navigation du joueur. Les tests GPU de transport et du pipeline
restent séparés et passent aussi.

## Contrôles avec le véritable rendu

Captures natives 720×540, MSAA4, raw, groupes de clignotement forcés à 1 :

- Seed99 : entry → seam-x → seam-x-across → seam-x-back → entry. Les changements
  de vue sont des téléportations. Toutes les attentes se terminent ; la vue du
  raccord avant/après est identique pixel par pixel. La vue entry finale est
  identique à `godot-s99-entry-gather-three-maps-b.png`.
- Seed7 : même séquence avec `walk_audit`. Les deux franchissements courts
  interpolent la position sur 36 frames et vérifient le dégagement à chaque
  point ; les autres changements de vue restent des téléportations. La vue
  du raccord avant/après est identique pixel par pixel, zéro calcul restant.
- Seed99, entry, `off` : extinction effective du panneau c260, recalcul achevé,
  zéro attente restante. 1 084 994 canaux de l'image changent, sur 1 166 400.
  Ce nombre confirme une modification, pas une mesure de justesse physique.

Les deux parcours mesurés ont respectivement p95 17,407 / 20,332 ms, maximum
146,764 / 63,319 ms. Statistiques cumulées pendant les calculs, pas benchmark
A/B et pas mesure GPU isolée. Les pics persistent ; aucune amélioration globale
de fluidité n'est revendiquée. Ces courts parcours ne remplacent pas une longue
session interactive ni une validation navigateur, non refaite dans ce lot.

Les premières captures de parcours précèdent le déplacement de l'affectation
CPU des cartes directes après l'attente AO ; le test d'extinction réelle et les
trois suites passent sur cette dernière version.

## Reproduire

Toujours via le watchdog, jamais deux processus GPU natifs simultanés :

```sh
GODOT_SCRIPT=res://tests/test_streaming.gd sh tools/capture.sh
GODOT_SCRIPT=res://tests/test_light_transport.gd sh tools/capture.sh
GODOT_SCRIPT=res://tests/test_light_pipeline.gd sh tools/capture.sh
sh tools/capture.sh seed=7 audit walk_audit shots=entry,seam-x,seam-x-across,seam-x-back,entry raw flicker=1 msaa=4 profile out=<hors-depot> tag=-streaming-walk
sh tools/capture.sh seed=99 shots=entry off raw flicker=1 msaa=4 profile out=<hors-depot> tag=-streaming-off
```

Captures, journaux et profils dans
`C:/Users/kenny/projects/backrooms-captures`, tags `streaming-route`,
`streaming-walk` et `streaming-off`. Aucun média de référence dans le dépôt.

## Suite

Cette validation ciblée débloque le travail sur les volumes à hauteur variable
et les compositions. Conserver les tests de parcours pour les prochaines
modifications. Une longue exploration avec chargement continu et un contrôle
Web restent nécessaires avant toute publication ; les pics ne sont pas clos.
