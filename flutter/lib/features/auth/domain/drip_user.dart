final class DripUser {
  const DripUser({required this.id, required this.email, this.displayName});

  final String id;
  final String email;
  final String? displayName;

  factory DripUser.fromJson(Map<String, dynamic> json) {
    return DripUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
    );
  }
}
