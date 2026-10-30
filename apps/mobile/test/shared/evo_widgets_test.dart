import 'package:evofit/app/theme/app_theme.dart';
import 'package:evofit/shared/widgets/evo_button.dart';
import 'package:evofit/shared/widgets/evo_state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('EvoButton em carregamento não aceita toques', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        EvoButton(label: 'Salvar', isLoading: true, onPressed: () => taps++),
      ),
    );

    expect(find.text('Salvar'), findsNothing);
    expect(find.bySemanticsLabel('Carregando'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
  });

  testWidgets('EvoButton tem área de toque mínima de 48dp', (tester) async {
    await tester.pumpWidget(_host(EvoButton(label: 'Ok', onPressed: () {})));

    final size = tester.getSize(find.byType(FilledButton));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('EvoErrorView chama onRetry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        EvoErrorView(
          title: 'Falhou',
          message: 'Detalhe',
          onRetry: () => retries++,
        ),
      ),
    );

    await tester.tap(find.text('Tentar novamente'));
    expect(retries, 1);
  });

  testWidgets('EvoEmptyView sem ação não mostra botão', (tester) async {
    await tester.pumpWidget(
      _host(const EvoEmptyView(title: 'Nada aqui', message: 'Ainda.')),
    );

    expect(find.text('Nada aqui'), findsOneWidget);
    expect(find.byType(EvoButton), findsNothing);
  });

  testWidgets('EvoEmptyView com ação executa o callback', (tester) async {
    var created = false;
    await tester.pumpWidget(
      _host(
        EvoEmptyView(
          title: 'Nenhuma ficha',
          message: 'Crie a primeira.',
          actionLabel: 'Criar ficha',
          onAction: () => created = true,
        ),
      ),
    );

    await tester.tap(find.text('Criar ficha'));
    expect(created, isTrue);
  });

  testWidgets('EvoLoadingView respeita redução de movimento', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(const EvoLoadingView()),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(EvoLoadingView),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Carregando'), findsOneWidget);
  });
}
