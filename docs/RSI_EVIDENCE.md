# DOWN HERE — Preuve d'auto-amélioration (mesurée, reproductible)

> Ce document répond honnêtement à la question : **« a-t-on une intelligence
> récursive qui s'améliore seule, comme chez Anthropic ? »** — et il le PROUVE
> avec des chiffres reproductibles, pas avec des affirmations.

## La réponse honnête en deux lignes

- **NON**, on n'a pas (et personne n'a en production, Anthropic compris) une IA qui
  réécrit ses propres poids et gagne en intelligence générale **sans supervision**,
  de façon ouverte. Ça reste de la recherche/spéculation.
- **OUI**, on a un **système autonome en boucle fermée qui, sans humain dans la
  boucle, améliore de façon mesurée une métrique de performance définie à partir
  de sa propre expérience.** C'est la forme rigoureuse et réaliste de
  l'auto-amélioration récursive, à notre échelle. Et c'est prouvé ci-dessous.

## Ce qui est « récursif » et « non supervisé » ici

Sans intervention humaine : le `dev_loop` produit des patchs → enregistre lesquels
réussissent/échouent → `recurse.ps1` **ré-entraîne** le world model là-dessus →
le world model **trie** les patchs suivants → ce qui change les résultats → donc
l'expérience → donc le prochain ré-entraînement. La **policy bandit** règle seule
le seuil de tri par récompense mesurée. Trois boucles : world model (apprend la
dynamique), policy (apprend la décision), arène (sélectionne le LLM lui-même).

Ce que ça N'EST PAS : ni nouvelle architecture neuronale, ni gain de capacité
ouvert. C'est de l'auto-amélioration **au niveau du processus de décision**, qui
est exactement ce qui est faisable et vérifiable en local.

---

## Protocole expérimental

Données : `scripts/logs/experience.jsonl` — **462 patchs réels** déjà produits par
le système (89 gardés / 373 cassés), features déterministes (`wm/features.py`).
Modèle : RandomForest (scikit-learn). Reproductible : `python scripts/wm/evaluate.py`
(5 graines aléatoires, moyenne ± écart-type, jeu de test tenu à l'écart).

### Expérience A — apprend-il de l'expérience ?
On entraîne sur des fractions **croissantes** des données et on mesure l'**AUC** sur
un jeu de test FIXE jamais vu. Si l'AUC monte avec la quantité de données, le
système apprend bien de son expérience accumulée.

### Expérience B — la politique apprise est-elle utile ?
Utilité par patch : `build→gardé = 1`, `build→cassé = 0`, `skip (gate) = 0.5`
(économiser un build vaut la moitié d'un succès). **Baseline = tout builder**
(seuil 0). Le seuil de gate est choisi **sur le train** puis évalué **sur le test**
(aucune fuite — exactement ce que fait le bandit en production).

---

## Résultats (mesurés le 14/06/2026, 5 graines)

### A. Courbe d'apprentissage — l'AUC monte avec l'expérience ✅
| n_train (~) | AUC (test tenu à l'écart) |
|---|---|
| 49  (15 %)  | 0.701 ± 0.058 |
| 97  (30 %)  | 0.724 ± 0.050 |
| 162 (50 %)  | 0.736 ± 0.052 |
| 243 (75 %)  | 0.766 ± 0.047 |
| 323 (100 %) | **0.790 ± 0.054** |

**Δ AUC = +0.089** du plus petit au plus grand échantillon. Monotone, faible
variance. → **Le world model apprend bien de son expérience accumulée.**

### B. Valeur de la politique — elle bat la baseline ✅
| Métrique | Valeur |
|---|---|
| Baseline (tout builder) | 0.194 ± 0.000 |
| Politique apprise (seuil choisi sur train) | **0.383 ± 0.014** |
| **Gain d'utilité** | **+0.189 ± 0.014 (≈ ×2)** |
| Taux de skip | 41.9 % |
| **Précision du skip** | **95.7 %** |

**Lecture :** la politique apprise **double** l'utilité moyenne. Elle saute ~42 %
des patchs, et parmi ceux-là **95.7 % auraient réellement cassé le build** — donc
elle économise massivement des builds en se trompant très rarement.

### Verdict automatique (du script)
- A — apprend avec l'expérience : **OUI** (Δ AUC +0.089)
- B — la politique bat la baseline : **OUI**

Chiffres bruts : `scripts/logs/wm_evidence.json`.

---

## Limites assumées (intégrité > hype)

- AUC ~0.79 est un bon signal, **pas un oracle**. Le gate reste utile parce que la
  précision du skip est haute, mais il rate parfois un bon patch.
- L'« amélioration continue dans le temps » est **prouvée par la courbe
  d'apprentissage** (plus de données → meilleur modèle) ; la démonstration *en
  direct* s'accumulera à mesure que le `dev_loop` tourne et génère du vécu neuf
  (`experience_raw.jsonl`), ré-ingéré à chaque cycle `recurse.ps1`.
- Le world model prédit ici le **succès build d'un patch**. Le world model du
  **gameplay** (prédire l'effet sur le jeu) est la marche suivante ; les séries
  d'état sont déjà collectées (`snapshot-state.ps1`).
- Pas de gain de capacité ouvert/non borné : ce n'est pas l'objectif et ce serait
  malhonnête de le prétendre.

## Reproduire
```powershell
python scripts/wm/bootstrap.py     # (re)construit experience.jsonl depuis les logs
python scripts/wm/evaluate.py      # imprime les tableaux + ecrit wm_evidence.json
```

Voir [RECURSIVE_SELF_IMPROVEMENT.md](RECURSIVE_SELF_IMPROVEMENT.md) (architecture)
et [GUIDE.md](GUIDE.md) (utilisation A→Z).
