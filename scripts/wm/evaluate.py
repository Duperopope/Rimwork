"""
DOWN HERE - PREUVE SCIENTIFIQUE de l'auto-amelioration (world model + policy).

On ne CLAME pas l'amelioration : on la MESURE, de facon reproductible.

Deux questions, deux experiences controlees sur l'experience reelle du systeme
(scripts/logs/experience.jsonl) :

  A. COURBE D'APPRENTISSAGE - "plus d'experience -> meilleures predictions ?"
     On entraine le world model sur des fractions croissantes des donnees et on
     mesure l'AUC sur un jeu de test FIXE et tenu a l'ecart. Repete sur N graines,
     on rapporte moyenne +/- ecart-type. Si l'AUC monte avec n, le modele APPREND.

  B. VALEUR DE LA POLITIQUE - "le gate appris bat-il la baseline ?"
     Utilite par patch :  build->garde = 1 | build->casse = 0 | gate(skip) = 0.5
     (sauver un build vaut la moitie d'un succes). Baseline = tout builder
     (seuil 0). On balaie les seuils, on calcule l'utilite moyenne sur le test,
     et on compare le MEILLEUR seuil a la baseline. On rapporte aussi la
     PRECISION du skip : parmi les patchs gates, combien auraient VRAIMENT casse.

Sortie : tableau lisible + scripts/logs/wm_evidence.json (chiffres exacts).

  python scripts/wm/evaluate.py
"""
import json
import os
import sys

import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LOGS = os.path.join(ROOT, "scripts", "logs")
EXP = os.path.join(LOGS, "experience.jsonl")
OUT = os.path.join(LOGS, "wm_evidence.json")

SEEDS = [0, 1, 2, 3, 4]
FRACTIONS = [0.15, 0.30, 0.50, 0.75, 1.0]


def load():
    X, y = [], []
    for line in open(EXP, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line:
            o = json.loads(line)
            X.append(o["x"]); y.append(int(o["y"]))
    return np.array(X, float), np.array(y, int)


def new_model():
    return make_pipeline(StandardScaler(),
                         RandomForestClassifier(n_estimators=200,
                                                class_weight="balanced", random_state=0))


def reward_at(threshold, p, y):
    """Utilite moyenne : skip(P<thr)=0.5 ; sinon 1 si garde, 0 si casse."""
    gate = p < threshold
    r = np.where(gate, 0.5, np.where(y == 1, 1.0, 0.0))
    return float(r.mean()), float(gate.mean())  # (utilite, taux de skip)


def main():
    if not os.path.exists(EXP):
        print("Pas d'experience.jsonl - lance bootstrap.py d'abord.")
        return 1
    X, y = load()
    print(f"Dataset: {len(y)} exemples ({int((y==1).sum())} gardes / {int((y==0).sum())} casses)\n")

    # ---------- A. Courbe d'apprentissage (AUC vs taille, test fixe) ----------
    lc = {f: [] for f in FRACTIONS}
    pol_improv, pol_base, pol_best, pol_prec, pol_skip = [], [], [], [], []
    for seed in SEEDS:
        Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.30, stratify=y, random_state=seed)
        for f in FRACTIONS:
            if f < 1.0:
                Xs, _, ys, _ = train_test_split(Xtr, ytr, train_size=f, stratify=ytr, random_state=seed)
            else:
                Xs, ys = Xtr, ytr
            m = new_model().fit(Xs, ys)
            p = m.predict_proba(Xte)[:, 1]
            lc[f].append(roc_auc_score(yte, p))

        # ---------- B. Valeur de la politique (seuil choisi sur TRAIN, evalue
        # sur TEST : aucune fuite, exactement ce que fait le bandit en prod) ----
        m = new_model().fit(Xtr, ytr)
        ptr = m.predict_proba(Xtr)[:, 1]
        pte = m.predict_proba(Xte)[:, 1]
        base, _ = reward_at(0.0, pte, yte)  # baseline = tout builder, sur TEST
        grid = np.quantile(ptr, np.linspace(0.0, 0.6, 25))
        best_tr, best_t = -1.0, 0.0
        for t in grid:
            r, _ = reward_at(t, ptr, ytr)   # choix du seuil sur TRAIN uniquement
            if r > best_tr:
                best_tr, best_t = r, float(t)
        best_r, _ = reward_at(best_t, pte, yte)  # evaluation sur TEST au seuil fixe
        gate = pte < best_t
        skip_rate = float(gate.mean())
        skip_prec = float((yte[gate] == 0).mean()) if gate.sum() > 0 else float("nan")
        pol_base.append(base); pol_best.append(best_r)
        pol_improv.append(best_r - base); pol_skip.append(skip_rate); pol_prec.append(skip_prec)

    def ms(a):
        a = np.array(a, float); return float(np.nanmean(a)), float(np.nanstd(a))

    print("A. COURBE D'APPRENTISSAGE (AUC sur test tenu a l'ecart, %d graines)" % len(SEEDS))
    curve = []
    for f in FRACTIONS:
        mean, std = ms(lc[f])
        n = int(round(f * 0.7 * len(y)))
        curve.append({"frac": f, "n_train": n, "auc_mean": round(mean, 3), "auc_std": round(std, 3)})
        print(f"   n_train~{n:4d} ({int(f*100):3d}%)  AUC = {mean:.3f} +/- {std:.3f}")
    rising = curve[-1]["auc_mean"] - curve[0]["auc_mean"]

    bm, bs = ms(pol_base); xm, xs = ms(pol_best)
    im, isd = ms(pol_improv); km, ks = ms(pol_skip); pm, ps = ms(pol_prec)
    print("\nB. VALEUR DE LA POLITIQUE (utilite moyenne par patch)")
    print(f"   baseline (tout builder) = {bm:.3f} +/- {bs:.3f}")
    print(f"   meilleur seuil appris   = {xm:.3f} +/- {xs:.3f}")
    print(f"   GAIN                    = {im:+.3f} +/- {isd:.3f}")
    print(f"   taux de skip            = {km:.1%}   precision du skip = {pm:.1%}")
    print("   (precision du skip = parmi les patchs gates, % qui auraient VRAIMENT casse)")

    verdict_A = rising > 0.01
    verdict_B = im > 0.0 and pm > 0.5
    print("\nVERDICT")
    print(f"   A. apprend avec l'experience : {'OUI' if verdict_A else 'NON'} (delta AUC {rising:+.3f})")
    print(f"   B. la politique bat la baseline : {'OUI' if verdict_B else 'NON'}")

    json.dump({
        "n": int(len(y)), "n_pos": int((y == 1).sum()), "n_neg": int((y == 0).sum()),
        "seeds": SEEDS, "learning_curve": curve, "auc_gain_small_to_full": round(rising, 3),
        "policy": {"baseline_reward": round(bm, 3), "best_reward": round(xm, 3),
                   "improvement": round(im, 3), "skip_rate": round(km, 3),
                   "skip_precision": round(pm, 3)},
        "verdict_learns": verdict_A, "verdict_policy_beats_baseline": verdict_B,
    }, open(OUT, "w", encoding="utf-8"), indent=2)
    print(f"\n-> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
