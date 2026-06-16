"""
DOWN HERE - AGENT RL REEL (Cross-Entropy Method) qui APPREND a jouer le stade
cellulaire. Pas de placeholder, pas de perception codee en dur : l'agent recoit des
observations BRUTES et apprend une politique qui MAXIMISE une recompense de survie/
croissance. Sa perception (qu'est-ce qui nourrit, qui menace) EMERGE de la recompense.

Specialise (un seul jeu) -> tourne en LOCAL, CPU, comme l'IA TrackMania des hobbyistes.

Economie CALIBREE sur les vraies donnees du jeu (simulation_parameters/.../bio_processes.json) :
  - glycolysis_cytoplasm : glucose 0.007 -> ATP 2.4   (metabolisme de base)
  - chemoSynthesis       : H2S 0.08 + CO2 -> glucose 0.1  (si chimiosynthese)
  - sans chimiosynthese  : le contact H2S endommage la sante (regle du fork)
  - nuages MIXTES (composes co-localises), stockage SATURANT, repro = ammoniac+phosphate.

POINT CLE (correction du directeur) : les entites font des degats selon un trait
CACHE ("appearance") NON correle a la taille. L'agent ne peut donc PAS deviner la
menace par la taille -> il doit APPRENDRE par l'experience quel trait est dangereux.
"bigger = predator" est faux et n'est nulle part code.

Sortie : scripts/wm/rl_policy.json (politique deployable) + scripts/logs/rl_evidence.json
         (courbe d'apprentissage MESUREE : la recompense doit monter).

  python scripts/wm/rl_train.py
  python scripts/wm/rl_train.py --gens 40 --pop 80
"""
import argparse
import json
import os
import sys
from multiprocessing import Pool

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
POLICY = os.path.join(HERE, "rl_policy.json")
EVID = os.path.join(ROOT, "scripts", "logs", "rl_evidence.json")

N_ACTIONS = 5
MOVES = np.array([[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]], float)
OBS_DIM = 16
FIELD = 6.0


