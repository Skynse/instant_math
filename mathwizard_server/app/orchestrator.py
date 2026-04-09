from __future__ import annotations

import re

import sympy as sp
from sympy.parsing.sympy_parser import (
    convert_xor,
    implicit_multiplication_application,
    parse_expr,
    standard_transformations,
)

from .latex_normalizer import normalize
from .ocr_client import SuryaOcrClient  # noqa: F401 (used as type hint)
from .schemas import OcrResponse, SolvedResponse, SolutionStep

_TRANSFORMS = standard_transformations + (implicit_multiplication_application, convert_xor)

# Single-letter variable candidates in preference order
_VAR_PREFERENCE = list("xyzntkabcm")
_VAR_RE = re.compile(r"\b([a-zA-Z])\b")

# ── LaTeX pattern detectors (applied to raw OCR output) ──────────────────────

# Derivative: \frac{d^n}{dx^n} or \frac{d}{dx}
_DERIV_FRAC_RE = re.compile(
    r"\\frac\s*\{"
    r"d(?:\^(?:\{(\d+)\}|(\d+)))?"   # numerator: d or d^n or d^{n}
    r"\}\s*\{"
    r"d([a-zA-Z])(?:\^(?:\{(\d+)\}|(\d+)))?"  # denominator: dx or dx^n
    r"\}",
    re.IGNORECASE,
)

# Integral: \int or \int_a^b
_INTEGRAL_RE = re.compile(
    r"\\int"
    r"(?:_\{([^}]*)\}\^\{([^}]*)\}"   # _{lower}^{upper} brace form
    r"|_([^\s{^]+)\^([^\s{]+))?"      # _a^b no-brace form
    r"\s*(.*?)\s*(?:\\[,\s])*d([a-zA-Z])\s*$",
    re.DOTALL,
)

# Limit: \lim_{x \to a}
_LIMIT_RE = re.compile(
    r"\\lim_\{([a-zA-Z])\s*\\to\s*([^}]+)\}\s*(.+)",
    re.DOTALL,
)

# Inequality operators (in normalized string)
_INEQ_RE = re.compile(r"(>=|<=|>(?!=)|<(?!=))")


class SolveOrchestrator:
    def __init__(self, ocr_client: SuryaOcrClient) -> None:
        self._ocr = ocr_client

    # ── public API ────────────────────────────────────────────────────────────

    def ocr_image(self, image_bytes: bytes) -> OcrResponse:
        text = self._ocr.extract_text(image_bytes)
        return OcrResponse(latex=text, problem_text=text)

    def solve_from_image(self, image_bytes: bytes) -> SolvedResponse:
        raw = self._ocr.extract_text(image_bytes)
        if not raw:
            return _error("Could not extract text from image", "ocr_failed")
        return self.solve_from_text(raw)

    def solve_from_text(self, text: str) -> SolvedResponse:
        try:
            return _dispatch(text)
        except Exception as exc:
            return _error(str(exc), "solver_error", latex=text)


# ── solver dispatch ───────────────────────────────────────────────────────────

def _dispatch(original: str) -> SolvedResponse:
    """Route to the appropriate solver based on detected operation type."""
    # Calculus operations detected from raw LaTeX before normalization
    if _DERIV_FRAC_RE.search(original):
        return _solve_derivative(original)

    if r"\int" in original:
        return _solve_integral(original)

    if r"\lim" in original:
        return _solve_limit(original)

    # Algebraic operations on normalized form
    normalized = normalize(original)

    if ";" in normalized:
        return _solve_system(normalized, original)

    if _INEQ_RE.search(normalized):
        return _solve_inequality(normalized, original)

    if "=" in normalized:
        return _solve_equation(normalized, original)

    return _evaluate(normalized, original)


# ── calculus solvers ──────────────────────────────────────────────────────────

