# DOWN HERE ! — Vision directeur : de la cellule aux étoiles

Document de direction (12/06/2026). Écrit AVANT le code, à la demande du
directeur. Décisions actées: GPL accepté, un seul jeu / une seule fenêtre,
Thrive devient la base, notre sim colonie se porte dedans, on ne réinvente
pas la roue — on UNIFIE des projets open-source existants sous une seule
direction artistique et une seule progression.

## 0. Le principe directeur : UNE colonne vertébrale, on RÉCOLTE le reste

On ne fusionne PAS 18 projets Godot (moteurs, ECS, autoloads, styles
incompatibles — ça ne tient pas dans une fenêtre). Règle d'or :

> **Thrive (rebrandé DOWN HERE) est l'UNIQUE moteur/épine.** Tous les
> autres projets de la liste sont des RÉFÉRENCES de design et de code, pas
> des dépendances. Pour chaque stade, on étudie la référence, on en RÉCOLTE
> les mécaniques, et on RECONSTRUIT le stade comme une scène Thrive, dans
> NOTRE art et branché sur NOTRE sauvegarde/progression.

Pourquoi Thrive comme épine et pas un autre :
- Il a DÉJÀ la machine à états de progression Spore complète (microbe →
  multicellulaire → macroscopique → éveil → société → industriel → spatial
  → ascension) + un SceneManager + un système de sauvegarde + des
  paramètres data-driven + une couche native C++ perf (GDExtension).
- Son stade cellulaire est le plus profond de tout l'open-source.
- Ses stades tardifs sont SQUELETTIQUES — c'est exactement là qu'on greffe
  les mécaniques riches récoltées ailleurs.

## 1. Le fil conducteur unique : TON génome, de la cellule au colon

Le truc qui transforme 18 sources en UN jeu, ce n'est pas la techno, c'est
l'IDENTITÉ. Une seule chose persiste à toutes les échelles : **l'organisme
que TU construis.**
- Tu assembles ta cellule (éditeur Thrive amélioré).
- Elle devient ton corps multicellulaire, puis ta créature.
- Cette créature devient ton ESPÈCE.
- Au passage à la tribu, tes individus = des créatures de ton espèce.
- **Tes colons, plus tard, SONT ton espèce évoluée** — pas des PNJ
  génériques (les NPC KayKit qu'on avait codés sont donc OBSOLÈTES, on les
  abandonne). Variation individuelle, mais même plan corporel hérité.
- Ta civilisation, ton esthétique spatiale : tout porte la marque de ce que
  tu as fait naître dans la flaque primordiale.

C'est ça, "Down Here" : une continuité de vie ininterrompue, du microbe à
l'empire stellaire, qui est LA TIENNE.

## 2. La progression et les points de GREFFE

On suit la progression de Thrive tant qu'elle est forte, puis on bifurque
sur NOTRE système au bon endroit (le "joint").

| Échelle | Épine / source de mécaniques | Statut Thrive | Action |
|---|---|---|---|
| Cellule / métabolisme / évolution | **Thrive** (base) | profond | polir, rebrander |
| Évolution par traits / sélection | Genesis (réf.) | — | récolter l'algo d'auto-evo |
| Multicellulaire → créature | **Thrive** | correct | améliorer l'éditeur de corps |
| Écosystème / biomes vivants | CellForest / A Tree Falls (réf.) | faible | récolter propagation/biome |
| **GREFFE: créature → peuple** | Thrive *awakening* + NOTRE sim | squelette | **porter RimWorldLab.Core ici** |
| Tribu / agents / récolte | ant-colony (réf.) | squelette | récolter pathfinding agents |
| Colonie / cité / économie | Unknown Horizons port, CityBuilder (réf.) | — | récolter prod/commerce/taxes |
| Construction en jeu | In-Game Building System (réf.) | — | récolter grille de build |
| Usines / industrialisation | GDQuest 2D Builder (réf.) | embryon | récolter chaînes de prod |
| RTS terrestre | godot-open-rts (réf.) | — | récolter contrôle d'unités |
| Combat tactique hex | godot-turnbased-hex-strategy (réf.) | — | récolter combat hex |
| Civ / 4X | OpenCiv3, Simulatio Humanitatis (réf.) | embryon | récolter diplomatie/tech tree |
| Vol / aérien | godot-simplified-flightsim (réf.) | — | récolter vol simplifié |
| Système solaire / orbital | I, Voyager (réf.) | embryon | récolter mécanique orbitale |
| Expansion solaire | Astropolis (réf.) | — | récolter colonisation système |
| Space sim / combat spatial | GDTLancer, yoel-space-sim (réf.) | embryon | récolter vaisseaux/combat |
| Multijoueur (option lointaine) | godot-multiplayer-template (réf.) | — | si un jour réseau |

**Le joint principal** = le stade *Awakening* de Thrive (l'animal qui
devient outilleur/tribu). C'est là que ton espèce devient TON PEUPLE et que
notre simulation de colonie prend la main. Avant le joint = Thrive règne.
Après = notre vision (colonie → cité → civ → terre → espace), bâtie en
récoltant les références, sur l'épine Thrive.