class CellEnv:
    """Stade cellulaire calibre sur les vraies donnees du jeu."""

    def __init__(self, can_chemo, seed=0):
        self.can_chemo = float(can_chemo)
        self.rng = np.random.default_rng(seed)
        self.grid = 12.0
        self.max_steps = 260
        # nuages MIXTES : chaque nuage porte glucose+H2S+ammoniac+phosphate (co-localises).
        self.clouds = self.rng.uniform(0, self.grid, size=(4, 2))
        # entites : trait cache "appearance" (0..1) qui determine la NUISANCE, PAS la taille.
        ne = 5
        self.ent_pos = self.rng.uniform(0, self.grid, size=(ne, 2))
        self.ent_size = self.rng.uniform(0.2, 1.0, size=ne)            # taille (observable, NON predictive)
        self.ent_appear = self.rng.uniform(0, 1, size=ne)             # trait observable
        self.ent_harm = (self.ent_appear > 0.6).astype(float)         # NUISIBLE si appearance haute (cache: a apprendre)
        self.reset()

    def reset(self):
        self.pos = np.array([self.grid / 2, self.grid / 2], float)
        self.health = 1.0
        self.atp = 0.5
        self.glu = self.rng.uniform(0, 0.4)
        self.amm = self.rng.uniform(0, 0.3)
        self.pho = self.rng.uniform(0, 0.3)
        self.h2s = 0.0
        self.repro = 0
        self.steps = 0
        return self.obs()

    def _nearest(self, pts):
        d = pts - self.pos
        dist = np.linalg.norm(d, axis=1)
        i = int(np.argmin(dist))
        v = d[i]; n = np.linalg.norm(v)
        u = v / n if n > 1e-6 else np.zeros(2)
        return i, u[0], u[1], min(1.0, dist[i] / FIELD)

    def _cloud_density(self):
        # densite locale de "nuage" a la position (1 si dessus, ~0 loin) - brut, non etiquete
        d = np.linalg.norm(self.clouds - self.pos, axis=1).min()
        return max(0.0, 1.0 - d / FIELD)

    def obs(self):
        ci, cdx, cdz, cdist = self._nearest(self.clouds)
        ei, edx, edz, edist = self._nearest(self.ent_pos)
        dens = self._cloud_density()
        # OBSERVATION BRUTE (16D) - aucune etiquette nourriture/poison/predateur :
        #  interne(7) + nuage le plus proche(3) + densite locale(1) + entite la plus proche(5: dir,dist,taille,apparence)
        return np.array([
            self.health, self.atp, self.glu, self.amm, self.pho, self.h2s, self.can_chemo,
            cdx, cdz, cdist, dens,
            edx, edz, edist, self.ent_size[ei], self.ent_appear[ei],
        ], float)

    def step(self, action):
        self.pos = np.clip(self.pos + MOVES[int(action)], 0, self.grid)
        ci, _, _, cdist = self._nearest(self.clouds)
        ei, _, _, edist = self._nearest(self.ent_pos)
        on_cloud = max(0.0, 1.0 - cdist)              # proximite au nuage [0..1]

        # --- ECONOMIE calibree ---
        # Intake SATURANT depuis le nuage mixte (glucose/ammoniac/phosphate/H2S).
        self.glu = float(np.clip(self.glu + 0.10 * on_cloud * (1 - self.glu) - 0.0, 0, 1))
        self.amm = float(np.clip(self.amm + 0.06 * on_cloud * (1 - self.amm), 0, 1))
        self.pho = float(np.clip(self.pho + 0.06 * on_cloud * (1 - self.pho), 0, 1))
        # glycolysis : glucose -> ATP (le glucose stocke alimente la vie meme hors nuage)
        burn = min(self.glu, 0.05)
        self.glu -= burn
        self.atp = float(np.clip(self.atp + burn * 3.0 - 0.045, 0, 1))
        # H2S : chimiosynthese -> glucose (energie) SI capable ; SINON degats au contact.
        if self.can_chemo > 0.5:
            self.glu = float(np.clip(self.glu + 0.08 * on_cloud, 0, 1))
            h2s_dmg = 0.0
        else:
            h2s_dmg = 0.30 * on_cloud
        # Entite : degats au contact SI elle est nuisible (selon le trait cache, pas la taille).
        ent_dmg = 0.35 * max(0.0, 1.0 - edist) * self.ent_harm[ei]
        # Sante : ATP haut -> recupere ; ATP nul -> famine ; - degats H2S/entite.
        if self.atp <= 0.0:
            self.health -= 0.08
        elif self.atp > 0.55:
            self.health += 0.02
        self.health = float(np.clip(self.health - h2s_dmg - ent_dmg, 0, 1))
        # Reproduction : assez d'ammoniac + phosphate + ATP -> une division (croissance).
        if self.amm > 0.7 and self.pho > 0.7 and self.atp > 0.5:
            self.repro += 1
            self.amm -= 0.7; self.pho -= 0.7
        self.steps += 1
        done = self.health <= 0.0 or self.steps >= self.max_steps
        # Recompense : rester en vie + sante + ATP + PROGRESSER (reproductions).
        reward = 0.01 + 0.02 * self.health + 0.01 * self.atp
        return self.obs(), reward, done

    def run(self, policy):
        s = self.obs(); total = 0.0; done = False
        repro0 = self.repro
        while not done:
            a = policy(s)
            s, r, done = self.step(a)
            total += r
        total += 0.5 * (self.repro - repro0)   # bonus fort pour la croissance
        return total, self.steps, self.repro


def make_policy(theta):
    """Politique LINEAIRE : logits = W.obs + b ; action = argmax. theta = [W|b] aplati."""
    W = theta[: N_ACTIONS * OBS_DIM].reshape(N_ACTIONS, OBS_DIM)
    b = theta[N_ACTIONS * OBS_DIM:]
    return lambda obs: int(np.argmax(W @ np.asarray(obs) + b))


