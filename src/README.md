# `src/` — RimWork (PARKÉ, futur stade planétaire / 4X)

> ⏸️ **Ce dossier est PARQUÉ, pas mort.** Le jeu ACTIF est `reference/thrive`
> (stade cellulaire). Voir [../docs/DOWN_HERE_DESIGN.md](../docs/DOWN_HERE_DESIGN.md).

C'est l'**embryon historique** du projet : on avait commencé à écrire un
colony-sim (type RimWorld) avec notre propre stade microbe, **avant** de
découvrir Thrive (10 ans de dev open-source) et de pivoter dessus pour le stade
cellulaire. RimWork est conservé car il devient la **base du futur stade
planétaire / 4X** (stade 3).

## Ce qu'il y a dedans

| Projet | Rôle | À réutiliser pour le 4X ? |
|--------|------|---------------------------|
| `RimWorldLab.Core/` | Simulation pure .NET déterministe (`GameWorld`, `Needs`, `Jobs`, `Pathing`, `HexGrid`, `RoomDetection`, `SaveLoad`…) | ✅ oui — cœur de sim colonie |
| `RimWorldGodot/` | Couche Godot (rendu 3D iso, UI, caméra). **`HexPlanet.cs` = tuiles-planètes hexagonales** | ✅ **surtout `HexPlanet.cs`** (vue spatiale) |
| `RimWorldLab/` | Harnais console de test de la sim (headless) | partiellement |

## Le stade microbe « interne » (abandonné, mais câblé)

`RimWorldGodot/MicroStage.cs`, `RimWorldGodot/CellEditor.cs` et
`RimWorldLab.Core/Origins/` (`Microbe.cs`, `CellModel.cs`) sont notre **première
tentative de stade cellulaire maison**. Direction **abandonnée** au profit de
Thrive — mais ce code reste **câblé** dans RimWork (`UiShell.StartMicroStage()`
→ `MicroStage` → `CellEditor` ; `GameWorld.cs` utilise `DownHere.Origins`).

➡️ **Ne pas supprimer fichier par fichier** : ça casserait le build de RimWork.
Si on veut s'en débarrasser un jour, il faut découpler proprement (retirer
l'entrée de menu + les diagnostics dans `GameWorld.cs`), pas un simple `rm`.

## Build (parké, pour archive seulement)

```powershell
dotnet build src/RimWorldGodot/RimWorldGodot.csproj
# La solution RimWorldGodot.sln référence RimWorldGodot + RimWorldLab.Core.
# (RimWorldLab/ — le harnais console — n'est dans aucune .sln : build à part.)
```
