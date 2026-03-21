class SolutionStepModel {
  final int stepNumber;
  final String title;
  final String description;
  final String? latexFormula;
  final String? explanation;

  SolutionStepModel({
    required this.stepNumber,
    required this.title,
    required this.description,
    this.latexFormula,
    this.explanation,
  });
}
