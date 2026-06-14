"""
DOWN HERE - Espace de SPECS d'agent (ce qui definit un "cerveau" decisionnel).

Une spec = la definition complete d'une version de l'agent decisionnel :
  - quel modele (logreg / forest / gboost) + ses hyperparametres,
  - quel sous-ensemble de features,
  - quel percentile de seuil de gate.

"Concevoir un successeur" = produire une nouvelle spec (mutation/recherche) et
l'evaluer. C'est la base d'AutoML/NAS et d'ADAS (un systeme qui conçoit ses
propres agents). Source unique de construction + scoring (utilise par successor.py
et train.py) -> le successeur promu est REELLEMENT deploye.
"""
import numpy as np
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.model_selection import train_test_split

from features import FEATURE_NAMES

MODELS = ["logreg", "forest", "gboost"]


def build_model(spec):
    m = spec["model"]
    if m == "logreg":
        clf = LogisticRegression(C=float(spec.get("C", 1.0)), class_weight="balanced", max_iter=1000)
    elif m == "forest":
        clf = RandomForestClassifier(n_estimators=int(spec.get("n_estimators", 200)),
                                     max_depth=spec.get("max_depth", None),
                                     class_weight="balanced", random_state=0)
    else:  # gboost
        clf = GradientBoostingClassifier(n_estimators=int(spec.get("n_estimators", 150)),
                                         max_depth=int(spec.get("max_depth", 3) or 3),
                                         learning_rate=float(spec.get("learning_rate", 0.1)),
                                         random_state=0)
    return make_pipeline(StandardScaler(), clf)


def random_spec(rng):
    k = rng.integers(3, len(FEATURE_NAMES) + 1)
    feats = list(rng.choice(FEATURE_NAMES, size=k, replace=False))
    return _fill(rng, {"model": str(rng.choice(MODELS)), "features": feats,
                       "threshold_pct": int(rng.integers(0, 41))})


def _fill(rng, spec):
    spec.setdefault("C", round(float(10 ** rng.uniform(-1, 1)), 3))
    spec.setdefault("n_estimators", int(rng.choice([100, 200, 300])))
    spec.setdefault("max_depth", int(rng.choice([3, 5, 8, 12])))
    spec.setdefault("learning_rate", round(float(rng.choice([0.05, 0.1, 0.2])), 3))
    return spec


def mutate_spec(spec, rng):
    s = dict(spec); s["features"] = list(spec["features"])
    gene = rng.integers(0, 5)
    if gene == 0:
        s["model"] = str(rng.choice(MODELS))
    elif gene == 1:  # toggle une feature
        f = str(rng.choice(FEATURE_NAMES))
        if f in s["features"] and len(s["features"]) > 3:
            s["features"].remove(f)
        elif f not in s["features"]:
            s["features"].append(f)
    elif gene == 2:
        s["threshold_pct"] = int(np.clip(spec.get("threshold_pct", 10) + rng.integers(-10, 11), 0, 45))
    elif gene == 3:
        s["n_estimators"] = int(rng.choice([100, 200, 300]))
        s["max_depth"] = int(rng.choice([3, 5, 8, 12]))
    else:
        s["C"] = round(float(10 ** rng.uniform(-1, 1)), 3)
        s["learning_rate"] = round(float(rng.choice([0.05, 0.1, 0.2])), 3)
    return _fill(rng, s)


def score_spec(spec, X, y, seeds=(0, 1, 2, 3, 4)):
    """Objectif de PRODUCTION : utilite moyenne par patch sur held-out.
       build->garde=1, build->casse=0, gate(skip)=0.5. Seuil choisi sur TRAIN."""
    cols = [FEATURE_NAMES.index(f) for f in spec["features"]]
    Xs = X[:, cols]
    utils = []
    for s in seeds:
        Xtr, Xte, ytr, yte = train_test_split(Xs, y, test_size=0.30, stratify=y, random_state=int(s))
        m = build_model(spec).fit(Xtr, ytr)
        ptr = m.predict_proba(Xtr)[:, 1]
        pte = m.predict_proba(Xte)[:, 1]
        thr = float(np.percentile(ptr, spec.get("threshold_pct", 0)))
        gate = pte < thr
        r = np.where(gate, 0.5, np.where(yte == 1, 1.0, 0.0)).mean()
        utils.append(float(r))
    return float(np.mean(utils)), float(np.std(utils))


def spec_summary(spec):
    return f"{spec['model']}|{len(spec['features'])}feat|thr{spec.get('threshold_pct',0)}"