def _solve_derivative(original: str) -> SolvedResponse:
    """Solve d^n/dx^n [expr] using SymPy differentiation."""
    m = _DERIV_FRAC_RE.search(original)
    if not m:
        return _error("Cannot parse derivative notation", "parse_error", original)

    # Determine order
    order_str = m.group(1) or m.group(2) or m.group(4) or m.group(5) or "1"
    order = int(order_str)
    var_char = m.group(3).lower()

    # Everything after the operator is the expression
    expr_raw = original[m.end():].strip()
    # Strip optional enclosing brackets/parens/braces
    expr_raw = re.sub(r"^[\[\({]", "", expr_raw)
    expr_raw = re.sub(r"[\]\)}]\s*$", "", expr_raw)
    # Also handle \left[ ... \right] wrappers
    expr_raw = re.sub(r"\\left[\[\({]", "", expr_raw)
    expr_raw = re.sub(r"\\right[\]\)}]", "", expr_raw)

    expr_norm = normalize(expr_raw)
    var = sp.Symbol(var_char)

    try:
        expr = _parse(expr_norm)
    except Exception:
        return _error(f"Cannot parse expression: {expr_norm!r}", "parse_error", original)

    result = sp.diff(expr, var, order)
    result_simplified = sp.simplify(result)
    result_latex = sp.latex(result_simplified)

    order_label = {1: "first", 2: "second", 3: "third"}.get(order, f"{order}th")
    d_notation = f"\\frac{{d{'{}^{}'.format('', order) if order > 1 else ''}}}{{d{var_char}{'{}^{}'.format('', order) if order > 1 else ''}}}"

    steps = [
        SolutionStep(
            number=1,
            title="Identify the expression",
            description=f"Find the {order_label} derivative with respect to ${var_char}$.",
            formula=f"$${d_notation}\\left[{sp.latex(expr)}\\right]$$",
        ),
        SolutionStep(
            number=2,
            title="Apply differentiation rules",
            description=_describe_diff_rules(expr, var),
            formula=f"$$\\frac{{d}}{{d{var_char}}}\\left[{sp.latex(expr)}\\right] = {sp.latex(sp.diff(expr, var))}$$",
        ),
    ]

    if order > 1:
        steps.append(SolutionStep(
            number=3,
            title=f"Differentiate again ({order_label} derivative)",
            description=f"Apply differentiation {order} times total.",
            formula=f"$$= {result_latex}$$",
        ))
    else:
        steps.append(SolutionStep(
            number=3,
            title="Simplify",
            description="Simplify the result.",
            formula=f"$$= {result_latex}$$",
        ))

    return SolvedResponse(
        success=True,
        latex=original,
        answer=str(result_simplified),
        finalAnswer=f"$${result_latex}$$",
        method="differentiation",
        problem_type=f"derivative_order_{order}",
        steps=steps,
    )


