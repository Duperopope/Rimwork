"""
DOWN HERE - PREUVE : world model AUTO-SUPERVISE -> comportement EMERGENT.

Pipeline (100% local, CPU, reproductible) :
  1. COLLECTE auto-supervisee : la cellule explore AU HASARD. On enregistre
     (etat, action) -> etat suivant. AUCUN label, AUCUNE recompense.
  2. WORLD MODEL : un MLP apprend a predire l'etat suivant. C'est de
     l'apprentissage auto-supervise (le "label" = le futur lui-meme), comme la
     prediction du prochain token des LLM ou les world models (Ha/Schmidhuber, JEPA).
  3. EMERGENCE : un agent qui n'a AUCUNE regle "va vers la nourriture" planifie
     avec le world model appris (choisit l'action dont le modele predit la
     meilleure energie). On mesure si un comportement de survie / recherche de
     nourriture EMERGE - alors qu'il n'est ecrit nulle part.

Comparaison honnete contre un agent ALEATOIRE. Sortie : tableau + JSON.

  python scripts/wm/emergence.py
"""
import json
import os
import sys

import numpy as np
from sklearn.neural_network import MLPRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from microbe_env import MicrobeEnv, N_ACTIONS  # noqa: E402

OUT = os.path.join(ROOT, "scripts", "logs", "emergence_evidence.json")


def onehot(a):
    v = np.zeros(N_ACTIONS); v[a] = 1.0; return v


def collect_random(n_episodes, seed):
    """Exploration ALEATOIRE -> transitions (auto-supervise, sans recompense)."""
    rng = np.random.default_rng(seed)
    Xs, Ys = [], []
    for ep in range(n_episodes):
        env = MicrobeEnv(seed=seed * 1000 + ep)
        s = env.state()
        done = False
        while not done:
            a = int(rng.integers(0, N_ACTIONS))
            ns, done = env.step(a)
            Xs.append(np.concatenate([s, onehot(a)]))
            Ys.append(ns)
            s = ns
    return np.array(Xs), np.array(Ys)


def plan_action(wm, state, horizon=6):
    """Planification a HORIZON (MPC) : pour chaque action de depart, on SIMULE
    `horizon` pas avec le world model (en repetant l'action) et on somme
    l'energie predite. On choisit l'action a la meilleure energie cumulee.
    Le SEUL objectif est l'energie predite ; AUCUNE regle sur la nourriture.
    L'horizon amplifie le signal directionnel au-dessus du bruit de prediction."""
    best_a, best_val = 0, -1e9
    for a in range(N_ACTIONS):
        s = state.copy()
        total = 0.0
        oh = onehot(a)
        for _ in range(horizon):
            s = wm.predict(np.concatenate([s, oh]).reshape(1, -1))[0]
            total += s[0]  # energie predite (indice 0 de l'etat)
        if total > best_val:
            best_val, best_a = total, a
    return best_a


def run_episodes(policy, n, seed_base):
    surv, energy, prox = [], [], []
    for i in range(n):
        env = MicrobeEnv(seed=seed_base + i)
        s = env.state()
        done = False
        dists = []
        while not done:
            a = policy(s)
            s, done = env.step(a)
            dists.append(env.dist_to_food())
        surv.append(env.steps)
        energy.append(env.energy)
        prox.append(float(np.mean(dists)))  # distance moyenne a la nourriture
    return np.array(surv), np.array(energy), np.array(prox)


def main():
    rng_seed = 0
    print("1) COLLECTE auto-supervisee (exploration aleatoire, sans recompense)")
    X, Y = collect_random(n_episodes=120, seed=rng_seed)
    print(f"   {len(X)} transitions (etat,action)->etat_suivant\n")

    print("2) WORLD MODEL auto-supervise : courbe d'apprentissage (MSE sur held-out)")
    Xtr, Xte, Ytr, Yte = train_test_split(X, Y, test_size=0.25, random_state=0)
    base_mse = mean_squared_error(Yte, Xte[:, :4])  # baseline "rien ne change"
    curve = []
    for frac in [0.1, 0.25, 0.5, 1.0]:
        nptr = max(50, int(frac * len(Xtr)))
        wm = MLPRegressor(hidden_layer_sizes=(64, 32), max_iter=600, random_state=0)
        wm.fit(Xtr[:nptr], Ytr[:nptr])
        mse = mean_squared_error(Yte, wm.predict(Xte))
        curve.append({"n": nptr, "mse": round(float(mse), 5)})
        print(f"   n_train={nptr:5d}  MSE={mse:.5f}")
    print(f"   baseline 'rien ne change' MSE={base_mse:.5f}  (le WM doit faire MIEUX)\n")
    wm_full = MLPRegressor(hidden_layer_sizes=(64, 32), max_iter=800, random_state=0).fit(Xtr, Ytr)
    final_mse = mean_squared_error(Yte, wm_full.predict(Xte))

    print("3) EMERGENCE : agent planifiant avec le WM appris vs agent ALEATOIRE")
    rng = np.random.default_rng(1)
    rand_policy = lambda s: int(rng.integers(0, N_ACTIONS))
    wm_policy = lambda s: plan_action(wm_full, s)
    rs, re, rp = run_episodes(rand_policy, 40, seed_base=10_000)
    ws, we, wp = run_episodes(wm_policy, 40, seed_base=10_000)  # memes graines = comparaison juste

    print(f"   {'':18s}{'survie(pas)':>14s}{'energie moy':>14s}{'dist.food moy':>15s}")
    print(f"   {'aleatoire':18s}{rs.mean():>14.1f}{re.mean():>14.3f}{rp.mean():>15.2f}")
    print(f"   {'planif. WM':18s}{ws.mean():>14.1f}{we.mean():>14.3f}{wp.mean():>15.2f}")
    print("   (dist.food moy plus BASSE = l'agent reste pres de la nourriture = strategie)")

    learns = final_mse < base_mse * 0.9
    surv_ratio = ws.mean() / max(rs.mean(), 1)
    emerges = surv_ratio > 1.5 and (we.mean() - re.mean()) > 0.2 and wp.mean() < rp.mean()
    print("\nVERDICT")
    print(f"   WM auto-supervise apprend la dynamique : {'OUI' if learns else 'NON'} "
          f"(MSE {final_mse:.4f} < baseline {base_mse:.4f})")
    print(f"   comportement de SURVIE EMERGE : {'OUI' if emerges else 'NON'} "
          f"(survie x{surv_ratio:.1f}, energie {we.mean():.2f} vs {re.mean():.2f}, "
          f"dist.food {wp.mean():.1f} vs {rp.mean():.1f})")
    print("   -> aucune regle 'va/reste vers la nourriture' n'est codee : la strategie")
    print("      vient de la PLANIFICATION (MPC) avec un modele appris SANS recompense.")

    json.dump({
        "transitions": int(len(X)),
        "wm_learning_curve": curve,
        "wm_final_mse": round(float(final_mse), 5),
        "baseline_nochange_mse": round(float(base_mse), 5),
        "random":  {"survival": round(float(rs.mean()), 1), "energy": round(float(re.mean()), 3), "mean_food_dist": round(float(rp.mean()), 2)},
        "wm_planner": {"survival": round(float(ws.mean()), 1), "energy": round(float(we.mean()), 3), "mean_food_dist": round(float(wp.mean()), 2)},
        "survival_ratio": round(float(surv_ratio), 2),
        "verdict_self_supervised_learns": bool(learns),
        "verdict_behavior_emerges": bool(emerges),
    }, open(OUT, "w", encoding="utf-8"), indent=2)
    print(f"\n-> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
