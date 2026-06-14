"""
DOWN HERE - World Model : extraction de features d'un patch SEARCH/REPLACE.

SOURCE DE VERITE UNIQUE des features (utilisee par bootstrap, train ET predict).
Les features sont 100% deterministes a partir du texte du patch + extension du
fichier cible. Aucune dependance lourde (stdlib seulement ici).

Un "patch" = (search, replace, ext). Le world model apprend a predire si un tel
patch sera GARDE (build/parse OK) ou REVERTE (casse), a partir de l'experience
passee reelle du systeme.
"""
import re

# Ordre des features = contrat (doit rester stable entre train et predict).
# Base (13) + features DERIVEES (ingenierie auto) que la recherche de successeur
# peut selectionner ou ignorer. Pool elargi = espace de conception plus riche.
FEATURE_NAMES = [
    # --- base ---
    "s_lines", "r_lines", "line_delta", "r_chars",
    "new_calls", "brace_bal", "paren_bal", "has_method_def",
    "has_placeholder", "is_csharp", "is_json", "semicolons", "new_idents",
    # --- derivees (feature engineering) ---
    "ratio_lines", "chars_per_rline", "new_idents_per_line", "net_brace",
    "new_calls_per_line", "has_control", "has_return", "comment_lines",
]

_CALL_RE = re.compile(r"\.[A-Z]\w{3,}\s*\(")
_METHOD_RE = re.compile(r"(public|private|protected|internal)\s+[\w<>\[\],\s]+\s+\w+\s*\([^)]*\)\s*\{?")
_PLACEHOLDER_RE = re.compile(r"(?i)TODO|NotImplemented|placeholder|will be (expanded|implemented)")
_IDENT_RE = re.compile(r"[A-Za-z_]\w{2,}")
_CONTROL_RE = re.compile(r"\b(if|for|foreach|while|switch)\b")


def _nonempty_lines(text):
    return [ln for ln in text.split("\n") if ln.strip()]


def extract_features(search, replace, ext):
    """Retourne un vecteur (liste de floats) dans l'ordre FEATURE_NAMES."""
    search = search or ""
    replace = replace or ""
    ext = (ext or "").lower().lstrip(".")

    s_lines = len(_nonempty_lines(search))
    r_lines = len(_nonempty_lines(replace))
    s_idents = set(_IDENT_RE.findall(search))
    r_idents = set(_IDENT_RE.findall(replace))
    new_idents = len(r_idents - s_idents)

    r_lines_nz = max(r_lines, 1)
    new_calls = len(_CALL_RE.findall(replace))
    comment_lines = sum(1 for ln in replace.split("\n") if ln.strip().startswith(("//", "#")))
    feats = {
        "s_lines": s_lines,
        "r_lines": r_lines,
        "line_delta": r_lines - s_lines,
        "r_chars": len(replace),
        "new_calls": new_calls,
        "brace_bal": abs(replace.count("{") - replace.count("}")),
        "paren_bal": abs(replace.count("(") - replace.count(")")),
        "has_method_def": 1 if _METHOD_RE.search(replace) else 0,
        "has_placeholder": 1 if _PLACEHOLDER_RE.search(replace) else 0,
        "is_csharp": 1 if ext == "cs" else 0,
        "is_json": 1 if ext == "json" else 0,
        "semicolons": replace.count(";"),
        "new_idents": new_idents,
        # --- derivees ---
        "ratio_lines": r_lines / max(s_lines, 1),
        "chars_per_rline": len(replace) / r_lines_nz,
        "new_idents_per_line": new_idents / r_lines_nz,
        "net_brace": replace.count("{") - replace.count("}"),
        "new_calls_per_line": new_calls / r_lines_nz,
        "has_control": 1 if _CONTROL_RE.search(replace) else 0,
        "has_return": 1 if re.search(r"\breturn\b", replace) else 0,
        "comment_lines": comment_lines,
    }
    return [float(feats[n]) for n in FEATURE_NAMES]


def ext_of(path):
    m = re.search(r"\.(\w+)$", path or "")
    return m.group(1).lower() if m else ""
