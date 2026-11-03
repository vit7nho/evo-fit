import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';
import '../../sessions/domain/set_rows.dart';
import '../../sessions/presentation/exercise_card.dart'
    show KindBadge, setValue;

/// Uma série no histórico: número ou letra do tipo (A, F, D, RP) e o valor.
/// Os segmentos (drop, rest-pause) aparecem recuados sob a série.
class HistorySetLine extends StatelessWidget {
  const HistorySetLine({
    super.key,
    required this.badge,
    required this.kind,
    this.reps,
    this.loadKg,
    this.durationS,
    this.segment = false,
  });

  final String badge;
  final RowKind kind;
  final int? reps;
  final double? loadKg;
  final int? durationS;
  final bool segment;

  @override
  Widget build(BuildContext context) {
    final value = setValue(reps: reps, loadKg: loadKg, durationS: durationS);
    return Semantics(
      container: true,
      label: '${kind == RowKind.working ? 'Série $badge' : kind.label}: $value',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: segment ? EvoSpace.x2xl : 0,
          bottom: EvoSpace.xs,
        ),
        child: Row(
          children: [
            Transform.scale(scale: 0.8, child: KindBadge(text: badge)),
            const SizedBox(width: EvoSpace.sm),
            Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badges das séries na ordem: número para as válidas, letra para as demais.
List<String> badgesFor(Iterable<RowKind> kinds) {
  var number = 0;
  final badges = <String>[];
  for (final kind in kinds) {
    // "F" também é série válida: conta na numeração, mas mostra a letra.
    if (kind.isMainWorking) number++;
    badges.add(kind == RowKind.working ? '$number' : kind.letter);
  }
  return badges;
}

/// Selo de recorde (troféu + texto), sem depender só da cor.
class RecordBadge extends StatelessWidget {
  const RecordBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EvoSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: EvoColors.accent,
        borderRadius: BorderRadius.circular(EvoRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            size: 14,
            color: EvoColors.onAccent,
          ),
          const SizedBox(width: EvoSpace.xs),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: EvoColors.onAccent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Um número em destaque com o rótulo em cima (resumo do treino, recordes).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
