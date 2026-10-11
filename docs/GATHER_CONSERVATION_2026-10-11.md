# Conservation du gather — 11 octobre 2026

Local uniquement. Aucun push ni déploiement. Images hors dépôt public dans
`C:/Users/kenny/projects/backrooms-captures`.

## Erreur isolée

Le gather utilise 16 azimuts et six élévations, uniformes sur la sphère,
avec un décalage d'élévation `lift` propre à chaque texel. Le poids de chaque
rayon est `4π/96`, multiplié par le cosinus positif du récepteur.

Pour le sol, la somme de ces poids vaut exactement
`π * (4/3 - 2*lift/3)`, au lieu de π. Selon le décalage, une radiance constante
est donc intégrée avec une erreur allant jusqu'à ±33 % avant débruitage.
Le plafond subit l'erreur opposée ; les murs ont aussi une erreur de quadrature.
Ce phénomène est distinct du déficit moyen de rebond face à Cycles.

## Correction

Accumulateur séparé de la somme des poids cosinus ; l'intégrale est normalisée
par `π / somme`. Cela préserve les radiances constantes pour tous les récepteurs.
Tous les rayons orientés devant le récepteur comptent dans le dénominateur,
y compris les rayons manqués et les surfaces noires. On ne renormalise donc
pas seulement les contributions lumineuses. Aucune lumière ambiante, aucun
changement d'albédo ni du facteur artistique de rebonds.

Il s'agit d'une quadrature normalisée de résolution limitée. Elle ne garantit
pas l'exactitude pour une radiance très variable, et ne remplace pas un test
contre Cycles. La géométrie, la visibilité et le stockage de l'indirect à une
seule hauteur restent des approximations séparées.

## Test GPU indépendant

Pièce fermée blanche, cartes de radiance réfléchie constantes, directe nulle
sur les quatre canaux. Le résultat attendu est la même irradiance partout,
sur le sol, le plafond et les murs (432 récepteurs contrôlés).

- Avant correction : erreur encodée maximale 24/255 ; exemple sol 0,553,
  plafond 0,435, mur 0,498 pour une valeur attendue 128/255.
- Après : erreur maximale 1/255, dans la quantification RGBA8.
- Contrôle sans radiance : aucune lumière inventée.

Test ajouté à `tests/test_light_transport.gd`. Le test utilise le gather réel,
avec des cartes synthétiques ; il ne recopie pas la formule corrigée.

## Comparaisons réelles

Mêmes caméras geotest seed2, directe et premier rebond isolés, références
`passes-geo1b-*-passes.json`. Première vue dim3 : directe 1,02 et rebond 0,83
fois Cycles, inchangés à deux décimales. Le haut droit reste à 0,62. La correction
de quadrature n'explique donc pas le déficit principal de cette vue.

## Diagnostic des captures

Une capture a dépassé la limite de 240 secondes ; la suivante a été arrêtée
pour investigation. Aucun message de shader dans le journal récupéré. Après
relance seule et instrumentée, dim3 termine ses bakes normalement (56 chunks).
La cause des premières attentes n'est pas établie ; ne pas les présenter comme
une régression GPU démontrée ni comme un incident définitivement résolu.

`tools/capture.sh` accepte maintenant `CAPTURE_LOG` pour conserver le journal
complet hors dépôt. L'option jeu `profile` imprime tous les 120 frames le nombre
de bakes en attente et les FPS. L'arrêt sur erreur et le watchdog restent actifs.
Éviter un export/import Godot concurrent lors des captures pour réduire les
sources d'interférence.

Seconde vue dim0 : directe 0,82, rebond 0,81 fois Cycles, également inchangés
à deux décimales. Certaines régions changent légèrement (bas droit 0,79 → 0,78) ;
ce correctif n'est pas un réglage pour éclaircir les coins. Le déficit de couleur
bleue y reste présent. La suite GPU complète, contrôle noir inclus, passe.

Prochaine investigation : comparer les récepteurs de mur réellement affichés
aux récepteurs calculés (une seule hauteur et normale estimée près des coins),
puis la position des impacts et les normales du raymarch aux intersections
exactes des boîtes. Ne pas augmenter le gain global pour masquer ces écarts.

## Validation du niveau normal

Seed99 entry/reveal, MSAA4, bakes terminés : aucune nouvelle discontinuité
visible sur les murs/sols/plafonds contrôlés. Capture native entry pendant bake :
p95 29,7 ms, maximum 75,0 ms. Ce travail ne résout pas les ralentissements de
préparation ; ces chiffres ne constituent pas un benchmark A/B de performance.

Pendant l'investigation, une modification du lanceur encore en cours d'exécution
a provoqué une erreur de lecture Bash en fin de relance. Cette capture a été
arrêtée explicitement ; les trois captures suivantes ont terminé avec la
version stable. Syntaxe vérifiée par `bash -n`. Ne pas éditer le lanceur pendant
qu'il s'exécute.

Export Web local vérifié dans le navigateur : seed99 entry, 99 passes terminées,
zéro calcul en attente, aucun avertissement ni erreur console. Onglet et serveur
de test fermés après contrôle. Aucun déploiement.
