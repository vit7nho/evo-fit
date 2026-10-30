import 'package:flutter/foundation.dart';

/// Dados da conta que a interface usa. Vem de GET /me.
@immutable
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return CurrentUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: profile?['display_name'] as String? ?? '',
    );
  }

  final String id;
  final String email;
  final String displayName;
}
