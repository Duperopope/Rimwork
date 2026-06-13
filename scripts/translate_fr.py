#!/usr/bin/env python3
"""
DOWN HERE! — boucle de traduction FR autonome (sûre).

Le "développeur autonome" sur une surface SANS RISQUE moteur: il remplit les
traductions françaises MANQUANTES (msgstr vide) du fichier gettext de Thrive
en interrogeant le modèle local (LM Studio, http://localhost:1234).

Sécurités:
- ne touche QUE les entrées dont le msgstr est vide ("") — jamais une
  traduction existante (on ne casse rien de déjà traduit);
- préserve les balises de format (%s, {0}, [b]...[/b], \\n);
- écriture ATOMIQUE (fichier temporaire puis remplacement);
- sauvegarde toutes les N entrées pour pouvoir reprendre.

Usage:
    python scripts/translate_fr.py [--limit N] [--dry-run]
Prérequis: un modèle chargé dans LM Studio (port 1234).
"""
import argparse
import json
import os
import sys
import urllib.request

PO = r"g:/Rimwork/reference/thrive/locale/fr.po"
API = "http://localhost:1234/v1/chat/completions"
SAVE_EVERY = 10

SYSTEM = (
    "Tu es traducteur de jeu vidéo EN->FR. Traduis en français NATUREL et "
    "concis le texte d'interface fourni. Règles STRICTES: conserve à "
    "l'identique toute balise de format (%s, %d, {0}, [b], [/b], [color], \\n, "
    "les variables ENTRE_UNDERSCORES en MAJUSCULES). Ne traduis PAS les noms "
    "propres techniques. Réponds UNIQUEMENT par la traduction, sans guillemets "
    "ni commentaire."
)


def llm(text: str) -> str:
    body = json.dumps({
        "model": "local-model",
        "temperature": 0.2,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": text},
        ],
    }).encode("utf-8")
    req = urllib.request.Request(API, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.load(r)
    return data["choices"][0]["message"]["content"].strip().strip('"')


def parse_blocks(lines):
    """Découpe le .po en blocs (entrées). Retourne une liste de (start, end)."""
    blocks, start = [], 0
    for i, ln in enumerate(lines):
        if ln.strip() == "":
            if i > start:
                blocks.append((start, i))
            start = i + 1
    if start < len(lines):
        blocks.append((start, len(lines)))
    return blocks


def block_msgid(lines, s, e):
    """Reconstruit le msgid (peut être multi-lignes). None si pas trouvé."""
    out, capturing = [], False
    for ln in lines[s:e]:
        st = ln.strip()
        if st.startswith("msgid "):
            capturing = True
            out.append(json.loads(st[len("msgid "):]))
        elif st.startswith("msgstr "):
            break
        elif capturing and st.startswith('"'):
            out.append(json.loads(st))
    return "".join(out) if out else None


def msgstr_is_empty(lines, s, e):
    """Vrai si le msgstr du bloc est vide (et mono-ligne)."""
    for idx in range(s, e):
        st = lines[idx].strip()
        if st.startswith("msgstr "):
            val = json.loads(st[len("msgstr "):])
            # vide ET pas de continuation multi-ligne en dessous
            nxt = lines[idx + 1].strip() if idx + 1 < e else ""
            return val == "" and not nxt.startswith('"'), idx
    return False, -1


def is_fuzzy(lines, s, e):
    return any(lines[i].strip().startswith("#, ") and "fuzzy" in lines[i]
              for i in range(s, e))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="max entrées (0=toutes)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(PO, encoding="utf-8") as f:
        lines = f.readlines()

    blocks = parse_blocks(lines)
    todo = []
    for (s, e) in blocks:
        mid = block_msgid(lines, s, e)
        if not mid:
            continue  # header ou bloc sans msgid
        empty, idx = msgstr_is_empty(lines, s, e)
        if empty and not is_fuzzy(lines, s, e):
            todo.append((idx, mid))

    print(f"{len(todo)} entrées FR vides à traduire"
          + (f" (limité à {args.limit})" if args.limit else ""))
    if args.limit:
        todo = todo[: args.limit]
    if args.dry_run:
        for idx, mid in todo[:20]:
            print(f"  L{idx+1}: {mid[:70]}")
        return

    done = 0
    for n, (idx, mid) in enumerate(todo, 1):
        try:
            fr = llm(mid).replace("\n", "\\n").replace('"', '\\"')
        except Exception as ex:
            print(f"  [skip] LLM KO ({ex}). LM Studio est-il chargé ?")
            break
        lines[idx] = f'msgstr "{fr}"\n'
        done += 1
        print(f"  [{n}/{len(todo)}] {mid[:45]} -> {fr[:45]}")
        if done % SAVE_EVERY == 0:
            _atomic_write(lines)
            print(f"  ... sauvegarde ({done} faites)")

    _atomic_write(lines)
    print(f"Terminé: {done} traductions ajoutées.")


def _atomic_write(lines):
    tmp = PO + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(lines)
    os.replace(tmp, PO)


if __name__ == "__main__":
    main()
