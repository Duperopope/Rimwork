# Tiers & références

## Thrive — référence design (PAS embarqué)
- Source: https://github.com/Revolutionary-Games/Thrive (Revolutionary Games)
- Licence code: GPL-3.0 ; assets: CC-BY-SA 3.0
- Copie locale d'étude: `reference/thrive/` (hors git, hors build)

### Décision (12/06/2026, révisée le même jour)
L'intégration "Thrive lancé tel quel en process séparé" (alpha) a été testée
puis **abandonnée** : fenêtre séparée = expérience cassée, et Thrive souffre
de problèmes de performance (lag) qu'on ne veut pas hériter.

**Doctrine actuelle** : le stade microbien tourne sur **notre moteur
propriétaire** (`src/RimWorldGodot/MicroStage.cs`, 100 % procédural).
Thrive sert uniquement de **référence design** :
- direction artistique (membranes organiques, soupe primordiale, lisibilité) ;
- boucle de gameplay (nage, prédation, organites, éditeur de cellule) ;
- UX des menus (la grande force de Thrive).

### Règle de licence (stricte)
On s'inspire des **idées** (non protégées), on réimplémente tout :
- AUCUN code GPL copié/adapté dans `src/` ;
- AUCUN asset CC-BY-SA repris (de toute façon : politique zéro-asset) ;
- `reference/thrive/` reste isolé du build et de la boucle IA (la boucle ne
  route jamais de patchs vers ce dossier).

## Assets 3D (stade colonie)
- KayKit (CC0) — Adventurers, Skeletons, Dungeon Remastered, Forest Nature,
  Furniture/Restaurant/Resource/RPG Tools Bits. Détail: docs/ASSET_CATALOG.md.
