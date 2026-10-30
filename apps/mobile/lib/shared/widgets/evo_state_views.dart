import 'package:flutter/material.dart';

import '../../app/theme/tokens.g.dart';
import 'evo_button.dart';

/// Esqueleto de carregamento: blocos com pulsação suave no lugar do conteúdo.
class EvoLoadingView extends StatefulWidget {
  const EvoLoadingView({super.key, this.lines = 3});

  final int lines;

  @override
  State<EvoLoadingView> createState() => _EvoLoadingViewState();
}

class _EvoLoadingViewState extends State<EvoLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final blocks = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.lines; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.md),
            child: FractionallySizedBox(
              // Larguras variadas para parecer texto, não uma grade.
              widthFactor: i.isEven ? 1 : 0.6,
              child: Container(
                height: 16,
                decoration: const BoxDecoration(
                  color: EvoColors.bgElevated,
                  borderRadius: BorderRadius.all(
                    Radius.circular(EvoRadius.input),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      label: 'Carregando',
      liveRegion: true,
      child: reduceMotion
          ? blocks
          : FadeTransition(
              opacity: Tween(begin: 0.45, end: 1.0).animate(_controller),
              child: blocks,
            ),
    );
  }
}

/// Estado de erro com mensagem legível e ação de nova tentativa.
class EvoErrorView extends StatelessWidget {
  const EvoErrorView({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _MessageLayout(
      icon: Icons.cloud_off_rounded,
      iconColor: EvoColors.danger,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : EvoButton(
              label: 'Tentar novamente',
              icon: Icons.refresh_rounded,
              variant: EvoButtonVariant.secondary,
              onPressed: onRetry,
            ),
    );
  }
}

/// Estado vazio: explica o que falta e oferece a ação principal.
class EvoEmptyView extends StatelessWidget {
  const EvoEmptyView({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inbox_outlined,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'actionLabel e onAction devem ser informados juntos',
       );

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _MessageLayout(
      icon: icon,
      iconColor: EvoColors.textSecondary,
      title: title,
      message: message,
      action: actionLabel == null
          ? null
          : EvoButton(label: actionLabel!, onPressed: onAction),
    );
  }
}

class _MessageLayout extends StatelessWidget {
  const _MessageLayout({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: iconColor),
        const SizedBox(height: EvoSpace.md),
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: EvoSpace.xs),
        Text(message, style: theme.textTheme.bodyMedium),
        if (action != null) ...[const SizedBox(height: EvoSpace.lg), action!],
      ],
    );
  }
}
