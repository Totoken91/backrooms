# Lecture des cartes aux impacts du gather — 11 octobre 2026

## Changement

`wall_direct` lisait les quatre cartes directes à chaque impact d'un rayon sur
un mur. Chaque orientation n'utilise que trois cartes consécutives :

| Orientation du mur | Cartes | Canal |
| --- | --- | --- |
| +X | 0, 1, 2 | vert |
| -X | 0, 1, 2 | bleu |
| +Z | 0, 1, 2 | alpha |
| -Z | 1, 2, 3 | rouge |

La lecture sélectionne maintenant ces trois cartes. Les trois énergies de
hauteur et leur reconstruction restent identiques. Pour un impact dans une
zone chargée, cela retire un appel `light_energy`, soit quatre lectures de
texels sur seize au niveau du code, avant optimisations du pilote. Aucun changement du nombre de rayons, de leur trajet,
du filtrage, du stockage ou de la lumière finale. Pas de mémoire supplémentaire.

## Mesures et portée

Seed99 entry, 720 × 540, raw, MSAA4, néons figés. Captures natives sérialisées, deux
exécutions par version, sur cette machine. Référence locale `b0b128e`.

| Variante | Attente bake a / b | p95 a / b | p99 a / b |
| --- | --- | --- | --- |
| Quatre cartes (référence précédente) | 20,684 / 20,317 s | 18,897 / 18,693 ms | 26,853 / 27,682 ms |
| Trois cartes | 20,012 / 20,798 s | 18,264 / 19,002 ms | 27,199 / 27,709 ms |

Le petit gain du premier essai ne se confirme pas au second. Ces relevés ne
prouvent pas un gain global de fluidité ou de FPS : les distributions se
recouvrent. La réduction des lectures demandées par le shader est explicite,
mais ne se traduit pas ici par un effet mesurable séparé du bruit des mesures.
Les pics isolés demeurent (maxima après : 59,021 et 66,390 ms).
La correction précédente des visibilités directes reste le gain majeur établi.

## Validation

- Nouveau test GPU comparant la fonction de production à l'ancienne fonction
  à quatre cartes, avec des valeurs RGBA distinctes : quatre orientations,
  plusieurs hauteurs, interpolation intérieure, frontière de chunks, chunk
  absent et coordonnées négatives non chargées. Résultat identique octet par octet.
- Web release local validé : seed99 entry, 99 passes, zéro attente et console
  sans erreur ni avertissement. Onglet et serveur temporaires fermés. Aucun
  benchmark Web A/B réalisé.
- Suites de transport et pipeline GPU réussies, dont conservation, ombres,
  symétrie des murs, oracle CPU/GPU et découpage en bandes.
- Seed99 entry/reveal et seed2 geotest dim3 : cinq images par vue identiques
  pixel par pixel à la référence précédente (final, matériau, directe,
  indirecte, premier rebond), soit quinze images de contrôle.

Captures hors du dépôt public : `C:/Users/kenny/projects/backrooms-captures/`,
tags `gather-three-maps-a`, `gather-three-maps-b`, `gather-three-maps-dim3`.
Les profils sont à côté des PNG. Référence seed2 dim3 : `receiver-prune-dim3`.

Aucun push ni déploiement. Préserver les mêmes contraintes d'image pour les
prochains travaux ; investiguer le coût de parcours des rayons et les pics
isolés avant d'augmenter leur nombre ou de modifier l'éclairage.
