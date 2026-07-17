import 'drip_user.dart';

final class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final DripUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      user: DripUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
