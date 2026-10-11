# Coût des récepteurs directs et essai de découpage — 11 octobre 2026

## Correction retenue

Chaque texel du bake direct refaisait les quatre visibilités sol/mur bas/mur
médian/mur haut pour chacun des neuf points de chaque néon, même quand la tuile
ne stockait que deux de ces hauteurs. Les quatre tuiles recalculaient donc les
mêmes informations avant de jeter les canaux inutilisés.

Le shader calcule uniquement les visibilités nécessaires aux canaux de sa tuile :

| Tuile | Récepteurs nécessaires |
| --- | --- |
| 0 | sol, mur bas |
| 1 | mur bas, mur médian |
| 2 | mur médian, mur haut |
| 3 | sol (groupes de clignotement), mur haut |
| 4 | encodage des hauteurs, aucun rayon lumineux |

Les hauteurs inférieures nécessaires au fallback des hauteurs solides sont
conservées. Dans le cas courant : huit requêtes de visibilité réparties sur les
quatre tuiles, contre seize auparavant. Cela ne divise pas tout le shader par deux.
Aucun changement de portée, quadrature, radiance, couleurs ou canaux stockés.

`prune_receivers=false` dans le shader est un oracle de test qui reproduit les
quatre visibilités d'origine. Il n'est pas exposé dans l'interface du jeu.

## Mesures répétées natives

Même seed99 entry, MSAA4, raw, néons figés, captures sérialisées sans export ou
autre Godot concurrent. Deux exécutions par variante ; les huit/seize bandes
ont été essayées dans l'ordre 8a, 16a, 16b, 8b, puis la correction 8 bandes a/b.
Échantillon limité à cette machine et cette graine, pas une garantie de FPS.

| Variante | Attente bake a / b | p95 a / b | p99 a / b | Images >33,3 ms a / b |
| --- | --- | --- | --- | --- |
| Référence 8 bandes | 23,14 / 22,38 s | 28,64 / 27,67 ms | 43,65 / 43,62 ms | 3,72 / 3,73 % |
| Essai 16 bandes | 30,39 / 30,70 s | 29,67 / 29,38 ms | 40,35 / 39,63 ms | 3,23 / 3,18 % |
| Récepteurs nécessaires, 8 bandes | 20,68 / 20,32 s | 18,90 / 18,69 ms | 26,85 / 27,68 ms | 0,16 / 0,12 % |

Le p95 observé baisse d'environ un tiers avec la correction retenue, et les
images lentes deviennent beaucoup plus rares. Des pics isolés restent : maximum
67,74 / 86,77 ms après correction. Ne pas annoncer la disparition des à-coups.
Les mesures de durée d'image sont murales, pas des timers GPU isolés.

## Découpage : choix et outils conservés

Seize bandes réduisent les très gros pics mais rallongent le bake de ~34 %
(environ 23 vers 30,5 s), sans amélioration du p95. Le défaut reste huit bandes.
Le débruitage reste lui aussi à huit bandes. Option diagnostic `light_bands=4|8|16`
pour les passes lourdes ; chaque valeur divise exactement les 160 lignes.
Le test du pipeline vérifie l'égalité octet par octet du découpage 8/16 bandes.

Les captures `profile` enregistrent désormais `light_bands`, `bake_wait_ms`,
p99 et pourcentage des images au-dessus de 16,7/33,3/50 ms. L'attente inclut
le minimum de stabilisation de la capture (90 frames, 30 après extinction).
Les quantiles portent sur la collection cumulée des frames de bake de la session,
tandis que l'attente est propre à la vue, extinction incluse si demandée.
Pour comparer des temps, préférer une seule vue par processus.

## Validation et fichiers locaux

- Suite GPU transport passée, avec comparaison byte-identical entre le shader
  complet et l'élagage sur pièce ouverte et sol masquant un néon ; tous les
  canaux RGBA des cinq tuiles sont comparés.
- Suite GPU pipeline passée : oracle CPU/GPU et découpage huit/seize bandes.
- Export Web release local : seed99 entry, 99 passes, zéro calcul en attente,
  aucune erreur ni avertissement console. Onglet et serveur temporaires fermés.
  Contrôle fonctionnel, sans benchmark Web A/B.
- Seed99 entry/reveal et seed2 geotest dim3 : cinq captures par vue,
  identiques pixel par pixel à la version précédente (matériau, directe,
  rebonds, premier rebond, final), soit quinze images de contrôle.

Mesures et captures hors dépôt public dans
`C:/Users/kenny/projects/backrooms-captures/` : tags `bands8-a/b`, `bands16-a/b`,
`receiver-prune-a/b` et `receiver-prune-dim3`. Profils JSON associés aux PNG.

Aucun push ni déploiement. La suite peut cibler le gather et les pics isolés,
avec les nouveaux indicateurs et un rendu inchangé comme contrainte.
