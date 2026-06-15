# DOWN HERE! — Évaluation honnête de l'autonomie (état de l'art)

**Date : 2026-06-15.** Auteur : l'assistant IA du projet, à la demande du directeur
(« rends la copie la plus parfaite possible techniquement à la date actuelle, et si
ce n'est pas possible je veux des preuves documentées et fiables »).

Ce document répond à **une** question, sans complaisance :

> Peut-on, **aujourd'hui**, fabriquer **sans supervision humaine** un jeu *à la
> hauteur de notre ambition* (pas un jeu jetable) grâce à un système autonome +
> world model ?

**Réponse courte : non — pas un jeu complet de qualité, de bout en bout, sans
humain.** Ce qui *est* atteignable maintenant : faire **progresser** un jeu de
façon **mesurée et gardée** avec un LLM + un prédicteur (world model embryonnaire),
chaque amélioration étant vérifiée automatiquement. Les preuves ci-dessous, datées
et sourcées, étayent les deux affirmations.

---

## 1. Les agents de code autonomes : forts sur une *issue*, pas sur un *jeu*

Le meilleur niveau public mesuré (SWE-bench Verified, juin 2026) place les agents
frontière autour de **80 % d'issues GitHub réelles résolues en autonomie**, les
scores extrêmes (~94 %) étant à lire avec des réserves de **contamination** et de
design de test signalées par des audits récents.

- Plage haute ~80 % (Claude Opus 4.x, Gemini 3.1 Pro, GPT-5.x Codex) ; un score
  isolé à 93,9 % existe mais doit être relativisé (contamination). Source :
  [Steel.dev — SWE-bench Verified Leaderboard 2026](https://leaderboard.steel.dev/leaderboards/swe-bench-verified/),
  [codeant.ai — SWE-bench Leaderboard 2026](https://www.codeant.ai/blogs/swe-bench-scores).
- Audit des caveats de mesure : [UTBoost, arXiv 2506.09289](https://arxiv.org/pdf/2506.09289).

**Ce que ça veut dire pour nous.** SWE-bench mesure une tâche **unitaire et bien
cadrée** : *un* dépôt, *un* bug, *un* patch, avec des tests qui disent oui/non. Un
jeu « à la hauteur » n'est pas ça : c'est **des milliers de tâches interdépendantes**
+ du **game design** + du **game feel** + des **assets cohérents** + de l'équilibrage,
sans oracle automatique qui dise « c'est *amusant* ». Réussir 4 issues sur 5 ne se
transfère pas mécaniquement à « concevoir un bon jeu ». C'est précisément l'écart
que notre banc d'essai mesure honnêtement (cf. §5).

## 2. Génération autonome de jeu complet : pas en 2026

L'état de l'art permet d'**automatiser des tâches isolées** (génération de
graphismes, de musique, de scripts de gameplay), mais **pas** de produire seul un
jeu complet, cohérent et de qualité :

- « La création entièrement autonome — une IA produisant un jeu complet, jouable,
  entièrement seule — *est encore en évolution* » et « une supervision humaine est
  requise pour maintenir la qualité » :
  [Rosebud AI — Can AI Create a Full Game Autonomously?](https://lab.rosebud.ai/blog/can-ai-create-a-full-game),
  [Jenova — AI-Generated Game, 2026 Guide](https://www.jenova.ai/en/resources/ai-generated-game).
- Les projections sérieuses situent le **AAA autonome avec supervision minimale
  vers ~2030** ; 2026 reste « une période de transition ». Source :
  [Jenova (2026)](https://www.jenova.ai/en/resources/ai-generated-game),
  [Shapiro — AI will ship a AAA game autonomously](https://daveshap.substack.com/p/ai-will-ship-a-aaa-game-autonomously).
- Rappel utile : les LLM **savent à peine *jouer*** à des jeux, a fortiori en
  *concevoir* — [IEEE Spectrum — Why AI Models Still Can't Handle Your Favorite Video Games](https://spectrum.ieee.org/ai-video-games-llms-togelius).

## 3. Le « world model » (notre techno cible) : recherche, pas production

La direction est juste (c'est la thèse de LeCun : un agent doté d'un **modèle
prédictif** du monde plutôt qu'un générateur de tokens aveugle), mais elle n'est
**pas mûre pour la production** d'agents autonomes :

- Avancées 2025-2026 réelles : **V-JEPA 2** (compréhension vidéo / raisonnement
  physique, contrôle robot zéro-shot), **LeWorldModel** (mars 2026, JEPA end-to-end
  depuis les pixels). Source :
  [World model (AI) — Wikipedia](https://en.wikipedia.org/wiki/World_model_(artificial_intelligence)),
  [Knowlee — World Models vs Agentic AI 2026](https://www.knowlee.ai/blog/world-models-vs-agentic-ai-2026).
- Mais l'industrie elle-même le dit : les world models **« ne sont pas encore à
  maturité de production »** (AMI Labs, 1,03 Md$ levés en 2025 *justement pour y
  arriver*). Source :
  [Knowlee (2026)](https://www.knowlee.ai/blog/world-models-vs-agentic-ai-2026).
- Les conditions mathématiques pour qu'un JEPA *récupère vraiment* les variables
  cachées du monde viennent seulement d'être posées (mai 2026) :
  [« When Does LeJEPA Learn a World Model? », arXiv](https://cryptobriefing.com/lejepa-world-model-conditions-lecun/).

**Conclusion §3 :** un world model qui rend un système « plus fort qu'un LLM pour
fabriquer un jeu sans humain » **n'existe nulle part en production aujourd'hui**.
Le bâtir nous-mêmes de zéro, en local, n'est pas réaliste. Le bâtir **en petit et
utile** l'est (cf. §5).

## 4. Nos contraintes propres durcissent encore le problème

Même les chiffres ci-dessus sont obtenus avec des **modèles frontière** (API,
clusters). Nous, on tourne :

- en **local sur 16 Go de VRAM** (RX 7800 XT), **partagés avec le jeu** ;
- avec des modèles **quantifiés** (Q3/Q4) — donc en-dessous des modèles full
  précision des classements ;
- **sans supervision** (le directeur ne « chapeaute » pas).

Donc nos résultats *plafonnent structurellement en-dessous* du SOTA cité. C'est une
contrainte assumée, pas un échec — mais elle interdit toute promesse d'« autonomie
totale de qualité AAA ».

## 5. Ce qui EST atteignable maintenant — et comment on le PROUVE

Le réalisable, et qui a de la valeur :

1. **Boucle de dev LLM gardée** : le LLM propose un patch `SEARCH/REPLACE`, on le
   **valide automatiquement** (build C# / JSON valide), on **garde** ou **revert**.
   Rien de cassé n'entre. C'est lent et incrémental, mais ça **avance réellement**.
2. **Prédicteur de patch (world model embryonnaire)** : à partir de l'historique
   `{patch → gardé/échec}` que la boucle produit, un modèle estime P(succès) et
   **évite de gaspiller des builds** sur des patchs voués à l'échec. Implémenté :
   `scripts/lib/WorldModel.ps1` + `scripts/wm/`. Il apprend désormais des **trois**
   modes d'échec (build cassé, SEARCH sans match, JSON invalide), pas seulement du
   build.
3. **Arène de sélection de modèle** : garantit qu'on tourne avec le **meilleur
   coder qui tient en 16 Go**, mesuré, pas supposé.

**Le mécanisme d'honnêteté (c'est le cœur).** Aucune de ces briques n'a le droit de
se déclarer « meilleure qu'un LLM » sans le **prouver sur une mesure** :

- le **banc d'essai** (qualité comparable dans le temps, barème versionné) ;
- les **métriques réelles de la boucle** : taux de patchs **gardés vs annulés**,
  build qui passe, % de la roadmap réellement coché avec **preuve** (`Test-ItemEvidence`).

Règle : **le world model / EVOLVE ne remplace la boucle simple que s'il la bat,
mesuré (A/B).** Tant qu'il ne gagne pas, il reste en R&D. C'est ce qui empêche le
système (et l'assistant) de raconter n'importe quoi sur le long terme.

## 6. Verdict

| Ambition | Faisable seul, sans humain, aujourd'hui ? | Preuve |
|---|---|---|
| Résoudre une tâche de code cadrée | **Partiellement** (~80 % au SOTA frontière ; moins en local 16 Go) | §1 |
| Fabriquer un jeu complet *de qualité* de bout en bout | **Non** (≈2030 selon les projections) | §2 |
| World model qui surpasse un LLM pour le gamedev | **Non en production** (R&D active) | §3 |
| Faire **progresser** un jeu, mesuré et gardé, en semi-autonomie | **Oui** | §5 |

**En clair :** viser « un jeu à la hauteur, entièrement autonome, sans supervision »
**maintenant** serait malhonnête — les sources ci-dessus le documentent. La stratégie
défendable est : **faire tourner la boucle gardée (DEV), accumuler les données,
faire émerger le prédicteur, et ne promouvoir l'autonomie que là où elle bat le
baseline sur le banc.** On construit vers la vision de LeCun pas à pas, en gardant
toujours une mesure qui dit la vérité.

---

*Ce document est versionné. Quand l'état de l'art bouge (nouveaux scores SWE-bench,
world models en production, nouveaux modèles tenant en 16 Go), le mettre à jour avec
la date et la source — c'est notre garde-fou anti-bullshit.*
