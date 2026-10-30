import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';

/// Encolhe levemente o filho enquanto o dedo está sobre ele, como nos apps nativos.
///
/// Só observa o ponteiro (não consome o toque): o botão ou o card filho continua
/// tratando o clique e a acessibilidade normalmente.
class EvoPressable extends StatefulWidget {
  const EvoPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<EvoPressable> createState() => _EvoPressableState();
}

class _EvoPressableState extends State<EvoPressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed && mounted) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final active = widget.enabled && !reduceMotion;
    return Listener(
      onPointerDown: active ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: active && _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 120),
        curve: EvoCurves.standard,
        child: widget.child,
      ),
    );
  }
}
