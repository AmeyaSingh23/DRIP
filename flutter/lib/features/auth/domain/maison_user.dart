final class MaisonUser {
  const MaisonUser({required this.id, required this.email, this.displayName});

  final String id;
  final String email;
  final String? displayName;

  factory MaisonUser.fromJson(Map<String, dynamic> json) {
    return MaisonUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
    );
  }
}


