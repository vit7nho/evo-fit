import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';
import '../../goals/presentation/goal_format.dart';
import '../domain/plan.dart';

/// Ícone redondo da modalidade do plano.
class PlanIcon extends StatelessWidget {
  const PlanIcon({super.key, required this.modality, this.muted = false});

  final String modality;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: muted ? EvoColors.bgElevated : EvoColors.accent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        modality == 'walk'
            ? Icons.directions_walk_rounded
            : Icons.directions_run_rounded,
        color: muted ? EvoColors.textPrimary : EvoColors.onAccent,
        size: 22,
      ),
    );
  }
}

/// "Semana 2 de 9 · 4 de 27 sessões" com a barra de progresso.
class PlanProgress extends StatelessWidget {
  const PlanProgress({super.key, required this.plan});

  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = plan.totalSessions == 0
        ? 0.0
        : plan.completedSessions / plan.totalSessions;
    final week = plan.active
        ? 'Semana ${plan.currentWeek} de ${plan.weeks}'
        : '${plan.weeks} semanas';
    final text =
        '$week · ${plan.completedSessions} de ${plan.totalSessions} sessões';
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.bodyMedium),
          const SizedBox(height: EvoSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: EvoColors.bgElevated,
              color: EvoColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Duração prevista, arredondada para minutos ("~30 min").
String formatPlannedDuration(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '~$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '~${minutes ~/ 60} h' : '~${minutes ~/ 60} h $rest min';
}

/// "qua., 5 de nov." (sugestão de data da sessão).
String formatSessionDate(BuildContext context, DateTime date) =>
    formatGoalDate(context, date);
