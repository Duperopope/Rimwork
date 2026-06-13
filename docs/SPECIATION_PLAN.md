# Spéciation scientifique (cladogenèse) + migration — plan d'exécution

Demande directeur: l'évolution du joueur doit pouvoir BRANCHER (cladogenèse)
au lieu d'écraser l'ancêtre (anagenèse). L'ancêtre persiste comme espèce PNJ
qui continue d'évoluer ET de migrer via l'auto-evo. L'arbre évolutif montre
la branche.

## État vérifié du code Thrive (12/06/2026)
- Édition joueur = anagenèse: `editedSpecies` (MicrobeEditor.cs) est muté
  sur place dans `ApplyEditorTab()`. Même ID, ancêtre écrasé.
- Machinerie de branchement DÉJÀ présente:
  - `SplitFromID` sur les records (lien fille→ancêtre).
  - `RegisterNewSpecies` (auto-evo/steps/RegisterNewSpecies.cs).
  - `EvolutionaryTree.cs` affiche déjà les branches via SplitFromID, et
    gère le renommage de l'espèce joueur (updatedPlayerSpeciesName).
- Migration: INTACTE et active. SpeciesMigration.cs + steps/MigrateSpecies.cs,
  `MoveAttemptsPerSpecies: 8` (auto-evo_parameters.json). NON supprimée par
  le superviseur (commits = liens/icônes/shader uniquement).

## Décisions de design (directeur)
- Branchement = SPÉCIATION EXPLICITE (pas à chaque édition). Par défaut,
  éditer raffine la lignée; un bouton "Spéciation" branche.
  (Note: le directeur a aussi évoqué le côté scientifique — à raffiner:
   éventuellement déclencher une spéciation suggérée quand la divergence
   morphologique dépasse un seuil, façon vraie divergence d'espèces.)
- Ancêtre maintenu = espèce PNJ qui ÉVOLUE (auto-evo), pas figée.

## Chantier 1 — Spéciation
1. Ajouter une action éditeur "Spéciation" (bouton, à côté d'ACCEPTER).
2. À la validation: cloner l'espèce joueur AVANT édition -> espèce ancêtre
   (nouvel ID), la garder dans GameWorld avec sa population actuelle;
   l'espèce éditée devient la fille avec SplitFromID = ancêtre.
   (réutiliser MicrobeSpecies.Clone + RegisterNewSpecies + le registre
    d'espèces de GameWorld.)
3. Vérifier que l'ancêtre entre bien dans la boucle auto-evo (mutation +
   migration) — normalement automatique une fois enregistré.
4. S'assurer que l'EvolutionaryTree reçoit le SplitFromID (affichage branche).
5. SÉRIALISATION: tout nouvel état doit passer load/save (sinon parties
   cassées). Tester un round-trip save/load avant de valider.

## Chantier 2 — Migration (clarification en cours)
Deux lectures possibles, à confirmer avec le directeur:
- (A) Migration Thrive patch-map: déjà active. Si invisible, diagnostiquer
  l'affichage (carte des secteurs) plutôt que "rebrancher".
- (B) "Migration" de l'ancien RimWorldGodot (expéditions/caravanes/sites):
  appartient aux stades colonie/civ futurs, pas au microbe. À ré-exprimer
  plus tard dans la progression.

## Garde-fous
- Implémentation en session FOCALISÉE, pas en fin de marathon: ça touche le
  cycle de vie des espèces + la sérialisation des sauvegardes.
- Build Thrive + test round-trip save/load OBLIGATOIRES avant commit.
