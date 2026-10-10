# Hors Plan — Backrooms, Niveau 0

Exploration à la première personne du Niveau 0 des Backrooms : papier peint jaune, moquette, plafond suspendu et néons, généré à l'infini à partir d'une graine. Jeu Godot 4.6 (moteur de rendu Compatibility), jouable dans le navigateur.

**Commandes** : ZQSD / WASD (touches physiques, donc AZERTY et QWERTY), souris, Maj pour sprinter, Échap pour la pause (sensibilité souris, son, nouvelle exploration).

## Ce qui est en place

- **Monde** (`scripts/world/`) : labyrinthe classique par chunks de 40 m et composition pilote **C01 « pièce désaxée »** au départ. Toute la géométrie est décrite en boîtes métriques (quantum 0,125 m) partagées par le maillage, les collisions et l'éclairage. Hachages 32 bits spécifiés par domaine : une graine donne le même monde quel que soit l'ordre de chargement.
- **Rendu** : vraies lumières Godot (spots avec ombres) sur les néons proches, éclairage de fond précalculé par chunk contre les collisions (aucune fuite à travers les murs), matériaux PBR générés procéduralement, glow, tonemapping, brouillard, clignotement synchronisé entre lumière et dalle.
- **Jeu** : déplacement physique sans inertie, sprint, regard sans lissage, pause automatique à la perte de la souris, bourdonnement et pas synthétisés.
- **Navigateur** : `web/raw-pointer.js` force la capture brute de la souris. Sous Windows/Chrome, la capture standard produit des sauts parasites mesurés de 676 à 923 px ; si le navigateur refuse la capture brute, ces paquets sont filtrés.

## Développement

```bash
# Tests du générateur (Godot sans fenêtre)
godot --headless --path . --script res://tests/test_world.gd

# Export navigateur local puis serveur sur http://127.0.0.1:8770/
node tools/build-web.cjs
node tools/serve-web.cjs
```

Options de développement dans l'URL (ou après `--` en ligne de commande) : `?seed=N` reproduit un monde, `?view=entry|reveal|interior|east` place la caméra sur une vue QA de C01, `?debug` affiche images/s, souris, chunks et lumières. `-- shots=entry,reveal out=dossier` capture des vues puis quitte.

`tools/export-textures.cjs` régénère les textures de `assets/textures/` à partir des matériaux procéduraux de `tools/art-materials.js`.

## Déploiement

Chaque push sur `main` déclenche `.github/workflows/web.yml` : Godot 4.6 officiel (sommes SHA-512 vérifiées), tests, export, puis publication du build seul sur la branche `web`. Vercel sert la branche `web` telle quelle (`vercel.json` : pas de build, pas de cache obsolète).

## Origine

Reprise d'un prototype WebGL maison (« Hors Plan », étude 0.3.0) dont la conception (`docs/`) guide les compositions à venir : C02 couloir comprimé, C03 enfilade, C04 salle à piliers, C05 cloisons basses, C06 salle de respiration, puis tranche finie bouclée et streaming. Les images de référence utilisées pour l'étude ne sont pas distribuées.
