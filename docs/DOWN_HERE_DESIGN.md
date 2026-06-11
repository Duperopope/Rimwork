# DOWN HERE ! — Document de design directeur (2026-06-11)

**Pitch** : gestion de colonie · stratégie temps réel/tour par tour · 4X ·
exploration spatiale et développement de civilisation, avec comportements
émergents et histoires auto-générées, et un endgame façon Kerbal Space
Program. Différenciateur face à Before We Leave (référence UX planète) :
la couche RimWorld/Bannerlord qui vit SOUS la couche 4X.

## Échelles (toutes naviguables, zoom continu molette)
Tuile locale (carte jouable) ↔ Planète hex (Goldberg) ↔ Système solaire ↔
(à venir) Multi-systèmes connectés (zoom supplémentaire).

## Chantiers actés — état
| Chantier | État |
|---|---|
| Planète Goldberg ~1212 tuiles, biome par tuile, props, lune, atmosphère | ✅ vérifié à l'image |
| Tuile illuminée à la sélection + fiche ressources | ✅ |
| Nuages stylisés BWL (amas joufflus) + toggle C | ✅ ce commit |
| Bouton Visiter → carte d'expédition par tuile + retour par dézoom | ✅ ce commit (v1: 64x64) |
| Pause machine depuis le dashboard (/pause /resume) | ✅ |
| Renommage Down Here !, version down-here-0.2 | ✅ |

## Chantiers suivants (ordre de dépendance)
1. **Sauvegardes multi-slots** : sérialisation GameWorldManager (JSON) →
   user://saves/slotN.json ; menu Continuer = liste des slots; Nouvelle
   partie → écran de création de monde.
2. **Écran de création de monde** (seed, nb de planètes, vitesse d'orbite,
   mix de biomes, densité pawns/animaux, taille des cartes locales) —
   toutes les variables alimentent la génération déterministe.
3. **Cartes locales ×10** (512+) avec génération PAR BIOME de la tuile
   (désert sans rivières, toundra gelée, forêt dense) — streaming/chunks si
   nécessaire; l'eau avec une vraie logique (rivières qui coulent vers les
   océans, lacs dans les dépressions).
4. **Jour/nuit orbital** : la position de la tuile sur le globe + la
   rotation de la planète + son orbite déterminent l'heure locale ; la lune
   module marées/raids nocturnes. Météo DÉTERMINISTE par tuile (seed +
   climat + saison orbitale).
5. **Vue 4X des unités** : pions/armées visibles sur les tuiles planète =
   agrégats réels des pawns présents dans la tuile (pas de fiction).
6. **Formes de vie par biome** : tables de faune par biome (toundra:
   caribous; forêt: cerfs/loups; désert: scarabées géants...) — d'abord en
   pression régionale (LOD), matérialisées en entités sur la carte locale.
7. **Gravité/atmosphère/composition par planète** : modificateurs réels
   (vitesse de déplacement, coût de construction, besoin d'équipement) —
   pont vers l'endgame spatial KSP.
8. **Multi-systèmes** : graphe d'étoiles connectées, l'échelle au-dessus de
   Solar (SimLOD.Galaxy), navigation par le même zoom continu.

## Règles de fabrication
- Toute affirmation visuelle se vérifie par screenshot auto avant d'être
  annoncée. Toute mécanique par test ou simulation headless.
- Le LLM local continue le gameplay coeur (GameWorld/WorldModel/Needs/Jobs)
  via le roadmap; les passes lourdes (3D/UI/architecture) restent frontier.
- UI freeze contract toujours en vigueur (structure, pas le contenu).
