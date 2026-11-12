import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/analytics/domain/analytics.dart';
import 'package:evofit/features/analytics/domain/body.dart';
import 'package:evofit/features/analytics/presentation/body_map.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  void Function(FakeAuthServer server)? setUp,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo');
  setUp?.call(server);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        httpClientAdapterProvider.overrideWithValue(server.adapter),
        draftStorageProvider.overrideWithValue(InMemoryDraftStorage()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage('salvo')),
      ],
      child: const EvoFitApp(),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openBody(WidgetTester tester) async {
  await _scrollTo(tester, find.text('Meu Corpo'));
  await tester.tap(find.text('Meu Corpo'));
  await tester.pumpAndSettle();
}

BodyMap _map(WidgetTester tester) =>
    tester.widget<BodyMap>(find.byKey(const ValueKey('body-map')));

/// Toca no ponto [point] do desenho (coordenadas da caixa de 200 x 440).
Future<void> _tapMap(WidgetTester tester, Offset point) async {
  final rect = tester.getRect(find.byKey(const ValueKey('body-map')));
  final t = bodyMapTransform(rect.size);
  await tester.tapAt(rect.topLeft + t.offset + point * t.scale);
  await tester.pumpAndSettle();
}

String _query(AnalyticsPeriod period) =>
    'from=${apiDate(period.from)}&to=${apiDate(period.to)}';

void _withData(FakeAuthServer server) {
  server
    ..bodyPerWeek = {
      'chest': 2.5,
      'triceps': 7,
      'delts': 13,
      'abs': 0.47,
      'quads': 3,
      'glutes': 3,
      'hamstrings': 1,
      'lats': 4,
      'traps': 1,
      'biceps': 2,
      'forearms': 1,
      'obliques': 0.5,
    }
    ..muscleDetails = {
      'chest': {
        'methodology_version': 'v2',
        'from_date': '2026-10-06',
        'to_date': '2026-11-04',
        'period_days': 30,
        'notice': FakeAuthServer.bodyNotice,
        'muscle': FakeAuthServer.muscleOut('chest', 2.5),
        'exercises': [
          {
            'exercise_id': 'supino',
            'name': 'Supino reto com barra',
            'role': 'primary',
            'weighted_sets': 8.5,
            'sets': 8,
            'best_load_kg': 62.5,
          },
          {
            'exercise_id': 'flexao',
            'name': 'Flexão de braço',
            'role': 'primary',
            'weighted_sets': 2.21,
            'sets': 3,
            'best_load_kg': null,
          },
        ],
        'loads': [
          {'day': '2026-10-28', 'exercise_id': 'supino', 'best_load_kg': 62.5},
          {'day': '2026-10-21', 'exercise_id': 'supino', 'best_load_kg': 60},
        ],
        'previous': {
          'from_date': '2026-09-06',
          'to_date': '2026-10-05',
          'weighted_sets_per_week': 2,
          'frequency': 2,
          'band': 'low',
          'difference': 0.5,
          'percent': 25.0,
        },
      },
    };
}

