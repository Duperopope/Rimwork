# DOWN HERE — Guide d'utilisation A → Z

> Pour piloter le système **sans être développeur**. Si tu ne lis qu'une chose
> pour la vision, c'est [DOWN_HERE_DESIGN.md](DOWN_HERE_DESIGN.md) ; pour la
> technique, [ARCHITECTURE.md](ARCHITECTURE.md) ; ici c'est le **mode d'emploi**.

---

## 0. Ce que c'est, en une image

Un système autonome qui développe le jeu (stade cellulaire, base Thrive) avec un
LLM local, que **tu pilotes depuis une page web**. Il choisit ses tâches, écrit
des patchs, les teste, garde ce qui marche — et il **apprend de ses résultats**
pour mieux trier ses patchs (world model + auto-amélioration ; preuves dans
[RSI_EVIDENCE.md](RSI_EVIDENCE.md)).

## 1. Prérequis (une fois)

- **Windows + PowerShell 7** (`pwsh`).
- **WSL Ubuntu** avec `llama-server` (llama.cpp ROCm) compilé — c'est le cerveau LLM.
- **Python 3.10+** avec `scikit-learn` + `numpy` (déjà présents sur cette machine).
- Le jeu actif dans `reference/thrive`. S'il manque (clone frais) :
  ```powershell
  pwsh -File scripts/setup-game.ps1
  ```

## 2. Tout démarrer

```powershell
pwsh -File scripts/startup_all.ps1
```
Ça lance, **dans le bon ordre** : le **dashboard** d'abord (≈1 s), puis
l'**orchestrateur**, puis le **LLM** (peut prendre ~1-2 min à charger). C'est
idempotent : tu peux le relancer sans risque. (Lancé aussi automatiquement à
l'ouverture de session.)

## 3. Piloter : le dashboard

Ouvre **http://localhost:8765**. Tu y trouves :
- **Santé en direct** : tâche en cours, jeu lancé ou non, leçons récentes.
- **Boutons de MODE** (un seul actif à la fois) :
  - **DEV** — le dev IA code le jeu (jeu fermé). *Mode par défaut.*
  - **PLAY** — l'agent JOUE le jeu (jeu ouvert).
  - **ARENA** — le système cherche/teste un meilleur LLM.
  - **EVOLVE** — le système améliore son **propre code** (auto-modification gardée :
    patchs validés à revoir, master jamais cassé). Voir [SELF_EVOLVE.md](SELF_EVOLVE.md).
  - **IDLE** — tout au repos (pour une session avec un superviseur).
- **PAUSE / REPRENDRE** — coupe ou relance toute la machine.
- **Feedback** — propose une feature/bug ; ça devient une tâche.
- **💬 Parler à l'IA** (`/chat`) — un onglet conversation : l'IA locale te répond
  librement et **se souvient** de vos échanges (mémoire persistante). Détails :
  [CONVERSATION.md](CONVERSATION.md). (Il faut le LLM démarré pour des réponses.)

En ligne de commande si besoin :
```powershell
pwsh -File scripts/set-mode.ps1 DEV     # ou PLAY / ARENA / IDLE
```

> Règle d'or : **un seul mode autonome à la fois** (le jeu et le dev ne tournent
> jamais ensemble). C'est garanti par l'orchestrateur.

## 4. Donner du travail au dev IA

Le dev IA exécute la **première case non cochée** de [ROADMAP.md](../ROADMAP.md).
Une bonne tâche est **étroite et vérifiable**, et nomme **un vrai fichier** sous
`reference/thrive`. Exemple :
```
- [ ] Augmente "CompoundCloudBrightness" à 1.5 dans simulation_parameters/microbe_stage/biomes.json.
```
Le LLM local ne game-designe pas et ne réécrit pas l'archi : pour ça → session
superviseur (toi + une IA frontière), **en mode IDLE**, on commite, puis on reprend.

## 5. L'auto-amélioration (world model)

Elle tourne toute seule en mode DEV. Pour la lancer/voir à la main :
```powershell
pwsh -File scripts/recurse.ps1        # un cycle : ingère l'expérience → ré-entraîne → journalise
python scripts/wm/evaluate.py         # PREUVE chiffrée (courbe d'apprentissage + gain politique)
```
Où regarder :
- `scripts/logs/wm_model.json` — métriques du modèle (AUC, importances).
- `scripts/logs/wm_evidence.json` — la preuve scientifique reproductible.
- `scripts/logs/wm_history.jsonl` — l'évolution dans le temps.
- `scripts/logs/policy.json` — ce que la politique a appris (seuils + récompenses).

## 6. Vérifier que tout va bien

```powershell
pwsh -File scripts/tests/run-tests.ps1     # doit afficher "27 OK, 0 echec(s)"
```
Et l'état machine en JSON : **http://localhost:8765/state.json**.

## 7. Routine type

1. Démarrer la pile (§2). Ouvrir le dashboard.
2. Écrire 1-3 tâches étroites dans `ROADMAP.md`.
3. Laisser en mode **DEV** — le dev IA travaille, le world model trie, ça commite
   les succès tout seul.
4. De temps en temps, passer en **PLAY** pour voir l'agent jouer, ou **ARENA**
   pour chercher un meilleur cerveau.
5. Pour une grosse décision (design, 3D, archi) : **PAUSE** ou **IDLE**, session
   superviseur, commit, puis **REPRENDRE**.

## 8. En cas de souci

| Symptôme | Quoi faire |
|---|---|
| `localhost:8765` inaccessible | Relance `pwsh -File scripts/startup_all.ps1` (le dashboard démarre en premier). |
| Le dev IA ne fait rien | Vérifie qu'une case `- [ ]` existe dans `ROADMAP.md` et que le mode = DEV. |
| LLM injoignable | Le serveur WSL met ~1-2 min à charger. Si ça reste « hors ligne » : le binaire llama-server peut être un build cassé « router mode ». **Répare-le UNE fois** : `pwsh -File scripts/setup-llm.ps1` (recompile, ~10-20 min, dans ton terminal). Ensuite DÉMARRER suffit. **Jamais LM Studio** (il squatte le port). |
| Le jeu et le dev tournent ensemble | Ne devrait plus arriver (machine à modes). Sinon PAUSE puis REPRENDRE. |
| Tests rouges | Lance `run-tests.ps1` et lis quelle ligne FAIL. |

## 9. Règles de fabrication (rappel)

- Toute affirmation visuelle se vérifie (capture / lancement réel) ; toute
  mécanique par test/simulation.
- Le dev IA travaille via `ROADMAP.md`, une tâche ancrée à la fois.
- Les idées de design vont dans `DOWN_HERE_DESIGN.md`, pas éparpillées.
- Dépôt à **miroir public** + auto-commits : **aucun fichier perso** dans l'arbre
  (les `*.pdf`/`CV-*` sont déjà ignorés).
