"""
DOWN HERE - CERVEAU world model pour PILOTER la VRAIE cellule du jeu.

Meme principe que emergence.py mais branche sur le JEU REEL (Thrive/Down Here) via
le pont fichier deja en place (MicrobeStage.cs ecrit agent_state.json / lit
agent_action.json). play_agent.ps1 :
  - construit un vecteur d'etat [energie, foodDx_unit, foodDz_unit, foodDistNorm],
  - LOGue les transitions reelles (s, action, s') dans real_transitions.jsonl,
  - appelle ce script pour DECIDER le mouvement (planification MPC avec un world
    model appris sur les transitions REELLES du jeu).

Deux modes :
  python play_brain.py --train          # (re)entraine game_wm.pkl depuis les transitions reelles
  echo '<state json>' | python play_brain.py   # decide : repond {"moveX","moveZ","engulf","src"}

Tolerant : tant qu'il n'y a pas assez de donnees reelles (ou pas de modele), on
retombe sur un REFLEXE (aller vers la nourriture) -> l'agent marche tout de suite,
et devient "world model" des qu'il a observe assez le vrai jeu. AUCUNE regle de
survie n'est codee dans la planification : elle vient du modele appris.
"""
import json
import os
import pickle
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LOGS = os.path.join(ROOT, "scripts", "logs")
TRANS = os.path.join(LOGS, "real_transitions.jsonl")
MODEL = os.path.join(HERE, "game_wm.pkl")

N_ACTIONS = 5
MOVES = {0: (0.0, 0.0), 1: (1.0, 0.0), 2: (-1.0, 0.0), 3: (0.0, 1.0), 4: (0.0, -1.0)}
MIN_TRANS = 120          # en-dessous : reflexe (pas assez vu le vrai jeu)
ENGULF_DIST = 0.15       # distance normalisee sous laquelle on engloutit


def _onehot(a):
    v = [0.0] * N_ACTIONS
    v[a] = 1.0
    return v


def reflex(state):
    """Aller vers la nourriture (repli sur). state = [energy, fdx, fdz, fdistN]."""
    _, fdx, fdz, fdist = (list(state) + [0, 0, 0, 1])[:4]
    n = (fdx * fdx + fdz * fdz) ** 0.5
    if n < 1e-6:
        return {"moveX": 0.0, "moveZ": 0.0, "engulf": False, "src": "reflex(idle)"}
    return {"moveX": round(fdx / n, 3), "moveZ": round(fdz / n, 3),
            "engulf": bool(fdist < ENGULF_DIST), "src": "reflex(seek)"}


def train():
    if not os.path.exists(TRANS):
        print("pas de real_transitions.jsonl"); return 1
    import numpy as np
    from sklearn.neural_network import MLPRegressor
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import mean_squared_error
    X, Y = [], []
    for line in open(TRANS, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
            s, a, ns = o["s"], int(o["a"]), o["ns"]
            if len(s) == 4 and len(ns) == 4 and 0 <= a < N_ACTIONS:
                X.append(list(s) + _onehot(a)); Y.append(list(ns))
        except Exception:
            continue
    n = len(X)
    if n < MIN_TRANS:
        print(f"pas assez de transitions ({n} < {MIN_TRANS}) - le reflexe continue"); return 1
    X, Y = np.array(X, float), np.array(Y, float)
    Xtr, Xte, Ytr, Yte = train_test_split(X, Y, test_size=0.25, random_state=0)
    base = mean_squared_error(Yte, Xte[:, :4])   # baseline "rien ne change"
    wm = MLPRegressor(hidden_layer_sizes=(64, 32), max_iter=800, random_state=0).fit(Xtr, Ytr)
    mse = mean_squared_error(Yte, wm.predict(Xte))
    pickle.dump(wm, open(MODEL, "wb"))
    json.dump({"n": n, "mse": round(float(mse), 5), "baseline_mse": round(float(base), 5),
               "learns": bool(mse < base * 0.9)},
              open(os.path.join(LOGS, "game_wm.json"), "w"))
    print(f"game_wm: {n} transitions reelles, MSE={mse:.5f} (baseline {base:.5f}) -> {MODEL}")
    return 0


def plan(state, horizon=6):
    """MPC : simule chaque action sur `horizon` pas avec le world model appris,
    choisit celle qui maximise l'energie predite. Aucune regle de survie codee."""
    import numpy as np
    if not os.path.exists(MODEL):
        return None
    wm = pickle.load(open(MODEL, "rb"))
    best_a, best_val = 0, -1e9
    for a in range(N_ACTIONS):
        s = np.array(state, float)
        oh = _onehot(a)
        total = 0.0
        for _ in range(horizon):
            s = wm.predict(np.concatenate([s, oh]).reshape(1, -1))[0]
            total += s[0]   # energie predite
        if total > best_val:
            best_val, best_a = total, a
    return best_a


def decide(state):
    try:
        a = plan(state)
    except Exception:
        a = None
    if a is None:
        return reflex(state)
    mx, mz = MOVES[a]
    fdist = (list(state) + [1])[3]
    return {"moveX": round(mx, 3), "moveZ": round(mz, 3),
            "engulf": bool(fdist < ENGULF_DIST), "src": "worldmodel(MPC)"}


def main():
    if "--train" in sys.argv:
        return train()
    raw = sys.stdin.read().strip()
    try:
        state = json.loads(raw)
        if isinstance(state, dict):
            state = state.get("state") or state.get("s")
    except Exception:
        state = None
    if not state or len(state) < 4:
        print(json.dumps({"moveX": 0.0, "moveZ": 0.0, "engulf": False, "src": "nostate"}))
        return 0
    print(json.dumps(decide(list(state)[:4])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
