# DOWN HERE !

Un seul jeu, **du vivant aux étoiles**, par stades successifs : on commence au
stade **cellule / microbe** et on progresse jusqu'à l'exploration spatiale.
Comportements émergents, histoires auto-générées, et une **pertinence
scientifique vulgarisée** (encyclopédie en jeu ; ex. « ATP » → « énergie vitale »).

**La particularité — et le vrai projet de R&D :** le gameplay est écrit par un
**système de développement autonome et récursif** qui tourne **en local** (LLM
servi sur GPU ROCm), se **pilote depuis un dashboard web**, **apprend de ses
propres résultats**, **conçoit son propre successeur** et peut **réécrire son
propre code** — supervisé par une IA frontière pour l'architecture, la 3D et l'UI.

> 📖 **Si tu ne lis qu'un seul fichier, lis [docs/DOWN_HERE_DESIGN.md](docs/DOWN_HERE_DESIGN.md)** —
> la source de vérité unique (vision, état actif/parké, comment piloter sans être
> développeur). Ce README est la porte d'entrée vers **tout** ce qu'on développe.

## Documentation (tout est documenté et **mesuré**)

| Doc | Ce que ça couvre |
|-----|------------------|
| [docs/GUIDE.md](docs/GUIDE.md) | 🛠️ **Mode d'emploi A→Z** — piloter sans être dev |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 🏗️ Carte mentale + schémas du système |
| [docs/RECURSIVE_SELF_IMPROVEMENT.md](docs/RECURSIVE_SELF_IMPROVEMENT.md) | 🤖 L'auto-amélioration récursive (world model) |
| [docs/RSI_EVIDENCE.md](docs/RSI_EVIDENCE.md) | 🔬 **Preuve chiffrée** que ça s'améliore (courbe d'apprentissage) |
| [docs/SUCCESSOR.md](docs/SUCCESSOR.md) | 🧠 Le système **conçoit son propre successeur** (champion-challenger, **+0.176 mesuré**) |
| [docs/EMERGENCE_EVIDENCE.md](docs/EMERGENCE_EVIDENCE.md) | 🧬 **Preuve** : world model auto-supervisé → survie **émergente** (×3.9) |
| [docs/SELF_EVOLVE.md](docs/SELF_EVOLVE.md) | ♻️ **Auto-modification** du code (mode EVOLVE, gardée + testée) |
| [docs/CONVERSATION.md](docs/CONVERSATION.md) | 💬 Onglet conversation : l'IA parle + **mémoire persistante** |
| [docs/THIRDPARTY.md](docs/THIRDPARTY.md) | ⚖️ Licences (le jeu est **GPL-3.0**, base Thrive) |

- 🌍 Suivi public (miroir, à jour) : https://raw.githack.com/Duperopope/Rimwork/master/docs/index.html
- 📋 [ROADMAP.md](ROADMAP.md) — file de tâches consommée par le dev IA · 🧾 [DEV_LOG.md](DEV_LOG.md) — journal de dev

## La vision en stades

| # | Stade | Base technique | État |
|---|-------|----------------|------|
| 1 | Cellule / microbe | **Thrive** rebrandé DOWN HERE (`reference/thrive`) | ✅ **ACTIF** |
| 2 | Animal / tribus | greffes open-source sur la base | 🔜 prochain |
| 3 | Planétaire / 4X | l'ancien code colonie **RimWork** (`src/`) + tuiles-planètes hex | ⏸️ **PARKÉ** (réutilisé, pas mort) |
| 4 | Spatial (type KSP) | à intégrer | 🌌 horizon |

## Le système autonome récursif (le cœur du projet)

