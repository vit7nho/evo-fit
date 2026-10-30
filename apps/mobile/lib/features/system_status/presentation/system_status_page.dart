import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../data/health_repository.dart';
import '../domain/health_status.dart';

final healthStatusProvider = FutureProvider.autoDispose<HealthStatus>(
  (ref) => ref.watch(healthRepositoryProvider).fetch(),
);

/// Diagnóstico: confirma que o app alcança a API e o banco.
class SystemStatusPage extends ConsumerWidget {
  const SystemStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(healthStatusProvider);
    final theme = Theme.of(context);
    void retry() => ref.invalidate(healthStatusProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: EvoColors.bgBase,
        title: const Text('Status do servidor'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(healthStatusProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(EvoSpace.xl),
            children: [
              Text(
                'Verifica se o app alcança a API e se a API alcança o banco '
                'de dados. Puxe para baixo para atualizar.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: EvoColors.textSecondary,
                ),
              ),
              const SizedBox(height: EvoSpace.xl),
              EvoCard(
                child: AnimatedSwitcher(
                  duration: EvoMotion.base,
                  child: status.when(
                    // Nova tentativa também mostra o carregamento: o toque tem retorno visível.
                    skipLoadingOnRefresh: false,
                    loading: () =>
                        const EvoLoadingView(key: ValueKey('loading')),
                    error: (error, _) => EvoErrorView(
                      key: const ValueKey('error'),
                      title: 'API indisponível',
                      message: error is ApiException
                          ? error.message
                          : 'Erro inesperado ao consultar a API.',
                      onRetry: retry,
                    ),
                    data: (health) => _HealthDetails(
                      key: const ValueKey('data'),
                      health: health,
                      apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
                      onRetry: retry,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthDetails extends StatelessWidget {
  const _HealthDetails({
    super.key,
    required this.health,
    required this.apiBaseUrl,
    required this.onRetry,
  });

  final HealthStatus health;
  final String apiBaseUrl;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!health.databaseOk) {
      return EvoErrorView(
        title: 'Banco de dados indisponível',
        message:
            'A API respondeu, mas não conseguiu acessar o banco. '
            'Verifique se o PostgreSQL está em execução.',
        onRetry: onRetry,
      );
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: EvoColors.success),
            const SizedBox(width: EvoSpace.sm),
            Text('API conectada', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: EvoSpace.md),
        _InfoRow(label: 'Versão', value: health.version),
        _InfoRow(label: 'Ambiente', value: health.environment),
        _InfoRow(label: 'Servidor', value: apiBaseUrl),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: EvoSpace.xs),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
