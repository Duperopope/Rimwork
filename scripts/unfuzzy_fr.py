#!/usr/bin/env python3
"""
DOWN HERE! — réactive les traductions FR désactivées.

Diagnostic: 627 entrées de locale/fr.po sont marquées "#, fuzzy" (traductions
existantes mais marquées périmées car le texte source anglais a évolué).
Godot IGNORE les entrées fuzzy -> repli sur l'anglais. D'où l'anglais qui
traîne alors que la traduction existe.

Ce script retire le marqueur "fuzzy" des entrées qui ONT une traduction
non vide, afin que Godot les affiche. Le français légèrement vieilli vaut
mieux que de l'anglais; le raffinement fin reste le travail de la boucle LLM.
Écriture atomique. Ne touche pas aux entrées vides.
"""
import os

PO = r"g:/Rimwork/reference/thrive/locale/fr.po"


def main():
    with open(PO, encoding="utf-8") as f:
        lines = f.readlines()

    out = []
    reactivated = 0
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()

        # Lignes de flags gettext: "#, fuzzy" ou "#, fuzzy, c-format" etc.
        if stripped.startswith("#,") and "fuzzy" in stripped:
            # Vérifie que l'entrée a bien une traduction non vide en aval.
            has_translation = _entry_has_translation(lines, i)
            if has_translation:
                # Retire 'fuzzy' des flags; supprime la ligne si plus rien.
                flags = [p.strip() for p in stripped[2:].split(",") if p.strip() and p.strip() != "fuzzy"]
                reactivated += 1
                if flags:
                    out.append("#, " + ", ".join(flags) + "\n")
                # sinon: on saute complètement la ligne (flag vide)
                i += 1
                continue

        out.append(line)
        i += 1

    tmp = PO + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(out)
    os.replace(tmp, PO)

    print(f"Traductions FR réactivées (fuzzy retiré): {reactivated}")


def _entry_has_translation(lines, flag_index):
    """Cherche le msgstr de l'entrée suivant la ligne de flag; vrai si non vide."""
    i = flag_index + 1
    n = len(lines)
    # Avance jusqu'au msgstr.
    while i < n and not lines[i].startswith("msgstr "):
        if lines[i].strip() == "" or lines[i].startswith("#"):
            # nouvelle entrée commencée sans msgstr -> pas de trad
            if lines[i].strip() == "":
                return False
        i += 1
    if i >= n:
        return False
    # msgstr "..." sur la ligne, + continuations "..." en dessous
    first = lines[i][len("msgstr "):].strip()
    content = first.strip('"')
    j = i + 1
    while j < n and lines[j].startswith('"'):
        content += lines[j].strip().strip('"')
        j += 1
    return len(content.strip()) > 0


if __name__ == "__main__":
    main()
