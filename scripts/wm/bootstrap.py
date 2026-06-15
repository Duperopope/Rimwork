"""
DOWN HERE - World Model : amorcage du dataset d'experience depuis les logs REELS.

Le systeme a deja produit :
  - training_data.jsonl : patchs GARDES (build/parse OK)        -> label 1
  - failed_builds.log   : patchs qui ont CASSE le build         -> label 0

On en extrait les blocs SEARCH/REPLACE, on calcule les features (features.py)
et on ecrit scripts/logs/experience.jsonl (1 exemple par ligne). Cela rend le
world model entrainable AUJOURD'HUI, pas "quand il y aura des donnees".

  python scripts/wm/bootstrap.py
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from features import extract_features, ext_of, FEATURE_NAMES  # noqa: E402

LOGS = os.path.join(ROOT, "scripts", "logs")
TRAIN_DATA = os.path.join(LOGS, "training_data.jsonl")
FAILED_BUILDS = os.path.join(LOGS, "failed_builds.log")
RAW = os.path.join(LOGS, "experience_raw.jsonl")  # vecu en direct par le dev_loop
OPEN = os.path.join(LOGS, "experience_open.jsonl")  # donnees OUVERTES (ingest_open.py)
OUT = os.path.join(LOGS, "experience.jsonl")

# Bloc SEARCH/REPLACE tolerant (3+ chevrons, comme dev_loop / failed_builds).
BLOCK_RE = re.compile(
    r"(?:FILE:\s*(?P<path>\S+)\s*)?<{3,}\s*SEARCH\s*\r?\n(?P<search>.*?)\r?\n={3,}\s*\r?\n(?P<replace>.*?)\r?\n>{3,}\s*REPLACE",
    re.DOTALL,
)
HEADER_FILE_RE = re.compile(r"\(([^)]*\.\w+)\)")


def from_training_data():
    rows = []
    if not os.path.exists(TRAIN_DATA):
        return rows
    for line in open(TRAIN_DATA, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        meta = obj.get("meta", {}) or {}
        default_ext = ext_of(meta.get("file", ""))
        content = ""
        for m in obj.get("messages", []):
            if m.get("role") == "assistant":
                content = m.get("content", "") or ""
        for b in BLOCK_RE.finditer(content):
            ext = ext_of(b.group("path") or "") or default_ext
            rows.append((b.group("search"), b.group("replace"), ext, 1))
    return rows


def from_failed_builds():
    rows = []
    if not os.path.exists(FAILED_BUILDS):
        return rows
    # Decoupe par enregistrement "=== [iter N] ... (file) ===".
    text = open(FAILED_BUILDS, encoding="utf-8", errors="ignore").read()
    records = re.split(r"^=== \[iter \d+\].*?===\s*$", text, flags=re.MULTILINE)
    headers = re.findall(r"^=== \[iter \d+\].*?===\s*$", text, flags=re.MULTILINE)
    for i, rec in enumerate(records[1:]):
        header = headers[i] if i < len(headers) else ""
        fm = HEADER_FILE_RE.search(header)
        ext = ext_of(fm.group(1)) if fm else ""
        for b in BLOCK_RE.finditer(rec):
            rows.append((b.group("search"), b.group("replace"), ext, 0))
    return rows


def _rows_from_jsonl(path):
    rows = []
    if not os.path.exists(path):
        return rows
    for line in open(path, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
            rows.append((o.get("search", ""), o.get("replace", ""), o.get("ext", ""), int(o.get("y", 0))))
        except Exception:
            continue
    return rows


def from_raw():
    """Experience vecue en direct par le dev_loop (Add-PatchExperience)."""
    return _rows_from_jsonl(RAW)


def from_open():
    """Donnees OUVERTES amorcees par ingest_open.py (commits reels + negatifs synth)."""
    return _rows_from_jsonl(OPEN)


def main():
    pos = from_training_data()
    neg = from_failed_builds()
    live = from_raw()
    opn = from_open()
    seen = set()
    n_written = n_pos = n_neg = 0
    with open(OUT, "w", encoding="utf-8") as f:
        for search, replace, ext, label in pos + neg + live + opn:
            key = (hash(search), hash(replace), label)
            if key in seen:
                continue
            seen.add(key)
            feats = extract_features(search, replace, ext)
            f.write(json.dumps({"x": feats, "y": label}) + "\n")
            n_written += 1
            n_pos += label == 1
            n_neg += label == 0
    print(f"experience.jsonl: {n_written} exemples ({n_pos} gardes / {n_neg} casses)")
    print(f"features ({len(FEATURE_NAMES)}): {', '.join(FEATURE_NAMES)}")
    return 0 if (n_pos > 0 and n_neg > 0) else 1


if __name__ == "__main__":
    sys.exit(main())
