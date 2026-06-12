using System;
using System.Collections.Generic;
using System.Linq;

namespace DownHere.Origins
{
    /// <summary>L'état environnemental d'une parcelle (équivalent "patch"
    /// Thrive): ce qui est disponible alimente les processus.</summary>
    public sealed class Environment
    {
        public float Sunlight = 1f;        // 0..1 (profondeur/jour-nuit)
        public float OxygenAvailable = 1f; // dissous
        public float HydrogenSulfide = 0f; // sources hydrothermales
        public float CarbonDioxide = 1f;
        public float GlucosePatch = 0.2f;  // sucre ambiant absorbable

        public static Environment SurfaceWater() => new()
        { Sunlight = 1f, OxygenAvailable = 1f, HydrogenSulfide = 0f, CarbonDioxide = 1f, GlucosePatch = 0.2f };

        public static Environment DeepVent() => new()
        { Sunlight = 0f, OxygenAvailable = 0.1f, HydrogenSulfide = 1f, CarbonDioxide = 1f, GlucosePatch = 0.05f };
    }

    /// <summary>Un microbe = un assemblage d'organites + un stock de
    /// composés. Toute la profondeur (métabolisme, mort, reproduction)
    /// est ici, sans aucune dépendance au rendu.</summary>
    public sealed class Microbe
    {
        public readonly List<PlacedOrganelle> Organelles = new();
        public readonly Dictionary<Compound, float> Stored = new();
        public bool IsDead { get; private set; }

        /// <summary>Mutation points dépensés (budget d'édition, façon Thrive).</summary>
        public const int MpBudget = 100;

        public Microbe() { }

        /// <summary>Cellule de départ canonique: un noyau de cytoplasme.</summary>
        public static Microbe Starter()
        {
            var m = new Microbe();
            m.Organelles.Add(new PlacedOrganelle(OrganelleRegistry.Cytoplasm, 0, 0));
            m.Organelles.Add(new PlacedOrganelle(OrganelleRegistry.Cytoplasm, 1, 0));
            m.RefillToCapacity();
            return m;
        }

        public bool CanPlace(OrganelleType type, int q, int r)
        {
            if (Occupied(q, r)) return false;
            // Doit toucher un hex déjà posé (cellule connexe) — sauf le 1er.
            if (Organelles.Count == 0) return true;
            return Neighbors(q, r).Any(n => Occupied(n.q, n.r));
        }

        public bool Place(OrganelleType type, int q, int r, int rotation = 0)
        {
            if (!CanPlace(type, q, r)) return false;
            Organelles.Add(new PlacedOrganelle(type, q, r, rotation));
            return true;
        }

        public bool Occupied(int q, int r) =>
            Organelles.Any(o => o.Q == q && o.R == r);

        private static IEnumerable<(int q, int r)> Neighbors(int q, int r)
        {
            yield return (q + 1, r);
            yield return (q - 1, r);
            yield return (q, r + 1);
            yield return (q, r - 1);
            yield return (q + 1, r - 1);
            yield return (q - 1, r + 1);
        }

        // ----------------------------------------------------------------
        // STATS dérivées — recalculées à la demande depuis la forme.
        // ----------------------------------------------------------------
        public CellStats ComputeStats(Environment env = null)
        {
            env ??= Environment.SurfaceWater();
            var s = new CellStats { StorageCapacity = 0f, MaxHp = 0f };
            float osmo = 0f, speed = 0f; int mp = 0, hex = 0;

            foreach (var po in Organelles)
            {
                var t = po.Type;
                hex += t.HexCount;
                s.StorageCapacity += t.StorageBonus;
                s.MaxHp += t.HpBonus;
                speed += t.SpeedBonus;
                osmo += t.OsmoregulationCost * t.HexCount;
                mp += (int)t.MpCost;
            }

            s.HexSize = hex;
            // Base: chaque hex donne un peu de PV et de stockage de base.
            s.MaxHp += hex * 10f;
            s.StorageCapacity += hex * 1f;
            // Plus c'est gros, plus c'est lent à se mouvoir (inertie).
            float baseSpeed = 20f + speed;
            s.BaseSpeed = baseSpeed / (1f + hex * 0.08f);
            s.OsmoregulationCost = osmo;
            s.MpCost = mp;
            s.AtpBalance = NetAtpPerSecond(env) - osmo;
            return s;
        }

