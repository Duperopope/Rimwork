# DOWN HERE !

Un jeu de gestion de colonie / stratégie temps réel / 4X / exploration spatiale,
avec comportements émergents et histoires auto-générées. La partie commence au
stade **bactérie** (à la Spore) et se termine dans les étoiles (endgame façon KSP).

**Particularité : chaque ligne de gameplay est écrite par une IA locale autonome**
(Qwen2.5-Coder-14B, ROCm) dans une boucle roadmap → patch → build → tests →
simulation → commit, supervisée par une IA frontière pour la 3D, l'UI et
l'architecture.

- 🌍 **Suivi public** : https://duperopope.github.io/Rimwork/
- 📋 **Roadmap** : [ROADMAP.md](ROADMAP.md) (consommée par la boucle IA)
- 📖 **Design** : [docs/DOWN_HERE_DESIGN.md](docs/DOWN_HERE_DESIGN.md)
- 🧾 **Journal de dev** : [DEV_LOG.md](DEV_LOG.md)

## Principes

- **100 % procédural** : zéro asset pour les stades organiques — membranes,
  créatures, eau et lumière sont du code et des shaders.
- **Déterministe** : même seed → même univers (tests reproductibles).
- **Multi-échelles** : Micro → Organisme → Local → Région → Planète → Système.
- **Sourcé, pas copié** : [Thrive](https://github.com/Revolutionary-Games/Thrive)
  (GPL) sert de référence design pour le stade microbien — boucle de gameplay et
  direction artistique réimplémentées sur notre moteur, aucun code/asset repris.
  Voir [docs/THIRDPARTY.md](docs/THIRDPARTY.md).

## Architecture

```
src/RimWorldLab.Core/   Simulation pure .NET (monde, pawns, jobs, météo, saves)
src/RimWorldGodot/      Présentation Godot 4.6 .NET (3D, planètes hex, UI, MicroStage)
src/RimWorldLab/        Harnais console headless (tests + simulation diagnostique)
scripts/dev_loop.ps1    La boucle de développement IA autonome
scripts/startup_all.ps1 Boot/heal de toute la pile (LLM, boucle, jeu, dashboard)
scripts/dashboard_server.ps1  Dashboard live sur http://localhost:8765
docs/                   Design, contrats (UI freeze), audit, tiers
```

## Lancer

```powershell
# Toute la pile (LLM local + boucle + jeu + dashboard) :
powershell -File scripts/startup_all.ps1

# Le jeu seul :
dotnet build src/RimWorldGodot/RimWorldGodot.csproj -c ExportRelease
# puis lancer via l'exe Godot 4.6 .NET complet avec --path src/RimWorldGodot
```
