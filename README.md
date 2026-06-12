# GRIMOIRE ONLINE — v0.3 (Sprint 1 : combat Elden Ring)

Jeu de **survie multijoueur magique** : monde féérique, sorts élémentaires avec
roue des contres, et le pilier du jeu — **la magie se gagne en PvE** (tuer des
boss débloque de nouvelles magies), puis se défend en PvP.

Références : la formule de **V Rising** (survie + pouvoirs débloqués par boss +
sièges de clans), le combat et la caméra d'**Elden Ring** (vue de dos, lock-on,
combos), les sorts/cooldowns de **WoW**, l'univers magique de **Fairy Tail**,
le modèle serveur de **Rust** (un monde = un serveur, pas un MMO mondial).

## Jouer (zéro installation — Godot est inclus dans `tools/`)

| Fichier | Effet |
|---|---|
| `JOUER.bat` | Lance le jeu. **Double-clique 2× pour tester le multi** (une fenêtre héberge, l'autre rejoint `127.0.0.1`) |
| `EDITEUR.bat` | Ouvre le projet dans l'éditeur Godot |
| `SERVEUR_DEDIE.bat` | Serveur headless port 7777 (pour jouer avec des amis : partage ton IP + ouvre le port) |

## Contrôles (type Elden Ring)

| Touche | Action |
|---|---|
| ZQSD / WASD | Déplacement (relatif à la caméra) |
| Souris | Caméra 3ᵉ personne, vue de dos (orbite libre) |
| **Clic gauche** | **Coup d'épée — re-cliquer enchaîne les combos (1→2→3)** |
| Tab / clic-molette | **Lock-on** : verrouille la cible (re-Tab : cible suivante) |
| 1 / 2 / 3 / 4 | Sorts de la magie active (sur la cible verrouillée) |
| R | Changer de magie (parmi celles débloquées) |
| Espace | Dash |
| Échap | Déverrouille la cible, puis libère la souris |
| Molette | Zoom caméra |

**Deux modèles de joueur disponibles** (toggle `USE_HUMAN_MODEL` dans `player.gd`) :

1. **Humain réaliste** (actif par défaut) — personnage Mixamo du repo
   [Tuto-Godot de PeGeDevelopment](https://github.com/PeGeDevelopment/Tuto-Godot)
   (MIT), squelette retargeté sur le profil humanoïde Godot, animé par la
   **MeleeLib** de [Godot4-OpenAnimationLibraries](https://github.com/catprisbrey/Godot4-OpenAnimationLibraries)
   (combo Slash1/2/3, roulade d'esquive, strafes en garde, canalisation,
   réactions aux coups). Pipeline réutilisable : n'importe quel personnage
   Mixamo s'intègre en 5 min via `assets/human/MixamoBoneMap.tres`.
2. **Mage KayKit Adventurers** (Kay Lousberg, CC0 — `assets/kaykit/LICENSE.txt`),
   style chibi cartoon, 75 animations. Chevalier/Barbare/Voleur dispo dans le
   même pack pour des classes futures.

**La mêlée** : 3 coups d'épée enchaînables au clic (le 3ᵉ est un coup à deux
mains plus lourd). L'épée est **imprégnée de ta magie active** → la roue des
contres s'applique aussi en mêlée (épée enflammée ×1.5 contre le boss de glace).
La caméra ne traverse jamais le décor (SpringArm), et en lock-on tu strafes
autour de ta cible comme dans Elden Ring.

⚠ Les sorts se canalisent immobile : **bouger pendant une incantation
l'interrompt** (la mêlée, elle, reste mobile).

## Les sorts actuels

**🔥 FEU** (magie de départ)
| Touche | Sort | Effet |
|---|---|---|
| 1 | Trait de feu | 11 dégâts, instantané, CD 1.2s |
| 2 | Boule de feu | 30 dégâts, incantation 1.8s, CD 6s |
| 3 | Nova ardente | 16 dégâts AoE 8m autour de soi, CD 10s |
| 4 | Météore | 35 dégâts AoE 4m **télégraphiés** au sol (0.9s → esquivable au dash), CD 12s |

**❄ GLACE** (débloquée en tuant le Gardien de Givre)
| Touche | Sort | Effet |
|---|---|---|
| 1 | Éclat de givre | 9 dégâts + ralentit 35% pendant 2.5s, CD 1.2s |
| 2 | Lance de glace | 28 dégâts, incantation 2s, CD 6s |
| 3 | Armure de givre | -30% dégâts subis pendant 5s, CD 14s |
| 4 | Blizzard | 18 dégâts AoE 4.5m télégraphiés (0.8s) + ralentit 50% pendant 3s, CD 12s |

**VFX** : canalisation visible (lueur + particules dans les mains, vue par tous
les joueurs), traînées de particules sur les projectiles (pic de cristal pour
la glace), explosions d'impact, télégraphes de zone au sol lisibles.

Tous les sorts ciblés sont **autoguidés** (comme la boule de feu de WoW) mais
le **décor bloque les projectiles** → se cacher derrière un arbre fonctionne.

## La boucle jouable

1. Tu spawns avec le **FEU**. Le boss est **GLACE** → ton feu fait ×1.5.
2. Au nord-est, un cercle de pierres : **le Gardien de Givre** (400 PV). Il
   poursuit, frappe au corps-à-corps (20) et lance des **traits de givre à
   distance qui ralentissent** → impossible de le kiter gratuitement.
3. **Tous les joueurs qui l'ont blessé débloquent la GLACE** à sa mort.
4. Le boss réapparaît 30 s plus tard.
5. PvP permanent : ta magie active est aussi ton **élément défensif** —
   changer de magie (R) change ton attaque ET ta défense. Mind-game.

## Architecture réseau (déjà en place)

- **Serveur autoritaire** : sorts validés côté serveur (cible, portée, cooldown,
  GCD), dégâts, PV, morts, buffs, déblocage de magie — tout dans `world.gd`.
- Mouvement répliqué par `MultiplayerSynchronizer` (autorité = joueur propriétaire).
- Spawn/despawn répliqués par `MultiplayerSpawner` (joueurs, projectiles, boss).
- Monde généré par code avec une **seed fixe** → identique sur tous les pairs.
- Listen server (héberger = jouer) ou serveur dédié headless (`--server`).
- Testé headless : serveur + bot (`--autojoin` + `--autotest`) qui combat
  réellement le boss (sorts, multiplicateurs, riposte) sans erreur.

## Structure

```
GRIMOIRE_ONLINE/
├── JOUER.bat / EDITEUR.bat / SERVEUR_DEDIE.bat
├── project.godot
├── validate.gd              ← validation headless dev-only
├── scenes/                  ← menu, world, player, projectile, boss
├── scripts/
│   ├── element_data.gd      ← AUTOLOAD : roue des contres (équilibrage défensif)
│   ├── spell_data.gd        ← AUTOLOAD : grimoire des sorts (équilibrage offensif)
│   ├── input_setup.gd       ← AUTOLOAD : mapping clavier (compatible AZERTY)
│   ├── net.gd               ← AUTOLOAD : connexion ENet + registre joueurs
│   ├── menu.gd              ← héberger / rejoindre / args --server --autojoin
│   ├── world.gd             ← génération du monde + logique serveur + HUD
│   ├── player.gd            ← mage : lock-on, combos mêlée, incantation, dash
│   ├── character_rig.gd     ← modèle KayKit Mage + pilotage des 75 animations
│   ├── human_model.gd       ← (archive) humain procédural, remplacé par KayKit
│   ├── third_person_camera.gd ← caméra Elden Ring (orbite, SpringArm, lock-on)
│   ├── projectile.gd        ← sort autoguidé (simulation locale, hits serveur)
│   └── boss.gd              ← Gardien de Givre (IA serveur : mêlée + trait à distance)
└── tools/                   ← Godot 4.4.1 portable (gitignored)
```

## Roadmap (phases honnêtes)

- **Phase 0 — FAIT** : fondation réseau, boss PvE → déblocage de magie, PvP.
- **Sprint 1 — FAIT** : personnage humain, caméra Elden Ring (vue de dos +
  lock-on), combos d'épée au clic, sorts 1-3 sur cible verrouillée.
- **Phase 1 — Survie** : récolte (arbres/pierre), craft, inventaire, jour/nuit, sauvegarde serveur (persistance).
- **Phase 2 — Construction** : poser murs/portes/coffres, destruction par sorts → les **raids de bases**.
- **Phase 3 — Social** : guildes, sièges GvG, donjons d'élite (magies rares : Ombre, Temps, Sang…), Lost Magic.
- **Phase 4 — Steam Early Access** : serveurs loués, anti-cheat (mouvement autoritatif serveur), optimisation 40+ joueurs.

Dette technique assumée pour l'instant (notée, pas oubliée) :
- Mouvement client-autoritaire (un cheateur pourrait se téléporter) → à durcir en Phase 4.
- Le timing d'incantation est mesuré côté client (latence = léger avantage) → serveur en Phase 4.
- Pas d'interpolation des positions distantes (léger stutter possible à haute latence).
- Pas de persistance : tout reset au redémarrage du serveur.
- Un joueur qui rejoint pendant qu'un projectile est en vol peut le voir
  rejouer depuis son point de lancement (visuel uniquement, < 3 s).
