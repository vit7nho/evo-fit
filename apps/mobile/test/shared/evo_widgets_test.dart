import 'package:evofit/app/theme/app_theme.dart';
import 'package:evofit/shared/widgets/evo_button.dart';
import 'package:evofit/shared/widgets/evo_entrance.dart';
import 'package:evofit/shared/widgets/evo_focus_ring.dart';
import 'package:evofit/shared/widgets/evo_form_error.dart';
import 'package:evofit/shared/widgets/evo_state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(find.bySemanticsLabel('Salvar, carregando'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
  });

  testWidgets('EvoButton ocupa a largura toda num pai esticado', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [EvoButton(label: 'Ok', onPressed: () {})],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(FilledButton)).width, 300);
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

    testWidgets('arrastar (rolagem) desfaz o encolhimento na hora', (
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

      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(scale(), 1);
      await gesture.up();
    });

    testWidgets('com redução de movimento, o erro aparece sem animar', (
      tester,
    ) async {
      Widget build(String? message) => MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(EvoFormError(message: message)),
      );
      await tester.pumpWidget(build(null));
      await tester.pumpWidget(build('Falhou.'));
      await tester.pump();

      expect(find.text('Falhou.'), findsOneWidget);
      // Já entrou por inteiro no primeiro quadro: nada de esmaecimento em curso.
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Falhou.'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
    });

    testWidgets('foco pelo teclado desenha o anel no botão', (tester) async {
      await tester.pumpWidget(_host(EvoButton(label: 'Ok', onPressed: () {})));
      Finder ring() => find.descendant(
        of: find.byType(EvoFocusRing),
        matching: find.byType(DecoratedBox),
      );
      expect(ring(), findsNothing);

      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(), findsOneWidget);
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