## 3. Les 5 piliers d'UNIFICATION (sinon ça reste un patchwork)

1. **Une métaphore d'échelle** — transitions de zoom cohérentes entre
   échelles (cellule dans une goutte → organisme dans un biome → tribu sur
   une tuile → colonie sur une planète → planète dans un système). On garde
   l'idiome de transitions par stade de Thrive.
2. **Une direction artistique** — un seul langage visuel. Le procédural
   organique semi-réaliste de Thrive est la référence par défaut; les
   stades civ/espace adoptent une palette et un rendu compatibles. ZÉRO
   mélange cartoon/réaliste.
3. **Le fil d'identité** — le génome/espèce du joueur s'exprime à chaque
   échelle (créature → colons → esthétique de civilisation).
4. **Une sauvegarde & progression** — un méta-save unique portant le génome,
   les stades débloqués, l'histoire. Base = système de save de Thrive.
5. **Une épine de données** — params data-driven (les JSON
   simulation_parameters de Thrive) étendus aux stades tardifs (biomes,
   espèces, techno, corps célestes).

## 4. Le rebranding (contrainte directeur ferme)

Le jeu ne doit JAMAIS renvoyer le joueur vers Thrive.
- Branding 100% DOWN HERE (déjà commencé: le menu affiche DOWN HERE!).
- "Voir le code source" → NOTRE dépôt, pas celui de Thrive.
- "Crédits" → DOWN HERE / direction, pas Revolutionary Games en façade.
- Obligation légale GPLv3 (on l'assume): on CONSERVE les notices de licence
  et copyright dans le code source et dans un fichier LICENSES/THIRDPARTY
  discret de la distribution. C'est suffisant pour la loi sans mettre
  "Thrive" devant le joueur. (On respecte la GPL, on ne la trahit pas — on
  ne la met juste pas en vitrine.)

## 5. Feuille de route directeur (un jeu JOUABLE à chaque palier)

- **Phase 0 — Fondation & identité (immédiat)**
  Thrive-rebrandé devient le projet principal du dépôt. Scrub des liens
  sortants vers Thrive (source → notre dépôt). Le stade cellulaire se joue
  de bout en bout sous DOWN HERE. On retire l'ancienne coquille
  RimWorldGodot et mes jouets (MicroStage 380 lignes, CellEditor) — rendus
  obsolètes par cette décision.
- **Phase 1 — L'ascension organique (force de Thrive)**
  Cellule → multicellulaire → créature. On transforme l'éditeur de Thrive
  en NOTRE créateur d'organisme (le "assemble ton être" que tu adores) et
  on pose le fil d'identité (génome persistant).
- **Phase 2 — La greffe : créature → peuple**
  Au stade éveil, l'espèce devient tribu; les individus = créatures de ton
  espèce. On porte notre SIM de colonie (RimWorldLab.Core, portable) comme
  cerveau de simulation de ce stade. Les vieux PNJ sont remplacés par tes
  créatures évoluées. Références: ant-colony, Unknown Horizons, building kit.
- **Phase 3 — La civilisation terrestre**
  Colonie → cité → industrie → RTS/tactique/civ. Récolte: CityBuilder,
  GDQuest factory, godot-open-rts, hex-strategy, OpenCiv3 — reconstruits en
  stades unifiés.
- **Phase 4 — Vers les étoiles**
  Vol → système solaire → expansion → combat spatial. Récolte: I Voyager,
  Astropolis, GDTLancer, space-sim. Les stades space/ascension de Thrive
  donnent le squelette.
- **(Plus tard, option) Multijoueur** via le template P2P.

## 6. Ce qui devient OBSOLÈTE (assumé)
- Les PNJ/colons KayKit codés à la main (remplacés par l'espèce du joueur).
- La coquille RimWorldGodot comme application principale (Thrive prend le
  relais; on n'en garde que la SIM portable RimWorldLab.Core).
- MicroStage (le jouet 380 lignes) et CellEditor (mon ébauche d'éditeur) —
  remplacés par le vrai éditeur de Thrive amélioré.
- Le modèle Origins/ que j'avais commencé (CellModel/Microbe) — son rôle
  est assuré, en mieux, par Thrive. On le garde comme référence de design
  un temps, puis on le retire.

## 7. Risques & honnêteté directeur
- Ambition à l'échelle de PLUSIEURS années. On la rend tenable en livrant
  un jeu JOUABLE à chaque phase et en ne bloquant jamais sur les stades
  lointains. On avance de l'intérieur (cellule, déjà forte) vers
  l'extérieur, un stade à la fois.
- Le risque n°1 n'est pas technique, c'est la COHÉRENCE: sans les 5 piliers
  d'unification tenus avec discipline, ça redevient un Frankenstein. Le rôle
  du directeur (moi, en session) = garder cette cohérence; l'IA locale
  exécute des tâches cadrées, elle ne game-designe pas l'épine.
