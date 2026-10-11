# Essai de profil vertical indirect â€” 11 octobre 2026

## DÃ©cision

Ne pas intÃ©grer les trois hauteurs au rendu par dÃ©faut. Le prototype fonctionne
et passe les tests GPU, mais dÃ©grade les deux comparaisons Cycles disponibles.
Aucun gain de fidÃ©litÃ© global dÃ©montrÃ©, donc aucun surcoÃ»t imposÃ© au jeu.
Aucun push ni dÃ©ploiement.

## Protocole et rÃ©sultat

Base locale : `da543d0`, aprÃ¨s correction des faces des murs dans le gather.
MÃªme seed 2, geotest, camÃ©ra, Ã©clairage figÃ©, raw, MSAA 0 et rÃ©fÃ©rences Cycles
Ã  un rebond. Comparaison des captures layer8 (direct) et layer10 (premier rebond).
Ratios : moyenne gÃ©omÃ©trique des neuf zones jeu / Cycles ; 1 est la cible.

| Vue | Direct inchangÃ© | Rebonds base | Rebonds trois hauteurs |
| --- | --- | --- | --- |
| dim3 | 1,02 | 0,93 | 0,89 |
| dim0 | 0,82 | 0,88 | 0,85 |

Dim3 haut droit progresse de 0,79 Ã  0,86 et bas centre de 1,09 Ã  0,96,
mais haut centre rÃ©gresse de 0,84 Ã  0,73 et bas gauche de 0,97 Ã  0,85.
Une moyenne seule ne dÃ©crit donc pas toutes les zones ; aucune conclusion
sur tous les niveaux ou toutes les graines. Le dÃ©ficit direct de dim0 demeure.

Prototype : floor/ceiling + wall low/middle/high Ã  0,4 / 1,65 / 2,9 m
(hauteurs adaptÃ©es au gap), interpolation verticale en Ã©nergie dÃ©codÃ©e,
clamp aux extrÃªmes. MÃªme filtrage spatial qu'avant pour l'affichage ;
transport interpolÃ© en Ã©nergie avant filtrage spatial. Les hits du second
gather lisent le profil du premier Ã  la hauteur d'intersection.
Diagnostic `wall_receiver_fraction` peut forcer les trois couches Ã  une hauteur.

Layout expÃ©rimental : 15 couches par slot au lieu de 11, 5 tiles de gather
au lieu de 3. Sur 49 slots et 160Â² RGBA8 : +20 070 400 octets de textures
GPU (~19,1 MiB), hors copies CPU. Travail de gather accru ; pas de comparaison
chronomÃ©trique rÃ©pÃ©tÃ©e contrÃ´lÃ©e permettant de quantifier le coÃ»t rÃ©el.

Tests expÃ©rimentaux rÃ©ussis : couleurs RGB distinctes par hauteur, mÃ©lange
linÃ©aire d'Ã©nergie, bornes, conservation de radiance uniforme (erreur 1/255),
symÃ©trie par rotation, raccords et couches des surfaces.

## Essai conservÃ© hors du dÃ©pÃ´t public

Dossier local `C:/Users/kenny/projects/backrooms-captures/` :

- `indirect-three-heights-da543d0.patch` : prototype complet et tests, basÃ©
  sur da543d0 (les amÃ©liorations du code retenu depuis sont Ã  prÃ©server).
- `godot-s2-at-height-profile-dim3*` et `...-dim0*` : captures et profils.
- `height-profile-dim3.log` et `height-profile-dim0.log` : logs complets.

Ce patch n'est pas un second mode actif. RÃ©Ã©valuer la cause de l'Ã©cart
(ray marching, reconstruction des sources, orientations du receveur, proximitÃ©
sol/mur) avant de rÃ©introduire une reprÃ©sentation plus coÃ»teuse.

## Optimisation retenue

`bmap` retourne immÃ©diatement zÃ©ro lorsque `use_bounce` est nul. La premiÃ¨re
passe ne transporte que du direct : elle lisait inutilement quatre texels de
premier rebond par hit avant de multiplier leur Ã©nergie par zÃ©ro.
La seconde passe garde exactement le mÃªme chemin.

Suite GPU complÃ¨te rÃ©ussie. Le test de gather noir utilise des cartes de
rebond non nulles et vÃ©rifie que la premiÃ¨re passe reste noire sans direct.
Sur dim3, les cinq captures final/matÃ©riau/direct/indirect/premier rebond
sont identiques pixel par pixel Ã  da543d0 (delta maximal 0/255).
Profil de cette exÃ©cution : p50 6,61 ms, p95 20,967 ms, max 65,767 ms.
Ce relevÃ© isolÃ© ne prouve pas un gain de performances ni la rÃ©solution des
pics de relecture GPU. Captures `godot-s2-at-gather-skip-zero-dim3*`.

Validation Web locale : export release réussi, seed99 entry, 99 passes et zéro
calcul en attente. Console sans erreur ni avertissement. Le graphique révèle
encore des pics pendant le calcul ; l'optimisation ne les élimine pas.
Onglet et serveur temporaires fermés après vérification.
