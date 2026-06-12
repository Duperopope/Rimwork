# ORIGINES — Reboot "profond comme Thrive, mais ce n'est pas Thrive"

Décision directeur (12/06/2026 soir): Origines ne doit PAS être un mini-jeu.
C'est un stade cellulaire COMPLET — profondeur et beauté de Thrive — mais
réécrit DE ZÉRO dans notre code, à notre manière, optimisé. On reprend les
PILIERS de Thrive, pas son code (les sources reference/thrive servent à
étudier les mécaniques, jamais à être lancées).

## Réalité de l'effort (honnête)
Thrive microbe stage = ~228 000 lignes C# + contenu data-driven, 10 ans de
travail collectif. Ce reboot est donc un ARC de plusieurs sessions, pas un
commit. Mais il avance par tranches livrables et TESTÉES, en partant des
fondations — pas par-dessus un jouet.

## Les piliers de Thrive à réimplémenter (cible)
1. **Compounds** — économie de composés (ATP, glucose, ammoniac, phosphates,
   H2S, O2, CO2, lumière, mucilage…). ✅ modèle de base posé.
2. **Organites data-driven** — chaque organite = des processus + des stats.
   ✅ registre initial (cytoplasme, mitochondrie, chloroplaste, thylakoïde,
   chimioplaste, vacuole, flagelle, pilus, membrane, vacuole à toxine).
3. **Éditeur d'assemblage HEXAGONAL** — poser/retirer des organites sur une
   grille hex, budget de points de mutation, cellule connexe, stats en
   direct. ⏳ modèle prêt (CanPlace/Place/ComputeStats); UI Godot = next.
4. **Métabolisme & processus** — production/consommation pondérées par
   l'environnement (lumière pour la photo, O2 pour la respiration…),
   osmorégulation, mort par manque d'ATP. ✅ posé et testé.
5. **Membrane procédurale** — rendu multi-sinus/métaballes suivant la forme
   assemblée (le "joli" du cahier des charges). ⏳ après l'éditeur.
6. **Auto-evo / pression de sélection** — les espèces PNJ évoluent toutes
   seules selon le biome (ce qui rend le monde vivant). ⏳ couche suivante.
7. **Patches/biomes** — eau de surface, sources hydrothermales, etc., avec
   compositions différentes. ✅ amorcé (Environment.SurfaceWater/DeepVent).
8. **Engloutissement, toxines, colonies** — interactions inter-cellules.
   ⏳ après le métabolisme solo.
9. **Reproduction & passage d'échelle** — diviser, puis multicellulaire,
   puis l'héritage vers la colonie (déjà câblé côté transition). ⏳

## Architecture (notre manière, optimisée)
- TOUT le modèle vit dans `src/RimWorldLab.Core/Origins/` — SANS Godot, donc
  testable en headless (déjà 2 tests verts). Le rendu Godot lira ce modèle.
  - `CellModel.cs`: Compound, BioProcess, OrganelleType, OrganelleRegistry,
    PlacedOrganelle, CellStats.
  - `Microbe.cs`: assemblage hex (CanPlace/Place/connexité), métabolisme
    (Tick/processus/osmorégulation/mort), reproduction, Environment.
- Pas d'ECS pour l'instant (Thrive en a un pour des milliers d'entités);
  on commence simple et on optimise quand le profil l'exige.
- Data-driven progressif: le registre est en code aujourd'hui; on le
  bascule en JSON quand le contenu grossit (comme organelles.json).

## Ordre de construction (prochaines tranches)
- T1 ✅ Fondation: composés + organites + assemblage + métabolisme + tests.
- T2  Éditeur Godot: grille hex cliquable, palette d'organites, budget MP,
      stats en direct, validation de connexité. (remplace le menu 3-choix)
- T3  Membrane procédurale qui épouse la forme; rendu des organites.
- T4  Monde vivant: cellules PNJ avec métabolisme, proies/prédateurs selon
      la taille, absorption de composés à l'écran.
- T5  Auto-evo léger: les espèces PNJ mutent entre deux générations.
- T6  Engloutissement + toxines + reproduction -> passage multicellulaire.

## Garde-fous
- Chaque tranche livrée avec test headless (modèle) ET screenshot (rendu).
- L'IA locale ne touche PAS à Origins/ pour l'instant (modèle structurel) —
  domaine superviseur, comme MicroStage/UiShell.
