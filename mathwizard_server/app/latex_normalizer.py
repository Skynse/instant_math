from __future__ import annotations

import re

# LaTeX command → sympy-parseable token
_COMMANDS: list[tuple[str, str]] = [
    # Inverse trig
    (r"\arcsin", "asin"),
    (r"\arccos", "acos"),
    (r"\arctan", "atan"),
    (r"\arccot", "acot"),
    (r"\arcsec", "asec"),
    (r"\arccsc", "acsc"),
    # Trig
    (r"\sin", "sin"),
    (r"\cos", "cos"),
    (r"\tan", "tan"),
    (r"\cot", "cot"),
    (r"\sec", "sec"),
    (r"\csc", "csc"),
    # Hyperbolic
    (r"\sinh", "sinh"),
    (r"\cosh", "cosh"),
    (r"\tanh", "tanh"),
    (r"\coth", "coth"),
    # Logarithms
    (r"\ln", "log"),
    (r"\log_{10}", "log10"),
    (r"\log_{2}", "log2"),
    (r"\log", "log10"),
    (r"\exp", "exp"),
    # Misc math
    (r"\abs", "Abs"),
    (r"\operatorname{sgn}", "sign"),
    (r"\operatorname{abs}", "Abs"),
    # Operators
    (r"\cdot", "*"),
    (r"\times", "*"),
    (r"\div", "/"),
    (r"\pm", "+"),   # lossy but parses; caller can note ambiguity
    # Constants
    (r"\pi", "pi"),
    (r"\infty", "oo"),
    (r"\e", "E"),
    # Relations (kept for inequality parsing)
    (r"\approx", "="),
    (r"\neq", "!="),
    (r"\geq", ">="),
    (r"\leq", "<="),
    (r"\gt", ">"),
    (r"\lt", "<"),
    (r"\ge", ">="),
    (r"\le", "<="),
]

# Surya sometimes capitalises function names
_CAPITAL_FUNCS: dict[str, str] = {
    "Sin": "sin",
    "Cos": "cos",
    "Tan": "tan",
    "Cot": "cot",
    "Sec": "sec",
    "Csc": "csc",
    "Sinh": "sinh",
    "Cosh": "cosh",
    "Tanh": "tanh",
    "Arcsin": "asin",
    "Arccos": "acos",
    "Arctan": "atan",
    "Sqrt": "sqrt",
    "Log": "log",
    "Ln": "log",
    "Exp": "exp",
    "Abs": "Abs",
}

_MATH_TAG_RE = re.compile(r"<math[^>]*>(.*?)</math>", re.DOTALL | re.IGNORECASE)


def normalize(text: str) -> str:
    """Convert raw LaTeX / surya output into a sympy-parseable string."""
    s = text.strip()

    # Strip <math> tags (surya math_mode output)
    m = _MATH_TAG_RE.search(s)
    if m:
        s = m.group(1).strip()

    # Strip $$ / $ math delimiters
    s = re.sub(r"\$+", "", s).strip()

    # ≈ → =
    s = s.replace(r"\approx", "=").replace("≈", "=")

    # Remove \left \right \big etc. (size hints that add no semantics)
    s = re.sub(r"\\(?:left|right|[Bb]ig[gG]?)\s*", "", s)

    # Remove LaTeX spacing commands (\, \; \! \quad \qquad)
    s = re.sub(r"\\(?:quad|qquad|,|;|!)\s*", " ", s)
    s = re.sub(r"\\[,;!\s]", " ", s)

    # |expr| → Abs(expr) — simple single-level bars only
    s = _expand_abs(s)

    # Expand \frac{num}{den} → (num)/(den)
    s = _expand_frac(s)

    # Expand \sqrt[n]{x} → (x)^(1/n),  \sqrt{x} → sqrt(x)
    s = _expand_sqrt(s)

    # ^{...} → ^(...)
    s = re.sub(r"\^\{([^{}]*)\}", r"^(\1)", s)

    # Replace LaTeX commands (longest-match first via list ordering)
    for cmd, repl in _COMMANDS:
        s = s.replace(cmd, repl)

    # Normalise capitalised function names from surya
    for cap, lower in _CAPITAL_FUNCS.items():
        s = re.sub(rf"\b{cap}\b", lower, s)

    # Remaining braces → parens
    s = s.replace("{", "(").replace("}", ")")

    return re.sub(r"\s+", " ", s).strip()


# ── internal helpers ──────────────────────────────────────────────────────────

def _extract_braces(s: str, start: int) -> tuple[str, int]:
    """Return (content, end_index) for the {…} group starting at `start`."""
    while start < len(s) and s[start] == " ":
        start += 1
    if start >= len(s) or s[start] != "{":
        # No braces: grab a single character as the argument
        if start < len(s):
            return s[start], start + 1
        return "", start
    depth = 0
    buf: list[str] = []
    i = start
    while i < len(s):
        c = s[i]
        i += 1
        if c == "{":
            depth += 1
            if depth > 1:
                buf.append(c)
        elif c == "}":
            depth -= 1
            if depth == 0:
                return "".join(buf), i
            buf.append(c)
        else:
            buf.append(c)
    return "".join(buf), i


def _expand_frac(s: str) -> str:
    while True:
        m = re.search(r"\\frac\s*", s)
        if not m:
            break
        i = m.end()
        num, i = _extract_braces(s, i)
        den, i = _extract_braces(s, i)
        s = s[: m.start()] + f"({_expand_frac(num)})/({_expand_frac(den)})" + s[i:]
    return s


def _expand_sqrt(s: str) -> str:
    while True:
        m = re.search(r"\\sqrt\s*", s)
        if not m:
            break
        i = m.end()
        nth: str | None = None
        if i < len(s) and s[i] == "[":
            close = s.find("]", i)
            if close != -1:
                nth = s[i + 1 : close].strip()
                i = close + 1
        content, i = _extract_braces(s, i)
        inner = _expand_sqrt(content)
        replacement = f"({inner})^(1/{nth})" if (nth and nth != "2") else f"sqrt({inner})"
        s = s[: m.start()] + replacement + s[i:]
    return s


def _expand_abs(s: str) -> str:
    """Replace |expr| with Abs(expr) for simple (non-nested) cases."""
    result = []
    i = 0
    while i < len(s):
        if s[i] == "|":
            # Find matching closing bar at same depth
            close = s.find("|", i + 1)
            if close != -1:
                inner = s[i + 1 : close]
                result.append(f"Abs({inner})")
                i = close + 1
            else:
                result.append(s[i])
                i += 1
        else:
            result.append(s[i])
            i += 1
    return "".join(result)
