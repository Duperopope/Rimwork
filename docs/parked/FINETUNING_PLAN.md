# Junior Godot — plan de fine-tuning (QLoRA / ROCm)

Objectif: spécialiser le LLM local pour qu'il code des jeux Godot/C# de
mieux en mieux, entraîné comme un dev junior sur les patchs réels du projet.
Vision world-model (LeCun) en toile de fond — voir mémoire [[world-model-jepa]].

## Réalité honnête (à ne pas survendre)
- **85 exemples curés** aujourd'hui = un SEED, PAS assez pour un fine-tune
  fort. Cible: 300-1000+ exemples de qualité avant un QLoRA sérieux.
- Le dataset GROSSIT tout seul: chaque patch accepté (sur Thrive) = un
  exemple. C'est le data flywheel — le junior apprend sur le tas.
- **D'ici là: few-shot/RAG** (injecter des exemples du dataset à chaque
  appel) donne 80% du bénéfice SANS entraînement. À faire en premier.

## Matériel
- AMD Radeon RX 7800 XT, 16 Go VRAM → QLoRA d'un modèle 7-9B OK.
- **ROCm tourne bien mieux sous Linux** → ce track se fait sur le Linux
  dev (voir [[dual-boot-linux-decision]]), pas sous Windows.

## Pile recommandée (Linux + ROCm)
1. **ROCm 6.x** + PyTorch ROCm (`pip install torch --index-url
   https://download.pytorch.org/whl/rocm6.x`).
2. **QLoRA** via `peft` + `bitsandbytes` (support ROCm) ou **Unsloth**
   (plus rapide; vérifier le support ROCm courant, sinon peft direct).
3. Base: modèle code 7B (Qwen2.5-Coder-7B ou Yi-Coder-9B, déjà champion).
4. Format dataset: chat/ShareGPT (déjà produit: datasets/godot_sft.jsonl),
   3 messages (system spécialisé Godot, user=contexte+tâche, assistant=patch).
5. Hyperparams de départ (QLoRA): r=16, alpha=32, lr=2e-4, 3 epochs,
   4-bit nf4, gradient checkpointing, seq len 2048-4096.

## Étapes
1. [fait] Curer le seed → datasets/godot_sft.jsonl (scripts/curate_dataset.py).
2. [en cours] Faire grossir le dataset: re-pointer la collecte du dev loop
   sur les patchs Thrive acceptés (chaque KEPT → exemple).
3. Few-shot/RAG maintenant: au moment d'appeler le modèle, injecter 2-3
   exemples proches du dataset (retrieval simple par fichier/tâche).
4. Quand ≥300 exemples propres: premier QLoRA sur Linux/ROCm.
5. Évaluer: tenir un set de tâches Godot de test, mesurer build-OK rate
   avant/après (comme l'arène de modèles existante).
6. Itérer: ré-entraîner périodiquement avec le dataset grossi.

## Variante world-model (plus tard, optionnel)
Enrichir chaque exemple avec la PRÉDICTION du modèle (résultat attendu du
patch) vs le RÉEL (build/test/sim). Dataset = (état, action, prédiction,
réel). Permet d'entraîner un prédicteur de conséquences — direction JEPA
sans l'architecture expérimentale. Honnêteté: recherche, pas court terme.

## Garde-fous
- Le fine-tune ne remplace PAS la supervision: le junior reste cadré
  (surfaces sûres: data-driven, traduction; pas le C# moteur de Thrive).
- Mesurer avant/après sur des tâches réelles, sinon on entraîne du bruit.
