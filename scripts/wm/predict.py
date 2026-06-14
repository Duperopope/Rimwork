"""
DOWN HERE - World Model : prediction du succes d'un patch.

Lit un patch en JSON sur stdin : {"search": "...", "replace": "...", "ext": "cs"}
et imprime la probabilite de SUCCES (build/parse OK) sur stdout, ex: 0.812
Si le modele n'est pas entraine, imprime "NA" (le dev_loop retombe alors sur
ses heuristiques). Aucune sortie parasite -> appelable depuis PowerShell.

  echo '{"search":"a","replace":"b","ext":"cs"}' | python scripts/wm/predict.py
"""
import json
import os
import sys
import pickle

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from features import extract_features  # noqa: E402

MODEL_PKL = os.path.join(HERE, "model.pkl")


def main():
    if not os.path.exists(MODEL_PKL):
        print("NA")
        return 0
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        x = extract_features(payload.get("search", ""), payload.get("replace", ""),
                             payload.get("ext", ""))
        model = pickle.load(open(MODEL_PKL, "rb"))
        p = float(model.predict_proba([x])[0][1])
        print(f"{p:.4f}")
    except Exception:
        print("NA")
    return 0


if __name__ == "__main__":
    sys.exit(main())
