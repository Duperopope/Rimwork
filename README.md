# DOWN HERE !

Un seul jeu, **du vivant aux étoiles**, par stades successifs : on commence au
stade **cellule / microbe** et on progresse jusqu'à l'exploration spatiale.
Comportements émergents, histoires auto-générées, et une **pertinence
scientifique vulgarisée** (encyclopédie en jeu ; ex. « ATP » → « énergie vitale »).

**Particularité du projet** : le gameplay est écrit par un **développeur IA local
autonome** (modèle servi en local, ROCm), piloté depuis un **dashboard web**, et
supervisé par une IA frontière pour l'architecture, la 3D et l'UI.

> 📖 **Si tu ne lis qu'un seul fichier, lis [docs/DOWN_HERE_DESIGN.md](docs/DOWN_HERE_DESIGN.md)** —
> c'est la source de vérité unique (vision, état actif/parké, comment piloter
> sans être développeur). Ce README n'est que la porte d'entrée.

- 🌍 Suivi public (miroir, à jour) : https://raw.githack.com/Duperopope/Rimwork/master/docs/index.html
- 📋 [ROADMAP.md](ROADMAP.md) — file de tâches consommée par le dev IA
- 🧾 [DEV_LOG.md](DEV_LOG.md) — journal de dev (rotation auto ; archive dans `docs/archive/`)
- ⚖️ [docs/THIRDPARTY.md](docs/THIRDPARTY.md) — licences (le jeu est **GPL-3.0**, base Thrive)

## La vision en stades

| # | Stade | Base technique | État |
|---|-------|----------------|------|
| 1 | Cellule / microbe | **Thrive** rebrandé DOWN HERE (`reference/thrive`) | ✅ **ACTIF** |
| 2 | Animal / tribus | greffes open-source sur la base | 🔜 prochain |
| 3 | Planétaire / 4X | l'ancien code colonie **RimWork** (`src/`) + tuiles-planètes hex | ⏸️ **PARKÉ** (réutilisé, pas mort) |
| 4 | Spatial (type KSP) | à intégrer | 🌌 horizon |

## Carte du dépôt (où est quoi)

```
g:\Rimwork\
├─ reference\thrive\   ← LE JEU ACTIF (Thrive rebrandé, Godot 4.6 mono, GPL-3.0).
│                         Son PROPRE dépôt git, non versionné ici (gitignoré).
├─ src\                ← RimWork colonie/4X — PARKÉ = futur stade planétaire.
│   ├─ RimWorldLab.Core\   (sim déterministe : GameWorld, Needs, Jobs, HexGrid…)
│   ├─ RimWorldGodot\      (couche Godot ; HexPlanet.cs = tuiles-planètes réutilisées)
│   └─ RimWorldLab\        (harnais console de test de la sim)
│                          → voir src\README.md
├─ scripts\            ← LE SYSTÈME AUTONOME (PowerShell). → voir scripts\README.md
│   └─ logs\              (télémétrie machine : santé, leçons, dataset…)
├─ datasets\           ← exemples prompt→patch (futur fine-tuning)
├─ docs\               ← design (DOWN_HERE_DESIGN.md = principal), licences, archives
└─ DEV_LOG.md, ROADMAP.md, README.md
```

> **`src\` n'est PAS du code mort.** C'est la base du futur stade 4X/planétaire
> (les tuiles-planètes hexagonales `HexPlanet.cs` y vivent). On le parque
> proprement, on ne le supprime pas. Il est juste déconnecté du jeu actif.

## Le système autonome (4 briques + 2)

Tout se pilote depuis le **dashboard**, sans toucher au code :

1. **Cerveau LLM** — `llama-server` (llama.cpp ROCm) **dans WSL**, port `1234`.
   C'est le chemin GPU rapide — **PAS LM Studio** (qui squatte ce port). Modèle
   servi : voir `scripts/llm_champion.txt`.
2. **Dev IA** — `scripts/dev_loop.ps1` : prend la 1ʳᵉ tâche non cochée du
   `ROADMAP.md`, demande un patch au LLM, l'applique, **build + teste**, et ne
   **garde que si ça compile/parse**. Cible le jeu actif (`reference/thrive`).
3. **Watchdog du jeu** — `scripts/game_watchdog.ps1` : maintient le jeu lancé.
4. **Dashboard** — `scripts/dashboard_server.ps1` sur **http://localhost:8765** :
   la vue vivante + un bouton PAUSE/REPRENDRE.
5. **Arène de LLM** — `scripts/model_arena.ps1` : télécharge des coders récents
   depuis HuggingFace, les fait combattre sur de vraies tâches du jeu, couronne
   le meilleur dans `llm_champion.txt`, supprime les perdants (sélection naturelle).
6. **Agent joueur** — `scripts/play_agent.ps1` : une IA qui **joue** le stade
   microbe (déterministe, but éducatif : stratégies / comportements émergents).

> Ces systèmes et le jeu **ne sont pas censés tourner tous en même temps**
> pendant le dev. Mets la pile en PAUSE (dashboard) avant une session superviseur.

## Lancer

```powershell
# Toute la pile autonome (idempotent, lancé auto au login) :
powershell -File scripts/startup_all.ps1

# Le jeu actif seul (Godot 4.6 .NET) :
godot --path reference/thrive
```

## Cap long terme

Aujourd'hui le dev IA fait fiable les **petites tâches étroites vérifiables**
(données d'équilibrage, traductions, correctifs ciblés). La direction long terme
est un **« world model »** qui prédit l'état du jeu et apprend de ses erreurs
(vision LeCun/JEPA) — un vrai dev local en boucle active. C'est un cap, pas le
présent : voir [docs/DOWN_HERE_DESIGN.md](docs/DOWN_HERE_DESIGN.md) §5.
