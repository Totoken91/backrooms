# Débruitage sans transfert CPU intermédiaire — 11 octobre 2026

## Changement retenu

Avant : dessiner le bake, lire toute la texture sur CPU (`get_image`), la
convertir en RGBA8, recréer une texture GPU, débruiter, relire le résultat.
Après : dessiner dans un viewport brut, le débruiteur échantillonne directement
sa texture dans un second viewport, puis une seule relecture du résultat final.
Les deux cibles sont réutilisées et mises à jour uniquement à la demande.
Une passe sans débruitage relit simplement la cible brute.

Deux cibles distinctes évitent de lire une texture pendant qu'on écrit dedans.
Le dessin reste en huit bandes, une par frame. Les formats des images retournées,
le découpage en tuiles et les onze couches de stockage ne changent pas.
Aucune modification des matériaux, des algorithmes lumineux ou de la génération.
Le viewport supplémentaire représente 800 × 160 × 4 = 512 000 octets pour sa
couleur RGBA8 (~0,49 MiB), hors autres ressources internes au moteur.

## Mesures natives

Mesures ponctuelles sur la même machine, hors build/export concurrent.
Elles ne constituent pas un benchmark répété permettant de promettre plus de FPS.

| Capture | Relectures avant / après | Temps CPU cumulé avant / après | Maximum par relecture avant / après |
| --- | --- | --- | --- |
| seed2 geotest dim3 | 209 / 104 | 256,511 / 57,956 ms | 11,567 / 1,864 ms |
| seed99 entry | 198 / 99 | 235,553 / 52,489 ms | 15,922 / 1,827 ms |

La capture dim3 s'arrête quand les chunks jouables ont fini ; une passe de la
couronne extérieure peut encore être partiellement comptée. D'où un compteur
avant impair. Le test isolé vérifie exactement une relecture par passe complète.

Temps d'images pendant les bakes : dim3 p95 20,967 vers 21,535 ms, maximum
65,767 vers 76,992 ms. Seed99 après : p95 29,959 ms, maximum 72,622 ms.
Les pics restent présents ; aucune amélioration globale de fluidité démontrée.
La correction supprime un transfert et réduit son coût observé. Le travail GPU,
la compilation, les autres tâches et la relecture finale restent à mesurer.

## Validation

- Nouveau `tests/test_light_pipeline.gd` : compare le chemin GPU à un oracle
  reproduisant l'ancienne lecture CPU et re-création d'ImageTexture. Deux motifs
  RGBA, directe et gather, rayons 0/1/3, cinq tuiles, bandes et réutilisation des
  cibles : images identiques octet par octet. Une relecture par passe vérifiée.
- Suite `tests/test_light_transport.gd` réussie.
- Export Web release local : seed99 entry, 99 passes, zéro calcul en attente,
  console sans erreur ni avertissement. Cibles brutes/filtrées correctement
  échantillonnées dans WebGL. Onglet et serveur temporaires fermés ensuite.
  Des pics restent visibles pendant le calcul ; pas de benchmark Web A/B.
- Captures dim3 et seed99 entry/reveal : cinq images par vue (final, matériau,
  directe, indirecte et premier rebond) identiques pixel par pixel aux captures
  précédentes. Delta maximal 0/255. Calcul de lumière terminé pour les vues.

Captures et logs hors du dépôt public :
`C:/Users/kenny/projects/backrooms-captures/` ; tags `gpu-filter-dim3` et
`gpu-filter` (seed99). Comparaisons dim3 avec `gather-skip-zero-dim3` ; seed99
avec `wall-faces-fixed`. Profils JSON à côté des PNG.

Reproduction (une commande à la fois, sans autre Godot en cours) :

```sh
GODOT_SCRIPT=res://tests/test_light_pipeline.gd sh tools/capture.sh
GODOT_SCRIPT=res://tests/test_light_transport.gd sh tools/capture.sh
sh tools/capture.sh seed=99 shots=entry,reveal flicker=1 layers raw msaa=4 profile out=<hors-depot> tag=-gpu-filter
```

Toujours aucun push ni déploiement.
