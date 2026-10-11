# Coupure de mur, stries et rebonds de lampe — 11 octobre 2026

## Reproductions

Captures utilisateur seed 1601967012 / P04 :
- mur : `(15.05, 17.52)`, cap 52°, tangage 18° ;
- lampe en noir : `(-52.05, -36.79)`, cap 240°, tangage −6°.

Reproduits en natif à 720×540, caméra identique, MSAA4, éclairage stabilisé,
flicker figé à 1, bloom/tonemap normaux. Les images utilisateur 2/3 ne donnent pas
la position du couloir : contrôle analytique des angles rasants et contrôle
visuel d’un autre vrai couloir sombre de la même graine, `(23.75,-86.25)`, cap 90°.
Les captures et journaux sont dans `backrooms-captures`, hors dépôt public.

## Coupure de lumière directe

La passe directe reproduisait une marche verticale sur la même face, près de
la transition de plafond. Le shader interpolait des valeurs encodées mesurées
à trois hauteurs différentes, puis interprétait ce mélange avec le gap du
plus proche texel. Au changement de gap, la reconstruction changeait brutalement.

`wall_surface.gdshaderinc` reconstruit maintenant chaque tap dans son propre
intervalle vertical, puis interpole les quatre énergies reconstruites. Les
lectures aux frontières continuent de respecter le propriétaire du slot voisin.
La reconstruction analytique et les trois hauteurs restent inchangées ; ni
l’exposition ni un filtre flou ne masquent la coupure. Même point de vue avant/
après inspecté, y compris les passes directe et indirecte.

## Stries d’ombre de lampe

Le PCF comparait la distance du fragment central aux profondeurs de quatre
rayons voisins. Sur un sol, plafond ou mur vu à angle rasant, ces rayons
intersectent la même surface à des distances très différentes : auto-ombrage.
Chaque tap est maintenant comparé à l’intersection de son propre rayon avec
le plan récepteur. La marge de profondeur reste petite ; on ne supprime pas
les stries en laissant la lampe traverser des murs. Le test GPU contrôle 96
récepteurs rasants à 8–15,75 m (sol, plafond, mur) : visibilité complète attendue.
L’occlusion par un obstacle séparé reste testée.

## Lampe avec lumière réfléchie

Le faisceau a un cœur et un halo périphérique plus large, avec une transition
progressive (demi-angle 35° environ). Quatre rayons du cône identifient les surfaces
touchées via le SpanMap CPU déjà en mémoire : murs, sols et plafonds inclus.
Chaque impact représente une portion de flux intercepté, réfléchie avec une
couleur moyenne de matériau et un lobe diffus. Les patches proches (moins de 10 m)
éclairent dans un rayon de 6 m ; leur lumière décroît avec la distance et dépend
des normales de la surface émettrice et du récepteur.

Un atlas d’ombres GPU de 144×96 (quatre cubes, faces 24²) empêche les rebonds de
traverser les obstacles. Il partage le traceur exact rayons/intervalles avec
l’ombre directe 128², sans readback GPU ni rebake des néons. Les patches et leur
atlas sont actualisés au maximum 15 Hz pendant le mouvement ; aucun redraw au
repos ou lampe éteinte. Réactivation F et changement de monde invalident les
anciens patches. Le modèle tenu reçoit aussi cette lumière réfléchie, via un
terme séparé de `Player.light`, sans éclairer globalement les zones noires.

C’est une approximation de premier rebond par quatre patches, pas une GI
complète ni un calcul Cycles convergé. Couleurs moyennes des matériaux,
occultation discrète 24² et mise à jour 15 Hz : compromis PC/Web à vérifier sur
les captures en mouvement. Pas d’ambiante constante, de rebond multiple ou de
nouvelle adaptation automatique d’exposition.

## Tests et coût

`test_lighting_regressions.gd` vérifie les distances/normales CPU des slabs,
96 récepteurs GPU rasants, un patch réfléchi visible avant une cloison et
occulté derrière, son extinction avec la lampe, et la continuité d’un mur
à la frontière de deux gaps synthétiques.

Benchmark natif ABBA dans le couloir, 720×540 : médianes éteinte 6,816/6,877 ms,
allumée 6,964/6,940 ms ; P95 9,8–12,2 ms selon les blocs. 209/210 mises à jour de
l’ombre directe contre 21 par bloc pour les rebonds ; zéro mise à jour de
l’une et de l’autre sur 30 images au repos. Ces temps incluent le renderer et
la synchronisation 144 Hz, ils ne mesurent pas isolément le temps GPU. Un appel
de dessin direct supplémentaire, plus un appel les images d’actualisation
de l’atlas réfléchi. Pas de gain universel de fluidité revendiqué.

Les douze suites passent : lighting_regressions, flashlight, light_transport,
light_pipeline, span_maps, streaming, spatial_assembly, varied_assembly, assembly,
promenade, world et variable_ceiling.

## Web local

Export release réussi. Au coin sombre utilisateur, 1280×720, éclairage
stabilisé à 108 bakes et zéro attente : rebonds visibles, console sans erreur
ni avertissement. Benchmark ABBA : médianes éteinte 22,1 / 18,1 ms, allumée
19,0 / 19,8 ms ; P95 38,1 / 26,0 contre 27,0 / 28,1 ms. La dérive du premier
bloc interdit d’en déduire un coût GPU précis ou un gain. Ombre directe
209/210 mises à jour, rebonds 54/54, zéro mise à jour des deux au repos.
La scène Web compile également la nouvelle reconstruction des murs.

## Reproduire

Toujours passer par `tools/capture.sh` :
```
seed=1601967012 composition=P04 at=15.05,17.52,0.90757,0.31416 view=at shots=at flicker=1 msaa=4
seed=1601967012 composition=P04 at=-52.05,-36.79,4.18879,-0.10472 view=at shots=at flicker=1 msaa=4 flashlight=1
seed=1601967012 composition=P04 at=23.75,-86.25,1.5707963,0 view=at shots=at flicker=1 msaa=4 flashlight=1 bench_flashlight=1
```
Conserver le bloom ; `raw` sert uniquement aux mesures scientifiques.
Aucun push ni déploiement dans ce correctif sans nouvelle autorisation.
Validation finale du mur en Web : 99 bakes, aucune attente, raccord continu, console sans erreur ni avertissement. Onglet et serveur de test fermes.
