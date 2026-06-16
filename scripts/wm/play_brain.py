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
PRETRAIN = os.path.join(LOGS, "pretrain_transitions.jsonl")  # sandbox (anti spirale de la mort)
MODEL = os.path.join(HERE, "game_wm.pkl")
RL_POLICY = os.path.join(HERE, "rl_policy.json")  # politique RL apprise (rl_train.py)

N_ACTIONS = 5
MOVES = {0: (0.0, 0.0), 1: (1.0, 0.0), 2: (-1.0, 0.0), 3: (0.0, 1.0), 4: (0.0, -1.0)}
MIN_TRANS = 120          # en-dessous : reflexe (pas assez vu le vrai jeu)
ENGULF_DIST = 0.15       # distance normalisee sous laquelle on engloutit


# Contrat d'indices de l'etat RICHE 14D (partage avec play_agent.ps1 Get-WmState) :
#  0 sante  1 ATP  2 glucose  3 H2S  4 ammoniac  5 phosphate  6 fer  7 canChemo
#  8 foodDx 9 foodDz 10 foodDist  11 toxinDx 12 toxinDz 13 toxinDist
IDX_HEALTH, IDX_ATP, IDX_GLU = 0, 1, 2
IDX_AMM, IDX_PHO = 4, 5
IDX_FOODDX, IDX_FOODDZ, IDX_FOODDIST = 8, 9, 10


def _onehot(a):
    v = [0.0] * N_ACTIONS
    v[a] = 1.0
    return v


def _food(state):
    """(fdx, fdz, fdist) selon la longueur d'etat (14D riche, ou 4D legacy en repli)."""
    n = len(state)
    if n > IDX_FOODDIST:
        return state[IDX_FOODDX], state[IDX_FOODDZ], state[IDX_FOODDIST]
    return (state[1] if n > 1 else 0.0), (state[2] if n > 2 else 0.0), (state[3] if n > 3 else 1.0)


def reflex(state):
    """Repli sur : aller vers la nourriture (utilise tant que le world model n'a pas
    encore assez de donnees du VRAI jeu)."""
    fdx, fdz, fdist = _food(state)
    n = (fdx * fdx + fdz * fdz) ** 0.5
    if n < 1e-6:
        return {"moveX": 0.0, "moveZ": 0.0, "engulf": False, "src": "reflex(idle)"}
    return {"moveX": round(fdx / n, 3), "moveZ": round(fdz / n, 3),
            "engulf": bool(fdist < ENGULF_DIST), "src": "reflex(seek)"}


def train():
    import numpy as np
    from collections import Counter
    from sklearn.neural_network import MLPRegressor
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import mean_squared_error
    # On apprend sur le PRE-ENTRAINEMENT (sandbox, comprend deja le compromis H2S) ET
    # l'experience REELLE. Resultat: la cellule NAIT en comprenant le risque (plus de
    # reflexe suicidaire au demarrage), puis affine sur le vrai jeu. Rien n'est code.
    recs = []
    nreal = 0
    for path in (PRETRAIN, TRANS):
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8", errors="ignore"):
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
                s, a, ns = o["s"], int(o["a"]), o["ns"]
                if len(s) >= 4 and len(s) == len(ns) and 0 <= a < N_ACTIONS:
                    recs.append((s, a, ns))
                    if path == TRANS:
                        nreal += 1
            except Exception:
                continue
    if not recs:
        print("aucune transition exploitable (ni pretrain ni reel)"); return 1
    # ROBUSTE aux changements de version (4D food seul -> 7D food+toxine) et aux
    # ecritures concurrentes : on entraine sur la dimension d'etat la PLUS FREQUENTE
    # et on ignore les lignes d'une autre dimension. La dynamique apprise inclut alors
    # la toxine (l'energie chute pres du poison) -> la planification l'evite.
    sdim = Counter(len(s) for s, _, _ in recs).most_common(1)[0][0]
    recs = [r for r in recs if len(r[0]) == sdim]
    n = len(recs)
    if n < MIN_TRANS:
        print(f"pas assez de transitions {sdim}D ({n} < {MIN_TRANS}) - le reflexe continue"); return 1
    X = np.array([list(s) + _onehot(a) for s, a, _ in recs], float)
    Y = np.array([list(ns) for _, _, ns in recs], float)
    Xtr, Xte, Ytr, Yte = train_test_split(X, Y, test_size=0.25, random_state=0)
    base = mean_squared_error(Yte, Xte[:, :sdim])   # baseline "rien ne change"
    wm = MLPRegressor(hidden_layer_sizes=(64, 32), max_iter=800, random_state=0).fit(Xtr, Ytr)
    mse = mean_squared_error(Yte, wm.predict(Xte))
    pickle.dump(wm, open(MODEL, "wb"))
    json.dump({"n": n, "n_real": nreal, "n_pretrain": n - nreal, "mse": round(float(mse), 5),
               "baseline_mse": round(float(base), 5), "learns": bool(mse < base * 0.9)},
              open(os.path.join(LOGS, "game_wm.json"), "w"))
    print(f"game_wm: {n} transitions ({nreal} reelles + {n - nreal} pre-entrainement), "
          f"MSE={mse:.5f} (baseline {base:.5f}) -> {MODEL}")
    return 0


