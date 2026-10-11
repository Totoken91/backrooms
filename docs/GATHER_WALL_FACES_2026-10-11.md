# Faces touchées par les rebonds — 11 octobre 2026

Travail local uniquement. Aucun push ni déploiement. Captures et références
restent dans `C:/Users/kenny/projects/backrooms-captures`, hors dépôt public.

## Défaut corrigé

Le raymarch du gather avance par pas horizontaux de 0,125 m. Quand un pas
traverse les deux axes de la grille, l'ancien calcul préférait X pour choisir
la normale de l'impact. Une face Z pouvait donc lire le champ de lumière X,
parfois noir alors que la vraie face était éclairée. Le défaut concernait la
radiance reçue des murs, pas seulement l'orientation du récepteur affiché.

Le shader vérifie maintenant les colonnes adjacentes à l'impact : si une seule
face est exposée, il prend celle-ci. Aux coins, il compare les temps de traversée
des deux limites de maille. La lecture de lumière utilise aussi la position et
la hauteur de cette intersection, puis le décalage conservé de 0,2 m devant
la face pour éviter de lire les texels internes noirs.

Aucun changement de gain, d'albédo, de portée par défaut (8 m), ni de hauteur
par défaut du récepteur de mur (milieu de son espace libre).

## Test GPU qui isolait le défaut

Une pièce carrée blanche, une seule face éclairée, récepteur exactement au
centre. La source est tournée successivement vers les quatre murs. Avec les
16 azimuts du gather, les rayons sont les mêmes à un quart de tour près ;
les énergies du sol, plafond et mur moyen doivent donc rester identiques.

Ancien calcul, deux orientations :

| Récepteur | Face X | Face Z |
| --- | --- | --- |
| Sol (encodé) | 0,3020 | 0,1608 |
| Plafond | 0,4431 | 0,2196 |
| Mur moyen | 0,3529 | 0,1451 |

Après correction, les deux orientations donnent respectivement 0,2431,
0,3490 et 0,2706. Test dans `tests/test_light_transport.gd`, avec contrôle
également des orientations opposées, de la radiance uniforme et du noir.
Les nombres sont encodés en racine carrée ; ce ne sont pas des ratios d'énergie.

## Comparaison à Cycles

Mêmes caméras geotest seed2, portée 8 m et fraction de hauteur 0,5. Moyenne
géométrique des neuf ratios jeu/Cycles, sur le premier rebond isolé :

| Vue | Directe avant → après | Premier rebond avant → après |
| --- | --- | --- |
| dim3 | 1,02 → 1,02 | 0,83 → 0,93 |
| dim0 | 0,82 → 0,82 | 0,81 → 0,88 |

Dans dim3 haut droit, le ratio de rebond passe de 0,62 à 0,79 ; milieu droit
0,68 → 0,87 ; bas droit 0,79 → 1,00. Ce n'est pas une résolution complète :
le haut droit reste insuffisant et le bas centre atteint 1,09. La couleur
bleue demeure déficitaire dans certaines régions.

## Diagnostics conservés

`tools/audit-gi-receivers.py scene.json dim3` intersecte neuf rayons caméra
avec les boîtes exportées et affiche hauteur réelle, normale réelle, hauteur
et normale estimées au texel de lumière le plus proche. Format caméra 4:3,
tangage nul, comme les captures mesurées ici. Ce sont des sondes de géométrie,
pas des moyennes d'image ni une reproduction du filtrage bilinéaire complet.
`--self-test` vérifie intersections, espaces libres et orientation caméra.
Sur les 18 sondes dim0/dim3, les normales de récepteur correspondent aux faces ;
les hauteurs visibles varient, tandis que le gather reste à 1,6 m.

Deux options QA permettent de séparer d'autres approximations :

- `direct_reach=9.5` : borné à 1..9,5 m pour rester dans la marge d'obstacles
  de 10 m, panneau compris. Par défaut 8 m, inchangé. Dim0 monte de 0,81 à
  0,86 au premier rebond, mais dim3 directe monte de 1,02 à 1,14 avec un excès
  relatif dans ses régions presque noires. Pas adopté comme réglage global.
- `wall_receiver_fraction=0.75` : diagnostic de hauteur, borné à 0,1..0,9.
  Par défaut 0,5, inchangé. Avant la correction des faces, dim3 à 2,4 m passait
  de 0,83 à 0,73 : déplacer un unique échantillon n'est pas une correction.
  Ce résultat n'établit pas le profil vertical exact du transport corrigé.

## Limites et suite

Le raymarch reste discrétisé ; ce correctif ne remplace pas un parcours DDA
exact des obstacles partiels. L'indirect des murs reste stocké à une seule
hauteur, et leur normale est encore estimée près des angles. Comparer ensuite
un profil vertical avec les faces corrigées avant de décider de nouvelles
couches de stockage. Préserver les zones noires et mesurer le coût Web de tout
échantillonnage supplémentaire.

## Validation finale

- Suite GPU passée, symétrie des quatre murs comprise ; noir et radiance
  constante conservés. Autotest de l'audit Python passé.
- Captures natives watchdog : dim3/dim0 geotest, seed99 entry/reveal normaux,
  calcul de lumière terminé. Aucun nouveau raccord cassé visible sur ces vues.
- Profil natif seed99 entry pendant bake : p95 28,9 ms, maximum 62,9 ms.
  Aucune conclusion de gain de performance : les à-coups de préparation restent
  à traiter et ces captures ne sont pas un benchmark A/B strict.
- Export Web local contrôlé dans le navigateur : seed99 entry, 99 passes,
  zéro calcul en attente, aucune erreur ni avertissement console. Onglet et
  serveur temporaires fermés après contrôle. Aucun déploiement.
