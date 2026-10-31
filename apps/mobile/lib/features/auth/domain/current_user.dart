import 'package:flutter/foundation.dart';

import '../../profile/domain/profile.dart';

/// Conta do usuário autenticado: dados, perfil e consentimentos ativos (GET /me).
@immutable
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.email,
    required this.profile,
    this.consents = const {},
  });

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return CurrentUser(
      id: json['id'] as String,
      email: json['email'] as String,
      profile: profile == null
          ? const UserProfile(displayName: '')
          : UserProfile.fromJson(profile),
      consents: {
        for (final c in (json['consents'] as List<dynamic>? ?? const []))
          (c as Map<String, dynamic>)['kind'] as String,
      },
    );
  }

  final String id;
  final String email;
  final UserProfile profile;

  /// Tipos de consentimento ativos (ex.: `health_data`).
  final Set<String> consents;

  String get displayName => profile.displayName;
  bool get needsOnboarding => !profile.onboardingCompleted;
  bool hasConsent(String kind) => consents.contains(kind);
}
