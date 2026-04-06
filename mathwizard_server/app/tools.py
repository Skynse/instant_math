from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

import sympy as sp
from sympy.parsing.sympy_parser import (
    convert_xor,
    implicit_multiplication_application,
    parse_expr,
    standard_transformations,
)


TRANSFORMATIONS = standard_transformations + (
    implicit_multiplication_application,
    convert_xor,
)


def _parse_expr(raw: str) -> sp.Expr:
    return parse_expr(raw, transformations=TRANSFORMATIONS, evaluate=True)


def _parse_equation(raw: str) -> tuple[sp.Expr, sp.Expr]:
    if "=" not in raw:
        expr = _parse_expr(raw)
        return expr, sp.Integer(0)
    left, right = raw.split("=", 1)
    return _parse_expr(left), _parse_expr(right)


def _latex(expr: Any) -> str:
    try:
        return f"$${sp.latex(expr)}$$"
    except Exception:
        return f"$${expr}$$"


def evaluate_expression(expression: str) -> dict[str, Any]:
    expr = _parse_expr(expression)
    simplified = sp.simplify(expr)
    return {
        "value": str(simplified),
        "latex": _latex(simplified),
    }


def simplify_expression(expression: str) -> dict[str, Any]:
    expr = _parse_expr(expression)
    simplified = sp.simplify(expr)
    return {
        "simplified": str(simplified),
        "latex": _latex(simplified),
    }


def factor_expression(expression: str) -> dict[str, Any]:
    expr = _parse_expr(expression)
    factored = sp.factor(expr)
    return {
        "factored": str(factored),
        "latex": _latex(factored),
    }


def solve_linear(equation: str, variable: str = "x") -> dict[str, Any]:
    lhs, rhs = _parse_equation(equation)
    symbol = sp.Symbol(variable)
    solutions = sp.solve(sp.Eq(lhs, rhs), symbol)
    rendered = [str(s) for s in solutions]
    return {
        "variable": variable,
        "solutions": rendered,
        "latex": _latex(sp.Eq(symbol, solutions[0])) if solutions else "",
    }


def solve_equation(equation: str, variable: str = "x") -> dict[str, Any]:
    lhs, rhs = _parse_equation(equation)
    symbol = sp.Symbol(variable)
    solutions = sp.solve(sp.Eq(lhs, rhs), symbol)
    return {
        "variable": variable,
        "solutions": [str(s) for s in solutions],
        "latex": _latex(sp.Eq(lhs, rhs)),
    }


def solve_quadratic(a: float, b: float, c: float, variable: str = "x") -> dict[str, Any]:
    symbol = sp.Symbol(variable)
    expr = a * symbol**2 + b * symbol + c
    solutions = sp.solve(sp.Eq(expr, 0), symbol)
    discriminant = b**2 - 4 * a * c
    return {
        "variable": variable,
        "discriminant": discriminant,
        "solutions": [str(s) for s in solutions],
        "latex": _latex(sp.Eq(expr, 0)),
    }


def solve_system(equations: list[str], variables: list[str]) -> dict[str, Any]:
    symbols = [sp.Symbol(v) for v in variables]
    sympy_equations = []
    for raw in equations:
        lhs, rhs = _parse_equation(raw)
        sympy_equations.append(sp.Eq(lhs, rhs))
    solution = sp.solve(sympy_equations, symbols, dict=True)
    return {
        "variables": variables,
        "solutions": [{k.name: str(v) for k, v in row.items()} for row in solution],
        "latex": "\n".join(_latex(eq) for eq in sympy_equations),
    }


@dataclass(frozen=True)
class ToolSpec:
    name: str
    description: str
    handler: Callable[..., dict[str, Any]]


class MathToolRegistry:
    def __init__(self) -> None:
        self._tools: dict[str, ToolSpec] = {
            "evaluate_expression": ToolSpec(
                name="evaluate_expression",
                description="Evaluate and simplify a numeric or symbolic expression.",
                handler=evaluate_expression,
            ),
            "simplify_expression": ToolSpec(
                name="simplify_expression",
                description="Simplify an algebraic expression.",
                handler=simplify_expression,
            ),
            "factor_expression": ToolSpec(
                name="factor_expression",
                description="Factor an algebraic expression.",
                handler=factor_expression,
            ),
            "solve_linear": ToolSpec(
                name="solve_linear",
                description="Solve a linear equation like 3*x - 5 = 10.",
                handler=solve_linear,
            ),
            "solve_equation": ToolSpec(
                name="solve_equation",
                description="Solve a single-variable equation exactly with SymPy.",
                handler=solve_equation,
            ),
            "solve_quadratic": ToolSpec(
                name="solve_quadratic",
                description="Solve ax^2 + bx + c = 0 using exact algebra.",
                handler=solve_quadratic,
            ),
            "solve_system": ToolSpec(
                name="solve_system",
                description="Solve a system of equations with named variables.",
                handler=solve_system,
            ),
        }

    def definitions(self) -> list[dict[str, str]]:
        return [
            {"name": spec.name, "description": spec.description}
            for spec in self._tools.values()
        ]

    def execute(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        spec = self._tools.get(name)
        if spec is None:
            raise ValueError(f"Unknown tool: {name}")
        return spec.handler(**arguments)
