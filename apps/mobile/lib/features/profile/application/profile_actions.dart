import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activities/application/activities_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../goals/application/goals_controller.dart';
import '../../plans/application/plans_controller.dart';
import '../data/profile_api.dart';
import '../domain/profile.dart';

/// Gravações do perfil. Cada uma atualiza a conta em memória com a resposta da API,
/// para que todas as telas (e o roteador) vejam o estado novo na hora.
///
/// Lança ApiException em caso de falha; a tela exibe a mensagem.
class ProfileActions {
  const ProfileActions(this._ref);

  final Ref _ref;

  ProfileApi get _api => _ref.read(profileApiProvider);
  AuthController get _auth => _ref.read(authControllerProvider.notifier);

  /// Atualização parcial do perfil (só as chaves enviadas mudam).
  Future<void> save(Map<String, Object?> changes) async {
    _auth.replaceUser(await _api.update(changes));
  }

  /// Concede ou revoga um consentimento. Revogar `health_data` apaga os dados de
  /// saúde no servidor (perfil, metas de peso, FC das atividades, ajustes dos
  /// planos): a conta, as metas, as atividades e os planos são recarregados.
  Future<void> setConsent(String kind, {required bool granted}) async {
    if (granted) {
      await _api.grantConsent(kind);
    } else {
      await _api.revokeConsent(kind);
    }
    _auth.replaceUser(await _api.me());
    if (!granted && kind == ConsentKinds.healthData) {
      _ref
        ..invalidate(goalsProvider)
        ..invalidate(activitiesProvider)
        ..invalidate(plansProvider)
        ..invalidate(planProvider)
        ..invalidate(planTemplatesProvider);
    }
  }

  /// Envia as respostas do onboarding e o marca como concluído.
  ///
  /// O consentimento de saúde vem antes: sem ele, a API recusa os dados de saúde.
  Future<void> completeOnboarding(
    Map<String, Object?> answers, {
    required bool grantHealthData,
  }) async {
    if (grantHealthData) await _api.grantConsent('health_data');
    await save({...answers, 'onboarding_completed': true});
  }
}

final profileActionsProvider = Provider<ProfileActions>(ProfileActions.new);
