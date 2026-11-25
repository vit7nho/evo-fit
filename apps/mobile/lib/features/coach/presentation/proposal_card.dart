import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../application/coach_controller.dart';
import '../domain/coach.dart';

/// Proposta da IA dentro da conversa (4.6): o que muda, o motivo e a decisão.
/// Nada é alterado até a pessoa tocar em Confirmar.
class ProposalCard extends ConsumerStatefulWidget {
  const ProposalCard({
    super.key,
    required this.conversationId,
    required this.proposal,
  });

  final String conversationId;
  final Proposal proposal;

  @override
  ConsumerState<ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends ConsumerState<ProposalCard> {
  bool? _deciding; // true: confirmando; false: recusando

  Future<void> _decide({required bool accept}) async {
    setState(() => _deciding = accept);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(chatProvider(widget.conversationId).notifier)
          .decide(widget.proposal, accept: accept);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            updated.status == ProposalStatus.accepted
                ? 'Alteração aplicada.'
                : 'Proposta recusada. Nada mudou.',
          ),
        ),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.message),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.proposal;
    final pending = p.status == ProposalStatus.pending;
    final statusColor = switch (p.status) {
      ProposalStatus.accepted => EvoColors.success,
      ProposalStatus.pending => EvoColors.textSecondary,
      ProposalStatus.failed => EvoColors.danger,
      _ => EvoColors.textSecondary,
    };
    return Semantics(
      container: true,
      label: 'Proposta da IA',
      child: Container(
        padding: const EdgeInsets.all(EvoSpace.lg),
        decoration: BoxDecoration(
          color: EvoColors.bgSurface,
          borderRadius: BorderRadius.circular(EvoRadius.input),
          border: Border.all(
            color: pending ? EvoColors.borderStrong : EvoColors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note_rounded, size: 20),
                const SizedBox(width: EvoSpace.sm),
                Expanded(
                  child: Text(
                    'Proposta · ${p.status.label}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: EvoSpace.sm),
            Text(p.summary, style: theme.textTheme.titleMedium),
            for (final line in p.details) ...[
              const SizedBox(height: EvoSpace.xs),
              Text(line, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: EvoSpace.sm),
            Text(
              'Motivo: ${p.rationale}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: EvoColors.textSecondary,
              ),
            ),
            if (p.result case final reason?) ...[
              const SizedBox(height: EvoSpace.sm),
              Text(
                reason,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: EvoColors.danger,
                ),
              ),
            ],
            if (pending) ...[
              const SizedBox(height: EvoSpace.md),
              Row(
                children: [
                  Expanded(
                    child: EvoButton(
                      label: 'Confirmar',
                      isLoading: _deciding == true,
                      onPressed: _deciding == null
                          ? () => _decide(accept: true)
                          : null,
                    ),
                  ),
                  const SizedBox(width: EvoSpace.sm),
                  Expanded(
                    child: EvoButton(
                      label: 'Recusar',
                      variant: EvoButtonVariant.secondary,
                      isLoading: _deciding == false,
                      onPressed: _deciding == null
                          ? () => _decide(accept: false)
                          : null,
                    ),
                  ),
                ],
              ),
            ] else if (p.status == ProposalStatus.accepted) ...[
              const SizedBox(height: EvoSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push(
                    p.templateId != null
                        ? AppRoutes.templateEdit(p.templateId!)
                        : p.goalId != null
                        ? AppRoutes.goalEdit(p.goalId!)
                        : AppRoutes.goals,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(p.templateId != null ? 'Ver ficha' : 'Ver meta'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
