# Profil vertical de lumière — 11 octobre 2026

Local uniquement ; aucun push ni déploiement. Captures conservées hors dépôt,
dans `C:/Users/kenny/projects/backrooms-captures`.

## Modification

Les trois échantillons de lumière directe des murs étaient interpolés par
une parabole dans log(E). Près du plan des néons, cette extrapolation peut
rester trop lumineuse ou sous-estimer le haut du mur.

Pour une source ponctuelle dirigée vers le bas, un récepteur vertical reçoit
`E = A*d/(r²+d²)²`. La quantité `sqrt(d/E)` est donc linéaire en `d²`.
Le shader reconstruit cette quantité à partir des trois valeurs stockées,
puis retrouve E. Une interpolation quadratique permet d'approcher les panneaux
étendus et les groupes de sources. Affichage et transport partagent la fonction.

Les échantillons nuls/ombrés, les dénominateurs invalides et les sources sous
l'échantillon haut conservent l'interpolation logarithmique précédente.
La borne existante `1.15 * max(samples)` est inchangée ; aucune lumière ambiante
n'a été ajoutée. Le plan source est celui du bake actuel : plafond global moins
0,01 m. Des néons à plusieurs altitudes demanderont un modèle adapté.

## Mesures indépendantes

`tools/measure-wall-profile.py` intègre un panneau carré par 48×48 points,
puis compare les reconstructions sur 63 hauteurs. Erreurs relatives moyennes,
avec la même borne de sécurité :

| Distance au centre du panneau | Ancien log | Nouveau profil |
| --- | --- | --- |
| 0,43 m | 3,40 % | 8,30 % |
| 0,50 m | 2,51 % | 7,94 % |
| 0,75 m | 16,15 % | 4,39 % |
| 1 m | 23,86 % | 2,03 % |
| 2 m | 21,87 % | 0,24 % |
| 4 m | 18,10 % | 0,01 % |

Ce n'est pas une solution exacte pour une source étendue : à très faible
distance, l'ancien profil est meilleur dans ce test. Les captures normales
seed99 entry/reveal ne montrent pas de nouveau saut de lumière près des panneaux.

## Comparaison Cycles

Scène geotest seed2, mêmes caméras et références `passes-geo1b-*-passes.json`.
Moyenne géométrique des neuf ratios jeu/Cycles, directe et premier rebond :

| Vue | Directe avant → après | Rebond avant → après |
| --- | --- | --- |
| dim3 | 1,01 → 1,02 | 0,81 → 0,83 |
| dim0 | 0,82 → 0,82 | 0,80 → 0,81 |

Dans la rangée haute dim3, les ratios directs passent de 0,89/0,81/0,87
à 1,01/0,92/1,02. Le rebond haut droit reste à 0,62 : le déficit de transport
n'est pas résolu. Le gather ne stocke toujours qu'une hauteur d'indirect sur
les murs ; les approximations de visibilité restent à investiguer.

## Vérification

- Test GPU `tests/test_light_transport.gd` : loi ponctuelle indépendante,
  rayons 2/4/8 m, cinq hauteurs entre et hors échantillons ; noir conservé.
  Suite transport complète passée.
- Captures watchdog : geotest dim3/dim0, seed99 entry/reveal, bake terminé.
- Export Web local, seed99 entry : 99 passes terminées, zéro calcul en attente,
  aucune erreur ni avertissement console. Aucun fichier de référence ajouté au dépôt.

## Fluidité

Capture native seed99 entry : frames pendant bake p95 27,6 ms, maximum 57,1 ms,
relecture CPU maximale 16,8 ms. Ces mesures ne prouvent pas une amélioration
de performance : les compilations et la charge de la machine varient entre runs.
Les à-coups pendant le calcul restent une tâche séparée.

## Prochain diagnostic conseillé

Isoler le premier rebond sur un mur uniforme à plusieurs hauteurs, avec une
source ponctuelle puis un panneau étendu. Comparer visibilité, albédo et énergie
avant de modifier le gain global ou le nombre de rebonds. Tester ensuite une
transition clair/sombre entre chunks en mouvement. Le profil direct à très
faible distance d'un panneau doit aussi rester dans les scènes de contrôle.