import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../application/analytics_controller.dart';
import '../domain/analytics.dart';
import '../domain/compare.dart';

/// "3 de nov. a 9 de nov." (com o ano quando não é o atual).
String describeSpan(BuildContext context, AnalyticsPeriod period) {
  final l = MaterialLocalizations.of(context);
  final now = DateTime.now().year;
  String day(DateTime d) =>
      d.year == now ? l.formatShortMonthDay(d) : l.formatShortDate(d);
  final days = period.days == 1 ? '1 dia' : '${period.days} dias';
  if (period.days == 1) return '${day(period.from)} ($days)';
  return '${day(period.from)} a ${day(period.to)} ($days)';
}

/// Comparativos (3.7): dois períodos lado a lado, indicador por indicador. Os
/// valores, a diferença e o percentual vêm da API.
class ComparePage extends ConsumerStatefulWidget {
  const ComparePage({super.key});

  @override
  ConsumerState<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends ConsumerState<ComparePage> {
  ComparePreset _preset = ComparePreset.month30;
  late PeriodPair _pair = ComparePreset.month30.pair(DateTime.now())!;

  void _choose(ComparePreset preset) {
    setState(() {
      _preset = preset;
      if (preset.pair(DateTime.now()) case final pair?) _pair = pair;
    });
  }

  Future<void> _pick({required bool isA}) async {
    final current = isA ? _pair.a : _pair.b;
    final today = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
      helpText: isA ? 'Período A (a base)' : 'Período B',
      saveText: 'Usar',
    );
    if (range == null || !mounted) return;
    final period = AnalyticsPeriod.range(range.start, range.end);
    if (period.days > AnalyticsPeriod.maxDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escolha um período de até ${AnalyticsPeriod.maxDays} dias.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _preset = ComparePreset.custom;
      _pair = isA ? (a: period, b: _pair.b) : (a: _pair.a, b: period);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = ref.watch(compareProvider(_pair));
    return Scaffold(
      appBar: AppBar(title: const Text('Comparativos')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(EvoSpace.xl),
          children: [
            EvoChipGroup(
              single: true,
              options: [
                for (final p in ComparePreset.values) (p.name, p.label),
              ],
              selected: {_preset.name},
              onChanged: (selected) {
                final preset = ComparePreset.values.byName(selected.first);
                if (preset == ComparePreset.custom) {
                  setState(() => _preset = preset);
                } else {
                  _choose(preset);
                }
              },
            ),
            const SizedBox(height: EvoSpace.lg),
            _PeriodTile(
              letter: 'A',
              text: describeSpan(context, _pair.a),
              hint: 'Base da comparação',
              onTap: () => _pick(isA: true),
            ),
            const SizedBox(height: EvoSpace.sm),
            _PeriodTile(
              letter: 'B',
              text: describeSpan(context, _pair.b),
              hint: 'Comparado com A',
              onTap: () => _pick(isA: false),
            ),
            const SizedBox(height: EvoSpace.sm),
            Text(
              _preset == ComparePreset.calendarMonth
                  ? 'Do dia 1 até hoje contra o mesmo trecho do mês passado.'
                  : 'Toque num período para escolher as datas.',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: EvoSpace.xl),
            ...rows.when(
              loading: () => const [EvoLoadingView(lines: 5)],
              error: (error, _) => [
                EvoErrorView(
                  title: 'Não foi possível comparar',
                  message: error is ApiException
                      ? error.message
                      : 'Erro inesperado.',
                  onRetry: () => ref.invalidate(compareProvider(_pair)),
                ),
              ],
              data: (rows) =>
                  rows.every(
                    (r) =>
                        (r.comparison.previous ?? 0) == 0 &&
                        (r.comparison.current ?? 0) == 0,
                  )
                  ? [
                      const EvoEmptyView(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Nada registrado nos dois períodos',
                        message:
                            'Escolha outros períodos ou registre treinos e '
                            'atividades para comparar.',
                      ),
                    ]
                  : [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: EvoSpace.md),
                          child: _CompareCard(row: row),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({
    required this.letter,
    required this.text,
    required this.hint,
    required this.onTap,
  });

  final String letter;
  final String text;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Período $letter: $text. $hint. Toque para mudar as datas.',
        excludeSemantics: true,
        child: Row(
          children: [
            _Letter(letter),
            const SizedBox(width: EvoSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: theme.textTheme.titleMedium),
                  Text(hint, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            const Icon(Icons.edit_calendar_rounded),
          ],
        ),
      ),
    );
  }
}

/// A letra do período: A em contorno, B preenchido (não depende só de cor).
class _Letter extends StatelessWidget {
  const _Letter(this.letter, {this.size = 32});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final filled = letter == 'B';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? EvoColors.accent : EvoColors.bgSurface,
        border: Border.all(color: EvoColors.accent, width: 1.5),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: EvoFontSize.caption,
          fontWeight: FontWeight.w700,
          color: filled ? EvoColors.onAccent : EvoColors.textPrimary,
        ),
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.row});

  final CompareRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = row.comparison;
    final a = c.previous;
    final b = c.current;
    final most = [a ?? 0, b ?? 0].reduce((x, y) => x > y ? x : y);
    final detail = describePairDifference(row);
    final color = switch (c.better) {
      'b' => EvoColors.success,
      'a' => EvoColors.warning,
      _ => EvoColors.textSecondary,
    };
    String value(double? v) => v == null ? 'sem dado' : row.format(v);
    return EvoCard(
      child: Semantics(
        container: true,
        label: '${row.title}. A: ${value(a)}. B: ${value(b)}. $detail',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(row.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: EvoSpace.md),
            _Bar(letter: 'A', value: a, most: most, text: value(a)),
            const SizedBox(height: EvoSpace.sm),
            _Bar(letter: 'B', value: b, most: most, text: value(b)),
            const SizedBox(height: EvoSpace.md),
            Text(
              detail,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.letter,
    required this.value,
    required this.most,
    required this.text,
  });

  final String letter;
  final double? value;
  final double most;
  final String text;

  @override
  Widget build(BuildContext context) {
    final fraction = most <= 0 || value == null ? 0.0 : value! / most;
    final filled = letter == 'B';
    return Row(
      children: [
        _Letter(letter, size: 24),
        const SizedBox(width: EvoSpace.sm),
        Expanded(
          flex: 3,
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 14,
                // Um traço mínimo para o zero não sumir.
                width: (constraints.maxWidth * fraction).clamp(
                  3,
                  constraints.maxWidth,
                ),
                decoration: BoxDecoration(
                  color: filled ? EvoColors.accent : EvoColors.bgElevated,
                  border: Border.all(color: EvoColors.accent),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: EvoSpace.sm),
        Flexible(
          flex: 2,
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