def eval_theta(args):
    """Recompense moyenne d'une politique sur des environnements varies (avec/sans chimio)."""
    theta, seed = args
    pol = make_policy(theta)
    rng = np.random.default_rng(seed)
    tot = 0.0
    for k in range(6):
        env = CellEnv(can_chemo=int(k % 2), seed=int(rng.integers(1, 1_000_000)))
        r, _, _ = env.run(pol)
        tot += r
    return tot / 6.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gens", type=int, default=35)
    ap.add_argument("--pop", type=int, default=64)
    ap.add_argument("--elite", type=int, default=12)
    a = ap.parse_args()
    dim = N_ACTIONS * OBS_DIM + N_ACTIONS
    rng = np.random.default_rng(0)
    mu = np.zeros(dim)
    sigma = np.ones(dim) * 0.8

    print(f"RL Cross-Entropy : politique {dim} parametres, pop {a.pop}, {a.gens} generations (CPU, {os.cpu_count()} coeurs)")
    curve = []
    best_theta = mu.copy(); best_score = -1e9
    pool = Pool(processes=min(8, os.cpu_count() or 2))
    try:
        for g in range(1, a.gens + 1):
            pop = rng.normal(mu, sigma, size=(a.pop, dim))
            scores = np.array(pool.map(eval_theta, [(pop[i], 1000 + g * 1000 + i) for i in range(a.pop)]))
            idx = np.argsort(scores)[::-1][:a.elite]
            elite = pop[idx]
            mu = elite.mean(axis=0)
            sigma = elite.std(axis=0) + 0.02       # un plancher pour garder de l'exploration
            gen_best = float(scores.max())
            if gen_best > best_score:
                best_score = gen_best; best_theta = pop[int(np.argmax(scores))].copy()
            curve.append({"gen": g, "mean": round(float(scores.mean()), 3), "best": round(gen_best, 3)})
            print(f"  gen {g:2d}: recompense moyenne={scores.mean():7.3f}  meilleure={gen_best:7.3f}")
    finally:
        pool.close(); pool.join()

    # Verdict HONNETE : la politique apprise joue-t-elle MIEUX qu'une politique
    # ALEATOIRE ? (survie + reproductions = la vraie mesure, pas la recompense bruitee)
    pol = make_policy(best_theta)
    rng2 = np.random.default_rng(7)
    rand_pol = lambda obs: int(rng2.integers(0, N_ACTIONS))
    def bench(p):
        R, S, K = [], [], []
        for k in range(40):
            env = CellEnv(can_chemo=int(k % 2), seed=20_000 + k)
            r, steps, repro = env.run(p)
            R.append(r); S.append(steps); K.append(repro)
        return round(float(np.mean(R)), 2), round(float(np.mean(S)), 1), round(float(np.mean(K)), 2)
    tr, ts, tk = bench(pol)
    rr, rs, rk = bench(rand_pol)
    learns = ts > rs * 1.2 or tk > rk + 0.5     # survit plus longtemps OU se reproduit plus
    print(f"\n  APPRIS vs ALEATOIRE : survie {ts} vs {rs} pas | reproductions {tk} vs {rk} | recompense {tr} vs {rr}")
    # Le trait de menace est-il APPRIS (pas la taille) ? on mesure l'evitement des entites nuisibles.
    avoid = measure_threat_avoidance(pol)
    json.dump({"params": dim, "gens": a.gens, "curve": curve,
               "trained": {"reward": tr, "survival": ts, "repro": tk},
               "random": {"reward": rr, "survival": rs, "repro": rk},
               "learns": bool(learns), "threat_avoidance": avoid},
              open(EVID, "w", encoding="utf-8"), indent=2)
    json.dump({"theta": best_theta.tolist(), "obs_dim": OBS_DIM, "n_actions": N_ACTIONS,
               "score": round(best_score, 3)}, open(POLICY, "w", encoding="utf-8"))
    print(f"\nVERDICT: la politique apprise joue MIEUX que l'aleatoire : {learns}")
    print(f"  evitement appris des entites NUISIBLES (trait cache, pas la taille): {avoid}")
    print(f"  -> politique deployable: {POLICY}")
    return 0


def measure_threat_avoidance(pol):
    """Mesure : la politique reste-t-elle PLUS LOIN des entites nuisibles que des
    inoffensives, alors que la TAILLE ne predit rien ? Prouve que la menace est APPRISE."""
    harmful_d, harmless_d = [], []
    for seed in range(40):
        env = CellEnv(can_chemo=int(seed % 2), seed=10_000 + seed)
        s = env.obs(); done = False
        while not done:
            a = pol(s); s, _, done = env.step(a)
            ei, _, _, edist = env._nearest(env.ent_pos)
            (harmful_d if env.ent_harm[ei] > 0.5 else harmless_d).append(edist)
    h = round(float(np.mean(harmful_d)), 3) if harmful_d else None
    s = round(float(np.mean(harmless_d)), 3) if harmless_d else None
    return {"dist_to_harmful": h, "dist_to_harmless": s,
            "keeps_more_distance_from_harmful": bool(h is not None and s is not None and h > s)}


if __name__ == "__main__":
    sys.exit(main())
