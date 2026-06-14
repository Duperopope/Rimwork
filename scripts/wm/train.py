"""
DOWN HERE - World Model : entrainement du predicteur DEPLOYE.

Si un SUCCESSEUR a ete conçu (wm_champion_spec.json par successor.py), on
DEPLOIE cette spec (le cerveau auto-conçu devient le modele reel). Sinon, repli :
on compare logreg vs forest et on garde le meilleur par AUC.

Sorties :
  - scripts/wm/model.pkl       : le pipeline sklearn (utilise par predict.py)
  - scripts/logs/wm_model.json : metriques + features + seuil (transparence)

  python scripts/wm/train.py
"""
import json
import os
import sys
import pickle
import datetime

import numpy as np
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score, StratifiedKFold

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from features import FEATURE_NAMES  # noqa: E402
from spec import build_model  # noqa: E402

LOGS = os.path.join(ROOT, "scripts", "logs")
EXP = os.path.join(LOGS, "experience.jsonl")
MODEL_PKL = os.path.join(HERE, "model.pkl")
METRICS = os.path.join(LOGS, "wm_model.json")
CHAMP = os.path.join(LOGS, "wm_champion_spec.json")
MIN_PER_CLASS = 8


def load():
    X, y = [], []
    for line in open(EXP, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line:
            o = json.loads(line); X.append(o["x"]); y.append(int(o["y"]))
    return np.array(X, dtype=float), np.array(y, dtype=int)


def main():
    if not os.path.exists(EXP):
        print("Pas d'experience.jsonl - lance bootstrap.py d'abord."); return 1
    X, y = load()
    n_pos, n_neg = int((y == 1).sum()), int((y == 0).sum())
    if n_pos < MIN_PER_CLASS or n_neg < MIN_PER_CLASS:
        print(f"Pas assez de donnees ({n_pos}/{n_neg}, min {MIN_PER_CLASS}/classe).")
        json.dump({"ready": False, "n_pos": n_pos, "n_neg": n_neg}, open(METRICS, "w", encoding="utf-8"))
        return 1

    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=0)
    source = "fallback"
    spec = None
    if os.path.exists(CHAMP):
        # DEPLOIE le successeur auto-conçu.
        spec = json.load(open(CHAMP, encoding="utf-8"))["spec"]
        feats = [f for f in spec["features"] if f in FEATURE_NAMES]
        cols = [FEATURE_NAMES.index(f) for f in feats]
        Xsel = X[:, cols]
        model = build_model(spec)
        auc = cross_val_score(model, Xsel, y, cv=cv, scoring="roc_auc").mean()
        model.fit(Xsel, y)
        ptr = model.predict_proba(Xsel)[:, 1]
        threshold = float(np.percentile(ptr, spec.get("threshold_pct", 20)))
        source = "successor"
        modelname = spec["model"]
    else:
        # Repli : logreg vs forest.
        cands = {"logreg": make_pipeline(StandardScaler(), LogisticRegression(class_weight="balanced", max_iter=1000)),
                 "forest": make_pipeline(StandardScaler(), RandomForestClassifier(n_estimators=200, class_weight="balanced", random_state=0))}
        scores = {k: cross_val_score(m, X, y, cv=cv, scoring="roc_auc").mean() for k, m in cands.items()}
        modelname = max(scores, key=scores.get)
        model = cands[modelname].fit(X, y)
        auc = scores[modelname]
        feats = list(FEATURE_NAMES)
        ptr = model.predict_proba(X)[:, 1]
        threshold = float(np.percentile(ptr, 20))

    pickle.dump(model, open(MODEL_PKL, "wb"))
    meta = {
        "ready": True,
        "trained_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "source": source, "model": modelname, "features": feats,
        "n": int(len(y)), "n_pos": n_pos, "n_neg": n_neg,
        "cv_auc": float(auc), "default_threshold": round(threshold, 4),
        "base_rate": round(n_pos / len(y), 3),
    }
    json.dump(meta, open(METRICS, "w", encoding="utf-8"), indent=2)
    print(f"Deploye [{source}] '{modelname}' sur {len(feats)} features. AUC={auc:.3f}. -> {MODEL_PKL}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
