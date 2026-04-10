from __future__ import annotations

import re
from typing import Optional

import sympy as sp
from sympy.parsing.sympy_parser import (
    convert_xor,
    implicit_multiplication_application,
    parse_expr,
    standard_transformations,
)

from .latex_normalizer import normalize
from .ocr_client import SuryaOcrClient  # noqa: F401
from .schemas import OcrResponse, SolvedResponse, SolutionStep

_TRANSFORMS = standard_transformations + (implicit_multiplication_application, convert_xor)

# Force 'e' to Euler's number so e^x isn't parsed as Symbol('e')^x
_LOCAL_DICT = {"e": sp.E, "pi": sp.pi, "oo": sp.oo}

_VAR_PREFERENCE = list("xyzntkabcm")
_VAR_RE = re.compile(r"\b([a-zA-Z])\b")

# ── LaTeX pattern detectors ───────────────────────────────────────────────────

_DERIV_FRAC_RE = re.compile(
    r"\\frac\s*\{"
    r"d(?:\^(?:\{(\d+)\}|(\d+)))?"
    r"\}\s*\{"
    r"d([a-zA-Z])(?:\^(?:\{(\d+)\}|(\d+)))?"
    r"\}",
    re.IGNORECASE,
)

_INTEGRAL_RE = re.compile(
    r"\\int"
    # bounds: optional, each bound is either _{...} or _token (any combo of braced/unbraced)
    r"(?:"
        r"(?:_\{([^}]*)\}|_([^\s{^]*))"   # lower: groups 1 (braced) or 2 (bare)
        r"\s*"
        r"(?:\^\{([^}]*)\}|\^([^\s{]*))"  # upper: groups 3 (braced) or 4 (bare)
    r")?"
    r"\s*(.*?)\s*(?:\\[,\s])*d([a-zA-Z])\s*$",
    re.DOTALL,
)

_LIMIT_RE = re.compile(
    r"\\lim_\{([a-zA-Z])\s*\\to\s*([^}]+)\}\s*(.+)",
    re.DOTALL,
)

_INEQ_RE = re.compile(r"(>=|<=|>(?!=)|<(?!=))")

# Transcendental function atoms
_TRANSCENDENTAL_FUNCS = (
    sp.sin, sp.cos, sp.tan, sp.cot, sp.sec, sp.csc,
    sp.sinh, sp.cosh, sp.tanh, sp.coth,
    sp.exp, sp.log, sp.asin, sp.acos, sp.atan,
)


class SolveOrchestrator:
    def __init__(self, ocr_client: SuryaOcrClient) -> None:
        self._ocr = ocr_client

    def ocr_image(self, image_bytes: bytes) -> OcrResponse:
        text = self._ocr.extract_text(image_bytes)
        return OcrResponse(latex=text, problem_text=text)

    def solve_from_image(self, image_bytes: bytes) -> SolvedResponse:
        raw = self._ocr.extract_text(image_bytes)
        if not raw:
            return _error("Could not extract text from image", "ocr_failed")
        return self.solve_from_text(raw)

    def solve_from_text(self, text: str, mode: str = "auto") -> SolvedResponse:
        try:
            return _dispatch(text, mode=mode)
        except Exception as exc:
            return _error(str(exc), "solver_error", latex=text)


# ── dispatch ──────────────────────────────────────────────────────────────────

def _dispatch(original: str, mode: str = "auto") -> SolvedResponse:
    # Explicit mode overrides auto-detection
    if mode == "expand":
        return _expand(original)
    if mode == "factor":
        return _factor(original)
    if mode == "simplify":
        normalized = normalize(original)
        return _evaluate(normalized, original)
    if mode == "differentiate":
        return _solve_derivative(original)
    if mode == "integrate":
        return _solve_integral(original)

    # Auto-detection
    if _DERIV_FRAC_RE.search(original):
        return _solve_derivative(original)
    if r"\int" in original:
        return _solve_integral(original)
    if r"\lim" in original:
        return _solve_limit(original)

    normalized = normalize(original)

    if ";" in normalized:
        return _solve_system(normalized, original)
    if _INEQ_RE.search(normalized):
        return _solve_inequality(normalized, original)
    if "=" in normalized:
        return _solve_equation(normalized, original)
    return _evaluate(normalized, original)


# ── equation solver ───────────────────────────────────────────────────────────

def _solve_equation(expr: str, original: str) -> SolvedResponse:
    lhs_str, rhs_str = expr.split("=", 1)
    lhs = _parse(lhs_str)
    rhs = _parse(rhs_str)
    equation = sp.Eq(lhs, rhs)
    var = _pick_variable(expr)
    symbol = sp.Symbol(var)

    # Strategy 1 – solveset first when transcendental (catches periodic/infinite solutions)
    if _has_transcendental(lhs - rhs):
        try:
            sol_set = sp.solveset(equation, symbol, domain=sp.S.Reals)
            if not sol_set.is_empty and not isinstance(sol_set, sp.ConditionSet):
                if isinstance(sol_set, sp.FiniteSet):
                    return _format_algebraic_solution(list(sol_set), equation, lhs, rhs, symbol, var, original)
                else:
                    return _format_infinite_solution(sol_set, equation, symbol, var, original)
        except Exception:
            pass

    # Strategy 2 – symbolic solve
    solutions: list[sp.Expr] = []
    try:
        raw = sp.solve(equation, symbol)
        real = [s for s in raw if _is_real(s)]
        solutions = real if real else raw
    except Exception:
        pass

    # Strategy 3 – solveset fallback (catches cases solve() misses)
    if not solutions:
        try:
            sol_set = sp.solveset(equation, symbol, domain=sp.S.Reals)
            if not sol_set.is_empty and not isinstance(sol_set, sp.ConditionSet):
                if isinstance(sol_set, sp.FiniteSet):
                    solutions = list(sol_set)
                else:
                    # Infinite / periodic solution set
                    return _format_infinite_solution(sol_set, equation, symbol, var, original)
        except Exception:
            pass

    # Strategy 3 – numerical (transcendental fallback)
    if not solutions:
        if _has_transcendental(lhs - rhs):
            return _solve_transcendental(lhs, rhs, symbol, var, equation, original)
        return _error(f"No solutions found for {var}", "no_solution", latex=original)

    return _format_algebraic_solution(solutions, equation, lhs, rhs, symbol, var, original)


