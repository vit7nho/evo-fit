import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../activities/domain/activity.dart';
import '../../analytics/domain/analytics.dart';
import '../../analytics/domain/compare.dart';
import '../../goals/presentation/goal_format.dart';
import '../../history/domain/history.dart';
import '../domain/dashboard.dart';

String _plural(int n, String one, String many) =>
    n == 1 ? '1 $one' : '$n $many';

/// "2 de 3 dias" com meta no perfil; "2 dias ativos" sem.
String weekHeadline(DashboardWeek week) => week.weeklyTarget == null
    ? _plural(week.activeDays, 'dia ativo', 'dias ativos')
    : '${week.activeDays} de ${week.weeklyTarget} dias';

String weekDetail(DashboardWeek week) => [
  _plural(week.sessions, 'treino ou atividade', 'treinos e atividades'),
  if (week.durationS > 0) formatTotalDuration(week.durationS),
].join(' · ');

String weekHistory(DashboardWeek week) => [
  'Semana passada: '
      '${_plural(week.previousActiveDays, 'dia ativo', 'dias ativos')}',
  switch (week.streakWeeks) {
    0 => 'nenhuma sequência em andamento',
    1 => 'sequência de 1 semana',
    final n => 'sequência de $n semanas',
  },
].join(' · ');

String strengthHeadline(StrengthFocus f) => f.sets == 0
    ? 'Nenhuma série nos últimos 7 dias'
    : '${_plural(f.sets, 'série', 'séries')} · ${formatVolume(f.volumeKg)} kg';

String strengthDetail(StrengthFocus f) =>
    '7 dias anteriores: ${_plural(f.previousSets, 'série', 'séries')}'
    '${f.previousVolumeKg > 0 ? ' · ${formatVolume(f.previousVolumeKg)} kg' : ''}';

