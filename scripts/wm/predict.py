"""
DOWN HERE - World Model : prediction du succes d'un patch (modele DEPLOYE).

Lit un patch JSON sur stdin : {"search": "...", "replace": "...", "ext": "cs"}
et imprime P(succes) sur stdout (ou "NA" si modele absent). Honore le
sous-ensemble de features du modele deploye (cf. wm_model.json -> "features"),
pour rester fidele au successeur auto-conçu. Aucune sortie parasite.

  echo '{"search":"a","replace":"b","ext":"cs"}' | python scripts/wm/predict.py
"""
import json
import os
import sys
import pickle

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from features import extract_features, FEATURE_NAMES  # noqa: E402

MODEL_PKL = os.path.join(HERE, "model.pkl")
METRICS = os.path.join(ROOT, "scripts", "logs", "wm_model.json")


def main():
    if not os.path.exists(MODEL_PKL):
        print("NA"); return 0
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        full = extract_features(payload.get("search", ""), payload.get("replace", ""), payload.get("ext", ""))
        # selectionne les memes features que le modele deploye
        feats = FEATURE_NAMES
        try:
            feats = json.load(open(METRICS, encoding="utf-8")).get("features", FEATURE_NAMES)
        except Exception:
            pass
        x = [full[FEATURE_NAMES.index(f)] for f in feats if f in FEATURE_NAMES]
        model = pickle.load(open(MODEL_PKL, "rb"))
        print(f"{float(model.predict_proba([x])[0][1]):.4f}")
    except Exception:
        print("NA")
    return 0


if __name__ == "__main__":
    sys.exit(main())
