"""
DOWN HERE - Micro-environnement deterministe (sandbox du stade cellulaire).

Une cellule sur une grille, avec une energie. Des sources de nourriture la
NOURRISSENT quand elle s'en approche (champ lisse : plus proche = plus d'energie).
Metabolisme constant -> elle MEURT si elle ne s'alimente pas.

L'AGENT N'A AUCUNE REGLE "va vers la nourriture". La dynamique (s'approcher
nourrit) est une propriete de l'ENVIRONNEMENT. Un agent doit la DECOUVRIR.

Etat percu (auto-suffisant, relatif) : [energie, dx, dy, dist] ou (dx,dy) est la
direction unitaire vers la nourriture la plus proche et dist sa distance (0..1).
Actions : 0=rester, 1=+x, 2=-x, 3=+y, 4=-y.
"""
import numpy as np

N_ACTIONS = 5
_MOVES = {0: (0, 0), 1: (1, 0), 2: (-1, 0), 3: (0, 1), 4: (0, -1)}


class MicrobeEnv:
    FIELD = 6.0  # echelle (cellules) du champ de nourrissement / perception

    def __init__(self, grid=11.0, n_food=2, metabolism=0.13, max_steps=150, seed=0):
        self.grid = grid
        self.n_food = n_food
        self.metab = metabolism
        self.max_steps = max_steps
        self.rng = np.random.default_rng(seed)
        self.reset()

    def reset(self):
        self.pos = np.array([self.grid / 2, self.grid / 2], float)
        self.foods = self.rng.uniform(0, self.grid, size=(self.n_food, 2))
        self.energy = 0.5
        self.steps = 0
        return self.state()

    def _nearest(self):
        d = self.foods - self.pos
        dist = np.linalg.norm(d, axis=1)
        i = int(np.argmin(dist))
        return d[i], dist[i]

    def state(self):
        d, dist = self._nearest()
        norm = np.linalg.norm(d)
        unit = d / norm if norm > 1e-6 else np.zeros(2)
        dnorm = min(1.0, dist / self.FIELD)
        return np.array([self.energy, unit[0], unit[1], dnorm], float)

    def step(self, action):
        mv = np.array(_MOVES[int(action)], float)
        self.pos = np.clip(self.pos + mv, 0, self.grid)
        _, dist = self._nearest()
        dnorm = min(1.0, dist / self.FIELD)
        # Champ de nourrissement LISSE (gradient sur ~FIELD cellules, donc une
        # direction est apprenable) mais EXIGEANT : au-dela de ~3 cellules,
        # nourish < metabolisme -> on perd de l'energie et on finit par mourir.
        nourish = 0.25 * (1.0 - dnorm)
        self.energy = float(np.clip(self.energy + nourish - self.metab, 0.0, 1.0))
        self.steps += 1
        done = self.energy <= 0.0 or self.steps >= self.max_steps
        return self.state(), done

    def dist_to_food(self):
        _, dist = self._nearest()
        return dist
