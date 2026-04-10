import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import '../theme/theme.dart';

class FinalAnswerCard extends StatelessWidget {
  final String answer;
  final double? numericValue;
  final bool isVerified;

  const FinalAnswerCard({
    super.key,
    required this.answer,
    this.numericValue,
    this.isVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'FINAL ANSWER',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MarkdownBody(
            data: answer,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            builders: {
              'latex': LatexElementBuilder(
                textStyle: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                textScaleFactor: 1.2,
              ),
            },
            extensionSet: md.ExtensionSet(
              [LatexBlockSyntax()],
              [LatexInlineSyntax()],
            ),
          ),
          if (numericValue != null) ...[
            const SizedBox(height: 8),
            Text(
              '≈ ${numericValue!.toStringAsFixed(5)}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
            ),
          ],
          if (isVerified) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.verified, color: AppColors.success, size: 16),
                const SizedBox(width: 4),
                const Text(
                  'Verified Logic',
                  style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