Tout se pilote depuis le **dashboard** (http://localhost:8765), **sans toucher au
code**. Le système se construit en couches :

### 🧠 Le cerveau
- **LLM local** — `llama-server` (llama.cpp **ROCm** sur RX 7800 XT) **dans WSL**,
  port `1234`. Chemin GPU rapide — **PAS LM Studio** (qui squatte ce port). Le
  modèle servi est celui couronné par l'arène (`scripts/llm_champion.txt`).
- **Arène de LLM** (`model_arena.ps1`) — **sélection naturelle de modèles** :
  télécharge des coders récents depuis HuggingFace, les fait combattre sur de
  vraies tâches du jeu, couronne le champion, supprime les perdants.

### 🛠️ Le dev qui code le jeu
- **Boucle de dev** (`dev_loop.ps1`) — prend la 1ʳᵉ tâche non cochée du
  `ROADMAP.md`, demande un patch SEARCH/REPLACE au LLM, l'applique sur
  `reference/thrive`, **build + teste**, et **ne garde que si ça compile/parse**
  (sinon revert). Garde-fous : anti-stub, prédiction d'échec, leçons, revert.

### 🔁 L'auto-amélioration récursive (RSI — la R&D)
- **World model** (`wm/`) — un modèle (scikit-learn) qui **prédit la probabilité
  de succès** d'un patch à partir de 21 features, et **apprend de chaque résultat
  réel**. Il refuse les patchs voués à l'échec **avant** de builder.
- **Politique** (`Policy.ps1`) — un bandit ε-greedy qui **auto-règle** ses seuils
  selon la récompense (gardé / annulé).
- **Conception du successeur** (`wm/successor.py`) — boucle **champion-challenger**
  (lignée AutoML/NAS) : le système **génère, évalue et promeut sa propre
  prochaine version** de cerveau, sous garde. Gain **mesuré +0.176** d'utilité.
- **Émergence** (`wm/emergence.py` + `microbe_env.py`) — un world model
  **auto-supervisé** qui, par MPC, fait **émerger un comportement de survie**
  (×3.9 vs aléatoire). Preuve reproductible.

### ♻️ L'auto-modification du code
- **Self-evolve** (`self_evolve.ps1`) — le système **réécrit son propre code**
  (mode EVOLVE), **gardé** : allowlist + validation parse/tests + revert auto +
  patch sur branche (jamais poussé sans revue). Le moteur ne s'édite pas lui-même.

### 💬 La conversation
- **Chat + mémoire** (`Chat.ps1`, onglet `/chat`) — l'IA locale répond librement
  et **se souvient** des échanges (mémoire persistante type MemGPT).

### 🎮 Le joueur
- **Agent joueur** (`play_agent.ps1`) — une IA **déterministe** qui **joue** le
  stade microbe (but éducatif : stratégies, comportements émergents).

### 🛰️ L'orchestration (un seul mode à la fois)
- **Orchestrateur** (`orchestrator.ps1`) — **autorité unique** : lit le mode
  voulu et aligne les processus pour garantir qu'**un seul** tourne. Il embarque
  un **watchdog LLM** : la prod (port 1234) **revient toute seule** dès qu'on
  n'est pas en train de benchmarker (self-heal).
- **Dashboard** (`dashboard_server.ps1`) — le **cockpit** : statut honnête
  (LLM/dev/mode), activité **réelle** (commits, hors bruit auto), KPIs, tâches,
  feedback, et la **boucle récursive** visualisée. Sert aussi le site public.

| Mode | Ce que fait le système |
|------|------------------------|
| **DEV** | code le jeu (jeu fermé) — *mode par défaut* |
| **PLAY** | l'agent **joue** le jeu (jeu ouvert) |
| **ARENA** | cherche/teste **un meilleur LLM** (swap GPU normal) |
| **EVOLVE** | améliore **son propre code** (auto-modif gardée) |
| **IDLE** | tout au repos (session superviseur) |

> ⚠️ Le jeu et les agents **ne tournent pas tous en même temps**. Un seul GPU
> 16 Go : le mode ARENA occupe la carte pour benchmarker, donc la prod est coupée
> par intermittence pendant l'arène — c'est normal, et le watchdog la remet en
> ligne dès qu'on en sort.

## Carte du dépôt (où est quoi)

```
g:\Rimwork\
├─ reference\thrive\   ← LE JEU ACTIF (Thrive rebrandé, Godot 4.6 mono, GPL-3.0).
│                         Son PROPRE dépôt git, non versionné ici (gitignoré).
├─ src\                ← RimWork colonie/4X — PARKÉ = futur stade planétaire.
│   ├─ RimWorldLab.Core\   (sim déterministe : GameWorld, Needs, Jobs, HexGrid…)
│   ├─ RimWorldGodot\      (couche Godot ; HexPlanet.cs = tuiles-planètes réutilisées)
│   └─ RimWorldLab\        (harnais console de test de la sim)
├─ scripts\            ← LE SYSTÈME AUTONOME (PowerShell). → voir scripts\README.md
│   ├─ lib\               (Config, Modes, State, Patch, WorldModel, Policy, Chat, Llm, Dashboard)
│   ├─ wm\                (world model Python : features, train, predict, successor, emergence)
│   └─ logs\              (télémétrie machine : santé, leçons, dataset, lignée…)
├─ datasets\           ← exemples prompt→patch (futur fine-tuning du cerveau)
├─ docs\               ← design (DOWN_HERE_DESIGN.md = principal), preuves, licences
└─ DEV_LOG.md, ROADMAP.md, README.md
```

> **`src\` n'est PAS du code mort.** C'est la base du futur stade 4X/planétaire
> (les tuiles-planètes hexagonales `HexPlanet.cs` y vivent). On le parque
> proprement, on ne le supprime pas — il est juste déconnecté du jeu actif.

## Lancer & piloter

```powershell
# Toute la pile autonome (idempotent, lancé auto au login) — monte le LLM,
# l'orchestrateur, le dashboard, publie le site :
pwsh -File scripts/startup_all.ps1

# Si le LLM reste hors ligne : relance + diagnostic (rapide, pas de recompilation) :
pwsh -File scripts/setup-llm.ps1

# Le jeu actif seul (Godot 4.6 .NET) :
godot --path reference/thrive

# Vérifier que tout va bien (harnais de tests sans dépendance) :
pwsh -File scripts/tests/run-tests.ps1
```

Puis ouvre **http://localhost:8765** et choisis un mode. Donne du travail au dev
IA en écrivant une tâche **étroite et vérifiable** dans `ROADMAP.md` (qui nomme un
vrai fichier sous `reference/thrive`).

## Ce qui est **prouvé** (pas de hype)

- 📈 La politique s'améliore : utilité **0.194 → 0.383** ; AUC du world model
  **0.701 → 0.790** ([RSI_EVIDENCE.md](docs/RSI_EVIDENCE.md)).
- 🧠 Le système conçoit un successeur **meilleur** : **+0.176** d'utilité sur
  lignée champion-challenger ([SUCCESSOR.md](docs/SUCCESSOR.md)).
- 🧬 Émergence **non supervisée** : survie **×3.9** vs aléatoire via MPC sur un
  world model auto-supervisé ([EMERGENCE_EVIDENCE.md](docs/EMERGENCE_EVIDENCE.md)).
- ✅ Le dev IA produit de vrais commits de jeu et **annule** ce qui ne build pas
  (ratio gardés/annulés visible dans le dashboard).

## Cap long terme

Aujourd'hui le dev IA fait fiable les **petites tâches étroites vérifiables**
(données d'équilibrage, traductions, correctifs ciblés). La direction est un
**« world model »** complet qui prédit l'état du jeu et apprend de ses erreurs
(vision LeCun/JEPA) — un vrai dev local en boucle active, qui conçoit ses propres
successeurs. C'est un cap documenté, pas une promesse en l'air : voir
[docs/DOWN_HERE_DESIGN.md](docs/DOWN_HERE_DESIGN.md) §5 et les preuves ci-dessus.

## Stack & licence

**Godot 4.6 (.NET/C#)** · **PowerShell** (orchestration) · **Python + scikit-learn**
(world model) · **llama.cpp ROCm** dans **WSL** (cerveau LLM) · **AMD RX 7800 XT**.
Le jeu est **GPL-3.0** (base [Thrive](https://github.com/Revolutionary-Games/Thrive)) —
voir [docs/THIRDPARTY.md](docs/THIRDPARTY.md).