def _solve_integral(original: str) -> SolvedResponse:
    """Solve ∫ expr dx (indefinite or definite) using SymPy integration."""
    m = _INTEGRAL_RE.search(original)
    if not m:
        return _error("Cannot parse integral expression", "parse_error", original)

    lower_raw = m.group(1) or m.group(3)
    upper_raw = m.group(2) or m.group(4)
    integrand_raw = (m.group(5) or "").strip()
    var_char = m.group(6).lower()

    # If integrand is empty, maybe there's no d-var at end—try simpler parse
    if not integrand_raw:
        # Strip \int and any bounds, normalize the rest
        body = re.sub(r"\\int(?:_[^\\s]+\^[^\\s]+)?", "", original).strip()
        integrand_raw = body

    integrand_norm = normalize(integrand_raw)
    var = sp.Symbol(var_char)

    try:
        integrand = _parse(integrand_norm)
    except Exception:
        return _error(f"Cannot parse integrand: {integrand_norm!r}", "parse_error", original)

    is_definite = bool(lower_raw and upper_raw)

    if is_definite:
        a = _safe_parse_bound(lower_raw)
        b = _safe_parse_bound(upper_raw)
        if a is None or b is None:
            return _error("Cannot parse integration bounds", "parse_error", original)

        result = sp.integrate(integrand, (var, a, b))
        result_simplified = sp.simplify(result)
        result_latex = sp.latex(result_simplified)
        bounds_latex = f"_{{{sp.latex(a)}}}^{{{sp.latex(b)}}}"

        steps = [
            SolutionStep(
                number=1,
                title="Set up the definite integral",
                description=f"Integrate with respect to ${var_char}$ from ${sp.latex(a)}$ to ${sp.latex(b)}$.",
                formula=f"$$\\int{bounds_latex} {sp.latex(integrand)}\\, d{var_char}$$",
            ),
            SolutionStep(
                number=2,
                title="Find the antiderivative",
                description="Compute the indefinite integral first.",
                formula=f"$$F({var_char}) = {sp.latex(sp.integrate(integrand, var))} + C$$",
            ),
            SolutionStep(
                number=3,
                title="Apply the Fundamental Theorem of Calculus",
                description=f"Evaluate $F({sp.latex(b)}) - F({sp.latex(a)})$.",
                formula=f"$$= {result_latex}$$",
            ),
        ]

        return SolvedResponse(
            success=True,
            latex=original,
            answer=str(result_simplified),
            finalAnswer=f"$${result_latex}$$",
            method="definite_integration",
            problem_type="definite_integral",
            steps=steps,
        )
    else:
        antideriv = sp.integrate(integrand, var)
        antideriv_simplified = sp.simplify(antideriv)
        antideriv_latex = sp.latex(antideriv_simplified)

        steps = [
            SolutionStep(
                number=1,
                title="Identify the integral",
                description=f"Find the antiderivative of ${sp.latex(integrand)}$ with respect to ${var_char}$.",
                formula=f"$$\\int {sp.latex(integrand)}\\, d{var_char}$$",
            ),
            SolutionStep(
                number=2,
                title="Apply integration rules",
                description=_describe_int_rules(integrand, var),
                formula=f"$$= {antideriv_latex} + C$$",
            ),
        ]

        return SolvedResponse(
            success=True,
            latex=original,
            answer=f"{antideriv_simplified} + C",
            finalAnswer=f"$${antideriv_latex} + C$$",
            method="integration",
            problem_type="indefinite_integral",
            steps=steps,
        )


def _solve_limit(original: str) -> SolvedResponse:
    """Solve lim_{x→a} expr using SymPy."""
    m = _LIMIT_RE.search(original)
    if not m:
        return _error("Cannot parse limit expression", "parse_error", original)

    var_char = m.group(1)
    point_raw = m.group(2).strip()
    expr_raw = m.group(3).strip()

    var = sp.Symbol(var_char)

    # Normalize the approach point
    point_norm = normalize(point_raw)
    if "oo" in point_norm or "infty" in point_raw.lower():
        point = sp.oo
    elif "-oo" in point_norm or "-infty" in point_raw.lower():
        point = -sp.oo
    else:
        try:
            point = _parse(point_norm)
        except Exception:
            return _error(f"Cannot parse limit point: {point_norm!r}", "parse_error", original)

    expr_norm = normalize(expr_raw)
    try:
        expr = _parse(expr_norm)
    except Exception:
        return _error(f"Cannot parse expression: {expr_norm!r}", "parse_error", original)

    result = sp.limit(expr, var, point)
    result_simplified = sp.simplify(result)
    result_latex = sp.latex(result_simplified)
    point_latex = "\\infty" if point == sp.oo else ("-\\infty" if point == -sp.oo else sp.latex(point))

    # Check if indeterminate form
    direct_sub = None
    try:
        direct_sub = expr.subs(var, point)
    except Exception:
        pass

    steps = [
        SolutionStep(
            number=1,
            title="Identify the limit",
            description=f"Evaluate $\\lim_{{{var_char} \\to {point_latex}}} {sp.latex(expr)}$.",
            formula=f"$$\\lim_{{{var_char} \\to {point_latex}}} {sp.latex(expr)}$$",
        ),
    ]

    if direct_sub is not None and not sp.zoo == direct_sub and not sp.nan == direct_sub:
        try:
            if direct_sub.is_finite:
                steps.append(SolutionStep(
                    number=2,
                    title="Direct substitution",
                    description=f"Substitute ${var_char} = {point_latex}$ directly.",
                    formula=f"$$= {result_latex}$$",
                ))
            else:
                steps.append(SolutionStep(
                    number=2,
                    title="Indeterminate form — apply L'Hôpital or algebraic manipulation",
                    description="Direct substitution gives an indeterminate form. Apply limit techniques.",
                    formula=f"$$\\lim_{{{var_char} \\to {point_latex}}} {sp.latex(expr)} = {result_latex}$$",
                ))
        except Exception:
            steps.append(SolutionStep(
                number=2,
                title="Evaluate limit",
                description="Apply limit evaluation techniques.",
                formula=f"$$= {result_latex}$$",
            ))
    else:
        steps.append(SolutionStep(
            number=2,
            title="Evaluate the limit",
            description="Apply limit laws and simplification.",
            formula=f"$$= {result_latex}$$",
        ))

    return SolvedResponse(
        success=True,
        latex=original,
        answer=str(result_simplified),
        finalAnswer=f"$${result_latex}$$",
        method="limit_evaluation",
        problem_type="limit",
        steps=steps,
    )


