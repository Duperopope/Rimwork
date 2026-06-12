using System;
using System.Collections.Generic;
using System.Linq;

// =====================================================================
// ORIGINES — modèle cellulaire (réimplémentation des piliers de Thrive,
// réécrite à notre manière, optimisée et testable en headless).
//
// Ce fichier est la FONDATION du stade microbien profond. Il ne dépend
// PAS de Godot: la simulation vit ici (testée sans rendu), le visuel
// (éditeur hexagonal, membranes procédurales) se branchera dessus.
//
// Piliers couverts (équivalents Thrive):
//   - Compounds (ATP, glucose, ammoniac, phosphates, O2, CO2, lumière…)
//   - Organelles posés sur une grille HEXAGONALE (axiale q,r)
//   - Processes: chaque organite transforme des composés (taux/seconde)
//   - Métabolisme: osmorégulation (coût ATP par hex), équilibre ATP
//   - Stats DÉRIVÉES de la forme assemblée (vitesse, stockage, PV, taille)
// =====================================================================
namespace DownHere.Origins
{
    /// <summary>Composés simulés. Vocabulaire repris de Thrive, réduit au
    /// cœur signifiant pour le stade cellulaire.</summary>
    public enum Compound
    {
        ATP,            // monnaie énergétique
        Glucose,        // sucre — carburant principal
        Ammonia,        // azote — synthèse
        Phosphates,     // phosphore — synthèse / reproduction
        HydrogenSulfide,// chimiosynthèse
        Oxygen,         // respiration aérobie
        CarbonDioxide,  // déchet / photosynthèse
        Sunlight,       // environnement (photosynthèse)
        Mucilage,       // sécrétion (vitesse/défense)
    }

    /// <summary>Une transformation de composés (par seconde, à plein régime).
    /// Les valeurs négatives = consommation, positives = production.</summary>
    public sealed class BioProcess
    {
        public string Name;
        public Dictionary<Compound, float> Rates; // par seconde
        public BioProcess(string name, Dictionary<Compound, float> rates)
        { Name = name; Rates = rates; }
    }

    /// <summary>Définition immuable d'un type d'organite (donnée, pas
    /// instance). Équivalent de organelles.json côté Thrive.</summary>
    public sealed class OrganelleType
    {
        public string Id;
        public string DisplayName;
        public int HexCount;                       // nb d'hex occupés (taille)
        public float MpCost;                        // coût en points de mutation
        public float StorageBonus;                  // capacité de stockage
        public float SpeedBonus;                    // bonus de vitesse (flagelle…)
        public float HpBonus;                        // robustesse (membrane…)
        public float OsmoregulationCost;            // ATP/s d'entretien (par hex)
        public IReadOnlyList<BioProcess> Processes; // métabolisme fourni

        public OrganelleType(string id, string name, int hexCount, float mp,
            float storage = 0, float speed = 0, float hp = 0, float osmo = 1f,
            IReadOnlyList<BioProcess> processes = null)
        {
            Id = id; DisplayName = name; HexCount = hexCount; MpCost = mp;
            StorageBonus = storage; SpeedBonus = speed; HpBonus = hp;
            OsmoregulationCost = osmo;
            Processes = processes ?? Array.Empty<BioProcess>();
        }
    }

    /// <summary>Catalogue des organites disponibles. Source unique de
    /// vérité — l'éditeur lit ce registre pour proposer les pièces.</summary>
    public static class OrganelleRegistry
    {
        public static readonly OrganelleType Cytoplasm = new(
            "cytoplasm", "Cytoplasme", 1, 0, storage: 1f, osmo: 1f,
            processes: new[] {
                // Glycolyse: glucose -> ATP (anaérobie, modeste)
                new BioProcess("Glycolyse", new() {
                    [Compound.Glucose] = -0.5f, [Compound.ATP] = +3f,
                }),
            });

        public static readonly OrganelleType Mitochondrion = new(
            "mitochondrion", "Mitochondrie", 1, 35, osmo: 1f,
            processes: new[] {
                // Respiration aérobie: glucose + O2 -> ATP (rendement élevé)
                new BioProcess("Respiration", new() {
                    [Compound.Glucose] = -1f, [Compound.Oxygen] = -1f,
                    [Compound.ATP] = +18f, [Compound.CarbonDioxide] = +1f,
                }),
            });

