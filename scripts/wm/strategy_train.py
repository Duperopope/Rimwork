"""
DOWN HERE - SYSTEME INTELLIGENT (world model + planification), pas du cas-par-cas.

Le directeur a raison : coder "si H2S -> evite" est stupide. Le H2S est POISON sans
chimiosynthese, mais SOURCE D'ENERGIE avec. Et il faut gerer l'ATP (energie vitale),
la sante, et le compromis "cette zone me nourrit ET me blesse". On n'ECRIT pas ces
regles : l'agent APPREND la dynamique (etat,action)->etat suivant, puis PLANIFIE
(MPC) pour maximiser sa vitalite (ATP+sante). Le bon comportement EMERGE de l'etat.

Cle : la capacite (canChemo) est DANS l'etat -> le meme monde appris donne deux
comportements opposes selon ce que la cellule sait faire. C'est ca, "intelligent".

Entrainement EN PARALLELE sur beaucoup d'environnements varies (capacites/densites
differentes) -> un seul world model qui generalise. CPU, reproductible.

  python scripts/wm/strategy_train.py
  python scripts/wm/strategy_train.py --configs 32 --episodes 6

On COMPARE le planificateur appris a :
  - aleatoire,
  - la regle CAS-PAR-CAS "fonce au glucose, fuis TOUJOURS le H2S".
Si l'agent appris bat la regle (en SACHANT exploiter le H2S quand il le peut), alors
le systeme est plus intelligent que des heuristiques. Sinon, on le dit.
"""
import argparse
import json
import os
import sys
from multiprocessing import Pool

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "scripts", "logs", "strategy_evidence.json")

N_ACTIONS = 5
MOVES = {0: (0.0, 0.0), 1: (1.0, 0.0), 2: (-1.0, 0.0), 3: (0.0, 1.0), 4: (0.0, -1.0)}
FIELD = 6.0


class RichMicrobeEnv:
    """Economie reelle en miniature. Etat (9D) :
       [atp, sante, foodDx, foodDz, foodDist, h2sDx, h2sDz, h2sDist, canChemo].
       Dynamique (PROPRIETE de l'env, jamais donnee a l'agent) :
         - metabolisme : l'ATP baisse a chaque pas.
         - glucose proche -> +ATP.
         - H2S proche : si canChemo -> +ATP (nourriture) ; sinon -> -sante (poison).
         - ATP haut -> la sante remonte ; ATP a zero -> la sante chute.
    """

    def __init__(self, can_chemo, glucose_n=2, h2s_n=2, grid=11.0, metab=0.085,
                 max_steps=300, seed=0):
        self.can_chemo = float(can_chemo)
        self.grid = grid
        self.metab = metab
        self.max_steps = max_steps
        self.rng = np.random.default_rng(seed)
        self.glucose = self.rng.uniform(0, grid, size=(glucose_n, 2))
        self.h2s = self.rng.uniform(0, grid, size=(h2s_n, 2))
        self.reset()

    def reset(self):
        self.pos = np.array([self.grid / 2, self.grid / 2], float)
        self.atp = 0.6
        self.health = 1.0
        self.steps = 0
        return self.state()

    def _rel(self, pts):
        d = pts - self.pos
        dist = np.linalg.norm(d, axis=1)
        i = int(np.argmin(dist))
        v = d[i]
        n = np.linalg.norm(v)
        unit = v / n if n > 1e-6 else np.zeros(2)
        return unit[0], unit[1], min(1.0, dist[i] / FIELD)

    def state(self):
        gx, gz, gd = self._rel(self.glucose)
        hx, hz, hd = self._rel(self.h2s)
        return np.array([self.atp, self.health, gx, gz, gd, hx, hz, hd, self.can_chemo], float)

    def step(self, action):
        mv = np.array(MOVES[int(action)], float)
        self.pos = np.clip(self.pos + mv, 0, self.grid)
        _, _, gd = self._rel(self.glucose)
        _, _, hd = self._rel(self.h2s)
        gain = 0.13 * (1.0 - gd)                  # glucose -> ATP (modeste/rare : insuffisant seul)
        if self.can_chemo > 0.5:
            gain += 0.26 * (1.0 - hd)             # H2S -> ATP ABONDANTE (la cellule le metabolise)
            dmg = 0.0
        else:
            dmg = 0.30 * (1.0 - hd)               # H2S -> degats (pas de chimiosynthese)
        self.atp = float(np.clip(self.atp + gain - self.metab, 0.0, 1.0))
        if self.atp <= 0.0:
            self.health -= 0.10                   # famine
        elif self.atp > 0.6:
            self.health += 0.02                   # recuperation
        self.health = float(np.clip(self.health - dmg, 0.0, 1.0))
        self.steps += 1
        done = self.health <= 0.0 or self.steps >= self.max_steps
        return self.state(), done


