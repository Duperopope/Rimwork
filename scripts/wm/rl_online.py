"""
DOWN HERE - APPRENTISSAGE EN LIGNE (REINFORCE) sur le VRAI jeu.

La politique pre-entrainee en sandbox (rl_train.py) est un point de depart ; ici elle
s'AMELIORE sur l'experience REELLE pour fermer l'ecart sim->reel. C'est ainsi que
l'IA TrackMania apprend : SUR le jeu, par la recompense.

Methode : REINFORCE (gradient de politique, Williams 1992). L'agent agit de facon
STOCHASTIQUE (echantillonne softmax(W.obs+b) -> exploration), le jeu lui donne une
recompense reelle (survie/sante/reproduction), et on pousse les parametres dans le
sens des actions qui ont mene a un meilleur RETOUR. Rien n'est code : la politique
apprend de la recompense.

Lit  scripts/logs/rl_episodes.jsonl   (lignes {s, a, r, done} ecrites par play_agent)
Met a jour  scripts/wm/rl_policy.json  (et consomme les episodes traites)
Trace  scripts/logs/rl_online.jsonl    (retour moyen par mise a jour -> doit monter)

  python scripts/wm/rl_online.py
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LOGS = os.path.join(ROOT, "scripts", "logs")
EPIS = os.path.join(LOGS, "rl_episodes.jsonl")
POLICY = os.path.join(HERE, "rl_policy.json")
CURVE = os.path.join(LOGS, "rl_online.jsonl")
GAMMA = 0.96
LR = 0.04
MIN_STEPS = 200   # n'apprend qu'avec assez d'experience reelle


def softmax(z, temp):
    z = (z - z.max()) / max(temp, 1e-3)
    e = np.exp(z)
    return e / e.sum()


def main():
    if not os.path.exists(POLICY):
        print("pas de rl_policy.json (lance rl_train.py d'abord)"); return 1
    if not os.path.exists(EPIS):
        print("pas encore d'experience reelle (rl_episodes.jsonl)"); return 1

    p = json.load(open(POLICY, encoding="utf-8"))
    od, na = int(p["obs_dim"]), int(p["n_actions"])
    temp = float(p.get("temp", 0.6))
    theta = np.array(p["theta"], float)
    W = theta[: na * od].reshape(na, od)
    b = theta[na * od:].copy()

    # Lit l'experience et la segmente en EPISODES (separes par done).
    episodes, cur = [], []
    for line in open(EPIS, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
            s, a, r = o["s"], int(o["a"]), float(o["r"])
            if len(s) != od or not (0 <= a < na):
                continue
            cur.append((np.asarray(s, float), a, r))
            if o.get("done"):
                episodes.append(cur); cur = []
        except Exception:
            continue
    if cur:
        episodes.append(cur)
    n_steps = sum(len(e) for e in episodes)
    if n_steps < MIN_STEPS:
        print(f"pas assez d'experience ({n_steps} pas < {MIN_STEPS}) - on continue a jouer"); return 1

    # Retours actualises G_t, puis baseline (moyenne) + normalisation -> faible variance.
    S, A, G = [], [], []
    ep_returns = []
    for ep in episodes:
        g = 0.0
        gs = []
        for (_, _, r) in reversed(ep):
            g = r + GAMMA * g
            gs.append(g)
        gs.reverse()
        ep_returns.append(sum(r for (_, _, r) in ep))
        for (s, a, _), gt in zip(ep, gs):
            S.append(s); A.append(a); G.append(gt)
    G = np.array(G, float)
    G = (G - G.mean()) / (G.std() + 1e-6)

    # REINFORCE : theta += LR * sum_t (G_t) * grad_logpi(a_t|s_t).
    gW = np.zeros_like(W); gb = np.zeros_like(b)
    for s, a, gt in zip(S, A, G):
        probs = softmax(W @ s + b, temp)
        dlogits = -probs
        dlogits[a] += 1.0                  # grad de log pi(a|s) p/r logits
        gW += gt * np.outer(dlogits, s)
        gb += gt * dlogits
    W += LR * gW / len(S)
    b += LR * gb / len(S)

    new_theta = np.concatenate([W.reshape(-1), b])
    p["theta"] = new_theta.tolist()
    json.dump(p, open(POLICY, "w", encoding="utf-8"))

    mean_ret = float(np.mean(ep_returns))
    mean_len = n_steps / max(1, len(episodes))
    with open(CURVE, "a", encoding="utf-8") as f:
        f.write(json.dumps({"episodes": len(episodes), "steps": n_steps,
                            "mean_return": round(mean_ret, 3), "mean_len": round(mean_len, 1)}) + "\n")
    # Consomme les episodes traites (on repart sur du frais -> on-policy).
    open(EPIS, "w").close()
    print(f"REINFORCE: {len(episodes)} episodes / {n_steps} pas reels -> politique mise a jour")
    print(f"  retour moyen={mean_ret:.3f}  duree moyenne={mean_len:.1f} pas  (voir {CURVE})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
