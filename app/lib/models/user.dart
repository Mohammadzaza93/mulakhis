class UserInfo {
  final int userId;
  final String email;
  final String plan; // free | pro
  final int used;
  final int limit;

  const UserInfo({
    required this.userId,
    required this.email,
    required this.plan,
    required this.used,
    required this.limit,
  });

  bool get isPro => plan == 'pro';
  int get remaining => (limit - used).clamp(0, limit);

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        userId: (j['user_id'] as num).toInt(),
        email: j['email'] as String? ?? '',
        plan: j['plan'] as String? ?? 'free',
        used: (j['used'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 0,
      );
}
