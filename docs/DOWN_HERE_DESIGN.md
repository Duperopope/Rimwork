# DOWN HERE ! — Document directeur UNIQUE (12/06/2026)

CE FICHIER EST LA SEULE SOURCE DE VÉRITÉ DU DESIGN. Toute idée de jeu va
ICI (pas dans le ROADMAP, pas dans le DEV_LOG, pas dans le dashboard).
Le ROADMAP.md ne contient QUE la file d'exécution dérivée du jalon actif.

**Pitch** : de la bactérie aux étoiles. Spore-like en début de partie,
RimWorld/Bannerlord au milieu, 4X/KSP en fin — un seul zoom continu,
comportements émergents, histoires auto-générées.

---

## 1. L'EXPÉRIENCE JOUEUR CIBLE (dans l'ordre où elle se vit)

1. **Menu** : titre, Continuer/Nouvelle partie/Charger/Options. Sobre, beau.
2. **Origines (microbe)** : on naît cellule dans la soupe primordiale.
   PROFONDEUR CIBLE = celle de Thrive, réécrite chez nous (voir
   docs/ORIGINES_REBOOT.md): économie de composés, organites à assembler
   sur grille hex, métabolisme/photosynthèse, membrane procédurale,
   auto-evo. ~10 évolutions débloquent la suite. L'ADN choisi LÈGUE des
   traits à la civilisation. État: fondation simulation posée + testée
   (compounds/organites/métabolisme), éditeur hex = prochaine tranche.
3. **Transition** : cinématique courte / fondu — "des éons passent" — la
   espèce devient tribu puis colonie. L'héritage microbe est visible
   (traits de départ des colons, biome de naissance).
4. **Colonie (cœur RimWorld)** : survie, besoins, humeur, pièces, économie,
   tech, raids, caravanes. Un ARC: survie précaire → base stable → fusée.
5. **Planète (hex Goldberg)** : expéditions sur les tuiles, sites
   extérieurs, factions, ressources régionales qui REMONTENT à la colonie.
6. **Système solaire** : observer, puis voyager (endgame fusée KSP-light),
   coloniser un second corps.
7. **Multi-systèmes** : la civilisation essaime (très long terme).

## 2. ÉTAT RÉEL — audit du 12/06/2026 (honnête, vérifié en jeu)

| Phase | État | Écart principal |
|---|---|---|
| Menu | ✅ propre (backdrop cellules, slots, options) | RAS |
| Origines | ✅ MicroStage interne (12/06 soir) | v1 = 3 mutations au choix; la CIBLE est l'éditeur d'assemblage (M4) |
| Transition | ✅ écran d'ascension + héritage (2 traits légués aux colons) | cinématique plus riche plus tard |
| Colonie | ⚠️ sim riche (besoins/humeur/pièces/éco/raids/tech) | pas d'arc, contenu mince, finit par "3 pièces" sans suite ressentie |
| Planète | ⚠️ belle vue + expéditions v1 | les expéditions ne rapportent rien à la colonie |
| Système | ⚠️ vue contemplative + HUD contextuel | zéro gameplay |
| Spatial/KSP | ❌ rien | — |

NB: si le jeu s'ouvre directement sur la carte SANS menu, c'est l'instance
de VÉRIFICATION du watchdog (RIMWORK_AUTOSTART=1). Un lancement normal
passe par le menu.

## 3. INCOHÉRENCES TRANCHÉES (décisions du 12/06/2026)

