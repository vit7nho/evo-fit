import 'package:evofit/app/theme/app_theme.dart';
import 'package:evofit/shared/widgets/evo_button.dart';
import 'package:evofit/shared/widgets/evo_entrance.dart';
import 'package:evofit/shared/widgets/evo_form_error.dart';
import 'package:evofit/shared/widgets/evo_state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
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

  group('movimento', () {
    double opacityOf(WidgetTester tester, Finder finder) => tester
        .widget<Opacity>(
          find.ancestor(of: finder, matching: find.byType(Opacity)).first,
        )
        .opacity;

    testWidgets('EvoEntrance começa invisível e termina visível', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          EvoEntrance(delay: EvoEntrance.stagger(2), child: const Text('Oi')),
        ),
      );
      expect(opacityOf(tester, find.text('Oi')), 0);

      await tester.pumpAndSettle();
      expect(opacityOf(tester, find.text('Oi')), 1);
    });

    testWidgets('EvoEntrance aparece na hora com redução de movimento', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(
            EvoEntrance(delay: EvoEntrance.stagger(5), child: const Text('Oi')),
          ),
        ),
      );
      await tester.pump();
      expect(opacityOf(tester, find.text('Oi')), 1);
    });

    testWidgets('EvoButton encolhe ao ser pressionado e volta ao soltar', (
      tester,
    ) async {
      await tester.pumpWidget(_host(EvoButton(label: 'Ok', onPressed: () {})));
      double scale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FilledButton)),
      );
      await tester.pump();
      expect(scale(), lessThan(1));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
    });

    testWidgets('EvoFormError sem mensagem não mostra nada', (tester) async {
      await tester.pumpWidget(_host(const EvoFormError(message: null)));
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

      await tester.pumpWidget(_host(const EvoFormError(message: 'Falhou')));
      await tester.pumpAndSettle();
      expect(find.text('Falhou'), findsOneWidget);
    });
  });
}
