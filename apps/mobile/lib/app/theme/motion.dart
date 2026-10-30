import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// Curvas "emphasized" do Material 3: saída rápida e chegada suave.
abstract final class EvoCurves {
  static const emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);
  static const standard = Cubic(0.2, 0, 0, 1);
}

/// Transição entre telas: a nova sobe levemente enquanto aparece; a anterior
/// recua um pouco e esmaece. Sem animação quando o sistema pede menos movimento.
class EvoPageTransition extends StatelessWidget {
  const EvoPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  static final _enterOffset = Tween(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );
  static final _exitScale = Tween<double>(begin: 1, end: 0.97);
  static final _exitFade = Tween<double>(begin: 1, end: 0.6);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;

    final enter = CurvedAnimation(
      parent: animation,
      curve: EvoCurves.emphasizedDecelerate,
      reverseCurve: EvoCurves.emphasizedAccelerate,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: EvoCurves.standard,
    );

    return FadeTransition(
      opacity: _exitFade.animate(exit),
      child: ScaleTransition(
        scale: _exitScale.animate(exit),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0, 0.6, curve: Curves.easeOut),
          ),
          child: SlideTransition(
            position: _enterOffset.animate(enter),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Usada pelas rotas do Navigator (diálogos de tela cheia, rotas sem go_router).
class EvoPageTransitionsBuilder extends PageTransitionsBuilder {
  const EvoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => EvoMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => EvoPageTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );
}
