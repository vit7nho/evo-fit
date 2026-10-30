import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';
import '../../app/theme/tokens.g.dart';

/// Entrada suave (sobe alguns pixels e aparece), com atraso para efeito em cascata.
///
/// O atraso faz parte da própria animação (um [Interval]), sem timers: nada fica
/// pendente se a tela fechar antes. Sem animação quando o sistema pede menos movimento.
class EvoEntrance extends StatefulWidget {
  const EvoEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = EvoMotion.slow,
    this.offsetY = 18,
  });

  /// Atraso crescente para uma lista de itens: 0, 60, 120 ms...
  static Duration stagger(int index) => Duration(milliseconds: 60 * index);

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  @override
  State<EvoEntrance> createState() => _EvoEntranceState();
}

class _EvoEntranceState extends State<EvoEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _controller.duration!.inMicroseconds == 0
          ? 0
          : widget.delay.inMicroseconds / _controller.duration!.inMicroseconds,
      1,
      curve: EvoCurves.emphasizedDecelerate,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _progress.value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - _progress.value)),
          child: child,
        ),
      ),
    );
  }
}
