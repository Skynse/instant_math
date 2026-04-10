import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import '../theme/theme.dart';

class _FormulaEntry {
  final String name;
  final String latex;
  const _FormulaEntry(this.name, this.latex);
}

class _FormulaCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<_FormulaEntry> formulas;
  const _FormulaCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.formulas,
  });
}

const _categories = [
  _FormulaCategory(
    title: 'Algebra',
    icon: Icons.calculate,
    color: Color(0xFF4A90E2),
    formulas: [
      _FormulaEntry('Quadratic formula', r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}'),
      _FormulaEntry('Difference of squares', r'a^2 - b^2 = (a+b)(a-b)'),
      _FormulaEntry('Perfect square (sum)', r'(a+b)^2 = a^2 + 2ab + b^2'),
      _FormulaEntry('Perfect square (diff)', r'(a-b)^2 = a^2 - 2ab + b^2'),
      _FormulaEntry('Sum of cubes', r'a^3 + b^3 = (a+b)(a^2-ab+b^2)'),
      _FormulaEntry('Difference of cubes', r'a^3 - b^3 = (a-b)(a^2+ab+b^2)'),
    ],
  ),
  _FormulaCategory(
    title: 'Trigonometry',
    icon: Icons.waves,
    color: Color(0xFF7B68EE),
    formulas: [
      _FormulaEntry('Pythagorean identity', r'\sin^2\theta + \cos^2\theta = 1'),
      _FormulaEntry('Tangent identity', r'\tan\theta = \frac{\sin\theta}{\cos\theta}'),
      _FormulaEntry('Sine addition', r'\sin(A \pm B) = \sin A\cos B \pm \cos A\sin B'),
      _FormulaEntry('Cosine addition', r'\cos(A \pm B) = \cos A\cos B \mp \sin A\sin B'),
      _FormulaEntry('Double angle (sin)', r'\sin 2\theta = 2\sin\theta\cos\theta'),
      _FormulaEntry('Double angle (cos)', r'\cos 2\theta = \cos^2\theta - \sin^2\theta'),
      _FormulaEntry('Law of sines', r'\frac{a}{\sin A} = \frac{b}{\sin B} = \frac{c}{\sin C}'),
      _FormulaEntry('Law of cosines', r'c^2 = a^2 + b^2 - 2ab\cos C'),
    ],
  ),
  _FormulaCategory(
    title: 'Differentiation',
    icon: Icons.trending_up,
    color: Color(0xFF20B2AA),
    formulas: [
      _FormulaEntry('Power rule', r'\frac{d}{dx}[x^n] = nx^{n-1}'),
      _FormulaEntry('Product rule', r"\frac{d}{dx}[uv] = u'v + uv'"),
      _FormulaEntry('Quotient rule', r"\frac{d}{dx}\left[\frac{u}{v}\right] = \frac{u'v - uv'}{v^2}"),
      _FormulaEntry('Chain rule', r"\frac{d}{dx}[f(g(x))] = f'(g(x))\cdot g'(x)"),
      _FormulaEntry('Derivative of sin', r'\frac{d}{dx}[\sin x] = \cos x'),
      _FormulaEntry('Derivative of cos', r'\frac{d}{dx}[\cos x] = -\sin x'),
      _FormulaEntry('Derivative of exp', r'\frac{d}{dx}[e^x] = e^x'),
      _FormulaEntry('Derivative of ln', r'\frac{d}{dx}[\ln x] = \frac{1}{x}'),
    ],
  ),
  _FormulaCategory(
    title: 'Integration',
    icon: Icons.area_chart,
    color: Color(0xFFFF7F50),
    formulas: [
      _FormulaEntry('Power rule', r'\int x^n\,dx = \frac{x^{n+1}}{n+1} + C,\quad n\neq-1'),
      _FormulaEntry('Integral of 1/x', r'\int \frac{1}{x}\,dx = \ln|x| + C'),
      _FormulaEntry('Integral of exp', r'\int e^x\,dx = e^x + C'),
      _FormulaEntry('Integral of sin', r'\int \sin x\,dx = -\cos x + C'),
      _FormulaEntry('Integral of cos', r'\int \cos x\,dx = \sin x + C'),
      _FormulaEntry('FTC', r'\int_a^b f(x)\,dx = F(b) - F(a)'),
      _FormulaEntry('Integration by parts', r'\int u\,dv = uv - \int v\,du'),
    ],
  ),
  _FormulaCategory(
    title: 'Limits',
    icon: Icons.linear_scale,
    color: Color(0xFFDAA520),
    formulas: [
      _FormulaEntry('Sine limit', r'\lim_{x \to 0}\frac{\sin x}{x} = 1'),
      _FormulaEntry('e definition', r'\lim_{n \to \infty}\left(1+\frac{1}{n}\right)^n = e'),
      _FormulaEntry("L'Hopital's rule", r"\lim_{x \to a}\frac{f(x)}{g(x)} = \lim_{x \to a}\frac{f'(x)}{g'(x)}"),
      _FormulaEntry('Squeeze theorem', r'g(x) \leq f(x) \leq h(x) \Rightarrow \lim f = \lim g = \lim h'),
    ],
  ),
];

class FormulasScreen extends StatefulWidget {
  const FormulasScreen({super.key});

  @override
  State<FormulasScreen> createState() => _FormulasScreenState();
}

class _FormulasScreenState extends State<FormulasScreen> {
  int _expanded = 0;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _categories
        : _categories
            .map((c) => _FormulaCategory(
                  title: c.title,
                  icon: c.icon,
                  color: c.color,
                  formulas: c.formulas
                      .where((f) =>
                          f.name.toLowerCase().contains(_search.toLowerCase()) ||
                          f.latex.toLowerCase().contains(_search.toLowerCase()))
                      .toList(),
                ))
            .where((c) => c.formulas.isNotEmpty)
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('MathWizard')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REFERENCE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Formula Sheet',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search formulas...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final cat = filtered[i];
                final isOpen = _search.isNotEmpty || _expanded == i;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => setState(() => _expanded = isOpen ? -1 : i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: cat.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(cat.icon, color: cat.color, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  cat.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                '${cat.formulas.length}',
                                style: TextStyle(
                                  color: cat.color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isOpen ? Icons.expand_less : Icons.expand_more,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isOpen) ...[
                        const Divider(height: 1),
                        ...cat.formulas.map((f) => _FormulaRow(entry: f, accent: cat.color)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FormulaRow extends StatelessWidget {
  final _FormulaEntry entry;
  final Color accent;

  const _FormulaRow({required this.entry, required this.accent});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  MarkdownBody(
                    data: '\$\$${entry.latex}\$\$',
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    builders: {
                      'latex': LatexElementBuilder(
                        textStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        textScaleFactor: 1.0,
                      ),
                    },
                    extensionSet: md.ExtensionSet(
                      [LatexBlockSyntax()],
                      [LatexInlineSyntax()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: MarkdownBody(
                data: '\$\$${entry.latex}\$\$',
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(fontSize: 14, color: accent),
                ),
                builders: {
                  'latex': LatexElementBuilder(
                    textStyle: TextStyle(fontSize: 18, color: accent),
                    textScaleFactor: 1.1,
                  ),
                },
                extensionSet: md.ExtensionSet(
                  [LatexBlockSyntax()],
                  [LatexInlineSyntax()],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
