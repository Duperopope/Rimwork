# DOWN HERE ! — Roadmap du développeur IA local

DOWN HERE! est un jeu de gestion de colonie / 4X / exploration spatiale
(voir docs/DOWN_HERE_DESIGN.md). Tu es le développeur du GAMEPLAY COEUR.

GRAND NETTOYAGE (12/06/2026, supervision Claude): l'ancienne roadmap était
polluée par ~120 items dupliqués générés en boucle, dont beaucoup visaient
des fichiers IMAGINAIRES. Tout a été purgé. Les règles ci-dessous sont
renforcées en conséquence.

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
Tout le coeur vit dans src/RimWorldLab.Core/GameWorld.cs qui contient les
classes: Cell, GameMap, Pawn, GameWorldManager (la vraie simulation),
ResourceNode, Furniture, Zone, et les enums du jeu.
DÉJÀ IMPLÉMENTÉ (ne pas re-proposer): HourOfDay/IsNight (GameWorld.cs
~l.1290), _functionalRoomCount, faim/soif/fatigue, chasse, météo,
pièces fonctionnelles, save/load, recherche/tech.

## FILE DE TRAVAIL (un item à la fois, ancres vérifiées le 12/06/2026)

- [x] Step G.10 - Rain refills the water stores. In
      src/RimWorldLab.Core/GameWorld.cs, find the exact line:
      `        if (TotalTicks % 1500 == 0)`
      Immediately BEFORE that line, insert:
      `        if (TotalTicks % 600 == 0 && Macro.ColonyWeather == WeatherKind.Rain)`
      `            Water++;`

- [x] Step G.11 - Wildlife respawns when hunted out. In
      src/RimWorldLab.Core/GameWorld.cs, find the exact line:
      `        if (TotalTicks % 200 == 0)`
      Immediately BEFORE that line, insert:
      `        if (TotalTicks % 6000 == 0 && !_pawns.Any(p => p.Name == "SmallAnimal" && p.HP > 0))`
      `        {`
      `            GenerateSmallAnimalPopulation();`
      `            LogEvent("La faune locale se repeuple.");`
      `        }`

- [ ] Step G.12 - Night rest is deeper. In
      src/RimWorldLab.Core/GameWorld.cs, find the exact line:
      `                pw.Fatigue = Math.Max(0f, pw.Fatigue - 2f);`
      and REPLACE it with:
      `                pw.Fatigue = Math.Max(0f, pw.Fatigue - (IsNight ? 4f : 2f));`

- [ ] Step G.13 - Collective morale warning. In
      src/RimWorldLab.Core/GameWorld.cs, find the exact line:
      `        if (TotalTicks % 100 == 0)`
      Immediately BEFORE that line, insert:
      `        if (TotalTicks % 2000 == 0 && _pawns.Count(p => p.HP > 0) > 0 && _pawns.Where(p => p.HP > 0).Average(p => p.Mood) < 30)`
      `            LogEvent("Moral de la colonie au plus bas — construisez des lits et nourrissez vos colons !");`

## TRAITÉ PAR LE SUPERVISEUR (12/06/2026 — ne pas retoucher)
- [x] Step F.1a - Guide message at tick 200 (done by Claude, in Tick()).
- [x] Step F.2a - OBSOLETE: HourOfDay/IsNight existaient déjà (l.1290).
- [x] Step F.3a - Fatigue recovery >80 in the %40 block (done by Claude).
- [x] Step F.5a - Idle pawns burn fewer calories (done by Claude, Needs.cs).
- [x] Step F.6a - OBSOLETE: _functionalRoomCount existait déjà.
- [x] Step D.1 - OBSOLETE: item tronqué (aucune ligne fournie), abandonné.
- [x] Step F.4b - ABANDONNÉ: "méthode sans appel" = stub, contraire aux règles.
- [x] Steps E.1/E.19/E.41/E.58 - GELÉS: redondants avec le système Needs
      existant (Hunger/Fatigue tournent déjà chaque tick dans Needs.cs).
- [x] CLEANUP - Classe poubelle `GameWorld` + `RegionMap` morte supprimées,
      champs morts purgés, bug Splash (crash petites cartes) corrigé,
      9/9 tests verts, HUD contextuel par vue (Local/Planet/Solar).

## NOTE: stade ORIGINES = fork de Thrive (reference/thrive, branche down-here)
NE TOUCHE PAS au fork. MicroStage.cs ne sert plus que de fond de menu.

## ARCHIVE (accompli avant le nettoyage — voir git history pour le détail)
- [x] Step D.2 - Hunting (chasse au petit gibier, +3 Food).
- [x] Step D.3 - Animals wander (errance %40 ticks).
- [x] Step D.4 - Low morale slows work (score de tâche pondéré par Mood).
- [x] Step V.1-V.4 - HexCoord, GridShape, rendu hex, carte de régions.
- [x] Steps A-T, W, Z, N2-N6, E, M.2 - gameplay de base: combat, raids,
      ressources, pièces, économie, météo, jour/nuit, sauvegarde.