void main() {
  testWidgets(
    'o mapa pinta cada músculo pela faixa da API e mostra a legenda',
    (tester) async {
      final server = await _pumpSignedIn(tester, setUp: _withData);
      await _openBody(tester);

      expect(
        server.analyticsQueries.last,
        'muscles?${_query(AnalyticsPeriod.options[1])}',
      );
      final bands = _map(tester).bands;
      expect(bands['chest'], StimulusBand.low);
      expect(bands['triceps'], StimulusBand.mid);
      expect(bands['delts'], StimulusBand.high);
      // v2: um pouco de estímulo já é "baixo"; só o zero fica cinza.
      expect(bands['abs'], StimulusBand.low);
      expect(bands['calves'], StimulusBand.none);
      expect(_map(tester).view, BodyView.front);

      expect(find.text('Sem estímulo: 0'), findsOneWidget);
      expect(find.text('Baixo: menos de 6'), findsOneWidget);
      expect(find.text('Moderado: 6 a 12'), findsOneWidget);
      expect(find.text('Alto: 12 ou mais'), findsOneWidget);
      expect(find.textContaining('não diagnóstico'), findsOneWidget);
      expect(find.textContaining('Metodologia v2'), findsOneWidget);

      await _scrollTo(tester, find.textContaining('Sem nenhuma série'));
      expect(
        find.text('Sem nenhuma série em 30 dias: Panturrilhas.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('com todos treinados, aponta os de menor estímulo e o valor', (
    tester,
  ) async {
    await _pumpSignedIn(
      tester,
      setUp: (server) {
        _withData(server);
        server.bodyPerWeek = {...server.bodyPerWeek, 'calves': 0.5, 'abs': 0.5};
      },
    );
    await _openBody(tester);
    await _scrollTo(tester, find.textContaining('Com menos estímulo'));
    expect(
      find.text(
        'Com menos estímulo: Abdômen, Oblíquos e Panturrilhas '
        '(0,5 séries/semana).',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'tocar no peito abre o detalhe com exercícios, cargas e comparação',
    (tester) async {
      final server = await _pumpSignedIn(tester, setUp: _withData);
      await _openBody(tester);

      await _tapMap(tester, const Offset(80, 100)); // peito, lado esquerdo
      expect(
        server.analyticsQueries.last,
        'chest?${_query(AnalyticsPeriod.options[1])}&compare=previous',
      );
      expect(_map(tester).selected, 'chest');
      expect(find.text('Peito'), findsWidgets);
      expect(find.text('2,5 séries/semana · 10,71 em 30 dias'), findsOneWidget);
      expect(
        find.text('Treinado em 2 dias · 1200 kg de volume'),
        findsOneWidget,
      );
      expect(
        find.text('+0,5 séries/semana (+25%) vs. 30 dias anteriores'),
        findsOneWidget,
      );
      expect(find.text('Supino reto com barra'), findsOneWidget);
      expect(
        find.text(
          'principal · 8 séries · 8,5 ponderadas · maior carga 62,5 kg',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Cargas: 60 kg'), findsOneWidget);
      expect(
        find.text('principal · 3 séries · 2,21 ponderadas'),
        findsOneWidget,
      );

      // Fechar o detalhe tira a seleção do mapa.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(_map(tester).selected, isNull);
    },
  );

  testWidgets('Costas mostra os músculos de trás; a lista leva ao lado certo', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester, setUp: _withData);
    await _openBody(tester);

    // Tocar fora do corpo não abre nada.
    await _tapMap(tester, const Offset(10, 10));
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('Costas'));
    await tester.pumpAndSettle();
    expect(_map(tester).view, BodyView.back);
    await _tapMap(tester, const Offset(49, 136)); // tríceps esquerdo
    expect(server.analyticsQueries.last, startsWith('triceps?'));
    expect(find.text('Treinado em 2 dias · 1200 kg de volume'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Frente'));
    await tester.pumpAndSettle();
    // Panturrilhas só aparecem de costas: abrir pela lista vira o mapa.
    await _scrollTo(tester, find.text('Panturrilhas'));
    await tester.tap(find.text('Panturrilhas'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nenhuma série para este músculo em 30 dias.'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(_map(tester).view, BodyView.back);
  });

  testWidgets('sem treinos no período, o mapa fica cinza e explica', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openBody(tester);

    expect(_map(tester).bands.values.toSet(), {StimulusBand.none});
    await _scrollTo(tester, find.textContaining('Nenhuma série de musculação'));

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 dias'));
    await tester.pumpAndSettle();
    expect(
      server.analyticsQueries.last,
      'muscles?${_query(AnalyticsPeriod.options.first)}',
    );
  });

  test('cada músculo do catálogo tem forma em cada lado em que aparece', () {
    for (final (id, _, view) in FakeAuthServer.muscleCatalog) {
      for (final side in BodyView.values) {
        final shown = view == 'both' || view == side.name;
        expect(musclesOf(side).containsKey(id), shown, reason: '$id em $side');
      }
    }
    // As formas não se sobrepõem no ponto central de cada uma.
    for (final side in BodyView.values) {
      final shapes = musclesOf(side);
      for (final MapEntry(:key, :value) in shapes.entries) {
        final hits = shapes.entries
            .where((e) => e.value.contains(value.getBounds().center))
            .map((e) => e.key)
            .toList();
        expect(hits.length, lessThanOrEqualTo(1), reason: '$key: $hits');
      }
    }
  });

  test('faixas descritas e períodos escolhidos', () {
    expect(const BandRange(0, 0).describe(), '0');
    expect(const BandRange(0, 0.5).describe(), 'menos de 0,5');
    expect(const BandRange(0.5, 6).describe(), '0,5 a 6');
    expect(const BandRange(12, null).describe(), '12 ou mais');

    final period = AnalyticsPeriod.range(
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 31, 15),
    );
    expect(period.days, 31);
    expect(period.isCustom, isTrue);
    expect(apiDate(period.from), '2026-10-01');
    expect(apiDate(period.to), '2026-10-31');
    expect(apiDate(period.previousTo), '2026-09-30');
    expect(apiDate(period.previousFrom), '2026-08-31');
    expect(
      period,
      AnalyticsPeriod.range(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
    );
    expect(period == const AnalyticsPeriod(31), isFalse);
  });
}
