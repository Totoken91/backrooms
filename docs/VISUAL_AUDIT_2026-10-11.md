# Consolidation visuelle — raccords et arêtes

Lot local suivant `fcc6025`. Aucun push ni déploiement.

## Défaut reproduit : frontières des chunks

Chaque chunk possède ses propres couches de texture array. Le filtrage linéaire
ne traverse pas les couches : aux bords, il répétait le dernier texel du chunk.
Le test GPU avec deux valeurs constantes 0.2 et 0.6 produisait donc 0.2 juste
avant x=40 et 0.6 juste après, au lieu d'environ 0.4 des deux côtés. Même défaut
pour l'occlusion de contact. Aux coins, la valeur sautait à celle d'un seul chunk.

Correction dans `light_maps.gdshaderinc` :

- Filtrage matériel habituel à l'intérieur de la carte.
- Dans la seule bande d'un demi-texel au bord, interpolation de quatre texels
  provenant des chunks voisins, avec contrôle de propriété des slots.
- Repli sur le bord du chunk courant si le voisin est absent ou son slot a été
  réutilisé ; jamais de lecture de données appartenant à un autre chunk.
- Même traitement pour l'occlusion. Les hauteurs encodées restent lues au
  centre du texel, sans interpolation entre niveaux.

Le test échouait avant correction et passe après, sur les deux axes, un coin,
les coordonnées négatives et les voisins absents/réutilisés. Les tests de
couleur et de sélection sol/plafond/murs restent verts.

## Petits points au pied des murs

Les arêtes horizontales des plinthes font 18 mm. Elles deviennent subpixel à
distance : sans anticrénelage géométrique, elles formaient des points brillants.
L'essai MSAA 4× atténue fortement ces points et stabilise aussi les arêtes des
néons. Le défaut n'a pas été masqué en assombrissant leur lumière.

MSAA 4× activé par défaut dans le projet. Son coût GPU est réel : les captures
ne constituent pas un benchmark, notamment pendant le calcul de lumière.
Option de diagnostic `msaa=0|2|4|8` pour comparer ou revenir au rendu sans MSAA.
Ne pas modifier la géométrie des plinthes sans une nouvelle comparaison.

## Captures examinées

Tous les fichiers ci-dessous sont dans `../backrooms-captures/`, hors dépôt :

- seed 2, entry/reveal : `*-seams-msaa4.png` ; comparaison avant/après
  `audit-plinths-before-after.png` (avant à gauche).
  Frontière X : `godot-s2-seam-x-audit.png`, couloir sombre vers une salle éclairée.
- seed 17, `geotest` : entry, frontière Z, dim0, `*-audit.png`.
  dim0 est entièrement noir : utile pour constater l'absence de lumière
  artificielle, insuffisant pour juger le détail des surfaces.
  La vue frontière X n'était pas disponible sur cette première recherche ;
  elle n'est pas comptée comme vérifiée. Recherche étendue ensuite et capture
  rendue strictement échouée si une vue demandée manque.
- seed 99, monde classique : entry, frontières X/Z, dim0/dim1, `*-audit.png`.
  Pas de quadrillage lumineux ou de ligne de filtrage évidente dans les vues
  examinées ; le motif vertical du papier peint reste volontairement présent.

Les vues `audit` sont choisies automatiquement dans des passages ayant assez
de place des deux côtés de la frontière à 40 m. Elles regardent vers le raccord,
avec un léger angle vers le sol. Les clignotements sont figés pour comparer.

```sh
sh tools/capture.sh seed=99 audit scout=2 scout_r=12 shots=entry,seam-x,seam-z,dim0,dim1 out=../backrooms-captures tag=-audit flicker=1
sh tools/capture.sh seed=2 audit view=seam-x shots=seam-x out=../backrooms-captures tag=-audit flicker=1
GODOT_SCRIPT=res://tests/test_light_transport.gd sh tools/capture.sh
godot --headless --path . --script res://tests/test_world.gd
```

Les vues personnalisées/audit sont maintenant créées avant de sélectionner
`view`, utilisable aussi dans l'URL de diagnostic. Une capture inconnue ne
réussit plus silencieusement en sautant la vue. Un bake toujours incomplet à
la fin de l'attente fait également échouer la capture.

## Validation finale

- Test monde : PASS, 12 seeds.
- Test GPU : PASS, couleurs, couches, filtrage intérieur, frontières et slots.
- Export Web release dans `../backrooms-captures/web-audit/`, hors dépôt.
- Contrôle WebGL local sur seed 99 : shader compilé, lumière calculée, pas
  d'erreur ou d'avertissement dans la console lors du contrôle de la vue entry.
- Aucun changement de génération, de collisions ou d'intensité des lumières.

## Limites et suite

- Ce contrôle ne prouve pas l'absence d'artefacts sur toute graine ou tout GPU.
- Les cartes voisines peuvent être momentanément incomplètes pendant le bake ;
  ce lot ne résout pas les transitions de chargement.
- Les ~20 % d'écart avec Cycles du lot précédent restent à analyser : prochaine
  étape, mesurer la directe aux impacts et le profil vertical des murs.
- Les pics de construction et le temps de bake Web restent à optimiser.
- Avant le nouveau générateur : valider ensuite une scène témoin avec piliers,
  demi-murs, grandes hauteurs et passages étroits, sans multiplier les systèmes.
