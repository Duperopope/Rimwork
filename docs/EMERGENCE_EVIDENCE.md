# DOWN HERE — Émergence & apprentissage auto-supervisé (mesurés)

> Réponse à : « au-delà de la hype, il y a de l'auto-supervisé et des
> comportements émergents documentés — je veux au moins ça. »
> Voici **au moins ça**, implémenté en local et **prouvé** avec des chiffres
> reproductibles. Sans fantastique, sans hype.

## Ce qu'on démontre (et qui est documenté dans la littérature)

1. **Apprentissage AUTO-SUPERVISÉ** : un *world model* apprend à prédire l'état
   suivant d'un environnement à partir de l'état+action — **sans aucun label ni
   récompense**, juste en observant le futur. C'est le même principe que la
   prédiction du prochain token des LLM, les *World Models* de Ha & Schmidhuber
   (2018), et la direction JEPA de LeCun.
2. **Comportement ÉMERGENT** : un agent qui n'a **aucune règle codée** « cherche
   la nourriture » développe une **stratégie de survie** en *planifiant* avec ce
   modèle appris (Model Predictive Control). Le comportement n'est écrit nulle
   part : il **émerge** de l'optimisation contre un modèle du monde — paradigme
   documenté du *model-based RL*.

## Le dispositif (100 % local, CPU, reproductible)

Sandbox : une **cellule** sur une grille, une **énergie**, des sources de
nourriture qui la nourrissent quand elle s'en approche (champ lisse), un
**métabolisme** constant → elle **meurt** si elle ne s'alimente pas. La règle
« s'approcher nourrit » est une propriété de l'**environnement**, pas de l'agent.

- `microbe_env.py` — l'environnement déterministe.
- `wm/emergence.py` — collecte aléatoire (auto-supervisée) → entraîne le world
  model (MLP scikit-learn) → planifie (MPC, horizon 6) → mesure → écrit la preuve.

Reproduire : `python scripts/wm/emergence.py` (graines fixes).

## Résultats (mesurés le 14/06/2026)

### A. Le world model auto-supervisé apprend ✅
Courbe d'apprentissage — l'erreur de prédiction (MSE, jeu tenu à l'écart) **baisse
avec l'expérience** :

| transitions d'entraînement | MSE |
|---|---|
| 325   | 0.058 |
| 814   | 0.051 |
| 1628  | 0.046 |
| 3256  | **0.042** |
| baseline « rien ne change » | 0.075 |

→ Le modèle prédit le futur **mieux** que l'hypothèse naïve, et **de mieux en
mieux** avec plus de données. Apprentissage auto-supervisé confirmé.

### B. Un comportement de survie ÉMERGE ✅
Agent qui **planifie avec le world model appris** vs agent **aléatoire**
(40 épisodes, mêmes graines, comparaison juste) :

| Agent | Survie (pas) | Énergie moy | Dist. nourriture moy |
|---|---|---|---|
| Aléatoire | 38.0 | 0.058 (**meurt**) | 3.60 |
| **Planif. world model** | **148.4 / 150** | **0.882** (**survit**) | **2.37** |

- **Survie ×3.9.** L'agent aléatoire meurt (énergie ~0) ; celui qui planifie
  survit quasiment tout l'épisode.
- Il **reste plus près de la nourriture** (2.37 vs 3.60) — la stratégie de survie.
- **Rien de tout ça n'est codé.** L'agent a pour seul objectif son énergie
  prédite ; le world model n'a vu que de l'exploration **aléatoire sans
  récompense**. La recherche/maintien près de la nourriture **émerge** de la
  planification.

### Verdict automatique du script
- Apprentissage auto-supervisé : **OUI** (MSE 0.042 < 0.075)
- Comportement de survie émergent : **OUI** (survie ×3.9, énergie 0.88 vs 0.06)

Chiffres bruts : `scripts/logs/emergence_evidence.json`.

## Honnêteté & portée

- C'est une **émergence réelle et mesurée** au sens scientifique : une stratégie
  non programmée qui apparaît par optimisation contre un modèle appris. Ce n'est
  **pas** une conscience ni une intelligence générale — ne nous racontons pas
  d'histoires.
- La sandbox est **fidèle à l'esprit du stade cellulaire** (survie d'une cellule
  qui doit s'alimenter) et sert à **prouver le mécanisme** avant de le brancher
  sur les vraies trajectoires du jeu (déjà collectées via `snapshot-state.ps1` et
  l'agent joueur). C'est la méthode standard : valider le mécanisme sur un banc
  contrôlé.
- Couplé au reste : ce world model auto-supervisé est le **moteur** visé pour le
  mode PLAY (un agent qui modélise le jeu et planifie), et complète le world
  model *supervisé* du dev (cf. [RSI_EVIDENCE.md](RSI_EVIDENCE.md)).

## Références (publiques, pas de la hype)
- Ha & Schmidhuber, *World Models* (2018).
- LeCun, *A Path Towards Autonomous Machine Intelligence* (JEPA, 2022).
- Model-Predictive Control / model-based RL (littérature standard).
- Émergence de stratégies par auto-jeu (lignée AlphaZero) ; agents à
  auto-curriculum et bibliothèque de compétences (lignée Voyager, 2023).

Voir [RECURSIVE_SELF_IMPROVEMENT.md](RECURSIVE_SELF_IMPROVEMENT.md),
[RSI_EVIDENCE.md](RSI_EVIDENCE.md) et [GUIDE.md](GUIDE.md).