# ── algebraic solvers ─────────────────────────────────────────────────────────

def _solve_equation(expr: str, original: str) -> SolvedResponse:
    lhs_str, rhs_str = expr.split("=", 1)
    lhs = _parse(lhs_str)
    rhs = _parse(rhs_str)
    equation = sp.Eq(lhs, rhs)

    var = _pick_variable(expr)
    symbol = sp.Symbol(var)
    solutions = sp.solve(equation, symbol)

    if not solutions:
        # Try solveset for more exotic equations
        sol_set = sp.solveset(equation, symbol, domain=sp.S.Reals)
        if sol_set.is_empty:
            return _error(f"No real solutions found for {var}", "no_solution", latex=original)
        # Convert finite set to list
        try:
            solutions = list(sol_set)
        except Exception:
            return _error(f"Solution set is not enumerable: {sol_set}", "no_solution", latex=original)

    sol_exprs = [sp.simplify(s) for s in solutions]
    answer_parts = [f"{var} = {sp.latex(s)}" for s in sol_exprs]
    final_answer = " \\ \\text{or} \\ ".join(answer_parts)

    eq_type = _classify_equation(lhs, rhs, symbol)
    method_map = {
        "linear": "linear algebra",
        "quadratic": "quadratic formula / factoring",
        "polynomial": "polynomial root finding",
        "equation": "symbolic solving",
    }
    method = method_map.get(eq_type, "symbolic solving")

    steps = [
        SolutionStep(
            number=1,
            title="Identify the equation",
            description=f"Solve for ${var}$ in a {eq_type} equation.",
            formula=f"$${sp.latex(equation)}$$",
        ),
        SolutionStep(
            number=2,
            title="Rearrange",
            description="Bring all terms to one side.",
            formula=f"$${sp.latex(lhs - rhs)} = 0$$",
        ),
    ]

    if eq_type == "quadratic":
        a_coeff = sp.Poly(lhs - rhs, symbol).nth(2)
        b_coeff = sp.Poly(lhs - rhs, symbol).nth(1)
        c_coeff = sp.Poly(lhs - rhs, symbol).nth(0)
        discriminant = b_coeff**2 - 4 * a_coeff * c_coeff
        steps.append(SolutionStep(
            number=3,
            title="Compute the discriminant",
            description=f"$\\Delta = b^2 - 4ac = {sp.latex(discriminant)}$",
            formula=f"$$\\Delta = {sp.latex(sp.simplify(discriminant))}$$",
        ))
        steps.append(SolutionStep(
            number=4,
            title="Apply the quadratic formula",
            description=f"$x = \\frac{{-b \\pm \\sqrt{{\\Delta}}}}{{2a}}$",
            formula=f"$${final_answer}$$",
        ))
    elif eq_type == "linear":
        steps.append(SolutionStep(
            number=3,
            title="Isolate the variable",
            description=f"Use algebraic operations to solve for ${var}$.",
            formula=f"$${final_answer}$$",
        ))
    else:
        steps.append(SolutionStep(
            number=3,
            title="Solve",
            description=f"Apply {method} to isolate ${var}$.",
            formula=f"$${final_answer}$$",
        ))

    return SolvedResponse(
        success=True,
        latex=original,
        answer=" or ".join(str(s) for s in sol_exprs),
        finalAnswer=f"$${final_answer}$$",
        method=method,
        problem_type=eq_type,
        steps=steps,
    )


