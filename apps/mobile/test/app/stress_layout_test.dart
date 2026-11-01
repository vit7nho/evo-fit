import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_server.dart';

/// Pior caso de layout: tela estreita (320dp), fonte do sistema em 200%, nomes e
/// e-mails longos e o vocabulário completo da API. Qualquer estouro de layout
/// (RenderFlex overflow etc.) reprova o teste.

const _longName = 'Maria Eduarda Albuquerque de Vasconcelos Cavalcanti';
const _longEmail =
    'maria.eduarda.albuquerque.vasconcelos.cavalcanti@empresa-com-nome-longo.com.br';

/// Cópia do vocabulário de services/api/app/modules/users/vocabulary.py.
const _fullOptions = <String, Object>{
  'objectives': [
    {'code': 'gain_muscle', 'label': 'Ganhar massa muscular'},
    {'code': 'lose_weight', 'label': 'Emagrecer'},
    {'code': 'maintain', 'label': 'Manter a forma'},
    {'code': 'run', 'label': 'Correr melhor'},
    {'code': 'walk_habit', 'label': 'Criar o hábito de caminhar'},
    {'code': 'general_health', 'label': 'Saúde geral'},
  ],
  'modalities': [
    {'code': 'strength', 'label': 'Musculação'},
    {'code': 'run', 'label': 'Corrida'},
    {'code': 'walk', 'label': 'Caminhada'},
    {'code': 'cycle', 'label': 'Ciclismo'},
    {'code': 'swim', 'label': 'Natação'},
    {'code': 'functional', 'label': 'Funcional'},
  ],
  'equipment': [
    {'code': 'gym', 'label': 'Academia completa'},
    {'code': 'dumbbells', 'label': 'Halteres'},
    {'code': 'barbell', 'label': 'Barra e anilhas'},
    {'code': 'kettlebell', 'label': 'Kettlebell'},
    {'code': 'bands', 'label': 'Elásticos'},
    {'code': 'pull_up_bar', 'label': 'Barra fixa'},
    {'code': 'bodyweight', 'label': 'Só o peso do corpo'},
    {'code': 'treadmill', 'label': 'Esteira'},
    {'code': 'bike', 'label': 'Bicicleta'},
    {'code': 'pool', 'label': 'Piscina'},
  ],
  'dietary_preferences': [
    {'code': 'vegetarian', 'label': 'Vegetariana'},
    {'code': 'vegan', 'label': 'Vegana'},
    {'code': 'lactose_free', 'label': 'Sem lactose'},
    {'code': 'gluten_free', 'label': 'Sem glúten'},
  ],
  'limitation_tags': [
    {'code': 'knee', 'label': 'Joelho'},
    {'code': 'lower_back', 'label': 'Lombar'},
    {'code': 'shoulder', 'label': 'Ombro'},
    {'code': 'neck', 'label': 'Pescoço'},
    {'code': 'wrist', 'label': 'Punho'},
    {'code': 'hip', 'label': 'Quadril'},
    {'code': 'ankle', 'label': 'Tornozelo'},
    {'code': 'cardiac_condition_reported', 'label': 'Condição cardíaca'},
    {'code': 'hypertension_reported', 'label': 'Pressão alta'},
  ],
  'experience_levels': [
    {'code': 'beginner', 'label': 'Iniciante'},
    {'code': 'intermediate', 'label': 'Intermediário'},
    {'code': 'advanced', 'label': 'Avançado'},
  ],
  'unit_systems': [
    {'code': 'metric', 'label': 'Métrico (kg, km)'},
    {'code': 'imperial', 'label': 'Imperial (lb, mi)'},
  ],
  'sex_for_calculations': [
    {'code': 'female', 'label': 'Feminino'},
    {'code': 'male', 'label': 'Masculino'},
    {'code': 'unspecified', 'label': 'Prefiro não informar'},
  ],
};

List<String> _codes(String key) => [
  for (final o in _fullOptions[key]! as List) (o as Map)['code'] as String,
];

Map<String, Object?> _maximalProfile() => {
  ...FakeAuthServer.onboardedProfile(),
  'display_name': _longName,
  'primary_objective': 'walk_habit',
  'secondary_objectives': _codes('objectives')
      .where((c) => c != 'walk_habit')
      .toList(),
  'preferred_modalities': _codes('modalities'),
  'experience_level': 'intermediate',
  'equipment': _codes('equipment'),
  'limitation_tags': _codes('limitation_tags'),
  'limitations_note': 'Dor ' * 120,
  'weekly_availability': {'days_per_week': 7, 'minutes_per_session': 300},
};

/// Prepara a tela de pior caso.
void _worstCaseScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320 * 3, 640 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<FakeAuthServer> _pump(
  WidgetTester tester, {
  Map<String, Object?>? profile,
  List<Map<String, Object?>> goals = const [],
  bool signedIn = true,
}) async {
  final server = FakeAuthServer(validRefreshToken: signedIn ? 'salvo' : null)
    ..accountEmail = _longEmail
    ..profileOptions = _fullOptions
    ..consents.add('health_data');
  if (profile != null) server.profile = profile;
  server.goals = [...goals];
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        httpClientAdapterProvider.overrideWithValue(server.adapter),
        tokenStorageProvider.overrideWithValue(
          InMemoryTokenStorage(signedIn ? 'salvo' : null),
        ),
      ],
      child: const EvoFitApp(),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