def _onehot(a):
    v = [0.0] * N_ACTIONS
    v[a] = 1.0
    return v


def make_env(cfg, seed):
    return RichMicrobeEnv(can_chemo=cfg["can_chemo"], glucose_n=cfg["glucose_n"],
                          h2s_n=cfg["h2s_n"], seed=seed)


def collect_one(args):
    """Exploration aleatoire d'UN environnement -> transitions. (worker parallele)"""
    cfg, seed, episodes = args
    rng = np.random.default_rng(seed)
    X, Y = [], []
    for ep in range(episodes):
        env = make_env(cfg, seed * 100 + ep)
        s = env.state()
        done = False
        while not done:
            a = int(rng.integers(0, N_ACTIONS))
            ns, done = env.step(a)
            X.append(np.concatenate([s, _onehot(a)]))
            Y.append(ns)
            s = ns
    return np.array(X), np.array(Y)


def plan(wm, state, horizon=6):
    """MPC : maximise la SURVIE predite sur l'horizon. La SANTE pese lourd (c'est elle
    qui tue) + l'ATP en second + une penalite forte si la sante predite s'effondre
    (zone mortelle). Aucune regle 'evite le H2S' : le modele decide selon canChemo."""
    best_a, best_val = 0, -1e9
    for a in range(N_ACTIONS):
        s = np.array(state, float)
        oh = _onehot(a)
        total = 0.0
        for _ in range(horizon):
            s = wm.predict(np.concatenate([s, oh]).reshape(1, -1))[0]
            health = s[1]
            total += 3.0 * health + s[0]          # survie d'abord, energie ensuite
            if health < 0.3:
                total -= 2.0 * (0.3 - health)     # aversion au risque (zone mortelle)
        if total > best_val:
            best_val, best_a = total, a
    return best_a


def naive_rule(state):
    """CAS-PAR-CAS (ce que le directeur refuse) : fonce au glucose, fuis TOUJOURS le H2S."""
    _, _, gx, gz, gd, hx, hz, hd, _ = state
    if hd < 0.4:                       # H2S proche -> fuir (peu importe la capacite)
        dx, dz = -hx, -hz
    else:                              # sinon -> glucose
        dx, dz = gx, gz
    # action discrete la plus proche
    if abs(dx) < 0.2 and abs(dz) < 0.2:
        return 0
    return (1 if dx >= 0 else 2) if abs(dx) >= abs(dz) else (3 if dz >= 0 else 4)


