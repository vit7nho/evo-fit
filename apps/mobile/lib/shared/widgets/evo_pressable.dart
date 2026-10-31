import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';

/// Encolhe levemente o filho enquanto o dedo está sobre ele, como nos apps nativos.
///
/// Só observa o ponteiro (não consome o toque): o botão ou o card filho continua
/// tratando o clique e a acessibilidade normalmente. Se o dedo arrasta (rolagem),
/// o filho volta ao tamanho na hora, em vez de ficar encolhido durante o arrasto.
class EvoPressable extends StatefulWidget {
  const EvoPressable({super.key, required this.child, this.enabled = true});

  /// Escala única do app enquanto pressionado (docs/UX_FLOWS.md §4).
  static const pressedScale = 0.97;

  final Widget child;
  final bool enabled;

  @override
  State<EvoPressable> createState() => _EvoPressableState();
}

class _EvoPressableState extends State<EvoPressable> {
  bool _pressed = false;
  Offset? _downAt;

  void _set(bool pressed) {
    if (_pressed != pressed && mounted) setState(() => _pressed = pressed);
  }

  void _up() {
    _downAt = null;
    _set(false);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final active = widget.enabled && !reduceMotion;
    return Listener(
      onPointerDown: active
          ? (event) {
              _downAt = event.position;
              _set(true);
            }
          : null,
      onPointerMove: (event) {
        final start = _downAt;
        if (start != null && (event.position - start).distance > kTouchSlop) {
          _up();
        }
      },
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedScale(
        scale: active && _pressed ? EvoPressable.pressedScale : 1,
        duration: const Duration(milliseconds: 120),
        curve: EvoCurves.standard,
        child: widget.child,
      ),
    );
  }
}
