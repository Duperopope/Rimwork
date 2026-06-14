"""
DOWN HERE - CONCEPTION DE SUCCESSEUR (auto-amelioration recursive du cerveau).

Le systeme conçoit des versions ameliorees de son PROPRE modele decisionnel et
ne PROMEUT un successeur que s'il bat l'actuel de facon fiable (champion-
challenger a promotion gardee). Repete sur plusieurs generations -> amelioration
mesurable. Methodologie : recherche evolutionnaire (AutoML/NAS) + ADAS + gating
statistique. Le champion promu est ECRIT et REELLEMENT deploye par train.py.

  python scripts/wm/successor.py            # plusieurs generations
  python scripts/wm/successor.py --gens 12

Sorties :
  scripts/logs/wm_champion_spec.json  -> la spec deployee (lue par train.py)
  scripts/logs/wm_lineage.jsonl       -> la genealogie (chaque generation)
"""
import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from spec import random_spec, mutate_spec, score_spec, spec_summary  # noqa: E402
from features import FEATURE_NAMES  # noqa: E402

LOGS = os.path.join(ROOT, "scripts", "logs")
EXP = os.path.join(LOGS, "experience.jsonl")
CHAMP = os.path.join(LOGS, "wm_champion_spec.json")
LINEAGE = os.path.join(LOGS, "wm_lineage.jsonl")


def load():
    X, y = [], []
    for line in open(EXP, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line:
            o = json.loads(line); X.append(o["x"]); y.append(int(o["y"]))
    return np.array(X, float), np.array(y, int)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gens", type=int, default=10)
    ap.add_argument("--children", type=int, default=8)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    if not os.path.exists(EXP):
        print("Pas d'experience.jsonl - lance bootstrap.py d'abord."); return 1
    X, y = load()
    rng = np.random.default_rng(a.seed)

    # Incumbent de depart VOLONTAIREMENT modeste (logreg, peu de features) pour
    # montrer honnetement la MONTEE generation apres generation. Si un champion
    # existe deja, on repart de lui (amelioration continue).
    if os.path.exists(CHAMP):
        champion = json.load(open(CHAMP, encoding="utf-8"))["spec"]
    else:
        champion = {"model": "logreg", "features": FEATURE_NAMES[:4], "threshold_pct": 5, "C": 1.0}
    champ_m, champ_s = score_spec(champion, X, y)
    gen0 = champ_m
    print(f"Incumbent initial: {spec_summary(champion)}  utilite={champ_m:.3f} +/- {champ_s:.3f}\n")

    open(LINEAGE, "w").close()  # reset la genealogie pour cette execution
    history = [round(champ_m, 4)]
    for g in range(1, a.gens + 1):
        # "Conçoit" des successeurs : mutations du champion + un peu d'exploration.
        children = [mutate_spec(champion, rng) for _ in range(a.children - 2)]
        children += [random_spec(rng) for _ in range(2)]
        scored = [(c, *score_spec(c, X, y)) for c in children]
        best, bm, bs = max(scored, key=lambda t: t[1])

        # PROMOTION GARDEE : on ne remplace que si le successeur bat l'actuel
        # au-dela du bruit (marge = la moitie de l'ecart-type combine).
        margin = 0.5 * max(bs, champ_s, 1e-6)
        promoted = bm > champ_m + margin
        if promoted:
            champion, champ_m, champ_s = best, bm, bs

        rec = {"gen": g, "champion": spec_summary(champion), "utility": round(champ_m, 4),
               "best_child": round(bm, 4), "promoted": bool(promoted)}
        json.dump(rec, open(LINEAGE, "a", encoding="utf-8")); open(LINEAGE, "a").write("\n")
        history.append(round(champ_m, 4))
        flag = "PROMU" if promoted else "garde l'actuel"
        print(f"  gen {g:2d}: meilleur enfant={bm:.3f}  champion={champ_m:.3f}  [{flag}] {spec_summary(champion)}")

    gain = champ_m - gen0
    json.dump({"spec": champion, "utility": round(champ_m, 4), "gens": a.gens,
               "history": history, "start_utility": round(gen0, 4),
               "gain": round(gain, 4)}, open(CHAMP, "w", encoding="utf-8"), indent=2)
    print(f"\nChampion final: {spec_summary(champion)}  utilite={champ_m:.3f}")
    print(f"Progression: {gen0:.3f} -> {champ_m:.3f}  (GAIN {gain:+.3f} sur {a.gens} generations)")
    print(f"-> {CHAMP}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