def plan(state, horizon=6):
    """MPC : simule chaque action sur `horizon` pas avec le world model appris et
    choisit celle qui maximise la SURVIE predite (sante d'abord, ATP ensuite, aversion
    au risque pres de la mort). AUCUNE regle 'evite le H2S' : le modele decide selon
    l'etat complet (dont canChemo) -> le H2S devient poison OU nourriture, appris."""
    import numpy as np
    if not os.path.exists(MODEL):
        return None
    wm = pickle.load(open(MODEL, "rb"))
    # Securite transition de version : si le modele a ete entraine sur une autre
    # dimension d'etat que celle recue, on repli sur le reflexe (pas de crash).
    try:
        if wm.n_features_in_ != len(state) + N_ACTIONS:
            return None
    except Exception:
        pass
    best_a, best_val = 0, -1e9
    for a in range(N_ACTIONS):
        s = np.array(state, float)
        oh = _onehot(a)
        total = 0.0
        for _ in range(horizon):
            s = wm.predict(np.concatenate([s, oh]).reshape(1, -1))[0]
            health = s[IDX_HEALTH]
            # DRIVE = survivre + maintenir ses RESERVES (le glucose alimente l'ATP, les
            # nutriments permettent de se reproduire). Comme les reserves SATURENT, ce
            # terme pousse a FORAGER quand on est bas et a PARTIR quand on est plein -
            # sans regle "va/evite" codee. La sante domine (on ne meurt pas pour du stock).
            total += 4.0 * health + s[IDX_ATP] + 1.5 * s[IDX_GLU] + 0.5 * (s[IDX_AMM] + s[IDX_PHO])
            if health < 0.3:
                total -= 3.0 * (0.3 - health)        # aversion au risque (zone mortelle)
        if total > best_val:
            best_val, best_a = total, a
    return best_a


def rl_action(state):
    """Politique RL APPRISE (rl_train.py) : on ECHANTILLONNE softmax(W.obs + b) au lieu
    d'un argmax -> EXPLORATION (indispensable pour l'apprentissage en ligne REINFORCE,
    voir rl_online.py). C'est la politique apprise qui decide ; rien n'est code.
    None si pas de politique ou dimension != obs."""
    if not os.path.exists(RL_POLICY):
        return None
    try:
        import numpy as np
        p = json.load(open(RL_POLICY, encoding="utf-8"))
        od, na = int(p["obs_dim"]), int(p["n_actions"])
        if len(state) != od:
            return None
        theta = np.array(p["theta"], float)
        W = theta[: na * od].reshape(na, od)
        b = theta[na * od:]
        temp = float(p.get("temp", 0.6))
        logits = W @ np.asarray(state, float) + b
        z = (logits - logits.max()) / max(temp, 1e-3)
        probs = np.exp(z); probs /= probs.sum()
        return int(np.random.default_rng().choice(na, p=probs))
    except Exception:
        return None


def decide(state):
    # 1) POLITIQUE RL apprise (primaire). 2) repli world-model MPC. 3) repli reflexe.
    a = rl_action(state)
    src = "rl_policy"
    if a is None:
        try:
            a = plan(state)
        except Exception:
            a = None
        src = "worldmodel(MPC)"
    if a is None:
        return reflex(state)
    mx, mz = MOVES[a]
    _, _, fdist = _food(state)
    return {"moveX": round(mx, 3), "moveZ": round(mz, 3),
            "engulf": bool(fdist < ENGULF_DIST), "src": src}


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
    # On garde l'etat COMPLET (4D ou 7D) : la planification a besoin de la toxine.
    print(json.dumps(decide(list(state))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
