# Logiciels tiers embarqués

## Thrive (stade microbien ORIGINES)
- Source: https://github.com/Revolutionary-Games/Thrive (Revolutionary Games)
- Version embarquée: 1.1.0 (release officielle Windows)
- Licence code: GPL-3.0 ; assets: CC-BY-SA 3.0
- Décision (12/06/2026): le stade microbien de DOWN HERE! EST Thrive,
  pris tel quel — même moteur (Godot.NET.Sdk 4.6.3), zéro modification.
  Lancé depuis le menu « Nouvelle partie — Origines ». Notre MicroStage
  procédural reste le fallback intégré si la release n'est pas installée.
- Installation: scripts/get_thrive.ps1 (téléchargé hors git, ~1 Go)
- IMPORTANT licence: distribuer DOWN HERE! AVEC les binaires Thrive impose
  les obligations GPL-3.0/CC-BY-SA (mention, sources, partage à l'identique
  pour les assets dérivés). v1 = lancement côte à côte (process séparé),
  ce qui garde nos codes distincts; une fusion de code (v2) placerait la
  partie fusionnée sous GPL.

## Architecture validée (12/06/2026)
- ALPHA: Thrive lancé tel quel depuis le menu (process séparé) - EN PLACE.
- RELEASE: bridge "Thrive fork -> Down Here!" :
  1. Fork minimal de Thrive couvrant jusqu'au stade cellulaire.
  2. À la fin du stade, le fork écrit les données d'espèce (les saves
     Thrive sont du JSON: organites, membrane, comportement, stats).
  3. Down Here! se lance en surcouche et IMPORTE ces données pour générer
     l'organisme/créature du joueur aux échelles suivantes.
  -> Deux logiciels séparés (GPL contenue dans le fork), pas de fusion de
     code, et la continuité de progression du joueur est préservée.