def _solve_system(expr: str, original: str) -> SolvedResponse:
    parts = [p.strip() for p in expr.split(";") if p.strip()]
    equations = []
    all_vars: set[str] = set()

    for part in parts:
        if "=" not in part:
            continue
        l, r = part.split("=", 1)
        lhs, rhs = _parse(l), _parse(r)
        equations.append(sp.Eq(lhs, rhs))
        all_vars |= {str(s) for s in (lhs.free_symbols | rhs.free_symbols)}

    symbols = [sp.Symbol(v) for v in sorted(all_vars)]
    solution = sp.solve(equations, symbols, dict=True)

    if not solution:
        return _error("No solution found for the system", "no_solution", latex=original)

    row = solution[0]
    answer_parts = [f"{k} = {sp.latex(v)}" for k, v in row.items()]
    final_answer = ",\\ ".join(answer_parts)

    steps = [
        SolutionStep(
            number=i + 1,
            title=f"Equation {i + 1}",
            description="",
            formula=f"$${sp.latex(eq)}$$",
        )
        for i, eq in enumerate(equations)
    ] + [
        SolutionStep(
            number=len(equations) + 1,
            title="Solve simultaneously",
            description="Use substitution or elimination to find all unknowns.",
            formula=f"$${final_answer}$$",
        )
    ]

    return SolvedResponse(
        success=True,
        latex=original,
        answer=str(row),
        finalAnswer=f"$${final_answer}$$",
        method="system of equations",
        problem_type="system",
        steps=steps,
    )


def _solve_inequality(expr: str, original: str) -> SolvedResponse:
    """Solve a univariate inequality."""
    m = _INEQ_RE.search(expr)
    if not m:
        return _error("Cannot parse inequality", "parse_error", original)

    op = m.group(1)
    idx = m.start(1)
    lhs_str = expr[:idx].strip()
    rhs_str = expr[idx + len(op):].strip()

    try:
        lhs = _parse(lhs_str)
        rhs = _parse(rhs_str)
    except Exception:
        return _error("Cannot parse inequality sides", "parse_error", original)

    var = _pick_variable(expr)
    symbol = sp.Symbol(var)

    rel_map = {">=": sp.Ge, "<=": sp.Le, ">": sp.Gt, "<": sp.Lt}
    rel = rel_map[op](lhs, rhs)

    try:
        solution = sp.solve_univariate_inequality(rel, symbol, relational=False)
    except Exception as exc:
        return _error(str(exc), "solver_error", original)

    solution_latex = sp.latex(solution)

    steps = [
        SolutionStep(
            number=1,
            title="Identify the inequality",
            description=f"Solve ${sp.latex(rel)}$ for ${var}$.",
            formula=f"$${sp.latex(rel)}$$",
        ),
        SolutionStep(
            number=2,
            title="Rearrange",
            description="Move all terms involving the variable to one side.",
            formula=f"$${sp.latex(sp.simplify(lhs - rhs))} {op} 0$$",
        ),
        SolutionStep(
            number=3,
            title="Solution set",
            description=f"The solution for ${var}$ is:",
            formula=f"$${solution_latex}$$",
        ),
    ]

    return SolvedResponse(
        success=True,
        latex=original,
        answer=str(solution),
        finalAnswer=f"$${solution_latex}$$",
        method="inequality solving",
        problem_type="inequality",
        steps=steps,
    )


