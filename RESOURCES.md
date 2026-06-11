# Resources — RimWorld Reference & Tools

## Tier 1: Source Décompilée (Disponible)

### RimWorldDecompiled

- **Repo** : `Chillu1/RimWorldDecompiled`  
- **Type** : C# Décompilé complet des DLLs RimWorld  
- **Status** : À jour, régulièrement maintenu  
- **Légalité** : RimWorld EULA autorise décompilation usage personnel  
- **Usage** : Référence de lecture directe pour comprendre le code réel

**Comment l'utiliser** :
1. Cloner le repo.
2. Ouvrir dans un IDE C#.
3. Naviguer les classes par système (Job, Pawn, Map, Need, etc.).
4. Utiliser comme "source de vérité" pour tests de conformité.

### RimWorldDecompile (Ancien)

- **Repo** : `josh-m/RW-Decompile`  
- **Status** : Plus à jour (ciblait les alphas)  
- **Usage** : Peut servir d'historique architecturale  

---

## Tier 2: Outils de Navigation

### RimSage

- **Type** : MCP Server pour recherche dans code source RimWorld  
- **Usage** : Accélère la recherche / requêtes dans le décompilé  
- **Lien** : GitHub MCP RimSage  

### ILSpy (Communauté Standard)

- **Type** : Décompilateur .NET open-source  
- **Usage** : Alternative au décompilé, utile pour décompiler soi-même des versions spécifiques  
- **Note** : RimWorld wiki recommande explicitement cet outil  

---

## Tier 3: Mods Open-Source (Patterns & Optimisations)

### Performance-Fish

- **Repo** : GitHub Topic `rimworld` → Performance-Fish  
- **Type** : Mod de perf + patchs avancés  
- **Usage** : Voir comment optimiser, patcher sans refaire les systèmes  
- **Valeur** : Montre les bottlenecks connus et solutions  

### Fishery

- **Type** : Librairie de modding  
- **Usage** : Patterns réutilisables pour système/extension  

### Multiplayer & RimWorld-Together

- **Type** : Mods sync réseau  
- **Usage** : Comprendre déterminisme, réplication état  
- **Valeur pour nous** : Inspiration pour save/load déterministe  

### Hardcore-SK

- **Type** : Total conversion massive  
- **Usage** : Exemple d'un gros projet qui étend l'archi  

---

## Tier 4: RimWorld-Like Open-Source (Blueprints Propres)

### FyWorld

- **Repo** : GitHub FyWorld  
- **Type** : Jeu Unity C# top-down base-building/simulation  
- **Description** : "RimWorld-like game" + mega tutorial  
- **Valeur** : Architecture propre, sans contrainte Ludeon, bien documentée  
- **Usage** : Référence pour une implémentation "libre"  

### colonize (Rust)

- **Repo** : `indiv0/colonize`  
- **Type** : "Dwarf Fortress / RimWorld-like game" en Rust  
- **Valeur** : Approche rustacée performante, multi-threaded par design  

### MagicalLife

- **Repo** : `TBye101/MagicalLife`  
- **Type** : 2D base-builder RimWorld-like  
- **Valeur** : Architecture Unity, extensible  

### name-needed (Rust)

- **Repo** : `DomWilliams0/name-needed`  
- **Type** : Effort solo haute perf (Dwarf Fortress/RimWorld-like)  
- **Valeur** : Performance-first design  

---

## Tier 5: Librairies & Concepts

### LibColony

- **Type** : Librairie C++/JS MIT pour task scheduling  
- **Usage** : Étude du système job/autonomie  
- **Valeur** : Abstractions réutilisables  

---

## Stratégie de Lecture : Phase 0

**Semaine 1** :
1. Cloner `Chillu1/RimWorldDecompiled`.
2. Lire structure générale (namespaces, classes principales).
3. Documenter les systèmes critiques : Job, Pawn, Map, Need, Reservation.

**Semaine 2** :
1. Lire Performance-Fish : comprendre les limites vanilla.
2. Lire Multiplayer : comprendre sync/déterminisme.
3. Voir FyWorld pour comparaison architecture.

**Semaine 3** :
1. Créer fiches système (voir `/docs/systems/`).
2. Identifier les dépendances critiques.
3. Proposer schéma de Phase 1 minimal.

**Semaine 4** :
1. Prêt à briefer le LLM avec corpus structuré.

---

## Commandes de Démarrage

```bash
# Clone décompilé
git clone https://github.com/Chillu1/RimWorldDecompiled.git reference/rimworld-decompiled/

# Clone FyWorld
git clone https://github.com/firefly-dev/FyWorld.git reference/fyworld/

# Clone Performance-Fish
git clone https://github.com/... reference/performance-fish/

# À remplir : autres repos key
```

---

## Prochaine Étape

→ Lancer Phase 0 Cartographie avec le corpus ci-dessus.
