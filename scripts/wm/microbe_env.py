"""
DOWN HERE - Micro-environnement deterministe (sandbox du stade cellulaire).

Une cellule sur une grille, avec une energie. Des sources de nourriture la
NOURRISSENT quand elle s'en approche (champ lisse : plus proche = plus d'energie).
Des TOXINES (optionnelles) la DRAINENT quand elle s'en approche (champ lisse aussi).
Metabolisme constant -> elle MEURT si elle ne s'alimente pas.

L'AGENT N'A AUCUNE REGLE "va vers la nourriture" / "fuis la toxine". Ces dynamiques
sont des proprietes de l'ENVIRONNEMENT. Un agent doit les DECOUVRIR. Avec des toxines,
la bonne strategie devient un COMPROMIS (s'approcher du sucre SANS toucher au poison) :
c'est la dynamique reelle du stade cellulaire de Down Here! (nutriments vs agentoxin).

Etat percu (auto-suffisant, relatif) :
  sans toxine (compat) : [energie, dxF, dyF, distF]
  avec toxine          : [energie, dxF, dyF, distF, dxT, dyT, distT]
ou (dx,dy) = direction unitaire vers la source la plus proche, dist normalisee 0..1.
Actions : 0=rester, 1=+x, 2=-x, 3=+y, 4=-y.
"""
import numpy as np

N_ACTIONS = 5
_MOVES = {0: (0, 0), 1: (1, 0), 2: (-1, 0), 3: (0, 1), 4: (0, -1)}


class MicrobeEnv:
    FIELD = 6.0  # echelle (cellules) des champs de nourrissement / toxine / perception

    def __init__(self, grid=11.0, n_food=2, n_hazard=0, metabolism=0.13,
                 hazard_strength=0.30, max_steps=150, seed=0):
        self.grid = grid
        self.n_food = n_food
        self.n_hazard = n_hazard
        self.metab = metabolism
        self.hazard_strength = hazard_strength
        self.max_steps = max_steps
        self.rng = np.random.default_rng(seed)
        self.reset()

    def reset(self):
        self.pos = np.array([self.grid / 2, self.grid / 2], float)
        self.foods = self.rng.uniform(0, self.grid, size=(self.n_food, 2))
        self.hazards = (self.rng.uniform(0, self.grid, size=(self.n_hazard, 2))
                        if self.n_hazard > 0 else np.zeros((0, 2)))
        self.energy = 0.5
        self.steps = 0
        return self.state()

    @staticmethod
    def _nearest(points, pos):
        d = points - pos
        dist = np.linalg.norm(d, axis=1)
        i = int(np.argmin(dist))
        return d[i], dist[i]

    def _rel(self, points):
        """(dx,dy) unitaire + distance normalisee vers le point le plus proche."""
        d, dist = self._nearest(points, self.pos)
        norm = np.linalg.norm(d)
        unit = d / norm if norm > 1e-6 else np.zeros(2)
        return unit[0], unit[1], min(1.0, dist / self.FIELD)

    def state(self):
        fx, fy, fd = self._rel(self.foods)
        base = [self.energy, fx, fy, fd]
        if self.n_hazard > 0:
            hx, hy, hd = self._rel(self.hazards)
            base += [hx, hy, hd]
        return np.array(base, float)

    def step(self, action):
        mv = np.array(_MOVES[int(action)], float)
        self.pos = np.clip(self.pos + mv, 0, self.grid)
        _, distf = self._nearest(self.foods, self.pos)
        dnorm = min(1.0, distf / self.FIELD)
        # Champ de nourrissement LISSE (gradient sur ~FIELD cellules, apprenable)
        # mais EXIGEANT : au-dela de ~3 cellules, nourish < metabolisme -> on meurt.
        nourish = 0.25 * (1.0 - dnorm)
        # TOXINE : champ de drain symetrique. S'approcher du poison COUTE de l'energie
        # -> la cellule doit apprendre a chercher le sucre en evitant le poison.
        toxin = 0.0
        if self.n_hazard > 0:
            _, disth = self._nearest(self.hazards, self.pos)
            toxin = self.hazard_strength * (1.0 - min(1.0, disth / self.FIELD))
        self.energy = float(np.clip(self.energy + nourish - self.metab - toxin, 0.0, 1.0))
        self.steps += 1
        done = self.energy <= 0.0 or self.steps >= self.max_steps
        return self.state(), done

    def dist_to_food(self):
        _, dist = self._nearest(self.foods, self.pos)
        return dist

    def dist_to_hazard(self):
        if self.n_hazard <= 0:
            return float("nan")
        _, dist = self._nearest(self.hazards, self.pos)
        return dist
