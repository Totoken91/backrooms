# Transport de lumière et bandes sur les murs — suite du 11 octobre 2026

Local uniquement. Aucun push, aucun déploiement. Images et profils dans
`C:/Users/kenny/projects/backrooms-captures`, hors dépôt public.

## Corrections

### Interpolation aux impacts

Les cartes stockent `sqrt(E / range)`. Le gather interpolait ces valeurs puis
les élevait au carré, perdant de l'énergie aux transitions. Par exemple, entre
0,2 et 0,6 encodés, il obtenait 0,16 plutôt que la moyenne physique 0,20.
`light_energy()` décode les quatre texels avant interpolation, avec les mêmes
contrôles d'appartenance aux chunks voisins. Seul le transport l'utilise pour
l'instant ; l'affichage conserve son chemin existant.

Cette erreur est réelle, mais sa correction seule laisse le ratio dim3 à
0,79 à deux décimales. Elle n'explique donc pas le déficit principal.
La lecture nécessite quatre taps au lieu d'un lookup filtré ; surveiller son
coût sur le Web. Une première capture après compilation a eu une attente de
bande de 1,33 s ; elle ne démontre pas un coût récurrent de cette ampleur.

### Ombres à chaque hauteur

Le direct réutilisait la visibilité du sol pour l'échantillon bas des murs,
situé 0,4 m plus haut. Une dalle peut cacher le néon au premier et le laisser
visible au second. Le shader calcule maintenant les quatre visibilités : sol,
mur bas, milieu et haut. Cela ajoute un trajet de visibilité par point du
néon ; le coût de la passe directe augmente.

Le test GPU place une dalle de 0,6 m près des récepteurs : le sol est noir,
le mur bas reçoit de la lumière (valeur encodée 0,20). Après retrait de la
dalle, les deux reçoivent de la lumière.

### Échantillonnage des panneaux

Les neuf points du panneau étaient tous déplacés par un même jitter qui
changeait à chaque texel. Cela déplaçait le centre de l'émetteur échantillonné.
Le profil vertical des murs pouvait étirer ces variations en stries.
Les neuf points utilisent désormais une quadrature de Gauss-Legendre
symétrique, avec des poids dont la somme représente exactement la surface
du panneau (0,694444 m²), sans modifier sa radiance.

La symétrie est testée sur deux récepteurs en miroir autour du même néon.
Cela supprime cette source de bruit sans ajouter de rayons. Les ombres de
panneau restent une approximation à neuf points, filtrée spatialement : ne
pas promettre des pénombres parfaites pour toutes les ouvertures.

## Bandes signalées pendant les tests

Kenny a signalé des bandes encore visibles sur un mur, puis a trouvé les
tests visuellement satisfaisants. Ne pas interpréter cela comme une preuve
d'absence de bandes sur toutes les graines.

Isolation seed 99 entry, même caméra, même bake : matériau seul (6), direct
(8), indirect (9), premier rebond (10). Le papier peint présente ses fines
rayures ; le direct possède aussi ses variations larges liées à l'éclairage.
La comparaison avant/après quadrature garde la même luminance moyenne (162
en sRGB) sur la région du mur droit [0,68;0,48]–[0,96;0,64]. Ce chiffre ne
mesure pas à lui seul la disparition des stries.

Option de capture `layers` : écrit quatre PNG supplémentaires `-layer6`,
`-layer8`, `-layer9`, `-layer10`, puis restaure le mode de chaque matériau.
Elle évite quatre bakes distincts pour comparer texture et lumière.

## Mesures Cycles

Graine 2 geotest, raw, MSAA 0, éclairage figé à 1. Références un rebond
`passes-geo1b-dim3-passes.json` et `passes-geo1b-dim0-passes.json` inchangées.
Ratios jeu/Cycles, moyennes géométriques des neuf régions :

| Vue | Direct frais | Premier rebond avant | Premier rebond après |
| --- | --- | --- | --- |
| dim3 (13,75; −8,75; yaw 2,03936660010186) | 1,01 | 0,79 | 0,81 |
| dim0 (16,25; −16,25; yaw 3,26328084778581) | 0,82 | 0,80 | 0,80 |

Dim3 bleu/rouge : environ 0,24–0,25 dans le jeu, contre 0,26–0,29 Cycles ;
avant les corrections, certaines régions étaient à 0,22. Le haut droit reste
faible (ratio indirect 0,63). Dim0 montre un déficit direct particulièrement
en haut : le profil en trois hauteurs reste une piste à examiner. Ne pas
déduire du direct dim3 proche de 1 que le direct est calibré partout.

Radiance, albédo, exposition et facteur des rebonds supérieurs inchangés.
Aucun remplissage ambiant ajouté. L'écart indirect reste ouvert.

## Validation et suite

- GPU PASS : tests précédents plus énergie à l'intérieur/aux raccords,
  ombres distinctes sol/mur bas, symétrie du panneau.
- Captures normales et isolées seed 99 ; deux vues geotest comparées à Cycles.
- Export Web release local réussi ; contrôle navigateur consigné ci-dessous.

WebGL/IAB, seed 99 entry, 1280×720, MSAA par défaut : les 99 passes terminent,
aucune erreur/alerte console. Le compteur affiche ponctuellement 60 FPS après
le calcul ; ce n'est pas un benchmark. Les pics pendant le bake subsistent.
Onglet temporaire fermé et serveur localhost arrêté après vérification.

Capture finale dim3 native : frame p50 6,693 ms, p95 22,639 ms, max 69,998 ms
pendant les calculs. Les attentes de bande comprennent aussi le cadencement
et ne sont pas une mesure GPU pure. Pas de revendication de gain de fluidité
sur cette étape : les corrections visent la validité du transport.

Suite : reconstruction verticale du direct et du rebond sur les murs, avec
tests analytiques de profils et comparaison à plusieurs vues Cycles. Optimiser
les relectures et les visibilités supplémentaires sans réintroduire les
raccourcis géométriquement faux.