Future<void> _back(WidgetTester tester) async {
  // pageBack() procura a dica "Back"; em pt-BR o botão diz "Voltar".
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('login e cadastro', (tester) async {
    _worstCaseScreen(tester);
    await _pump(tester, signedIn: false);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      _longEmail,
    );
    final enter = find.widgetWithText(FilledButton, 'Entrar');
    await tester.ensureVisible(enter);
    await tester.pumpAndSettle();
    await tester.tap(enter);
    await tester.pumpAndSettle();

    final create = find.widgetWithText(OutlinedButton, 'Criar conta');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Criar conta');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final terms = find.text('Ler o resumo dos termos');
    await tester.ensureVisible(terms);
    await tester.pumpAndSettle();
    await tester.tap(terms);
    await tester.pumpAndSettle();
    expect(find.text('Resumo dos termos'), findsOneWidget);
  });

  testWidgets('início, perfil e cada seção com o perfil máximo', (
    tester,
  ) async {
    _worstCaseScreen(tester);
    await _pump(tester, profile: _maximalProfile());

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();

    const sections = ['Dados pessoais', 'Objetivos', 'Atividades', 'Rotina'];
    for (final section in [...sections, 'Saúde']) {
      // A lista é preguiçosa: rola até o cartão existir e aparecer.
      final card = find.text(section).first;
      await tester.scrollUntilVisible(
        find.text(section),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Salvar');
      expect(save, findsOneWidget, reason: section);
      await _back(tester);
    }

    final logout = find.widgetWithText(OutlinedButton, 'Sair da conta');
    await tester.scrollUntilVisible(
      logout,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(find.text('Sair da conta?'), findsOneWidget);
  });

  testWidgets('onboarding marcando tudo', (tester) async {
    _worstCaseScreen(tester);
    await _pump(
      tester,
      profile: {...FakeAuthServer.newProfile(), 'display_name': _longName},
    );

    Future<void> tapAll(List<String> labels) async {
      for (final label in labels) {
        final finder = find.text(label).last;
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
    }

    Future<void> next(String label) async {
      final button = find.widgetWithText(FilledButton, label);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    // Continuar sem escolher mostra o aviso no rodapé.
    await next('Continuar');
    expect(
      find.textContaining('Escolha um objetivo principal'),
      findsOneWidget,
    );
    await tapAll([
      'Criar o hábito de caminhar',
      'Saúde geral',
      'Correr melhor',
    ]);
    await next('Continuar');
    await tapAll(['Musculação', 'Natação', 'Funcional', 'Intermediário']);
    await next('Continuar');
    final days = find.bySemanticsLabel('5 dias por semana');
    await tester.ensureVisible(days);
    await tester.pumpAndSettle();
    await tester.tap(days);
    await tester.pumpAndSettle();
    await tapAll(['60 min', 'Só o peso do corpo', 'Barra e anilhas']);
    await next('Continuar');
    await tapAll(['Condição cardíaca', 'Pressão alta', 'Tornozelo']);
    await next('Concluir');
    expect(find.textContaining('Olá, Maria'), findsOneWidget);
  });

  testWidgets('metas: lista, edição e formulário novo', (tester) async {
    _worstCaseScreen(tester);
    final server = FakeAuthServer.strengthGoal();
    await _pump(
      tester,
      profile: _maximalProfile(),
      goals: [
        {
          ...server,
          'title':
              'Levantar o dobro do meu peso corporal no levantamento terra',
          'summary': 'Levantamento terra sumô com pausa: 182,5 kg × 3',
          'target_date': '2026-01-15',
          'priority': 1,
        },
      ],
    );

    final goals = find.text('Metas');
    await tester.scrollUntilVisible(
      goals,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(goals);
    await tester.pumpAndSettle();
    expect(find.textContaining('Prazo vencido'), findsOneWidget);

    await tester.tap(find.textContaining('Levantar o dobro'));
    await tester.pumpAndSettle();
    final delete = find.text('Excluir meta');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await _back(tester);

    final create = find.widgetWithText(FilledButton, 'Nova meta');
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Força'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Criar meta');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Dê um nome para a meta.'), findsOneWidget);
  });

  testWidgets('exercícios: biblioteca, detalhe e formulário', (tester) async {
    _worstCaseScreen(tester);
    await _pump(tester, profile: _maximalProfile());

    final library = find.text('Exercícios');
    await tester.scrollUntilVisible(
      library,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(library);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agachamento livre'));
    await tester.pumpAndSettle();
    await _back(tester);

    final create = find.widgetWithText(OutlinedButton, 'Criar exercício');
    await tester.tap(create);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Criar exercício');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Dê um nome ao exercício.'), findsOneWidget);
  });
}