String _names(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';

/// Resposta curta de "qual recebeu menos" (o Meu Corpo tem a lista inteira).
String bodyHeadline(BodyFocus f) {
  final names = [for (final m in f.least) m.name];
  if (f.untrained == 0) {
    return 'Menos estímulo: ${_names(names)} '
        '(${formatDecimal(f.least.first.perWeek)} séries/semana)';
  }
  if (f.untrained <= names.length) {
    return 'Sem nenhuma série em ${f.periodDays} dias: ${_names(names)}';
  }
  return '${f.untrained} músculos sem nenhuma série em ${f.periodDays} dias, '
      'como ${_names(names)}';
}

String enduranceHeadline(EnduranceFocus f) {
  if (f.sessions == 0) return 'Nada nos últimos 7 dias';
  final rhythm = switch (f.modality) {
    'swim' =>
      f.paceSPer100m == null
          ? null
          : 'ritmo ${formatPace(f.paceSPer100m!, per: '100 m')}',
    'cycle' => f.speedKmh == null ? null : formatSpeed(f.speedKmh!),
    _ =>
      f.paceSPerKm == null
          ? null
          : 'pace ${formatPace(f.paceSPerKm!, per: 'km')}',
  };
  return [
    if (f.distanceM > 0)
      formatDistance(f.distanceM, modality: f.modality)
    else
      _plural(f.sessions, 'vez', 'vezes'),
    if (f.distanceM == 0) formatTotalDuration(f.durationS),
    ?rhythm,
  ].join(' · ');
}

String enduranceDetail(EnduranceFocus f) => f.previousDistanceM == 0
    ? 'Sem distância nos 7 dias anteriores'
    : '7 dias anteriores: '
          '${formatDistance(f.previousDistanceM, modality: f.modality)}';

String planHeadline(PlanFocus f) =>
    'Semana ${f.currentWeek} de ${f.weeks} · '
    '${f.completedSessions} de ${f.totalSessions} sessões';

String _amount(String unit, double value) => switch (unit) {
  'kg' => '${formatDecimal(value)} kg',
  'km' => '${formatDecimal(value)} km',
  's' => formatDuration(value.round()),
  'sets_per_week' => '${formatDecimal(value)} séries/semana',
  'sessions' => _plural(value.round(), 'treino', 'treinos'),
  _ => formatDecimal(value),
};

/// "8 de 10 km", "27:30 (alvo 25:00)", "1 treino de 4 nesta semana".
String goalProgressText(GoalProgress p) {
  final current = p.current;
  if (current == null) return 'Ainda sem registro que meça esta meta';
  if (p.achieved) return 'Alvo atingido: ${_amount(p.unit, current)}';
  if (p.lowerIsBetter) {
    return '${_amount(p.unit, current)} (alvo ${_amount(p.unit, p.target)})';
  }
  if (p.unit == 'sessions') {
    return '${_amount(p.unit, current)} de ${p.target.round()} nesta semana';
  }
  return '${formatDecimal(current)} de ${_amount(p.unit, p.target)}';
}

String lastRecordTitle(LastRecord r) => r.modality == 'strength'
    ? (r.title ?? 'Musculação')
    : modalityLabel(r.modality);

String lastRecordDetail(LastRecord r) => [
  if (r.sets != null) _plural(r.sets!, 'série', 'séries'),
  if ((r.volumeKg ?? 0) > 0) '${formatVolume(r.volumeKg!)} kg',
  if (r.distanceM case final m? when m > 0)
    formatDistance(m, modality: r.modality),
  if (r.durationS > 0) formatTotalDuration(r.durationS),
].join(' · ');

/// Cabeçalho de seção do painel.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: EvoSpace.md),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Esta semana: dias ativos (contra a meta do perfil), treinos, tempo e sequência.
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.week, required this.onTap});

  final DashboardWeek week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = week.weeklyTarget;
    final reached = target != null && week.activeDays >= target;
    return EvoCard(
      onTap: onTap,
      child: Semantics(
        label: [
          'Esta semana',
          weekHeadline(week),
          if (reached) 'meta da semana batida',
          weekDetail(week),
          weekHistory(week),
        ].join('. '),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Esta semana', style: theme.textTheme.bodyMedium),
            const SizedBox(height: EvoSpace.xs),
            Row(
              children: [
                Flexible(
                  child: Text(
                    weekHeadline(week),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                if (reached) ...[
                  const SizedBox(width: EvoSpace.sm),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: EvoColors.success,
                    size: 22,
                  ),
                ],
              ],
            ),
            if (target != null) ...[
              const SizedBox(height: EvoSpace.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (week.activeDays / target).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: reached ? EvoColors.success : EvoColors.accent,
                ),
              ),
            ],
            const SizedBox(height: EvoSpace.sm),
            Text(weekDetail(week), style: theme.textTheme.bodyMedium),
            const SizedBox(height: EvoSpace.xs),
            Text(weekHistory(week), style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// Um cartão do foco: ícone, título, número principal e um detalhe.
class FocusTile extends StatelessWidget {
  const FocusTile({
    super.key,
    required this.icon,
    required this.title,
    required this.headline,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String headline;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: [title, headline, ?detail].join('. '),
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: EvoColors.bgElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: EvoColors.textPrimary, size: 20),
            ),
            const SizedBox(width: EvoSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(headline, style: theme.textTheme.titleMedium),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail!, style: theme.textTheme.labelSmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma meta ativa com o progresso medido pelos registros (quando dá para medir).
class GoalProgressTile extends StatelessWidget {
  const GoalProgressTile({super.key, required this.goal, required this.onTap});

  final GoalCard goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = goal.progress;
    final ratio = progress?.ratio;
    final text = progress == null ? null : goalProgressText(progress);
    final deadline = goal.targetDate == null
        ? null
        : 'Prazo: ${formatGoalDate(context, goal.targetDate!)}';
    return EvoCard(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: [
          goal.title,
          goal.summary,
          ?text,
          if (ratio != null) '${(ratio * 100).round()}% do alvo',
          ?deadline,
        ].join('. '),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(goal.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(goal.summary, style: theme.textTheme.bodyMedium),
            if (ratio != null) ...[
              const SizedBox(height: EvoSpace.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  color: progress!.achieved
                      ? EvoColors.success
                      : EvoColors.accent,
                ),
              ),
            ],
            if (text != null) ...[
              const SizedBox(height: EvoSpace.xs),
              Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: progress!.achieved ? EvoColors.success : null,
                ),
              ),
              if (progress!.achieved)
                Text(
                  'Toque para marcar como alcançada.',
                  style: theme.textTheme.labelSmall,
                ),
            ],
            if (deadline != null) ...[
              const SizedBox(height: EvoSpace.xs),
              Text(deadline, style: theme.textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}