def _evaluate(expr: str, original: str) -> SolvedResponse:
    """Simplify/evaluate a pure expression (no equals sign)."""
    parsed = _parse(expr)
    result = sp.simplify(parsed)

    # Also try numerical if result is still symbolic
    try:
        num = complex(result)
        if num.imag == 0:
            num_str = f"{num.real:.6g}"
        else:
            num_str = f"{num.real:.6g} + {num.imag:.6g}i"
    except Exception:
        num_str = None

    result_latex = sp.latex(result)

    steps = [
        SolutionStep(
            number=1,
            title="Expression",
            description="Evaluate and simplify.",
            formula=f"$${sp.latex(parsed)}$$",
        ),
        SolutionStep(
            number=2,
            title="Simplified result",
            description="After applying simplification rules:",
            formula=f"$$= {result_latex}$$",
        ),
    ]

    if num_str:
        steps.append(SolutionStep(
            number=3,
            title="Numerical value",
            description="",
            formula=f"$$\\approx {num_str}$$",
        ))

    return SolvedResponse(
        success=True,
        latex=original,
        answer=str(result),
        finalAnswer=f"$${result_latex}$$",
        method="simplify",
        problem_type="arithmetic",
        steps=steps,
    )


# ── helpers ───────────────────────────────────────────────────────────────────

def _parse(s: str) -> sp.Expr:
    return parse_expr(s.strip(), transformations=_TRANSFORMS, evaluate=True)


def _safe_parse_bound(raw: str) -> sp.Expr | None:
    try:
        norm = normalize(raw)
        if "oo" in norm:
            return sp.oo
        return _parse(norm)
    except Exception:
        return None


def _pick_variable(expr: str) -> str:
    candidates = set(_VAR_RE.findall(expr)) - {"e", "E"}  # 'e' is Euler's number
    for v in _VAR_PREFERENCE:
        if v in candidates:
            return v
    return next(iter(candidates), "x")


def _classify_equation(lhs: sp.Expr, rhs: sp.Expr, symbol: sp.Symbol) -> str:
    diff = sp.expand(lhs - rhs)
    degree = sp.degree(diff, symbol) if diff.is_polynomial(symbol) else -1
    if degree == 1:
        return "linear"
    if degree == 2:
        return "quadratic"
    if degree > 2:
        return "polynomial"
    return "equation"


def _describe_diff_rules(expr: sp.Expr, var: sp.Symbol) -> str:
    """Produce a brief human description of which differentiation rules apply."""
    rules = []
    if isinstance(expr, sp.Add):
        rules.append("sum rule")
    if isinstance(expr, sp.Mul):
        rules.append("product rule")
    if isinstance(expr, sp.Pow):
        if expr.args[1].free_symbols:
            rules.append("exponential differentiation")
        else:
            rules.append("power rule")
    if any(isinstance(a, (sp.sin, sp.cos, sp.tan, sp.exp, sp.log)) for a in expr.atoms(sp.Function)):
        rules.append("chain rule")
    if not rules:
        rules.append("standard differentiation rules")
    return "Apply " + ", ".join(rules) + "."


def _describe_int_rules(expr: sp.Expr, var: sp.Symbol) -> str:
    """Produce a brief human description of which integration rules apply."""
    rules = []
    if isinstance(expr, sp.Add):
        rules.append("sum rule")
    if isinstance(expr, sp.Pow):
        rules.append("power rule")
    if any(isinstance(a, (sp.sin, sp.cos, sp.exp)) for a in expr.atoms(sp.Function)):
        rules.append("standard integral formulas")
    if not rules:
        rules.append("standard integration rules")
    return "Apply " + ", ".join(rules) + "."


def _error(msg: str, method: str, latex: str = "") -> SolvedResponse:
    return SolvedResponse(
        success=False,
        latex=latex,
        answer="",
        finalAnswer="",
        method=method,
        problem_type="unknown",
        steps=[],
        error=msg,
    )