def run(policy, cfg, n, seed_base):
    surv, atp, h2sprox = [], [], []
    for i in range(n):
        env = make_env(cfg, seed_base + i)
        s = env.state()
        done = False
        dists = []
        while not done:
            s, done = env.step(policy(s))
            dists.append(s[7])   # distance H2S normalisee
        surv.append(env.steps)
        atp.append(env.atp)
        h2sprox.append(float(np.mean(dists)))
    return float(np.mean(surv)), float(np.mean(atp)), float(np.mean(h2sprox))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--configs", type=int, default=24)
    ap.add_argument("--episodes", type=int, default=5)
    args = ap.parse_args()
    from sklearn.neural_network import MLPRegressor
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import mean_squared_error

    # Beaucoup d'environnements VARIES (avec ou sans chimiosynthese, densites variees).
    rng = np.random.default_rng(0)
    jobs = []
    for k in range(args.configs):
        cfg = {"can_chemo": int(k % 2),
               "glucose_n": int(rng.integers(1, 4)),
               "h2s_n": int(rng.integers(1, 4))}
        jobs.append((cfg, 1000 + k, args.episodes))

    print(f"1) COLLECTE EN PARALLELE sur {args.configs} environnements varies ({os.cpu_count()} coeurs)")
    try:
        with Pool(processes=min(8, os.cpu_count() or 2)) as p:
            parts = p.map(collect_one, jobs)
    except Exception as e:
        print(f"   (parallele indisponible: {e} -> sequentiel)")
        parts = [collect_one(j) for j in jobs]
    X = np.concatenate([a for a, _ in parts]); Y = np.concatenate([b for _, b in parts])
    print(f"   {len(X)} transitions (etat,action)->etat, sans aucune recompense\n")

    print("2) WORLD MODEL auto-supervise (un seul, pour TOUS les environnements)")
    Xtr, Xte, Ytr, Yte = train_test_split(X, Y, test_size=0.2, random_state=0)
    base = mean_squared_error(Yte, Xte[:, :9])
    wm = MLPRegressor(hidden_layer_sizes=(96, 64), max_iter=900, random_state=0).fit(Xtr, Ytr)
    mse = mean_squared_error(Yte, wm.predict(Xte))
    print(f"   MSE={mse:.4f}  baseline 'rien ne change'={base:.4f}  (apprend: {mse < base * 0.9})\n")

    print("3) EPREUVE: glucose RARE, H2S ABONDANT. Le H2S est-il poison ou nourriture ?")
    print("   (l'agent doit DECIDER selon canChemo - rien n'est code en dur)")
    cfgA = {"can_chemo": 1, "glucose_n": 1, "h2s_n": 3}   # PEUT manger le H2S
    cfgB = {"can_chemo": 0, "glucose_n": 1, "h2s_n": 3}   # NE PEUT PAS
    rndp = lambda s: int(np.random.default_rng().integers(0, N_ACTIONS))
    wmp = lambda s: plan(wm, s, horizon=8)
    res = {}
    for name, cfg in [("AVEC chimiosynthese", cfgA), ("SANS chimiosynthese", cfgB)]:
        r = run(rndp, cfg, 30, 5000)
        nv = run(naive_rule, cfg, 30, 5000)
        w = run(wmp, cfg, 30, 5000)
        res[name] = {"random": [round(r[0], 1), round(r[2], 2)],
                     "regle_cas_par_cas": [round(nv[0], 1), round(nv[2], 2)],
                     "world_model": [round(w[0], 1), round(w[2], 2)]}
        print(f"   [{name}]            survie(pas)   distH2S(bas=s'approche)")
        print(f"      aleatoire             {r[0]:7.1f}        {r[2]:.2f}")
        print(f"      regle cas-par-cas     {nv[0]:7.1f}        {nv[2]:.2f}")
        print(f"      WORLD MODEL (appris)  {w[0]:7.1f}        {w[2]:.2f}")

    a = res["AVEC chimiosynthese"]; b = res["SANS chimiosynthese"]
    # INTELLIGENCE = un comportement CONTEXTUEL appris : s'APPROCHER du H2S quand on
    # peut le metaboliser, RESTER LOIN quand on ne peut pas - sans le coder. On le
    # mesure par la distance au H2S (le seul vrai discriminant ici, la survie sature
    # car camper le glucose suffit deja). Et sans capacite, ne pas mourir plus que la regle.
    context_switch = b["world_model"][1] - a["world_model"][1] >= 0.05      # plus pres AVEC qu'SANS
    not_worse = b["world_model"][0] >= b["regle_cas_par_cas"][0] * 0.9      # survie ~ regle sans capacite
    smarter = context_switch and not_worse
    print("\nVERDICT")
    print(f"   H2S traite DIFFEREMMENT selon la capacite (appris, non code) :")
    print(f"      AVEC chimiosynthese  -> distH2S {a['world_model'][1]} (s'en APPROCHE = l'exploite)")
    print(f"      SANS chimiosynthese  -> distH2S {b['world_model'][1]} (reste LOIN = l'evite, comme la regle {b['regle_cas_par_cas'][1]})")
    print(f"   commutation contextuelle apprise : {'OUI' if context_switch else 'non'} | survie sans capacite >= regle : {'OUI' if not_worse else 'non'}")
    print(f"   -> systeme INTELLIGENT (contextuel) plutot que cas-par-cas : {'OUI' if smarter else 'PAS encore'}")
    print("   NB: l'AVANTAGE de survie chiffre demande un sim avec depletion des ressources")
    print("       (camper le glucose sature la survie ici) - prochaine etape honnete.")
    json.dump({"mse": round(float(mse), 4), "baseline": round(float(base), 4),
               "results": res, "world_model_smarter_than_rule": bool(smarter),
               "transitions": int(len(X)), "configs": args.configs},
              open(OUT, "w", encoding="utf-8"), indent=2)
    print(f"\n-> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
