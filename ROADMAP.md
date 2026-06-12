# DOWN HERE ! — File d'exécution du développeur IA local

LE DESIGN EST AILLEURS: docs/DOWN_HERE_DESIGN.md est la SEULE source de
vérité (vision, jalons M0-M5, backlog d'idées). Ce fichier ne contient QUE
la file de micro-tâches dérivée du jalon actif (M1: boucle colonie sentie).
Jalon M0 (flux menu→origines→colonie) = travail superviseur, pas ici.

## Règles permanentes
- UN SEUL petit changement par itération, ancré sur des lignes EXACTES.
- Fichiers autorisés: src/RimWorldLab.Core/GameWorld.cs, WorldModel.cs,
  Needs.cs, Jobs.cs, src/RimWorldGodot/Game3D.cs.
- INTERDITS (rejet automatique): UiShell.cs, Boot3D.tscn, RenderCatalog.cs,
  Main.cs 2D legacy, tout placeholder/stub/dummy.
- Chaque feature doit avoir un effet MESURABLE dans la simulation.

## CARTE DU CODE (vérité terrain — ne JAMAIS inventer de fichier)
Ces fichiers N'EXISTENT PAS, ne les référence jamais:
Enums.cs, ZoneKind.cs, Pawn.cs, RegionMap.cs, GameWorldManager.cs.
Tout le coeur vit dans src/RimWorldLab.Core/GameWorld.cs (classes Cell,
GameMap, Pawn, GameWorldManager — la vraie simulation).
DÉJÀ IMPLÉMENTÉ (ne pas re-proposer): HourOfDay/IsNight, faim/soif/fatigue,
chasse, météo, pièces, save/load, recherche/tech, relations sociales par
proximité (bloc %100 dans Tick()), alerte de moral bas, repos nocturne,
pluie→eau, repeuplement de la faune.

## FILE DE TRAVAIL — jalon M1 (ancres vérifiées le 12/06/2026 16h40)

- [x] Step M1.1 - Trade caravan event. In src/RimWorldLab.Core/GameWorld.cs,

- [ ] Step M1.2 - Colony festival lifts spirits. In
      src/RimWorldLab.Core/GameWorld.cs, find the exact line:
      `        // --- Metallurgy: sustained mining smelts Metal from Stone ---`
      Immediately BEFORE that line, insert:
      `        if (TotalTicks % 24000 == 0 && Food >= _pawns.Count(p => p.HP > 0))`
      `        {`
      `            foreach (var fp in _pawns.Where(p => p.HP > 0)) { fp.Mood = Math.Clamp(fp.Mood + 8f, 0f, 100f); fp.Remember(TotalTicks, "fete au village", +3f); }`
      `            LogEvent("Festival ! La colonie celebre — moral en hausse.");`
      `        }`

## GELÉ (redondant — ne pas reprendre)
- [x] Steps E.1/E.14/E.30 - "Social need": REDONDANT, les relations sociales
      par proximité existent déjà (GameWorld.cs bloc %100, Relationships).
- [x] Steps G.10-G.13 - faits (pluie→eau, faune, nuit, alerte moral).
- [x] Steps F.1a-F.6a, D.1, E.x - faits/obsolètes (détail: git log).

## NOTE: stade ORIGINES (M0 câblé le 12/06 soir par le superviseur)
Nouvelle partie → MicroStage interne → 10 évolutions → écran d'ascension →
héritage (2 traits) → création du monde → colonie. Le code de Thrive dans
reference/ est de la LECTURE uniquement, on ne le lance jamais.
NE TOUCHE PAS à MicroStage.cs ni UiShell.cs — domaine superviseur.

## ARCHIVE (avant le nettoyage du 12/06 — détail dans git history)
- [x] Gameplay de base: combat, raids, ressources, pièces, économie, météo,
      jour/nuit, sauvegarde, hex/planète, chasse, humeur→travail.