        public static readonly OrganelleType Chloroplast = new(
            "chloroplast", "Chloroplaste", 2, 45, osmo: 1f,
            processes: new[] {
                // Photosynthèse: lumière + CO2 -> glucose + O2
                new BioProcess("Photosynthèse", new() {
                    [Compound.Sunlight] = -1f, [Compound.CarbonDioxide] = -1f,
                    [Compound.Glucose] = +0.6f, [Compound.Oxygen] = +1f,
                }),
            });

        public static readonly OrganelleType Thylakoid = new(
            "thylakoid", "Thylakoïde", 1, 30, osmo: 1f,
            processes: new[] {
                new BioProcess("Photosynthèse (protéine)", new() {
                    [Compound.Sunlight] = -0.6f, [Compound.CarbonDioxide] = -0.6f,
                    [Compound.Glucose] = +0.3f, [Compound.Oxygen] = +0.6f,
                }),
            });

        public static readonly OrganelleType Chemoplast = new(
            "chemoplast", "Chimioplaste", 2, 40, osmo: 1f,
            processes: new[] {
                // Chimiosynthèse: H2S + CO2 -> glucose
                new BioProcess("Chimiosynthèse", new() {
                    [Compound.HydrogenSulfide] = -1f, [Compound.CarbonDioxide] = -1f,
                    [Compound.Glucose] = +0.5f,
                }),
            });

        public static readonly OrganelleType Vacuole = new(
            "vacuole", "Vacuole", 1, 15, storage: 5f, osmo: 1f);

        public static readonly OrganelleType Flagellum = new(
            "flagellum", "Flagelle", 1, 25, speed: 25f, osmo: 1.2f,
            processes: new[] {
                new BioProcess("Propulsion", new() { [Compound.ATP] = -1f }),
            });

        public static readonly OrganelleType Pilus = new(
            "pilus", "Pilus", 1, 25, hp: 0f, osmo: 1f); // arme: géré au combat

        public static readonly OrganelleType MetabolosomeMembrane = new(
            "double_membrane", "Membrane double", 1, 20, hp: 30f, osmo: 0.5f);

        public static readonly OrganelleType ToxinVacuole = new(
            "toxin_vacuole", "Vacuole à toxine", 1, 40, storage: 2f, osmo: 1f,
            processes: new[] {
                new BioProcess("Synthèse oxytoxine", new() {
                    [Compound.ATP] = -1f, [Compound.Mucilage] = +0.2f,
                }),
            });

        public static IReadOnlyList<OrganelleType> All { get; } = new[]
        {
            Cytoplasm, Mitochondrion, Chloroplast, Thylakoid, Chemoplast,
            Vacuole, Flagellum, Pilus, MetabolosomeMembrane, ToxinVacuole,
        };

        public static OrganelleType ById(string id) =>
            All.FirstOrDefault(o => o.Id == id);
    }

    /// <summary>Un organite POSÉ dans une cellule, à une coordonnée hex
    /// axiale (q,r). L'orientation servira au rendu/flagelles.</summary>
    public struct PlacedOrganelle
    {
        public OrganelleType Type;
        public int Q, R;          // coordonnée hexagonale axiale
        public int Rotation;      // 0..5 (sextants)
        public PlacedOrganelle(OrganelleType type, int q, int r, int rotation = 0)
        { Type = type; Q = q; R = r; Rotation = rotation; }
    }

    /// <summary>Stats dérivées de la forme assemblée — calculées, jamais
    /// stockées en dur. C'est ce que l'éditeur affiche en temps réel.</summary>
    public struct CellStats
    {
        public int HexSize;              // nb total d'hex (taille)
        public float StorageCapacity;    // capacité composés
        public float BaseSpeed;          // vitesse de nage
        public float MaxHp;              // points de vie
        public float OsmoregulationCost; // ATP/s d'entretien total
        public float AtpBalance;         // ATP/s net à plein régime
        public int MpCost;               // coût total en points de mutation
    }
}
