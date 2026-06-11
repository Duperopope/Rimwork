# GAMEJAM PLAYABLE CHECKLIST (manual jury verification)

## Démarrage
Lancer: `godot --path src/RimWorldGodot` (exe complet WinGet si le shim échoue:
`...\WinGet\Packages\GodotEngine...\Godot_v4.6.3-stable_mono_win64.exe`).
- [ ] Le menu RIMWORK apparaît
- [ ] « Nouvelle partie » → scène 3D + bannière « Colonie fondée » + log `[FLOW] New Game`
- [ ] « Nouvelle partie » en cours de partie → reset propre (rechargement scène)
- [ ] « Continuer » désactivé avec infobulle honnête
- [ ] Options s'ouvrent/ferment, valeurs persistées après redémarrage
- [ ] Échap: jeu→menu, sous-menus→retour

## Contrôles
ZQSD/flèches = caméra · molette = zoom · clic = sélection (anneau doré) ·
clic-milieu = pan · **Tab ou M = vue Planète/Local** · Échap = menu ·
1x/3x/pause dans le HUD.

## Jouabilité (vérifié par simulation 10 000 ticks = 10 jours)
- [x] 8/8 pawns vivants au jour 10 (aucune famine: 24 nourriture de départ + baies + four)
- [x] 45 murs construits, 11 meubles, files de tâches actives
- [x] 2 pièces fonctionnelles au jour 10 (Bedroom + DiningRoom), 3/3 ~jour 12-14
- [x] Murs orientés par voisinage (RenderOrientation, testé unitairement)
- [x] Pas de deadlock (bois remonte à 30 après épuisement, repousse active)

## Vue monde (Tab/M)
- [ ] Plateau 5×5 régions colorées par biome, marqueur COLONIE
- [ ] 3 sites extérieurs étiquetés (rouge=hostile, bleu=neutre/ami)
- [ ] Étoile Kerel + 3 corps célestes
- [ ] Couche affichée dans l'horloge HUD `[Local]/[Planet]` + dev tab

## Dev tab (preuve jury)
- [ ] Section 3: état Menu/En jeu, couche active, blessés/affamés/assoiffés
- [ ] Sections 5-6: LOD timestamps, pressions macro, sites
