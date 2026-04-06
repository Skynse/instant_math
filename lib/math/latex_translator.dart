/// Translates a LaTeX math expression into a standard infix expression
/// that [MathExpressionEvaluator] can handle.
class LatexTranslator {
  static const _knownFunctions = {
    'sin', 'cos', 'tan', 'asin', 'acos', 'atan',
    'sqrt', 'log', 'log10', 'log2', 'logb', 'exp', 'abs', 'cbrt',
    'floor', 'ceil', 'round',
  };

  static String translate(String latex) {
    var s = latex.trim();
    // Strip display-math delimiters
    s = s.replaceAll(r'$$', '').replaceAll(r'$', '').trim();
    // Treat ≈ as = for solving
    s = _normaliseApprox(s);
    // Remove size hints early so downstream parsers see clean parens
    s = s.replaceAll(RegExp(r'\\(left|right|[Bb]ig[gG]?)'), '');
    s = s.replaceAll(RegExp(r'\\[,;!]'), ' ');
    // Handle \begin{cases}...\end{cases} → semicolon-separated equations
    s = _expandCases(s);
    // Expand \log_{b} before subscript removal destroys the base
    s = _expandLogBase(s);
    s = _expandFrac(s);
    s = _expandSqrt(s);
    s = _expandSuperscript(s);
    s = _removeSubscripts(s);
    s = _replaceCommands(s);
    // Convert any remaining braces to parentheses
    s = s.replaceAll('{', '(').replaceAll('}', ')');
    s = _addImplicitMultiplication(s);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── brace / paren extraction ──────────────────────────────────────────────

  static (String, int) _extractBraces(String s, int i) {
    if (i >= s.length || s[i] != '{') return ('', i);
    int depth = 0;
    final buf = StringBuffer();
    while (i < s.length) {
      final c = s[i++];
      if (c == '{') {
        if (++depth > 1) buf.write(c);
      } else if (c == '}') {
        if (--depth == 0) return (buf.toString(), i);
        buf.write(c);
      } else {
        buf.write(c);
      }
    }
    return (buf.toString(), s.length);
  }

  static (String, int) _extractParens(String s, int i) {
    if (i >= s.length || s[i] != '(') return ('', i);
    int depth = 0;
    final buf = StringBuffer();
    while (i < s.length) {
      final c = s[i++];
      if (c == '(') {
        if (++depth > 1) buf.write(c);
      } else if (c == ')') {
        if (--depth == 0) return (buf.toString(), i);
        buf.write(c);
      } else {
        buf.write(c);
      }
    }
    return (buf.toString(), s.length);
  }

  // ── \approx normalisation ─────────────────────────────────────────────────

  static String _normaliseApprox(String s) =>
      s.replaceAll(r'\approx', '=').replaceAll('≈', '=');

  // ── \begin{cases} ─────────────────────────────────────────────────────────

  static String _expandCases(String s) {
    final match = RegExp(
      r'\\begin\{cases\}(.*?)\\end\{cases\}',
      dotAll: true,
    ).firstMatch(s);
    if (match == null) return s;
    final inner = match.group(1)!;
    final equations = inner
        .split(RegExp(r'\\\\|\\newline'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // Replace the cases block; leave anything before/after intact
    return s.replaceRange(match.start, match.end, equations.join(';'));
  }

  // ── \log_{b} ─────────────────────────────────────────────────────────────

  static String _expandLogBase(String s) {
    final buf = StringBuffer();
    int i = 0;
    while (i < s.length) {
      if (s.startsWith(r'\log_', i)) {
        i += 5; // skip \log_
        while (i < s.length && s[i] == ' ') i++;
        // Extract base (braced or single char)
        String base;
        if (i < s.length && s[i] == '{') {
          final (b, after) = _extractBraces(s, i);
          base = b.trim();
          i = after;
        } else if (i < s.length) {
          base = s[i++];
        } else {
          base = '';
        }
        while (i < s.length && s[i] == ' ') i++;
        // Extract argument: paren-delimited or brace-delimited
        String? arg;
        if (i < s.length && s[i] == '(') {
          final (a, after) = _extractParens(s, i);
          arg = _expandLogBase(a);
          i = after;
        } else if (i < s.length && s[i] == '{') {
          final (a, after) = _extractBraces(s, i);
          arg = _expandLogBase(a);
          i = after;
        }
        if (arg != null) {
          if (base == '10') {
            buf.write('log10($arg)');
          } else if (base == 'e') {
            buf.write('log($arg)');
          } else if (base == '2') {
            buf.write('log2($arg)');
          } else if (base.isNotEmpty) {
            buf.write('logb($base,$arg)');
          } else {
            buf.write('log10($arg)');
          }
        } else {
          // No argument captured — emit a named command for _replaceCommands
          if (base == '10') {
            buf.write(r'\log');
          } else if (base == 'e') {
            buf.write(r'\ln');
          } else if (base == '2') {
            buf.write('log2');
          } else {
            buf.write(r'\log');
          }
        }
      } else {
        buf.write(s[i++]);
      }
    }
    return buf.toString();
  }

  // ── \frac ────────────────────────────────────────────────────────────────

  static String _expandFrac(String s) {
    final buf = StringBuffer();
    int i = 0;
    while (i < s.length) {
      if (s.startsWith(r'\frac', i)) {
        i += 5;
        while (i < s.length && s[i] == ' ') i++;
        final (num, afterNum) = _extractBraces(s, i);
        i = afterNum;
        while (i < s.length && s[i] == ' ') i++;
        final (den, afterDen) = _extractBraces(s, i);
        i = afterDen;
        buf.write('(${_expandFrac(num)})/(${_expandFrac(den)})');
      } else {
        buf.write(s[i++]);
      }
    }
    return buf.toString();
  }

  // ── \sqrt ────────────────────────────────────────────────────────────────

  static String _expandSqrt(String s) {
    final buf = StringBuffer();
    int i = 0;
    while (i < s.length) {
      if (s.startsWith(r'\sqrt', i)) {
        i += 5;
        while (i < s.length && s[i] == ' ') i++;
        double? nthRoot;
        if (i < s.length && s[i] == '[') {
          final close = s.indexOf(']', i);
          if (close != -1) {
            nthRoot = double.tryParse(s.substring(i + 1, close));
            i = close + 1;
          }
        }
        while (i < s.length && s[i] == ' ') i++;
        final (content, end) = _extractBraces(s, i);
        i = end;
        final inner = _expandSqrt(content);
        buf.write(nthRoot != null && nthRoot != 2
            ? '($inner)^(1/$nthRoot)'
            : 'sqrt($inner)');
      } else {
        buf.write(s[i++]);
      }
    }
    return buf.toString();
  }

  // ── superscripts ─────────────────────────────────────────────────────────

  static String _expandSuperscript(String s) =>
      s.replaceAllMapped(RegExp(r'\^\{([^{}]*)\}'), (m) => '^(${m.group(1)})');

  // ── subscripts ───────────────────────────────────────────────────────────

  static String _removeSubscripts(String s) => s
      .replaceAll(RegExp(r'_\{[^{}]*\}'), '')
      .replaceAll(RegExp(r'_[a-zA-Z0-9]'), '');

  // ── named commands ────────────────────────────────────────────────────────

  static String _replaceCommands(String s) => s
      .replaceAll(r'\arcsin', 'asin')
      .replaceAll(r'\arccos', 'acos')
      .replaceAll(r'\arctan', 'atan')
      .replaceAll(r'\ln', 'log')
      // \log10 / \log2 may be emitted by _expandLogBase — handle before \log
      .replaceAll(r'\log10', 'log10')
      .replaceAll(r'\log2', 'log2')
      .replaceAll(r'\log', 'log10')
      .replaceAll(r'\sin', 'sin')
      .replaceAll(r'\cos', 'cos')
      .replaceAll(r'\tan', 'tan')
      .replaceAll(r'\exp', 'exp')
      .replaceAll(r'\cdot', '*')
      .replaceAll(r'\times', '*')
      .replaceAll(r'\div', '/')
      .replaceAll(r'\pi', 'pi')
      .replaceAll(r'\geq', '>=')
      .replaceAll(r'\leq', '<=')
      .replaceAll(r'\neq', '!=')
      .replaceAll(r'\gt', '>')
      .replaceAll(r'\lt', '<');

  // ── implicit multiplication ───────────────────────────────────────────────

  static String _addImplicitMultiplication(String s) {
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      buf.write(s[i]);
      if (i + 1 >= s.length) continue;
      final curr = s[i];
      final next = s[i + 1];

      if (_isDigit(curr) && (_isLetter(next) || next == '(')) {
        buf.write('*');
      } else if (curr == ')' && (next == '(' || _isLetter(next) || _isDigit(next))) {
        buf.write('*');
      } else if (_isLetter(curr) && next == '(') {
        int start = i;
        while (start > 0 && _isLetter(s[start - 1])) start--;
        if (!_knownFunctions.contains(s.substring(start, i + 1))) {
          buf.write('*');
        }
      }
    }
    return buf.toString();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}
