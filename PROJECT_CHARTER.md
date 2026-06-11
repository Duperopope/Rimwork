# RimWorld Lab — Charte de Projet

## Intention Fondamentale

**Ce n'est PAS un clone RimWorld.**

C'est un **laboratoire privé de reconstruction et d'expérimentation assistée par IA** pour :
- Comprendre l'architecture d'une simulation de colonie.
- Reconstruire progressivement une base jouable comme patron de compréhension.
- S'en servir comme tremplin vers un **moteur de simulation massive moderne** (multi-scale, 1M citoyens).

## Utilité

Comparer deux approches :

| Approche | Objectif | Résultat |
|----------|----------|---------|
| **Vanilla Reconstruction** | Reproduire le comportement vanilla | Comprendre les systèmes existants |
| **Modern Engine** | Remplacer l'archi par une version 2026-scale | Moteur nouveau, testé, massif |

**Le vrai produit** n'est pas la reconstruction vanilla. C'est ce qu'on en apprend pour **construire mieux**.

## Règles d'Or

- ❌ Pas de distribution du code ou assets Rockstar.
- ❌ Pas de copie ligne par ligne.
- ✅ Analyse du comportement observable → compréhension → réécriture propre.
- ✅ Tests automatisés à chaque étape.
- ✅ Documentation continuellement.
- ✅ Chaque système a une version vanilla + une version "future moderne".

## Références Approuvées

Source : étude de la vidéo Underscore/Saïm (GTA San Andreas Reverse + Claude Codex).

**Méthodologie transposée** :
```
Binaire/Source → Analyse → Isolation système → Réécriture →  Test → Comparaison source de vérité → Validation
```

Pour nous (RimWorld privé) :
```
Décompilé → Comprendre → Système minimal → Tester → Documenter → Remplacer progressif
```

## Phases

### Phase 0 — Cartographie (Passive)
Lire les ressources existantes (décompilé + mods). Documenter sans coder.

### Phase 1 — Mini-Rim Headless (Actif)
Prototype sans graphismes : 10 agents, faim, sommeil, nourriture, lits, jobs, réservations, tick loop, save/load, tests.

### Phase 2 — Reconstruction Système par Système (Itératif)
Ajouter tous les concepts vanilla un par un, avec tests.

### Phase 3 — Remplacement Moteur (Rearchitectural)
Passer à une architecture multi-scale : agents détaillés + agents simplifiés + population abstraite.

## Horizon

- **Mois 1** : Phases 0 + début Phase 1.
- **Mois 2-3** : Phase 1 complète + Phase 2 à 30 %.
- **Mois 4+** : Phase 2-3, benchmarks, massive scale.

---

**Prochaine étape** : Cartographie (Phase 0).
