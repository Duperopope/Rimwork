"""
DOWN HERE - PRE-ENTRAINEMENT du world model du jeu (anti spirale de la mort).

Probleme observe : a la naissance, le world model n'a AUCUNE donnee -> l'agent
retombe sur le reflexe "fonce au glucose", qui le pousse dans les vagues de H2S et
le TUE avant qu'il ait pu apprendre quoi que ce soit. Ce reflexe est justement la
regle codee en dur que le directeur ne veut pas.

Solution (apprise, pas codee) : on PRE-ENTRAINE le world model sur une sandbox qui
reproduit l'ECONOMIE reelle (ATP, glucose->energie, H2S = energie si chimiosynthese
SINON degats, sante liee a l'ATP), au MEME format d'etat 14D que le vrai jeu. La
cellule NAIT alors en COMPRENANT le compromis : ne pas risquer la mort dans une
vague toxique pour un glucose marginal quand on va deja bien. Puis elle affine sur
le vrai jeu. Aucune regle "evite le H2S" n'est ecrite : tout vient du modele appris.

Etat 14D (meme contrat que play_agent/play_brain) :
  0 sante 1 ATP 2 glucose 3 H2S 4 ammoniac 5 phosphate 6 fer 7 canChemo
  8 foodDx 9 foodDz 10 foodDist 11 toxinDx 12 toxinDz 13 toxinDist

Sortie : scripts/logs/pretrain_transitions.jsonl  (lu par play_brain.train)

  python scripts/wm/pretrain_world.py
  python scripts/wm/pretrain_world.py --configs 48 --episodes 8
"""
import argparse
import json
import os
import sys
from multiprocessing import Pool

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "scripts", "logs", "pretrain_transitions.jsonl")

N_ACTIONS = 5
MOVES = {0: (0.0, 0.0), 1: (1.0, 0.0), 2: (-1.0, 0.0), 3: (0.0, 1.0), 4: (0.0, -1.0)}
FIELD = 6.0


class GameLikeEnv:
    """Economie du stade cellulaire, format d'etat 14D du vrai jeu."""

    def __init__(self, can_chemo, glucose_n=2, h2s_n=2, grid=11.0, metab=0.06,
                 max_steps=200, seed=0):
        self.can_chemo = float(can_chemo)
        self.grid = grid
        self.metab = metab
        self.max_steps = max_steps
        self.rng = np.random.default_rng(seed)
        self.glucose = self.rng.uniform(0, grid, size=(glucose_n, 2))
        self.h2s = self.rng.uniform(0, grid, size=(h2s_n, 2))
        self.nutrient = self.rng.uniform(0, grid, size=(2, 2))   # ammoniac/phosphate
        self.reset()

    def reset(self):
        self.pos = np.array([self.grid / 2, self.grid / 2], float)
        self.atp = self.rng.uniform(0.3, 0.7)
        self.health = 1.0
        self.glu = self.rng.uniform(0, 0.5); self.h2sStock = 0.0
        self.amm = self.rng.uniform(0, 0.3); self.pho = self.rng.uniform(0, 0.3)
        self.iron = self.rng.uniform(0, 0.3)
        self.steps = 0
        return self.state()

    def _rel(self, pts):
        d = pts - self.pos
        dist = np.linalg.norm(d, axis=1)
        i = int(np.argmin(dist))
        v = d[i]; n = np.linalg.norm(v)
        unit = v / n if n > 1e-6 else np.zeros(2)
        return unit[0], unit[1], min(1.0, dist[i] / FIELD)

    def state(self):
        gx, gz, gd = self._rel(self.glucose)
        hx, hz, hd = self._rel(self.h2s)
        return np.array([self.health, self.atp, self.glu, self.h2sStock, self.amm, self.pho,
                         self.iron, self.can_chemo, gx, gz, gd, hx, hz, hd], float)

    def step(self, action):
        mv = np.array(MOVES[int(action)], float)
        self.pos = np.clip(self.pos + mv, 0, self.grid)
        _, _, gd = self._rel(self.glucose)
        _, _, hd = self._rel(self.h2s)
        _, _, nd = self._rel(self.nutrient)
        gain = 0.18 * (1.0 - gd)                       # glucose -> ATP
        if self.can_chemo > 0.5:
            gain += 0.22 * (1.0 - hd); self.h2sStock = min(1.0, self.h2sStock + 0.1 * (1.0 - hd))
            dmg = 0.0
        else:
            dmg = 0.28 * (1.0 - hd)                    # H2S -> degats (pas de chimiosynthese)
        self.atp = float(np.clip(self.atp + gain - self.metab, 0.0, 1.0))
        self.glu = float(np.clip(self.glu + 0.12 * (1.0 - gd) - 0.03, 0.0, 1.0))
        self.amm = float(np.clip(self.amm + 0.1 * (1.0 - nd) - 0.01, 0.0, 1.0))
        self.pho = float(np.clip(self.pho + 0.1 * (1.0 - nd) - 0.01, 0.0, 1.0))
        if self.atp <= 0.0:
            self.health -= 0.10
        elif self.atp > 0.6:
            self.health += 0.02
        self.health = float(np.clip(self.health - dmg, 0.0, 1.0))
        self.steps += 1
        done = self.health <= 0.0 or self.steps >= self.max_steps
        return self.state(), done


def _onehot(a):
    v = [0.0] * N_ACTIONS; v[a] = 1.0; return v


def collect_one(args):
    cfg, seed, episodes = args
    rng = np.random.default_rng(seed)
    rows = []
    for ep in range(episodes):
        env = GameLikeEnv(can_chemo=cfg["can_chemo"], glucose_n=cfg["glucose_n"],
                          h2s_n=cfg["h2s_n"], seed=seed * 100 + ep)
        s = env.state(); done = False
        while not done:
            a = int(rng.integers(0, N_ACTIONS))
            ns, done = env.step(a)
            rows.append({"s": [round(float(x), 4) for x in s], "a": a,
                         "ns": [round(float(x), 4) for x in ns]})
            s = ns
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--configs", type=int, default=40)
    ap.add_argument("--episodes", type=int, default=6)
    args = ap.parse_args()
    rng = np.random.default_rng(0)
    jobs = [({"can_chemo": int(k % 2), "glucose_n": int(rng.integers(1, 4)),
              "h2s_n": int(rng.integers(1, 4))}, 2000 + k, args.episodes)
            for k in range(args.configs)]
    print(f"pre-entrainement: {args.configs} environnements varies en PARALLELE ({os.cpu_count()} coeurs)")
    try:
        with Pool(processes=min(8, os.cpu_count() or 2)) as p:
            parts = p.map(collect_one, jobs)
    except Exception as e:
        print(f"  (parallele indispo: {e} -> sequentiel)")
        parts = [collect_one(j) for j in jobs]
    n = 0
    with open(OUT, "w", encoding="utf-8") as f:
        for rows in parts:
            for r in rows:
                f.write(json.dumps(r) + "\n"); n += 1
    print(f"{n} transitions 14D ecrites -> {OUT}")
    print("   (la moitie AVEC chimiosynthese, la moitie SANS -> le modele apprend le compromis)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
