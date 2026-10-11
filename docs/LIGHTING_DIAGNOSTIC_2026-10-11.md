# Reprise lumière — 11 octobre 2026

Base : `21670cd`. Aucun push ni déploiement. Références et captures conservées
dans `../backrooms-captures/`, hors du dépôt public.

## Diagnostic vérifié

Le bleu existe encore dans les cartes RGBA8 mais disparaît à l'affichage.
Un patch unshaded constant `(0.004, 0.003, 0.001)` linéaire produisait
`(8, 4, 0)` en sRGB 8 bits, au lieu d'environ `(13, 10, 3)`.

Compatibility 4.6 utilise un décodage polynomial d'ALBEDO et une courbe
d'affichage sans la branche linéaire sRGB. `color_space.gdshaderinc` inverse le
polynôme pour transmettre la lumière linéaire correctement. En mode `raw`
seulement, il compense aussi la courbe d'affichage pour les mesures. AgX reste
actif en jeu normal. Sources officielles :
[scene.glsl](https://github.com/godotengine/godot/blob/4.6-stable/drivers/gles3/shaders/scene.glsl),
[tonemap_inc.glsl](https://github.com/godotengine/godot/blob/4.6-stable/drivers/gles3/shaders/tonemap_inc.glsl).

Les ajustements d'image neutres forçaient un deuxième aller-retour sRGB
approximatif. Activer `adjustment_enabled` reproduit la perte dans le test GPU
isolé, même avec le matériau corrigé. Cette passe inutile est désactivée.

Autres corrections :

- Débruitage : moyenne de l'énergie décodée, puis réencodage sqrt ; la moyenne
  de l'encodage assombrissait les zones bruitées. Les hauteurs restent intactes.
- Couches de rebond : le rendu inversait murs et plafond. Ordre confirmé par
  l'upload : 8 sol, 9 plafond, 10 murs.
- Dumps : première passe séparée et valeurs imprimées à six décimales.

Pas d'éclairage ambiant ajouté, ni de changement de portée ou de facteur des
rebonds suivants. Le zéro reste exactement noir dans le test GPU.

## Mesures à un rebond, points de vue identiques

`seed=2 geotest raw tune=debug_view:10`, références `passes-geo1b-*`.
Moyenne géométrique du rapport jeu/Cycles sur les neuf zones :

| Vue | Avant | Après | Bleu/rouge après (Cycles) |
| --- | ---: | ---: | --- |
| dim3, coin sombre | 0.21 | 0.79 | 0.22–0.25 (0.26–0.29) |
| dim0 | 0.71 | 0.80 | ~0.28 (0.30–0.32) |

La sous-estimation restante n'est pas résolue. Les cartes 8 bits gardent une
quantification ; mesurer ensuite la directe aux impacts et le profil des murs
avant de modifier l'encodage ou les rayons. La colonne directe de ces mesures
réutilise les anciennes captures : ce n'est pas une mesure de la correction.

```sh
sh tools/capture.sh seed=2 geotest at=13.75,-8.75,2.03936660010186 shots=at out=../backrooms-captures tag=-codex-final10 tune=debug_view:10 raw dump
sh tools/capture.sh seed=2 geotest at=16.25,-16.25,3.26328084778581 shots=at out=../backrooms-captures tag=-codex-dim0-final10 tune=debug_view:10 raw
node tools/measure-gi.cjs ../backrooms-captures/godot-s2-dim3-geo8.png ../backrooms-captures/godot-s2-at-codex-final10.png ../backrooms-captures/passes-geo1b-dim3-passes.json
```

## Bandes et cases

La texture array reste liée une seule fois en filtrage linéaire. Les hauteurs
sont lues au centre du texel ; ne pas ajouter un second sampler nearest de la
même texture (voir passation). Le test GPU vérifie une valeur intermédiaire
entre texels contrastés, ainsi que les couches sol/plafond/murs distinctes.

Contrôle visuel natif : entry, reveal, interior, east, seed 2, calcul terminé.
Contrôle WebGL : seed 2 entry, directe puis indirecte isolées (F7), calcul
terminé, sans quadrillage lumineux évident ni bandes de filtrage sur ces vues.
Le papier peint a son propre motif vertical. Ces vérifications ne prouvent pas
l'absence d'artefacts sur tous les seeds ou aux frontières des chunks.

Autre artefact visible, hors correction actuelle : petits points lumineux sur
la lèvre de plinthe, surtout en directe. À examiner côté géométrie / aliasing.

## Validation

- Test monde PASS : 12 seeds et invariants de génération.
- Test GPU PASS : uniforms linéaires, noir exact, bleu faible, gris, sélection
  des couches et filtrage bilinéaire du sol.
- Export Web release réussi dans `../backrooms-captures/web-codex/` et contrôlé
  dans le navigateur local ; aucune erreur de shader observée.
- Captures normales natives : 116–132 FPS une fois le calcul terminé sur ces
  vues (pas un benchmark). Pics de construction : 26.6 ms sur la série normale,
  jusqu'à 44.3 ms sur geotest ; optimisation encore nécessaire.
- Le diagnostic de libération d'un shader Canvas à la fermeture existait déjà
  sur la capture de base ; ce n'est pas une compilation échouée.

```sh
GODOT_SCRIPT=res://tests/test_light_transport.gd sh tools/capture.sh
godot --headless --path . --script res://tests/test_world.gd
```

Le lanceur accepte `GODOT_SCRIPT`, transmet le code de sortie du processus,
et arrête les tests sur `FAIL:`. Ne pas lancer deux captures natives en même
temps : le nettoyage des fenêtres est partagé. Le test graphique désactive
l'interpolation pour ses téléportations de caméra.

Demander l'accord de Kenny avant tout push, conformément à la passation.