        /// <summary>ATP/s produit net par les processus (hors osmorégulation),
        /// borné par la disponibilité environnementale des intrants.</summary>
        private float NetAtpPerSecond(Environment env)
        {
            float atp = 0f;
            foreach (var (comp, rate) in ProcessThroughput(env))
                if (comp == Compound.ATP) atp += rate;
            return atp;
        }

        /// <summary>Débit net de CHAQUE composé/seconde à plein régime,
        /// pondéré par la disponibilité des intrants environnementaux.</summary>
        public Dictionary<Compound, float> ProcessThroughput(Environment env)
        {
            var net = new Dictionary<Compound, float>();
            foreach (var po in Organelles)
                foreach (var proc in po.Type.Processes)
                {
                    float eff = EnvEfficiency(proc, env);
                    if (eff <= 0f) continue;
                    foreach (var (comp, rate) in proc.Rates)
                        net[comp] = net.GetValueOrDefault(comp) + rate * eff;
                }
            return net;
        }

        /// <summary>Un processus tourne à plein (1.0) seulement si ses
        /// intrants environnementaux sont là (lumière pour la photo, etc.).</summary>
        private static float EnvEfficiency(BioProcess proc, Environment env)
        {
            float eff = 1f;
            if (proc.Rates.ContainsKey(Compound.Sunlight))
                eff = Math.Min(eff, env.Sunlight);
            if (proc.Rates.TryGetValue(Compound.Oxygen, out var o) && o < 0)
                eff = Math.Min(eff, env.OxygenAvailable);
            if (proc.Rates.TryGetValue(Compound.HydrogenSulfide, out var h) && h < 0)
                eff = Math.Min(eff, env.HydrogenSulfide);
            return eff;
        }

        // ----------------------------------------------------------------
        // MÉTABOLISME — un pas de simulation (dt en secondes).
        // ----------------------------------------------------------------
        public void Tick(float dt, Environment env)
        {
            if (IsDead) return;
            var stats = ComputeStats(env);
            var flux = ProcessThroughput(env);

            // Absorption passive de glucose ambiant.
            Add(Compound.Glucose, env.GlucosePatch * dt, stats.StorageCapacity);

            // Applique les flux des processus (production/consommation).
            foreach (var (comp, rate) in flux)
            {
                if (rate >= 0) Add(comp, rate * dt, stats.StorageCapacity);
                else Stored[comp] = Math.Max(0f, Stored.GetValueOrDefault(comp) + rate * dt);
            }

            // Osmorégulation: coût d'entretien prélevé sur l'ATP.
            float upkeep = stats.OsmoregulationCost * dt;
            float atp = Stored.GetValueOrDefault(Compound.ATP);
            if (atp >= upkeep) Stored[Compound.ATP] = atp - upkeep;
            else
            {
                // Plus d'ATP pour s'entretenir: la cellule s'éteint.
                Stored[Compound.ATP] = 0f;
                IsDead = true;
            }
        }

        private void Add(Compound c, float amount, float cap)
        {
            float v = Stored.GetValueOrDefault(c) + amount;
            Stored[c] = cap > 0 ? Math.Min(v, cap) : Math.Max(0f, v);
        }

        public void RefillToCapacity()
        {
            var cap = ComputeStats().StorageCapacity;
            Stored[Compound.ATP] = cap * 0.5f;
            Stored[Compound.Glucose] = cap * 0.5f;
        }

        /// <summary>Prêt à se diviser quand assez de phosphates/glucose
        /// stockés (proxy de la reproduction Thrive).</summary>
        public bool CanReproduce()
        {
            var cap = ComputeStats().StorageCapacity;
            return Stored.GetValueOrDefault(Compound.Glucose) >= cap * 0.9f;
        }
    }
}
