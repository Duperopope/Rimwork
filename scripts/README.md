# `scripts/` — Le système autonome (PowerShell)

Carte des scripts. Tout se pilote depuis le **dashboard** (http://localhost:8765).
Détails et philosophie : [../docs/DOWN_HERE_DESIGN.md](../docs/DOWN_HERE_DESIGN.md) §5.

## Orchestration

| Fichier | Rôle |
|---------|------|
| `startup_all.ps1` | **Boot/heal de toute la pile** après reboot (idempotent, tâche au login) : LLM WSL, dev loop, dashboard, watchdog jeu, arène, agent joueur, publication du site. |
| `dev_loop_watchdog.ps1` | Relance `dev_loop.ps1` s'il meurt (exactement une instance). |
| `run_hidden.vbs`, `run_arena_hidden.vbs` | Lancent un script PowerShell en fenêtre cachée. |

## Dev IA

| Fichier | Rôle |
|---------|------|
| `dev_loop.ps1` | **La boucle de dev.** Prend une tâche du `ROADMAP.md`, demande un patch SEARCH/REPLACE au LLM, l'applique sur `reference/thrive`, build/parse, ne garde que si ça passe, commit dans le git de Thrive. Garde-fous : anti-stub, prédiction d'échec, preuve, leçons, revert. |
| `llm_call.ps1`, `test_lm_api.ps1` | Appel / test de l'API LLM locale (port 1234). |
| `downhere-dev.ps1` | **Chat dev interactif** avec le LLM local (Godot/C#). Parle au `llama-server` déjà debout (port 1234) ; ne lance rien. |
| `llm_champion.txt` | Le modèle GGUF couronné par l'arène (lu par `startup_all`). |
| `godot_api_reference.md`, `../LM_STUDIO_SYSTEM_PROMPT.md` | Contexte injecté au LLM (prompt système + API Godot). |

## Sélection de modèle (arène)

| Fichier | Rôle |
|---------|------|
| `model_arena.ps1` | **Arène de sélection naturelle des LLM** : crawle HuggingFace, télécharge des challengers qui tiennent sur 16 Go, les fait combattre sur de vraies tâches, couronne le champion, supprime les perdants. Mode `-Forever` = continu. |

## Agent joueur / playtest

| Fichier | Rôle |
|---------|------|
| `play_agent.ps1` | **L'IA qui JOUE** le stade microbe (machine à états : newgame → survie → évolution). Lit l'état du jeu, décide, pilote la cellule. But éducatif (stratégies / émergence). |
| `playtest_agent.ps1`, `playtest_origines.ps1` | Playtests automatisés / diagnostics. |

## Dashboard & site public

| Fichier | Rôle |
|---------|------|
| `dashboard_server.ps1` | Serveur du **dashboard** (http://localhost:8765) : état vivant + PAUSE/REPRENDRE. |
| `site_gen.ps1`, `publish_site.ps1` | Génèrent et publient le site de suivi public (`docs/index.html`). |

## Données / i18n

| Fichier | Rôle |
|---------|------|
| `curate_dataset.py` | Curation du dataset prompt→patch (`../datasets/`, `logs/training_data.jsonl`). |
| `translate_fr.py`, `unfuzzy_fr.py` | Outils de traduction FR (fichiers `.po`). |

## `logs/`

Télémétrie machine. **Versionnés** (utiles) : `lessons.md`, `feedback.jsonl`,
`model_arena.json`, `training_data.jsonl`. **Locaux/gitignorés** (régénérés) :
`iter_*.txt`, `*.log`, `*.err`, `*.out`, `health*.json`, `current_item.json`,
`shots/`, flags transitoires.

## Rappel architecture

Le cerveau LLM est **`llama-server` (llama.cpp ROCm) dans WSL**, port `1234` —
**jamais LM Studio** (il squatte ce port + la VRAM). `startup_all.ps1` expulse
même LM Studio s'il squatte. Tous les scripts parlent à `http://localhost:1234`.
