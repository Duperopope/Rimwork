#!/usr/bin/env python3
"""
DOWN HERE! — curation du dataset de fine-tuning "junior Godot".

Prend les patchs accumulés par le dev loop (scripts/logs/training_data.jsonl,
format {meta, messages}) et produit un dataset d'instruction-tuning PROPRE,
prêt pour QLoRA (format ShareGPT/chat).

Filtres qualité:
- ne garde que les exemples où le contexte indique BUILD: OK;
- déduplique (même fichier + même patch);
- injecte un system prompt de spécialisation Godot/C#;
- rejette les patchs vides ou tronqués.

Sortie: datasets/godot_sft.jsonl (une conversation par ligne).
Honnêteté: ~85 exemples = un SEED, pas assez pour un fine-tune fort. Le
dataset grossit avec chaque patch accepté sur Thrive (data flywheel).
"""
import json
import os
import hashlib

SRC = r"g:/Rimwork/scripts/logs/training_data.jsonl"
OUT_DIR = r"g:/Rimwork/datasets"
OUT = os.path.join(OUT_DIR, "godot_sft.jsonl")

SYSTEM = (
    "Tu es un développeur de jeux vidéo expert sur le moteur Godot (4.x) en "
    "C#. On te donne le contexte d'un projet (résultat de build, tests, état "
    "de simulation) et une tâche. Tu réponds par un patch chirurgical au "
    "format SEARCH/REPLACE qui compile du premier coup, sans stub ni "
    "placeholder, en respectant le style du code existant."
)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    seen = set()
    kept, rejected = [], 0

    with open(SRC, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                d = json.loads(ln)
            except json.JSONDecodeError:
                rejected += 1
                continue

            msgs = d.get("messages", [])
            user = next((m["content"] for m in msgs if m["role"] == "user"), "")
            asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "")

            # Qualité: build OK, patch non vide et structuré
            if "BUILD: OK" not in user:
                rejected += 1
                continue
            if "SEARCH" not in asst or "REPLACE" not in asst or len(asst) < 40:
                rejected += 1
                continue

            sig = hashlib.sha1((d["meta"].get("file", "") + asst).encode()).hexdigest()
            if sig in seen:
                rejected += 1
                continue
            seen.add(sig)

            kept.append({
                "messages": [
                    {"role": "system", "content": SYSTEM},
                    {"role": "user", "content": user.strip()},
                    {"role": "assistant", "content": asst.strip()},
                ],
                "meta": d.get("meta", {}),
            })

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        for ex in kept:
            f.write(json.dumps(ex, ensure_ascii=False) + "\n")

    print(f"Dataset curé: {len(kept)} exemples gardés, {rejected} rejetés")
    print(f"-> {OUT}")
    if len(kept) < 200:
        print(f"\n[!] {len(kept)} exemples = SEED seulement. Vise 300-1000+ "
              "exemples (via les patchs Thrive) avant un QLoRA sérieux.")


if __name__ == "__main__":
    main()
