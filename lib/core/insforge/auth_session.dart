/// Tokens + user returned by any InsForge auth endpoint (signup/login/refresh).
class AuthSession {
  AuthSession({required this.accessToken, this.refreshToken, required this.user});

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      user: Map<String, dynamic>.from(json['user'] as Map),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final Map<String, dynamic> user;

  String get userId => user['id'] as String;
}
