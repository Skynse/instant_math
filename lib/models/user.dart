class User {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final int totalSolved;
  final int dayStreak;
  final int formulasMastered;
  final DateTime joinedAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.totalSolved = 0,
    this.dayStreak = 0,
    this.formulasMastered = 0,
    required this.joinedAt,
  });
}
