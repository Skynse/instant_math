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

_FUNCTION_NAMES = set(_CAPITAL_FUNCS.values()) | {
    "acos",
    "acot",
    "acsc",
    "asec",
    "asin",
    "atan",
    "log10",
    "log2",
    "sign",
}

_MATH_TAG_RE = re.compile(r"<math[^>]*>(.*?)</math>", re.DOTALL | re.IGNORECASE)


def clean_display_latex(text: str) -> str:
    """Remove OCR transport markup while preserving LaTeX-like math text."""
    s = text.strip()
    s = _MATH_TAG_RE.sub(lambda m: m.group(1).strip(), s)
    s = re.sub(r"</?math[^>]*>", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\$+", "", s)
    return re.sub(r"\s+", " ", s).strip()


def normalize(text: str) -> str:
    """Convert raw LaTeX / surya output into a sympy-parseable string."""
    s = clean_display_latex(text)

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
    s = _group_implicit_division_denominators(s)

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


def _group_implicit_division_denominators(s: str) -> str:
    """Treat a denominator followed by implicit multiplication as one term.

    OCR often emits textbook-style expressions such as ``6 / 2(1+2)``. For this
    app we interpret that as ``6 / (2(1+2))`` while leaving explicit
    ``6 / 2 * (1+2)`` untouched.
    """
    result: list[str] = []
    i = 0
    while i < len(s):
        if s[i] != "/":
            result.append(s[i])
            i += 1
            continue

        result.append("/")
        denom, end = _parse_implicit_denominator(s, i + 1)
        if denom is None:
            i += 1
            continue

        result.append(denom)
        i = end

    return "".join(result)


def _parse_implicit_denominator(s: str, start: int) -> tuple[str | None, int]:
    leading_space_end = _skip_spaces(s, start)
    atom, end = _parse_atom(s, leading_space_end)
    if atom is None:
        return None, start

    factors = [atom]
    while True:
        next_start = _skip_spaces(s, end)
        if next_start >= len(s) or s[next_start] in "+-*/=<>;,)":
            break

        next_atom, next_end = _parse_atom(s, next_start)
        if next_atom is None:
            break
        factors.append(next_atom)
        end = next_end

    if len(factors) == 1:
        return s[start:end], end
    return f"({'*'.join(factors)})", end


def _parse_atom(s: str, start: int) -> tuple[str | None, int]:
    if start >= len(s):
        return None, start

    if s[start] == "(":
        end = _find_matching_paren(s, start)
        if end is None:
            return None, start
        return s[start : end + 1], end + 1

    number = re.match(r"\d+(?:\.\d+)?", s[start:])
    if number:
        return number.group(0), start + len(number.group(0))

    name = re.match(r"[A-Za-z_][A-Za-z0-9_]*", s[start:])
    if not name:
        return None, start

    atom = name.group(0)
    end = start + len(atom)
    next_start = _skip_spaces(s, end)
    if atom in _FUNCTION_NAMES and next_start < len(s) and s[next_start] == "(":
        paren_end = _find_matching_paren(s, next_start)
        if paren_end is not None:
            return s[start : paren_end + 1], paren_end + 1

    return atom, end


def _skip_spaces(s: str, start: int) -> int:
    while start < len(s) and s[start].isspace():
        start += 1
    return start


def _find_matching_paren(s: str, start: int) -> int | None:
    depth = 0
    for i in range(start, len(s)):
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return None