- **Fork Thrive vs MicroStage interne** : un processus séparé ne peut PAS
  porter la progression. DÉCISION (confirmée par le directeur 12/06): les
  sources de Thrive dans reference/ sont du MATÉRIEL DE LECTURE
  (s'inspirer des mécaniques), on ne lance JAMAIS Thrive depuis le jeu —
  "pour jouer à Thrive, y'a Thrive". Origines = MicroStage interne. ✅ fait
- **Pawns KayKit vs "100% procédural"** : contradiction de l'ancien doc.
  DÉCISION: KayKit assumé à court terme (lisible, fini), le système de
  créature procédurale est le chantier M4 et remplacera les assets quand
  il sera MEILLEUR, pas avant.
- **Qui fait quoi** : l'IA locale (Qwen) ne fait QUE des micro-pas ancrés
  dans la sim (GameWorld/Needs/Jobs/WorldModel). Tout ce qui est
  structurel (flux de jeu, UI, 3D, transitions) = sessions superviseur.
  C'est une limite assumée: un modèle 30B ne game-designe pas.

## 4. ORDRE DE PRODUCTION (jalons, dans l'ordre, avec critère de fin)

### M0 — Une session cohérente de bout en bout  [superviseur] ← ACTIF
Menu → Nouvelle partie → Origines INTERNE (MicroStage) → 10 évolutions →
écran de transition (texte + héritage: 2 traits hérités par les colons) →
création du monde → colonie. Continuer/Charger reprennent au bon stade.
**Fini quand**: un playtest vidéo complet menu→colonie sans toucher au
code, et l'héritage visible dans la fiche d'un colon.

### M1 — La boucle colonie SENTIE (arc complet)  [IA locale + superviseur]
Arc: jour 1 précaire → stabilité (3 pièces, stocks) → événement de bascule
(gros raid / hiver) → objectif long (atelier fusée). Défaite possible et
annoncée, victoire d'étape célébrée. Guide contextuel (déjà commencé).
**Fini quand**: 30 min de jeu sans temps mort ni écran figé, défaite ET
victoire d'étape atteignables, 12 événements distincts minimum.

### M2 — La planète qui compte  [superviseur structure, IA locale règles]
Expéditions qui RAPPORTENT (ressources/colons/artefacts), tuiles aux
biomes réellement différents (génération par biome), sites extérieurs
visitables, faune par biome.
**Fini quand**: une expédition modifie mesurablement l'économie colonie.

### M3 — Spatial v1 (endgame KSP-light)  [superviseur]
Atelier fusée = projet long de colonie (matériaux, tech, échecs), lancement,
voyage dans la vue système, seconde colonie sur un autre corps.
**Fini quand**: une partie "gagnée" = seconde colonie fondée.

### M4 — L'ÉDITEUR D'ASSEMBLAGE du vivant  [superviseur]
Référence assumée (directeur, 12/06): ce qu'on aime dans Thrive, c'est
qu'on ASSEMBLE littéralement son être vivant — pas un menu de mutations,
un éditeur. C'est pour ça que les sources de Thrive sont dans reference/:
étudier leur éditeur cellulaire (grille hex d'organites, coûts, stats
dérivées de la forme), pas lancer leur jeu.
- v1 (Origines): à chaque division, ouvrir un ÉDITEUR: placer les
  organites sur la membrane (flagelle, cils, vacuole, chloroplaste,
  pointes) — la forme assemblée détermine vitesse/énergie/défense, et le
  rendu procédural (membrane multi-sinus, métaballes) suit la forme.
- v2 (Organisme): même éditeur à l'échelle créature (membres, bouches,
  yeux); les ANIMAUX du jeu sont générés par le même système.
- v3: remplace les pawns KayKit quand c'est plus beau qu'eux.

### M5 — Multi-systèmes  [horizon]
Graphe d'étoiles, même zoom continu (SimLOD.Galaxy).

## 5. BACKLOG D'IDÉES CONSOLIDÉ (tout ce qui traînait ailleurs)
- Cartes locales ×10 (512+), eau logique (rivières → océans, lacs).
- Jour/nuit orbital par tuile + lune (marées, raids nocturnes). [partiel ✅]
- Météo déterministe par tuile (seed + climat + saison). [✅ v1]
- Vue 4X: pions/armées = agrégats RÉELS des pawns des tuiles.
- Gravité/atmosphère/composition par planète (modificateurs réels).
- Sauvegardes multi-slots [✅], écran création de monde [✅].
- Caravanes commerciales, factions avec attitude [partiel: sites/attitude].
- Besoin social (les relations existent déjà; en faire une jauge visible).
- Audio procédural (bips d'événements via AudioStreamGenerator).
- Teaser web JS procédural sur la Pages (export C# Godot indispo en 4.6).

## 6. RÈGLES DE FABRICATION (inchangées)
- Toute affirmation visuelle se vérifie par screenshot auto. Toute
  mécanique par test ou simulation headless.
- L'IA locale travaille UNIQUEMENT via ROADMAP.md (items ancrés, un par
  itération, fichiers sim autorisés seulement).
- UI freeze contract en vigueur (structure figée, contenu libre).
- Avant toute session superviseur: arrêter dev_loop + watchdog, commiter,
  relancer après.
