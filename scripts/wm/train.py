"""
DOWN HERE - World Model : entrainement du predicteur de succes d'un patch.

Lit scripts/logs/experience.jsonl (features + label), compare quelques modeles
en validation croisee (AUC), garde le meilleur, et l'enregistre :
  - scripts/wm/model.pkl   : le pipeline sklearn (utilise par predict.py)
  - scripts/logs/wm_model.json : metriques + importances (transparence/dashboard)

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

LOGS = os.path.join(ROOT, "scripts", "logs")
EXP = os.path.join(LOGS, "experience.jsonl")
MODEL_PKL = os.path.join(HERE, "model.pkl")
METRICS = os.path.join(LOGS, "wm_model.json")

MIN_PER_CLASS = 8  # en-dessous, pas assez pour un modele fiable


def load():
    X, y = [], []
    for line in open(EXP, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if not line:
            continue
        o = json.loads(line)
        X.append(o["x"])
        y.append(int(o["y"]))
    return np.array(X, dtype=float), np.array(y, dtype=int)


def main():
    if not os.path.exists(EXP):
        print("Pas d'experience.jsonl - lance bootstrap.py d'abord.")
        return 1
    X, y = load()
    n_pos, n_neg = int((y == 1).sum()), int((y == 0).sum())
    if n_pos < MIN_PER_CLASS or n_neg < MIN_PER_CLASS:
        print(f"Pas assez de donnees ({n_pos} gardes / {n_neg} casses, min {MIN_PER_CLASS}/classe).")
        json.dump({"ready": False, "n_pos": n_pos, "n_neg": n_neg},
                  open(METRICS, "w", encoding="utf-8"))
        return 1

    candidates = {
        "logreg": make_pipeline(StandardScaler(),
                                LogisticRegression(class_weight="balanced", max_iter=1000)),
        "forest": make_pipeline(StandardScaler(),
                                RandomForestClassifier(n_estimators=200, class_weight="balanced",
                                                       random_state=0)),
    }
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=0)
    scores = {}
    for name, model in candidates.items():
        auc = cross_val_score(model, X, y, cv=cv, scoring="roc_auc").mean()
        acc = cross_val_score(model, X, y, cv=cv, scoring="balanced_accuracy").mean()
        scores[name] = {"auc": float(auc), "balanced_acc": float(acc)}
        print(f"  {name:7s} AUC={auc:.3f}  balanced_acc={acc:.3f}")

    best = max(scores, key=lambda k: scores[k]["auc"])
    model = candidates[best].fit(X, y)
    pickle.dump(model, open(MODEL_PKL, "wb"))

    # Seuil de GATE adaptatif : comme les classes sont desequilibrees (taux de
    # base ~ n_pos/n), un seuil fixe rejetterait tout. On rejette ~le pire
    # quintile (20e percentile des proba predites) = "n'economise un build que
    # sur les patchs les plus surement casses". Conservateur par design.
    probs = model.predict_proba(X)[:, 1]
    threshold = float(np.percentile(probs, 20))

    # Importances (transparence) : coef logreg, ou feature_importances_ forest.
    importance = {}
    try:
        clf = model.steps[-1][1]
        if hasattr(clf, "coef_"):
            importance = {f: float(w) for f, w in zip(FEATURE_NAMES, clf.coef_[0])}
        elif hasattr(clf, "feature_importances_"):
            importance = {f: float(w) for f, w in zip(FEATURE_NAMES, clf.feature_importances_)}
    except Exception:
        pass

    meta = {
        "ready": True,
        "trained_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "model": best,
        "n": int(len(y)), "n_pos": n_pos, "n_neg": n_neg,
        "cv_auc": scores[best]["auc"],
        "cv_balanced_acc": scores[best]["balanced_acc"],
        "all_scores": scores,
        "features": FEATURE_NAMES,
        "importance": importance,
        "base_rate": round(n_pos / len(y), 3),
        "default_threshold": round(threshold, 4),
    }
    json.dump(meta, open(METRICS, "w", encoding="utf-8"), indent=2)
    print(f"Modele '{best}' garde (AUC={scores[best]['auc']:.3f}). -> {MODEL_PKL}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
