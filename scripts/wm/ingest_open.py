"""
DOWN HERE - World Model : ingestion de DONNEES OUVERTES reelles pour amorcer le
predicteur de patch (au-dela de notre seule experience, encore rare).

SOURCE (concrete, sourcee, libre) :
  bigcode/commitpackft  (sous-ensemble filtre de CommitPack)
  https://huggingface.co/datasets/bigcode/commitpackft
  ~ 39 777 commits pour le seul config "json", des dizaines de langages.
  On lit via l'API datasets-server de HuggingFace (HTTP, PAS de telechargement
  du dataset entier) :  https://datasets-server.huggingface.co/rows
  Chaque ligne = un commit REEL accepte : old_contents -> new_contents (+ license,
  + repo). Un commit accepte = un patch qui a tenu => exemple POSITIF (y=1).

NEGATIFS (honnete) : on ne dispose pas a grande echelle de patchs REJETES open
source ; on SYNTHETISE donc des negatifs en corrompant un positif selon les VRAIS
modes d'echec qu'on observe (accolade desequilibree, placeholder, troncature).
Ils sont marques src="synthetic:<mode>" pour la transparence. Les negatifs REELS
(builds casses, SEARCH sans match, JSON invalide) continuent d'arriver en direct
via le dev_loop et priment a terme.

Sortie : scripts/logs/experience_open.jsonl  (schema lu par bootstrap.py:from_open)
  {"search","replace","ext","y","src","license"}

Usage :
  python scripts/wm/ingest_open.py                 # defaut : 120 / config
  python scripts/wm/ingest_open.py --per 300       # plus de donnees
  python scripts/wm/ingest_open.py --configs json,python,javascript
"""
import argparse
import difflib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LOGS = os.path.join(ROOT, "scripts", "logs")
OUT = os.path.join(LOGS, "experience_open.jsonl")

DATASET = "bigcode/commitpackft"
API = "https://datasets-server.huggingface.co/rows"
# config commitpackft -> extension de fichier (pour nos features is_csharp/is_json...)
EXT = {"json": "json", "python": "py", "javascript": "js", "java": "java",
       "c-sharp": "cs", "csharp": "cs", "typescript": "ts", "go": "go"}
# Licences permissives uniquement (rigueur juridique : on ne garde que du reutilisable).
OK_LICENSES = {"mit", "apache-2.0", "bsd-3-clause", "bsd-2-clause", "isc", "unlicense", "cc0-1.0"}
MAX_SEARCH_LINES = 40      # on veut des patchs MINIMAUX, comme notre dev_loop
MAX_CHARS = 3000


def fetch(config, offset, length):
    q = urllib.parse.urlencode({"dataset": DATASET, "config": config,
                                "split": "train", "offset": offset, "length": length})
    req = urllib.request.Request(API + "?" + q, headers={"User-Agent": "downhere-wm/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def minimal_patch(old, new):
    """Extrait le plus petit bloc change (search<-old, replace<-new) + 1 ligne de
    contexte, pour ressembler a un vrai SEARCH/REPLACE contigu."""
    a, b = old.splitlines(), new.splitlines()
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    changed = [op for op in sm.get_opcodes() if op[0] != "equal"]
    if not changed:
        return None
    i1 = max(0, min(op[1] for op in changed) - 1)
    i2 = min(len(a), max(op[2] for op in changed) + 1)
    j1 = max(0, min(op[3] for op in changed) - 1)
    j2 = min(len(b), max(op[4] for op in changed) + 1)
    search = "\n".join(a[i1:i2]).strip("\n")
    replace = "\n".join(b[j1:j2]).strip("\n")
    if not search or not replace or search == replace:
        return None
    if len(a[i1:i2]) > MAX_SEARCH_LINES or len(search) > MAX_CHARS or len(replace) > MAX_CHARS:
        return None
    return search, replace


def corrupt(replace, mode):
    """Negatif synthetique selon un VRAI mode d'echec observe."""
    if mode == "brace":
        for ch in "}])":
            idx = replace.rfind(ch)
            if idx != -1:
                return replace[:idx] + replace[idx + 1:]
        return None
    if mode == "placeholder":
        return replace + "\n    // TODO: implement the rest ..."
    if mode == "truncate" and len(replace) > 24:
        return replace[: len(replace) // 2]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per", type=int, default=120, help="positifs vises par config")
    ap.add_argument("--configs", default="json,python,javascript")
    args = ap.parse_args()
    os.makedirs(LOGS, exist_ok=True)

    n_pos = n_neg = n_seen = 0
    lic_counts = {}
    modes = ["brace", "placeholder", "truncate"]
    mi = 0
    with open(OUT, "w", encoding="utf-8") as f:
        for config in [c.strip() for c in args.configs.split(",") if c.strip()]:
            ext = EXT.get(config, "")
            got = 0
            offset = 0
            while got < args.per:
                try:
                    data = fetch(config, offset, min(100, args.per - got + 20))
                except Exception as e:
                    print(f"[{config}] fetch offset={offset} ERREUR: {e}", file=sys.stderr)
                    break
                rows = data.get("rows", [])
                if not rows:
                    break
                offset += len(rows)
                for item in rows:
                    n_seen += 1
                    row = item.get("row", {})
                    lic = (row.get("license") or "").lower()
                    if OK_LICENSES and lic not in OK_LICENSES:
                        continue
                    mp = minimal_patch(row.get("old_contents", "") or "", row.get("new_contents", "") or "")
                    if not mp:
                        continue
                    search, replace = mp
                    f.write(json.dumps({"search": search, "replace": replace, "ext": ext,
                                        "y": 1, "src": f"commitpackft:{config}", "license": lic}) + "\n")
                    n_pos += 1
                    got += 1
                    lic_counts[lic] = lic_counts.get(lic, 0) + 1
                    # ~1 negatif synthetique tous les 2 positifs -> classes equilibrees
                    if got % 2 == 0:
                        for _ in range(len(modes)):
                            cm = modes[mi % len(modes)]
                            mi += 1
                            bad = corrupt(replace, cm)
                            if bad and bad != replace:
                                f.write(json.dumps({"search": search, "replace": bad, "ext": ext,
                                                    "y": 0, "src": f"synthetic:{cm}", "license": lic}) + "\n")
                                n_neg += 1
                                break
                    if got >= args.per:
                        break
                time.sleep(0.2)  # politesse envers l'API
            print(f"[{config}] {got} positifs")
    print(f"\nexperience_open.jsonl : {n_pos} positifs (commits reels) / {n_neg} negatifs (synthetiques)")
    print(f"vus: {n_seen} lignes  |  licences: " + ", ".join(f"{k}={v}" for k, v in sorted(lic_counts.items())))
    print(f"source: {DATASET} via datasets-server  ->  {OUT}")
    return 0 if n_pos > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
