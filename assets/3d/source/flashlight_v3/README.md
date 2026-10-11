# Lampe utilitaire noire — v3

Nouvelle géométrie inspirée des proportions d'une Maglite courte, sans logo.
Longueur 23,3 cm, corps 38 mm, tête 57 mm. Bouton caoutchouc, grip à croisillons,
réflecteur concave visible derrière la lentille. Abrasion des extrémités,
rayures fines et variations de rugosité. Sans mains.

## Budget et fichiers

- GLB : 5 952 triangles, 2 meshes, 2 surfaces, 2 matériaux.
- Atlas 1024 × 1024 : albedo, normal OpenGL, ORM, embarqués dans le GLB.
- Source Blender dans `source/`, exclue de l'import par `.gdignore`.
- `preview.png` : rendu Blender de présentation, pas capture du jeu.

## Godot 4.6

Copier le dossier dans `res://assets/flashlight/`, instancier `flashlight.tscn`
sous `Player/Head/Camera3D`. Position et orientation sont préconfigurées.
F allume/éteint lorsque la souris est capturée. Le paramètre `enabled`
permet de commander la lampe depuis le jeu.

Le niveau Hors Plan utilise un shader unshaded avec son propre éclairage.
Il reste à raccorder le faisceau à ce shader et à adapter l'éclairage de
la lampe à `Player.light`. Le projet existant n'est pas modifié par ce pack.
Pas de benchmark de performance Web ; les ombres ajoutent des passes.

## Références

Photos de forme/usure uniquement, non incorporées aux textures :
- https://www.ebay.com/itm/166172682968
- https://maglite.com/products/ml300l-led-2-cell-d-flashlight

Texture utilisée : carte de rugosité **Metal Plate 02**, Rob Tuytel,
Poly Haven, CC0. Modulation de saleté/rugosité, conservée dans `source/`.
- https://polyhaven.com/a/metal_plate_02
- https://polyhaven.com/license

Géométrie, moletage en normal map et masques d'usure créés pour ce projet.
