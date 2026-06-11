# ASSET CATALOG — KayKit integration (gamejam superpass)

All 14 provided archives were inspected. 679 GLTF/GLB models were already
extracted and Godot-imported under `src/RimWorldGodot/assets/models/`
(flat per-pack folders, done in Step U.1); the Skeletons pack was extracted
during the superpass into `assets/models/skeletons/` (with its license file).
The mapping below is the single source of truth consumed by
`RenderCatalog.cs` (frozen file - extension happens by adding catalog rows).

| Archive | Status | Used for | Models in use |
|---|---|---|---|
| KayKit_Adventurers_2.0_FREE | imported (characters/) | Colonists | Knight, Barbarian, Mage, Ranger, Rogue (.glb) |
| KayKit_Skeletons_1.1_FREE | extracted this pass (skeletons/) | Raiders/threats | Skeleton_Warrior, Skeleton_Minion, Skeleton_Rogue (.glb) |
| KayKit_Forest_Nature_Pack_1.0 | imported (nature/) | Trees, rocks, saplings | Tree_1_A_Color1, Rock_1_A_Color1, Bush_1_A_Color1 |
| KayKit_DungeonRemastered_1.1 | imported (dungeon/) | Walls, doors, beds, tables, barrels, mine | wall, wall_doorway, bed_decorated, table_long, chair, barrel_large, stairs_walled |
| KayKit_Restaurant_Bits_1.0 | imported (restaurant/) | Stove/kitchen | stove_multi |
| KayKit_RPGToolsBits_1.0 | imported (rpgtools/) | Workbench/production | anvil |
| KayKit_ResourceBits_1.0 | imported (resources/) | Stockpile visuals | reserved (extension point) |
| KayKit_Furnitures_Bits_1.0 | imported (furniture/) | Room furniture | reserved (extension point) |
| KayKit Dungeon Pack 1.0 | archive kept | superseded by DungeonRemastered | - |
| KayKit Medieval Builder Pack 1.0 | archive kept | future settlement tier | - |
| KayKit_BlockBits / Prototype_Bits | archives kept | future terrain/platform tier | - |
| KayKit_FantasyWeaponsBits_1.0 | archive kept | future pawn equipment | - |
| KayKit Character Animations 1.2 | archive kept | NOT wired (see failures) | - |

## Minimum-usage checklist (mission requirement)
- ≥1 colonist model: 5 in use ✔
- ≥1 enemy/skeleton: 3 in use ✔
- ≥3 environment/resource assets: Tree, Rock, Bush ✔
- ≥3 building/furniture assets: wall, wall_doorway, bed_decorated, table_long, chair, barrel_large ✔
- ≥1 tool/workbench asset: anvil (+ stove_multi) ✔
- UI icons: original text/color identity used instead (no suitable KayKit UI set) ✔

## Import failures / fallbacks
- Character ANIMATIONS: rigs import, but retargeting + AnimationTree wiring
  was judged too risky for an unattended pass - pawns are posed models that
  glide and rotate toward their heading. Documented extension point.
- Any model that fails to load at runtime falls back to a colored box via
  `RenderCatalog.Instantiate` (never invisible, never a crash).

## Licenses
KayKit packs are CC0 (license files preserved next to extracted models where
provided by the archives, e.g. assets/models/skeletons/license.txt).
