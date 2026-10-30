import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_logo.dart';

/// Esqueleto das telas de entrada (login e cadastro).
///
/// Marca no topo, título grande, subtítulo e o formulário; cada bloco entra em
/// cascata. O conteúdo rola com o teclado aberto e o rodapé fica no fim da tela.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.leading,
    this.footer,
  });

  final String title;
  final String subtitle;

  /// Blocos do formulário; cada um recebe seu atraso na cascata.
  final List<Widget> children;

  /// Substitui a marca no topo (ex.: botão de voltar no cadastro).
  final Widget? leading;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var order = 0;
    Widget enter(Widget child) =>
        EvoEntrance(delay: EvoEntrance.stagger(order++), child: child);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  // spaceBetween com altura mínima = tela: o rodapé fica embaixo sem
                  // IntrinsicHeight, que mede errado durante as animações de tamanho.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: EvoSpace.lg),
                          enter(
                            Align(
                              alignment: Alignment.centerLeft,
                              child: leading ?? const EvoLogo(size: 36),
                            ),
                          ),
                          const SizedBox(height: EvoSpace.x3xl),
                          enter(
                            Text(title, style: theme.textTheme.displayMedium),
                          ),
                          const SizedBox(height: EvoSpace.md),
                          enter(
                            Text(
                              subtitle,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: EvoColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: EvoSpace.x2xl),
                          for (final child in children) enter(child),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: EvoSpace.xl,
                          bottom: EvoSpace.lg,
                        ),
                        child: footer == null ? null : enter(footer!),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Separador "ou" entre a ação principal e a alternativa.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EvoSpace.lg),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EvoSpace.md),
            child: Text('ou', style: Theme.of(context).textTheme.labelSmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
