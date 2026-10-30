import 'dart:async';

import 'package:evofit/app/provider_config.dart';
import 'package:evofit/app/theme/app_theme.dart';
import 'package:evofit/core/network/api_exception.dart';
import 'package:evofit/features/system_status/data/health_repository.dart';
import 'package:evofit/features/system_status/domain/health_status.dart';
import 'package:evofit/features/system_status/presentation/system_status_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositório controlado pelo teste: cada chamada consome a próxima resposta da fila.
class _QueuedHealthRepository implements HealthRepository {
  _QueuedHealthRepository(this._responses);

  final List<Future<HealthStatus> Function()> _responses;
  int calls = 0;

  @override
  Future<HealthStatus> fetch() => _responses[calls++]();
}

const _healthy = HealthStatus(
  databaseOk: true,
  version: '0.1.0',
  environment: 'development',
);

Future<void> _pump(WidgetTester tester, HealthRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [healthRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SystemStatusPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra carregamento e depois "API conectada"', (tester) async {
    final completer = Completer<HealthStatus>();
    await _pump(tester, _QueuedHealthRepository([() => completer.future]));

    expect(find.bySemanticsLabel('Carregando'), findsOneWidget);

    completer.complete(_healthy);
    await tester.pumpAndSettle();

    expect(find.text('API conectada'), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('development'), findsOneWidget);
  });

  testWidgets('banco indisponível mostra erro específico', (tester) async {
    await _pump(
      tester,
      _QueuedHealthRepository([
        () async => const HealthStatus(
          databaseOk: false,
          version: '0.1.0',
          environment: 'development',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Banco de dados indisponível'), findsOneWidget);
    expect(find.text('API conectada'), findsNothing);
  });

  testWidgets('erro de rede permite tentar novamente até conectar', (
    tester,
  ) async {
    final repository = _QueuedHealthRepository([
      () async => throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Não foi possível conectar ao servidor.',
      ),
      () async => _healthy,
    ]);
    await _pump(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('API indisponível'), findsOneWidget);
    expect(find.text('Não foi possível conectar ao servidor.'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('API conectada'), findsOneWidget);
  });
}
