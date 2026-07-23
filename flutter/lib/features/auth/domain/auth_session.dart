import 'maison_user.dart';

final class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final MaisonUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      user: MaisonUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}