def _format_algebraic_solution(
    solutions: list[sp.Expr],
    equation: sp.Eq,
    lhs: sp.Expr,
    rhs: sp.Expr,
    symbol: sp.Symbol,
    var: str,
    original: str,
) -> SolvedResponse:
    sol_exprs = [sp.simplify(s) for s in solutions]
    answer_parts = [f"{var} = {sp.latex(s)}" for s in sol_exprs]
    final_answer = " \\quad\\text{or}\\quad ".join(answer_parts)

    eq_type = _classify_equation(lhs, rhs, symbol)
    method_map = {
        "linear": "linear algebra",
        "quadratic": "quadratic formula / factoring",
        "polynomial": "polynomial root finding",
        "equation": "symbolic solving",
    }
    method = method_map.get(eq_type, "symbolic solving")

    steps: list[SolutionStep] = [
        SolutionStep(
            number=1,
            title="Identify the equation",
            description=f"Solve for ${var}$ — this is a {eq_type} equation.",
            formula=f"$${sp.latex(equation)}$$",
        ),
        SolutionStep(
            number=2,
            title="Rearrange to standard form",
            description="Move all terms to the left side.",
            formula=f"$${sp.latex(sp.expand(lhs - rhs))} = 0$$",
        ),
    ]

    if eq_type == "linear":
        steps.append(SolutionStep(
            number=3,
            title="Isolate the variable",
            description=f"Use inverse operations to solve for ${var}$.",
            formula=f"$${final_answer}$$",
        ))

    elif eq_type == "quadratic":
        a = sp.Poly(lhs - rhs, symbol).nth(2)
        b = sp.Poly(lhs - rhs, symbol).nth(1)
        c = sp.Poly(lhs - rhs, symbol).nth(0)
        disc = sp.expand(b**2 - 4*a*c)
        disc_val = sp.simplify(disc)

        # Try to show factored form first
        factored = _try_factor(lhs - rhs)
        if factored:
            steps.append(SolutionStep(
                number=3,
                title="Factor the quadratic",
                description="Express as a product of linear factors.",
                formula=f"$$({factored}) = 0$$",
            ))
            steps.append(SolutionStep(
                number=4,
                title="Zero product property",
                description="Each factor gives a solution.",
                formula=f"$${final_answer}$$",
            ))
        else:
            steps.append(SolutionStep(
                number=3,
                title="Compute the discriminant",
                description=f"$\\Delta = b^2 - 4ac$ with $a={sp.latex(a)},\\ b={sp.latex(b)},\\ c={sp.latex(c)}$",
                formula=f"$$\\Delta = ({sp.latex(b)})^2 - 4({sp.latex(a)})({sp.latex(c)}) = {sp.latex(disc_val)}$$",
            ))
            steps.append(SolutionStep(
                number=4,
                title="Apply the quadratic formula",
                description=f"$x = \\dfrac{{-b \\pm \\sqrt{{\\Delta}}}}{{2a}}$",
                formula=f"$${final_answer}$$",
            ))

    elif eq_type in ("polynomial",):
        factored = _try_factor(lhs - rhs)
        if factored:
            steps.append(SolutionStep(
                number=3,
                title="Factor the polynomial",
                description="Express as a product of linear (and possibly irreducible) factors.",
                formula=f"$$({factored}) = 0$$",
            ))
            steps.append(SolutionStep(
                number=4,
                title="Zero product property",
                description="Set each factor equal to zero.",
                formula=f"$${final_answer}$$",
            ))
        else:
            steps.append(SolutionStep(
                number=3,
                title="Find the roots",
                description=f"Apply numerical / algebraic root-finding for degree {sp.degree(lhs - rhs, symbol)} polynomial.",
                formula=f"$${final_answer}$$",
            ))

    else:
        steps.append(SolutionStep(
            number=3,
            title="Solve symbolically",
            description=f"Apply algebraic manipulation to isolate ${var}$.",
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


def _format_infinite_solution(
    sol_set: sp.Set,
    equation: sp.Eq,
    symbol: sp.Symbol,
    var: str,
    original: str,
) -> SolvedResponse:
    set_latex = sp.latex(sol_set)
    # Try to express as a human-readable general form
    general = set_latex
    steps = [
        SolutionStep(
            number=1,
            title="Identify the equation",
            description="This equation has infinitely many solutions (periodic or parametric).",
            formula=f"$${sp.latex(equation)}$$",
        ),
        SolutionStep(
            number=2,
            title="General solution",
            description=f"The complete solution set for ${var}$ is:",
            formula=f"$${general}$$",
        ),
    ]
    return SolvedResponse(
        success=True,
        latex=original,
        answer=f"{var} ∈ {set_latex}",
        finalAnswer=f"$${general}$$",
        method="solveset (periodic)",
        problem_type="periodic_equation",
        steps=steps,
    )


def _solve_transcendental(
    lhs: sp.Expr,
    rhs: sp.Expr,
    symbol: sp.Symbol,
    var: str,
    equation: sp.Eq,
    original: str,
) -> SolvedResponse:
    """Numerical root-finding for transcendental equations."""
    try:
        import numpy as np
    except ImportError:
        return _error("Numerical solver requires numpy", "numerical_error", original)

    expr = sp.simplify(lhs - rhs)

    try:
        f_num = sp.lambdify(symbol, expr, modules=["numpy"])
    except Exception:
        return _error("Cannot evaluate expression numerically", "numerical_error", original)

    # Scan over a range
    x_arr = np.linspace(-20.0, 20.0, 5000)
    try:
        raw_y = f_num(x_arr)
        # handle possible complex outputs
        y_arr = np.real(np.asarray(raw_y, dtype=complex))
        finite_mask = np.isfinite(y_arr)
        x_arr = x_arr[finite_mask]
        y_arr = y_arr[finite_mask]
    except Exception:
        return _error("Expression is not real-valued over [-20, 20]", "no_real_solution", original)

    if len(y_arr) < 2:
        return _error("No real-valued domain found in [-20, 20]", "no_real_solution", original)

    # Collect sign-change midpoints
    roots: list[float] = []
    for i in range(len(y_arr) - 1):
        if y_arr[i] * y_arr[i + 1] < 0:
            x0 = float((x_arr[i] + x_arr[i + 1]) / 2)
            try:
                root = float(sp.nsolve(expr, symbol, x0, tol=1e-10))
                if not any(abs(root - r) < 1e-7 for r in roots):
                    roots.append(root)
            except Exception:
                pass

    is_periodic = any(isinstance(f, (sp.sin, sp.cos, sp.tan)) for f in expr.atoms(sp.Function))

    if not roots:
        return SolvedResponse(
            success=True,
            latex=original,
            answer="No real solutions in [-20, 20]",
            finalAnswer="$$\\text{No real solutions in } [-20,\\,20]$$",
            method="numerical analysis",
            problem_type="transcendental",
            steps=[
                SolutionStep(number=1, title="Identify transcendental equation",
                    description="This equation mixes algebraic and transcendental functions — no closed-form algebraic solution exists.",
                    formula=f"$${sp.latex(equation)}$$"),
                SolutionStep(number=2, title="Numerical scan",
                    description="Scanned $[-20,\\,20]$ for sign changes. None found — no real solutions exist in this range.",
                    formula=f"$$f({var}) = {sp.latex(expr)} \\neq 0 \\text{{ on }} [-20,20]$$"),
            ],
        )

    roots.sort()
    sols_latex = "\\quad\\text{or}\\quad".join(f"{var} \\approx {r:.6g}" for r in roots)
    periodic_note = (
        "\n\n*Trig functions are periodic — additional solutions may exist outside $[-20,\\,20]$.*"
        if is_periodic and len(roots) >= 2
        else ""
    )

    steps = [
        SolutionStep(
            number=1,
            title="Identify the transcendental equation",
            description=(
                "This equation mixes algebraic and transcendental (trig/exp/log) functions. "
                "No closed-form solution exists — numerical methods are required."
            ),
            formula=f"$${sp.latex(equation)}$$",
        ),
        SolutionStep(
            number=2,
            title="Rewrite as $f(x) = 0$",
            description=f"Define $f({var}) = {sp.latex(expr)}$ and find its zeros.",
            formula=f"$$f({var}) = {sp.latex(expr)} = 0$$",
        ),
        SolutionStep(
            number=3,
            title=f"Scan $[-20,\\,20]$ for sign changes → {len(roots)} root(s)",
            description=(
                f"Found {len(roots)} sign change(s). "
                "Refined each with Newton's method (tolerance $10^{{-10}}$)."
                + ("  Trig functions are periodic — there may be more solutions outside this window." if is_periodic else "")
            ),
            formula=f"$${sols_latex}$$",
        ),
    ]

    return SolvedResponse(
        success=True,
        latex=original,
        answer=" or ".join(f"{var} ≈ {r:.6g}" for r in roots),
        finalAnswer=f"$${sols_latex}$$",
        method="numerical (Newton's method)",
        problem_type="transcendental",
        steps=steps,
    )


# ── derivative solver ─────────────────────────────────────────────────────────

def _solve_derivative(original: str) -> SolvedResponse:
    m = _DERIV_FRAC_RE.search(original)
    if not m:
        return _error("Cannot parse derivative notation", "parse_error", original)

    order_str = m.group(1) or m.group(2) or m.group(4) or m.group(5) or "1"
    order = int(order_str)
    var_char = m.group(3).lower()

    expr_raw = original[m.end():].strip()
    expr_raw = _strip_outer_brackets(expr_raw)

    expr_norm = normalize(expr_raw)
    var = sp.Symbol(var_char)

    try:
        expr = _parse(expr_norm)
    except Exception:
        return _error(f"Cannot parse expression: {expr_norm!r}", "parse_error", original)

    first_deriv = sp.diff(expr, var)
    result = sp.diff(expr, var, order)
    result_simplified = sp.powsimp(sp.simplify(result))
    result_latex = sp.latex(result_simplified)

    steps = _build_derivative_steps(expr, var, var_char, order, first_deriv, result_simplified)

    return SolvedResponse(
        success=True,
        latex=original,
        answer=str(result_simplified),
        finalAnswer=f"$${result_latex}$$",
        method="differentiation",
        problem_type=f"derivative_order_{order}",
        steps=steps,
    )


def _build_derivative_steps(
    expr: sp.Expr,
    var: sp.Symbol,
    var_char: str,
    order: int,
    first_deriv: sp.Expr,
    result: sp.Expr,
) -> list[SolutionStep]:
    first_latex = sp.latex(sp.powsimp(sp.simplify(first_deriv)))
    expr_latex = sp.latex(expr)

    steps: list[SolutionStep] = [
        SolutionStep(
            number=1,
            title="Identify the expression",
            description=f"Differentiate $f({var_char}) = {expr_latex}$ with respect to ${var_char}$.",
            formula=f"$$f({var_char}) = {expr_latex}$$",
        ),
    ]

    # Detect and describe the dominant rule
    rule_step = _describe_diff_rule_step(expr, var, var_char)
    steps.append(rule_step)

    if order == 1:
        steps.append(SolutionStep(
            number=3,
            title="Simplify",
            description="Combine and simplify all terms.",
            formula=f"$$f'({var_char}) = {sp.latex(result)}$$",
        ))
    else:
        steps.append(SolutionStep(
            number=3,
            title="First derivative",
            description="Result after first differentiation:",
            formula=f"$$f'({var_char}) = {first_latex}$$",
        ))
        for k in range(2, order + 1):
            kth = sp.diff(expr, var, k)
            kth_s = sp.powsimp(sp.simplify(kth))
            label = {2: "second", 3: "third"}.get(k, f"{k}th")
            steps.append(SolutionStep(
                number=k + 2,
                title=f"Differentiate again ({label} derivative)",
                description=f"Apply differentiation rules to $f^{{({k-1})}}({var_char})$.",
                formula=f"$$f^{{({k})}}({var_char}) = {sp.latex(kth_s)}$$",
            ))

    return steps


def _describe_diff_rule_step(expr: sp.Expr, var: sp.Symbol, var_char: str) -> SolutionStep:
    """Return a step that names and applies the correct rule(s)."""
    # Composition (chain rule)
    if isinstance(expr, sp.Function) and expr.args:
        inner = expr.args[0]
        if inner != var and inner.has(var):
            outer_type = type(expr).__name__
            outer_deriv = sp.diff(type(expr)(sp.Symbol("u")), sp.Symbol("u"))
            inner_deriv = sp.diff(inner, var)
            return SolutionStep(
                number=2,
                title="Apply the chain rule",
                description=(
                    f"Outer: $f(u) = \\{outer_type.lower()}(u)$, "
                    f"inner: $g({var_char}) = {sp.latex(inner)}$\n"
                    f"$\\frac{{d}}{{du}}[{sp.latex(type(expr)(sp.Symbol('u')))}] = {sp.latex(outer_deriv)}$, "
                    f"$g'({var_char}) = {sp.latex(inner_deriv)}$"
                ),
                formula=f"$$\\frac{{d}}{{d{var_char}}}[{sp.latex(expr)}] = "
                        f"{sp.latex(outer_deriv.subs(sp.Symbol('u'), inner))} \\cdot {sp.latex(inner_deriv)}$$",
            )

    # Product of two or more factors
    if isinstance(expr, sp.Mul) and len(expr.args) >= 2:
        factors = expr.args
        u, v = factors[0], sp.Mul(*factors[1:])
        du = sp.diff(u, var)
        dv = sp.diff(v, var)
        return SolutionStep(
            number=2,
            title="Apply the product rule",
            description=(
                f"Let $u = {sp.latex(u)}$, $v = {sp.latex(v)}$\n"
                f"$u' = {sp.latex(sp.simplify(du))}$, $v' = {sp.latex(sp.simplify(dv))}$"
            ),
            formula=f"$$\\frac{{d}}{{d{var_char}}}[uv] = u'v + uv' = "
                    f"({sp.latex(du)})({sp.latex(v)}) + ({sp.latex(u)})({sp.latex(dv)})$$",
        )

    # Sum rule
    if isinstance(expr, sp.Add):
        terms = expr.args
        term_derivs = [f"\\frac{{d}}{{d{var_char}}}[{sp.latex(t)}] = {sp.latex(sp.simplify(sp.diff(t, var)))}" for t in terms[:3]]
        return SolutionStep(
            number=2,
            title="Apply the sum rule",
            description="Differentiate each term separately.",
            formula="$$" + ",\\quad ".join(term_derivs) + "$$",
        )

    # Power rule
    if isinstance(expr, sp.Pow) and not expr.args[1].has(var):
        base, exp = expr.args
        return SolutionStep(
            number=2,
            title="Apply the power rule",
            description=f"$\\frac{{d}}{{d{var_char}}}[{var_char}^n] = n{var_char}^{{n-1}}$ with $n = {sp.latex(exp)}$",
            formula=f"$$\\frac{{d}}{{d{var_char}}}[{sp.latex(expr)}] = {sp.latex(exp)} \\cdot {sp.latex(base)}^{{{sp.latex(exp-1)}}}$$",
        )

    # Fallback
    return SolutionStep(
        number=2,
        title="Apply differentiation rules",
        description=_describe_diff_rules(expr, var),
        formula=f"$$\\frac{{d}}{{d{var_char}}}[{sp.latex(expr)}] = {sp.latex(sp.simplify(sp.diff(expr, var)))}$$",
    )


# ── integral solver ───────────────────────────────────────────────────────────

def _solve_integral(original: str) -> SolvedResponse:
    m = _INTEGRAL_RE.search(original)
    if not m:
        return _error("Cannot parse integral expression", "parse_error", original)

    lower_raw = m.group(1) or m.group(2)
    upper_raw = m.group(3) or m.group(4)
    integrand_raw = (m.group(5) or "").strip()
    var_char = m.group(6).lower()

    if not integrand_raw:
        body = re.sub(r"\\int(?:_[^\s]+\^[^\s]+)?", "", original).strip()
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

        antideriv = sp.integrate(integrand, var)
        result = sp.integrate(integrand, (var, a, b))
        result_simplified = sp.simplify(result)
        result_latex = sp.latex(result_simplified)
        bounds_latex = f"_{{{sp.latex(a)}}}^{{{sp.latex(b)}}}"

        steps = [
            SolutionStep(
                number=1,
                title="Set up the definite integral",
                description=f"Integrate $f({var_char}) = {sp.latex(integrand)}$ from ${sp.latex(a)}$ to ${sp.latex(b)}$.",
                formula=f"$$\\int{bounds_latex} {sp.latex(integrand)}\\, d{var_char}$$",
            ),
            SolutionStep(
                number=2,
                title="Find the antiderivative",
                description=_describe_int_technique(integrand, var, var_char),
                formula=f"$$F({var_char}) = {sp.latex(sp.simplify(antideriv))} + C$$",
            ),
            SolutionStep(
                number=3,
                title="Apply the Fundamental Theorem of Calculus",
                description=f"Evaluate $F({sp.latex(b)}) - F({sp.latex(a)})$.",
                formula=f"$$F({sp.latex(b)}) - F({sp.latex(a)}) = {result_latex}$$",
            ),
        ]

        return SolvedResponse(
            success=True,
            latex=original,
            answer=str(result_simplified),
            finalAnswer=f"$${result_latex}$$",
            method="definite integration",
            problem_type="definite_integral",
            steps=steps,
        )

    else:
        antideriv = sp.integrate(integrand, var)
        antideriv_simplified = sp.simplify(antideriv)
        antideriv_latex = sp.latex(antideriv_simplified)

        tech_steps = _build_integral_steps(integrand, antideriv_simplified, var, var_char)

        return SolvedResponse(
            success=True,
            latex=original,
            answer=f"{antideriv_simplified} + C",
            finalAnswer=f"$${antideriv_latex} + C$$",
            method=_identify_int_method(integrand, var),
            problem_type="indefinite_integral",
            steps=tech_steps,
        )


def _build_integral_steps(
    integrand: sp.Expr,
    antideriv: sp.Expr,
    var: sp.Symbol,
    var_char: str,
) -> list[SolutionStep]:
    """Generate rich step list for indefinite integration."""
    steps: list[SolutionStep] = [
        SolutionStep(
            number=1,
            title="Set up the integral",
            description=f"Find $\\int {sp.latex(integrand)}\\, d{var_char}$.",
            formula=f"$$\\int {sp.latex(integrand)}\\, d{var_char}$$",
        ),
    ]

    # Integration by parts detection
    ibp = _detect_ibp(integrand, var, var_char)
    if ibp:
        u_expr, dv_expr, du_expr, v_expr = ibp
        ibp_rhs = sp.integrate(integrand, var)  # full result
        residual = sp.simplify(ibp_rhs - u_expr * v_expr)
        steps += [
            SolutionStep(
                number=2,
                title="Choose $u$ and $dv$ (LIATE rule)",
                description=(
                    f"Let $u = {sp.latex(u_expr)}$ (algebraic/higher LIATE)\n"
                    f"Let $dv = {sp.latex(dv_expr)}\\, d{var_char}$\n"
                    f"Then $du = {sp.latex(du_expr)}\\, d{var_char}$, "
                    f"$v = {sp.latex(v_expr)}$"
                ),
                formula=(
                    f"$$u = {sp.latex(u_expr)},\\quad "
                    f"dv = {sp.latex(dv_expr)}\\,d{var_char}$$\n"
                    f"$$du = {sp.latex(du_expr)}\\,d{var_char},\\quad "
                    f"v = {sp.latex(v_expr)}$$"
                ),
            ),
            SolutionStep(
                number=3,
                title="Apply the IBP formula: $\\int u\\,dv = uv - \\int v\\,du$",
                description="Substitute into the integration by parts formula.",
                formula=(
                    f"$$= {sp.latex(u_expr)} \\cdot {sp.latex(v_expr)} "
                    f"- \\int {sp.latex(sp.simplify(v_expr * du_expr))}\\, d{var_char}$$"
                ),
            ),
            SolutionStep(
                number=4,
                title="Evaluate the remaining integral",
                description="Integrate the simpler remaining term.",
                formula=f"$$= {sp.latex(antideriv)} + C$$",
            ),
        ]
        return steps

    # u-substitution detection
    sub = _detect_substitution(integrand, var, var_char)
    if sub:
        u_expr, u_deriv, inner_str = sub
        steps += [
            SolutionStep(
                number=2,
                title="Apply $u$-substitution",
                description=f"Let $u = {sp.latex(u_expr)}$, so $du = {sp.latex(u_deriv)}\\, d{var_char}$.",
                formula=f"$$u = {sp.latex(u_expr)},\\quad du = {sp.latex(u_deriv)}\\, d{var_char}$$",
            ),
            SolutionStep(
                number=3,
                title="Integrate and back-substitute",
                description=f"Compute the integral in terms of $u$, then replace $u = {sp.latex(u_expr)}$.",
                formula=f"$$= {sp.latex(antideriv)} + C$$",
            ),
        ]
        return steps

    # Partial fractions detection
    if _is_rational(integrand, var):
        numer, denom = sp.fraction(sp.together(integrand))
        steps += [
            SolutionStep(
                number=2,
                title="Partial fraction decomposition",
                description="Express the rational integrand as a sum of simpler fractions.",
                formula=f"$$\\frac{{{sp.latex(numer)}}}{{{sp.latex(denom)}}} = {sp.latex(sp.apart(integrand, var))}$$",
            ),
            SolutionStep(
                number=3,
                title="Integrate each partial fraction",
                description="Use $\\int \\frac{1}{x-a}dx = \\ln|x-a| + C$ etc.",
                formula=f"$$= {sp.latex(antideriv)} + C$$",
            ),
        ]
        return steps

    # Generic fallback with technique name
    technique = _describe_int_technique(integrand, var, var_char)
    steps.append(SolutionStep(
        number=2,
        title="Apply integration rules",
        description=technique,
        formula=f"$$= {sp.latex(antideriv)} + C$$",
    ))
    return steps


# ── limit solver ──────────────────────────────────────────────────────────────

def _solve_limit(original: str) -> SolvedResponse:
    m = _LIMIT_RE.search(original)
    if not m:
        return _error("Cannot parse limit expression", "parse_error", original)

    var_char = m.group(1)
    point_raw = m.group(2).strip()
    expr_raw = m.group(3).strip()

    var = sp.Symbol(var_char)

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
    point_latex = (
        "\\infty" if point == sp.oo
        else "-\\infty" if point == -sp.oo
        else sp.latex(point)
    )

    steps = _build_limit_steps(expr, var, var_char, point, point_latex, result_simplified)

    return SolvedResponse(
        success=True,
        latex=original,
        answer=str(result_simplified),
        finalAnswer=f"$${result_latex}$$",
        method="limit evaluation",
        problem_type="limit",
        steps=steps,
    )


def _build_limit_steps(
    expr: sp.Expr,
    var: sp.Symbol,
    var_char: str,
    point: sp.Expr,
    point_latex: str,
    result: sp.Expr,
) -> list[SolutionStep]:
    lim_notation = f"\\lim_{{{var_char} \\to {point_latex}}}"
    result_latex = sp.latex(result)

    steps: list[SolutionStep] = [
        SolutionStep(
            number=1,
            title="Identify the limit",
            description=f"Evaluate ${lim_notation} {sp.latex(expr)}$.",
            formula=f"$${lim_notation} {sp.latex(expr)}$$",
        ),
    ]

    # Try direct substitution first
    direct: Optional[sp.Expr] = None
    if point not in (sp.oo, -sp.oo):
        try:
            direct = expr.subs(var, point)
            direct = sp.simplify(direct)
        except Exception:
            direct = None

    if direct is not None and direct.is_finite and not direct.has(sp.nan, sp.zoo):
        steps.append(SolutionStep(
            number=2,
            title="Direct substitution",
            description=f"Substitute ${var_char} = {point_latex}$ directly.",
            formula=f"$${sp.latex(expr.subs(var, point))} = {result_latex}$$",
        ))
        return steps

    # Check for rational 0/0 or ∞/∞ → L'Hôpital
    numer, denom = sp.fraction(sp.together(expr))
    if denom != 1:
        form = _detect_indeterminate_form(numer, denom, var, point)
        if form in ("0/0", "∞/∞"):
            steps += _lhopital_steps(numer, denom, var, var_char, point, point_latex, result_latex, form)
            return steps

    # Check for 0·∞ form
    if isinstance(expr, sp.Mul):
        factors = expr.args
        if len(factors) == 2:
            f1_limit = sp.limit(factors[0], var, point)
            f2_limit = sp.limit(factors[1], var, point)
            if (f1_limit == 0 and f2_limit in (sp.oo, -sp.oo)) or \
               (f2_limit == 0 and f1_limit in (sp.oo, -sp.oo)):
                steps.append(SolutionStep(
                    number=2,
                    title="Indeterminate form $0 \\cdot \\infty$",
                    description="Rewrite as a ratio and apply L'Hôpital's rule.",
                    formula=f"$${lim_notation} {sp.latex(expr)} = {lim_notation} \\frac{{{sp.latex(factors[0])}}}{{{sp.latex(1/factors[1])}}}"
                            f"\\quad\\text{{(or vice versa)}}$$",
                ))
                steps.append(SolutionStep(
                    number=3,
                    title="Evaluate",
                    description="After resolving the indeterminate form:",
                    formula=f"$$= {result_latex}$$",
                ))
                return steps

    # Generic: just show the result
    steps.append(SolutionStep(
        number=2,
        title="Apply limit laws",
        description="Use continuity, algebraic manipulation, or standard limit results.",
        formula=f"$${lim_notation} {sp.latex(expr)} = {result_latex}$$",
    ))
    return steps


def _lhopital_steps(
    numer: sp.Expr,
    denom: sp.Expr,
    var: sp.Symbol,
    var_char: str,
    point: sp.Expr,
    point_latex: str,
    result_latex: str,
    form: str,
) -> list[SolutionStep]:
    """Build L'Hôpital rule steps, applying up to 3 times."""
    lim = f"\\lim_{{{var_char} \\to {point_latex}}}"
    steps: list[SolutionStep] = []

    n, d = numer, denom
    step_n = 2
    for iteration in range(1, 4):
        n_sub = n.subs(var, point)
        d_sub = d.subs(var, point)
        current_form = _detect_indeterminate_form(n, d, var, point)
        if current_form not in ("0/0", "∞/∞"):
            break

        dn = sp.diff(n, var)
        dd = sp.diff(d, var)
        dn_s = sp.simplify(dn)
        dd_s = sp.simplify(dd)

        suffix = "" if iteration == 1 else f" (application {iteration})"
        steps.append(SolutionStep(
            number=step_n,
            title=f"Indeterminate form ${current_form}$ -- apply L'Hopital's rule{suffix}",
            description=(
                f"Direct substitution gives ${sp.latex(n_sub)}/{sp.latex(d_sub)}$. "
                "Differentiate numerator and denominator separately."
            ),
            formula=(
                f"$$\\frac{{d}}{{d{var_char}}}[{sp.latex(n)}] = {sp.latex(dn_s)},\\quad"
                f"\\frac{{d}}{{d{var_char}}}[{sp.latex(d)}] = {sp.latex(dd_s)}$$"
            ),
        ))
        step_n += 1

        new_expr = sp.simplify(dn_s / dd_s)
        new_lim = sp.limit(new_expr, var, point)
        new_lim_s = sp.simplify(new_lim)

        if new_lim_s.is_finite and not new_lim_s.has(sp.nan):
            steps.append(SolutionStep(
                number=step_n,
                title="Evaluate the new limit",
                description=f"Substitute ${var_char} = {point_latex}$ into the differentiated ratio.",
                formula=f"$${lim} \\frac{{{sp.latex(dn_s)}}}{{{sp.latex(dd_s)}}} = {result_latex}$$",
            ))
            return steps

        n, d = dn_s, dd_s
        step_n += 1

    steps.append(SolutionStep(
        number=step_n,
        title="Result",
        description="After applying L'Hôpital's rule:",
        formula=f"$$= {result_latex}$$",
    ))
    return steps


# ── system solver ─────────────────────────────────────────────────────────────

def _solve_system(expr: str, original: str) -> SolvedResponse:
    parts = [p.strip() for p in expr.split(";") if p.strip()]
    equations: list[sp.Eq] = []
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
    answer_parts = [f"{k} = {sp.latex(v)}" for k, v in sorted(row.items(), key=lambda x: str(x[0]))]
    final_answer = ",\\quad ".join(answer_parts)

    method = "elimination" if len(equations) == 2 else "Gaussian elimination"

    steps = [
        SolutionStep(number=i + 1, title=f"Equation {i + 1}", description="", formula=f"$${sp.latex(eq)}$$")
        for i, eq in enumerate(equations)
    ]

    if len(equations) == 2 and len(symbols) == 2:
        # Show substitution hint
        sym0 = symbols[0]
        try:
            sub_expr = sp.solve(equations[0], sym0)[0]
            sub_eq = equations[1].subs(sym0, sub_expr)
            sub_sol = sp.solve(sub_eq, symbols[1])
            if sub_sol:
                steps.append(SolutionStep(
                    number=len(equations) + 1,
                    title="Substitution / elimination",
                    description=f"From equation (1): ${sp.latex(sym0)} = {sp.latex(sub_expr)}$. Substitute into equation (2).",
                    formula=f"$${sp.latex(sub_eq)}$$",
                ))
        except Exception:
            pass

    steps.append(SolutionStep(
        number=len(steps) + 1,
        title="Solution",
        description="Solve the resulting system simultaneously.",
        formula=f"$${final_answer}$$",
    ))

    return SolvedResponse(
        success=True, latex=original,
        answer=str(row), finalAnswer=f"$${final_answer}$$",
        method=method, problem_type="system", steps=steps,
    )


# ── inequality solver ─────────────────────────────────────────────────────────

def _solve_inequality(expr: str, original: str) -> SolvedResponse:
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
        SolutionStep(number=1, title="Identify the inequality",
            description=f"Solve ${sp.latex(rel)}$ for ${var}$.", formula=f"$${sp.latex(rel)}$$"),
        SolutionStep(number=2, title="Rearrange",
            description="Move all terms to one side.",
            formula=f"$${sp.latex(sp.simplify(lhs - rhs))} {op} 0$$"),
        SolutionStep(number=3, title="Solve for the solution interval",
            description=f"The solution for ${var}$:",
            formula=f"$${solution_latex}$$"),
    ]

    return SolvedResponse(
        success=True, latex=original,
        answer=str(solution), finalAnswer=f"$${solution_latex}$$",
        method="inequality solving", problem_type="inequality", steps=steps,
    )


# ── evaluate (pure expression) ────────────────────────────────────────────────

def _evaluate(expr: str, original: str) -> SolvedResponse:
    parsed = _parse(expr)
    result = sp.powsimp(sp.simplify(parsed))
    result_latex = sp.latex(result)

    steps: list[SolutionStep] = [
        SolutionStep(number=1, title="Expression", description="Evaluate and simplify.", formula=f"$${sp.latex(parsed)}$$"),
        SolutionStep(number=2, title="Result", description="After simplification:", formula=f"$$= {result_latex}$$"),
    ]

    try:
        num = complex(result)
        if num.imag == 0 and result != sp.sympify(f"{num.real:.10g}"):
            steps.append(SolutionStep(number=3, title="Numerical value", description="",
                formula=f"$$\\approx {num.real:.6g}$$"))
    except Exception:
        pass

    return SolvedResponse(
        success=True, latex=original, answer=str(result), finalAnswer=f"$${result_latex}$$",
        method="simplify", problem_type="arithmetic", steps=steps,
    )


# ── expand ───────────────────────────────────────────────────────────────────

def _expand(original: str) -> SolvedResponse:
    normalized = normalize(original)
    # Strip the equation sign if present — expand the LHS expression
    expr_str = normalized.split("=")[0] if "=" in normalized else normalized
    try:
        parsed = _parse(expr_str)
    except Exception as exc:
        return _error(str(exc), "parse_error", original)

    expanded = sp.expand(parsed)
    expanded_latex = sp.latex(expanded)

    steps: list[SolutionStep] = [
        SolutionStep(number=1, title="Identify expression", description="Apply distributive property to expand the product.",
                     formula=f"$${sp.latex(parsed)}$$"),
        SolutionStep(number=2, title="Expand", description="Multiply out all terms:",
                     formula=f"$$= {expanded_latex}$$"),
    ]

    # If it's a polynomial, optionally collect like terms note
    terms = sp.Add.make_args(expanded)
    if len(terms) > 1:
        steps.append(SolutionStep(
            number=3, title="Collect like terms",
            description=f"The expanded form has {len(terms)} terms.",
            formula=f"$$= {expanded_latex}$$",
        ))

    return SolvedResponse(
        success=True, latex=original,
        answer=str(expanded), finalAnswer=f"$${expanded_latex}$$",
        method="expand", problem_type="expansion", steps=steps,
    )


# ── factor ───────────────────────────────────────────────────────────────────

def _factor(original: str) -> SolvedResponse:
    normalized = normalize(original)
    expr_str = normalized.split("=")[0] if "=" in normalized else normalized
    try:
        parsed = _parse(expr_str)
    except Exception as exc:
        return _error(str(exc), "parse_error", original)

    factored = sp.factor(parsed)
    factored_latex = sp.latex(factored)

    # Check if factoring actually changed anything
    if factored == parsed or isinstance(factored, sp.core.numbers.Number):
        return SolvedResponse(
            success=True, latex=original,
            answer=str(factored), finalAnswer=f"$${factored_latex}$$",
            method="factor", problem_type="factoring",
            steps=[
                SolutionStep(number=1, title="Expression", description="Check for factorable form.", formula=f"$${sp.latex(parsed)}$$"),
                SolutionStep(number=2, title="Already irreducible", description="The expression cannot be factored further over the rationals.", formula=f"$${factored_latex}$$"),
            ],
        )

    steps: list[SolutionStep] = [
        SolutionStep(number=1, title="Identify expression", description="Factor the polynomial by finding common factors and roots.",
                     formula=f"$${sp.latex(parsed)}$$"),
        SolutionStep(number=2, title="Factored form", description="The completely factored form is:",
                     formula=f"$$= {factored_latex}$$"),
    ]

    return SolvedResponse(
        success=True, latex=original,
        answer=str(factored), finalAnswer=f"$${factored_latex}$$",
        method="factor", problem_type="factoring", steps=steps,
    )


# ── helpers ───────────────────────────────────────────────────────────────────

def _parse(s: str) -> sp.Expr:
    return parse_expr(s.strip(), transformations=_TRANSFORMS, evaluate=True, local_dict=_LOCAL_DICT)


def _safe_parse_bound(raw: str) -> Optional[sp.Expr]:
    try:
        norm = normalize(raw)
        if "oo" in norm:
            return sp.oo
        return _parse(norm)
    except Exception:
        return None


def _pick_variable(expr: str) -> str:
    candidates = set(_VAR_RE.findall(expr)) - {"e", "E", "C"}
    for v in _VAR_PREFERENCE:
        if v in candidates:
            return v
    return next(iter(candidates), "x")


def _is_real(expr: sp.Expr) -> bool:
    try:
        return expr.is_real is not False
    except Exception:
        return True


def _has_transcendental(expr: sp.Expr) -> bool:
    return any(isinstance(f, _TRANSCENDENTAL_FUNCS) for f in expr.atoms(sp.Function))


def _is_rational(expr: sp.Expr, var: sp.Symbol) -> bool:
    try:
        numer, denom = sp.fraction(sp.together(expr))
        return denom != 1 and sp.degree(sp.Poly(denom, var)) >= 1
    except Exception:
        return False


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


def _try_factor(poly: sp.Expr) -> Optional[str]:
    """Return LaTeX of factored form, or None if factoring doesn't simplify."""
    try:
        factored = sp.factor(poly)
        if factored != poly and not isinstance(factored, sp.Add):
            return sp.latex(factored)
    except Exception:
        pass
    return None


def _detect_indeterminate_form(numer: sp.Expr, denom: sp.Expr, var: sp.Symbol, point: sp.Expr) -> str:
    try:
        n = sp.limit(numer, var, point)
        d = sp.limit(denom, var, point)
        if n == 0 and d == 0:
            return "0/0"
        if n in (sp.oo, -sp.oo) and d in (sp.oo, -sp.oo):
            return "∞/∞"
    except Exception:
        pass
    return "other"


def _detect_ibp(integrand: sp.Expr, var: sp.Symbol, var_char: str):
    """Detect integration by parts pattern. Returns (u, dv, du, v) or None."""
    if not isinstance(integrand, sp.Mul):
        return None

    factors = list(integrand.args)
    if len(factors) < 2:
        return None

    # LIATE ordering: L > I > A > T > E
    def liate_rank(expr: sp.Expr) -> int:
        atoms = expr.atoms(sp.Function)
        if any(isinstance(a, sp.log) for a in atoms):
            return 5  # L
        if any(isinstance(a, (sp.asin, sp.acos, sp.atan)) for a in atoms):
            return 4  # I
        if expr.is_polynomial(var):
            return 3  # A
        if any(isinstance(a, (sp.sin, sp.cos, sp.tan)) for a in atoms):
            return 2  # T
        if any(isinstance(a, sp.exp) for a in atoms) or (isinstance(expr, sp.Pow) and expr.args[0] == sp.E):
            return 1  # E
        return 0

    # Split into u (highest rank) and dv (rest)
    ranked = sorted(factors, key=liate_rank, reverse=True)
    u_expr = ranked[0]
    dv_expr = sp.Mul(*ranked[1:]) if len(ranked) > 2 else ranked[1]

    # Only suggest IBP if u has a finite antiderivative and dv can be integrated
    try:
        du_expr = sp.diff(u_expr, var)
        v_expr = sp.integrate(dv_expr, var)
        if v_expr.has(sp.Integral):
            return None  # dv not integrable in closed form
        # Sanity: the residual integral should be simpler
        residual = sp.simplify(v_expr * du_expr)
        if residual.atoms(sp.Function) >= integrand.atoms(sp.Function):
            return None  # Not actually simpler
        return u_expr, dv_expr, du_expr, v_expr
    except Exception:
        return None


def _detect_substitution(integrand: sp.Expr, var: sp.Symbol, var_char: str):
    """Detect u-substitution pattern. Returns (u_expr, u_deriv, inner_str) or None."""
    # Look for composite function: f(g(x)) * g'(x)
    for atom in integrand.atoms(sp.Function):
        if not atom.args:
            continue
        inner = atom.args[0]
        if inner == var or not inner.has(var):
            continue
        inner_deriv = sp.diff(inner, var)
        # Check if inner_deriv appears as a factor in the integrand
        remaining = sp.simplify(integrand / inner_deriv)
        if not remaining.has(var) or sp.simplify(integrand - remaining * inner_deriv) == 0:
            return inner, inner_deriv, str(inner)
    return None


def _identify_int_method(integrand: sp.Expr, var: sp.Symbol) -> str:
    if _detect_ibp(integrand, var, "x"):
        return "integration by parts"
    if _detect_substitution(integrand, var, "x"):
        return "u-substitution"
    if _is_rational(integrand, var):
        return "partial fractions"
    return "integration"


def _describe_int_technique(integrand: sp.Expr, var: sp.Symbol, var_char: str) -> str:
    if _is_rational(integrand, var):
        return "Decompose into partial fractions, then integrate each term."
    funcs = integrand.atoms(sp.Function)
    if any(isinstance(f, (sp.sin, sp.cos)) for f in funcs):
        return "Apply standard trig integral formulas."
    if any(isinstance(f, sp.exp) for f in funcs):
        return "Use $\\int e^u\\,du = e^u + C$ (with chain/substitution if needed)."
    if any(isinstance(f, sp.log) for f in funcs):
        return "Use $\\int \\ln(u)\\,du = u\\ln(u) - u + C$ or integration by parts."
    return "Apply the power rule and linearity of integration."


def _describe_diff_rules(expr: sp.Expr, var: sp.Symbol) -> str:
    rules = []
    if isinstance(expr, sp.Add):
        rules.append("sum rule")
    if isinstance(expr, sp.Mul):
        rules.append("product rule")
    if isinstance(expr, sp.Pow):
        rules.append("exponential differentiation" if expr.args[1].free_symbols else "power rule")
    func_atoms = expr.atoms(sp.Function)
    if func_atoms:
        rules.append("chain rule")
    if not rules:
        rules.append("standard differentiation rules")
    return "Apply " + ", ".join(rules) + "."


def _strip_outer_brackets(s: str) -> str:
    """Remove one matched layer of outer brackets, parens, or \\left/\\right pairs."""
    s = s.strip()
    # \left[ ... \right]  /  \left( ... \right)
    m = re.match(r"^\\left([\[\({])(.*?)\\right([\]\)}])\s*$", s, re.DOTALL)
    if m:
        return m.group(2).strip()
    # Plain [ ... ]  or  ( ... )  or  { ... }
    pairs = {"[": "]", "(": ")", "{": "}"}
    if s and s[0] in pairs and s[-1] == pairs[s[0]]:
        return s[1:-1].strip()
    return s


def _error(msg: str, method: str, latex: str = "") -> SolvedResponse:
    return SolvedResponse(
        success=False, latex=latex, answer="", finalAnswer="",
        method=method, problem_type="unknown", steps=[], error=msg,
    )
