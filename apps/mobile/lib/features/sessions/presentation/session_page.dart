import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../goals/presentation/goal_format.dart';
import '../../training/data/templates_api.dart';
import '../../training/domain/template.dart';
import '../../training/presentation/exercise_picker_page.dart';
import '../../training/presentation/item_editor_page.dart' show restLabel;
import '../application/session_controller.dart';
import '../domain/session.dart';

/// Treino em andamento: séries em tela única, descanso e finalização.
class SessionPage extends ConsumerWidget {
  const SessionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(EvoSpace.xl),
            child: EvoErrorView(
              title: 'Não foi possível carregar o treino',
              message: error is ApiException
                  ? error.message
                  : 'Erro inesperado.',
              onRetry: () => ref.invalidate(sessionProvider),
            ),
          ),
        ),
      ),
      data: (session) => session == null
          ? Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(EvoSpace.xl),
                  child: EvoEmptyView(
                    icon: Icons.fitness_center_rounded,
                    title: 'Nenhum treino em andamento',
                    message: 'Comece um treino a partir de uma ficha.',
                    actionLabel: 'Ver fichas',
                    onAction: () => context.go(AppRoutes.templates),
                  ),
                ),
              ),
            )
          : _SessionView(session: session),
    );
  }
}

class _SessionView extends ConsumerStatefulWidget {
  const _SessionView({required this.session});

  final WorkoutSession session;

  @override
  ConsumerState<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends ConsumerState<_SessionView> {
  bool _busy = false;

  /// Linhas extras acrescentadas na hora ("+ Série"), por exercício.
  final _extraRows = <String, int>{};

  /// Segmento em registro, por exercício: a série que ele continua e a técnica.
  final _pending = <String, ({String parentId, String kind})>{};

  /// Pausa curta do rest-pause, entre a série e as repetições extras.
  static const _restPauseS = 15;

  WorkoutSession get _session => widget.session;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _afterSet(int index) {
    final rest = _session.restAfter(index);
    if (rest != null && rest > 0) {
      ref.read(restTimerProvider.notifier).start(rest);
    }
  }

  /// Abre a linha de um drop ou rest-pause logo abaixo da série [parentId]. O drop
  /// emenda sem descanso; o rest-pause começa com a pausa curta.
  void _openSegment(String entryId, String parentId, String kind) {
    setState(() => _pending[entryId] = (parentId: parentId, kind: kind));
    final timer = ref.read(restTimerProvider.notifier);
    if (kind == SetKind.restPause) {
      timer.start(_restPauseS);
    } else {
      timer.skip();
    }
  }

  Future<void> _toggleFailure(SessionExercise entry, LoggedSet set) => _run(
    () => ref.read(sessionProvider.notifier).updateSet(entry.id, set.id, {
      'to_failure': !set.toFailure,
      // Até a falha não sobra repetição em reserva.
      if (!set.toFailure && (set.rir ?? 0) > 0) 'rir': null,
    }),
  );

  Future<void> _addExercises() async {
    final picked = await Navigator.of(context).push<List<TemplateExercise>>(
      MaterialPageRoute(builder: (_) => const ExercisePickerPage()),
    );
    if (picked == null || picked.isEmpty) return;
    await _run(
      () => ref.read(sessionProvider.notifier).addExercises([
        for (final e in picked) e.id,
      ]),
    );
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar treino?'),
        content: const Text(
          'As séries registradas neste treino serão apagadas. Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar treinando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: EvoColors.danger,
              minimumSize: const Size(88, evoTouchTargetMin),
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    final router = GoRouter.of(context);
    await _run(() async {
      await ref.read(sessionProvider.notifier).discard();
      ref.read(restTimerProvider.notifier).skip();
      router.go(AppRoutes.home);
    });
  }

  Future<void> _finish() async {
    final result = await showModalBottomSheet<(int?, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _FinishSheet(),
    );
    if (result == null || !mounted) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _run(() async {
      final finished = await ref
          .read(sessionProvider.notifier)
          .finish(
            effort: result.$1,
            notes: result.$2.isEmpty ? null : result.$2,
          );
      ref.read(restTimerProvider.notifier).skip();
      final minutes = (finished.elapsedS / 60).round();
      final sets = finished.setCount == 1
          ? '1 série'
          : '${finished.setCount} séries';
      messenger.showSnackBar(
        SnackBar(content: Text('Treino salvo: $sets em $minutes min')),
      );
      router.go(AppRoutes.home);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = ref.watch(clockTickProvider).value ?? DateTime.now();
    final paused = _session.isPaused;
    final options = ref.watch(workoutOptionsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _session.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: paused ? 'Retomar treino' : 'Pausar treino',
            icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            onPressed: _busy
                ? null
                : () => _run(
                    () => paused
                        ? ref.read(sessionProvider.notifier).resume()
                        : ref.read(sessionProvider.notifier).pause(),
                  ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (_) => _discard(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'discard', child: Text('Descartar treino')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Faixa do tempo (fora da barra do topo: com fonte grande, duas linhas
            // de título não cabem nela).
            Container(
              width: double.infinity,
              color: EvoColors.bgElevated,
              padding: const EdgeInsets.symmetric(
                horizontal: EvoSpace.xl,
                vertical: EvoSpace.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    paused ? Icons.pause_rounded : Icons.timer_outlined,
                    size: 16,
                  ),
                  const SizedBox(width: EvoSpace.xs),
                  Flexible(
                    child: Text(
                      paused
                          ? 'Pausado · ${formatElapsed(_session.elapsedAt(now))}'
                          : formatElapsed(_session.elapsedAt(now)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: EvoColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(EvoSpace.xl),
                children: [
                  if (_session.exercises.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EvoSpace.lg),
                      child: Text(
                        'Treino livre: acrescente os exercícios que for fazer.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ..._cards(options),
                  const SizedBox(height: EvoSpace.sm),
                  EvoButton(
                    label: 'Adicionar exercício',
                    icon: Icons.add_rounded,
                    variant: EvoButtonVariant.secondary,
                    onPressed: _busy ? null : _addExercises,
                  ),
                ],
              ),
            ),
            const _RestBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EvoSpace.xl,
                EvoSpace.sm,
                EvoSpace.xl,
                EvoSpace.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: EvoButton(
                  label: 'Finalizar treino',
                  icon: Icons.flag_rounded,
                  isLoading: _busy,
                  onPressed: _finish,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cartões dos exercícios; os de um grupo ficam juntos, com uma barra lateral.
  List<Widget> _cards(WorkoutOptions? options) {
    final widgets = <Widget>[];
    var index = 0;
    while (index < _session.exercises.length) {
      final group = _session.exercises[index].group;
      // Os membros de um grupo são consecutivos (a API garante).
      final block = group == null
          ? [index]
          : [
              for (var i = index; i < _session.exercises.length; i++)
                if (_session.exercises[i].group == group) i,
            ];
      final cards = [for (final i in block) _card(i)];
      widgets.add(
        group == null
            ? cards.single
            : _GroupBlock(
                label:
                    options?.groupLabel(_session.groups[group].kind) ??
                    _session.groups[group].kind,
                rest: _session.groups[group].restAfterS,
                children: cards,
              ),
      );
      index = block.last + 1;
    }
    return widgets;
  }

  Widget _card(int index) {
    final entry = _session.exercises[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: EvoSpace.md),
      child: _ExerciseCard(
        key: ValueKey(entry.id),
        entry: entry,
        extraRows: _extraRows[entry.id] ?? 0,
        pending: _pending[entry.id],
        busy: _busy,
        onAddRow: () => setState(
          () => _extraRows[entry.id] = (_extraRows[entry.id] ?? 0) + 1,
        ),
        onLogged: (row, logged) {
          final extra = _extraRows[entry.id] ?? 0;
          if (extra > 0 && entry.mainSets.length + 1 >= entry.rowCount()) {
            _extraRows[entry.id] = extra - 1;
          }
          // Série planejada com técnica: a linha do segmento já abre embaixo.
          final technique = entry.technique(row);
          if (technique != null && !logged.isWarmup) {
            _openSegment(entry.id, logged.id, technique);
          } else {
            _afterSet(index);
          }
        },
        onOpenSegment: (parent, kind) =>
            _openSegment(entry.id, parent.id, kind),
        onSegmentDone: (logged) {
          setState(() => _pending.remove(entry.id));
          if (logged != null) _afterSet(index);
        },
        onToggleFailure: (set) => _toggleFailure(entry, set),
        onRemove: () => _run(
          () => ref.read(sessionProvider.notifier).removeExercise(entry.id),
        ),
      ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.label,
    required this.rest,
    required this.children,
  });

  final String label;
  final int? rest;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: EvoSpace.md),
      padding: const EdgeInsets.only(left: EvoSpace.md),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: EvoColors.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.sm),
            child: Semantics(
              header: true,
              child: Text(
                rest == null
                    ? '$label · sem descanso entre os exercícios'
                    : '$label · descanso ${restLabel(rest!)} após a rodada',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    super.key,
    required this.entry,
    required this.extraRows,
    required this.pending,
    required this.busy,
    required this.onAddRow,
    required this.onLogged,
    required this.onOpenSegment,
    required this.onSegmentDone,
    required this.onToggleFailure,
    required this.onRemove,
  });

  final SessionExercise entry;
  final int extraRows;
  final ({String parentId, String kind})? pending;
  final bool busy;
  final VoidCallback onAddRow;
  final void Function(int row, LoggedSet logged) onLogged;
  final void Function(LoggedSet parent, String kind) onOpenSegment;

  /// Segmento salvo (com a série) ou cancelado (nulo).
  final void Function(LoggedSet? logged) onSegmentDone;
  final void Function(LoggedSet set) onToggleFailure;
  final VoidCallback onRemove;

  /// Segmentos e a barra de técnicas abaixo da série feita da linha [row].
  List<Widget> _afterRow(int row, List<LoggedSet> mains) {
    final parent = mains[row];
    final segments = entry.segmentsOf(parent.id);
    final open = pending?.parentId == parent.id ? pending : null;
    return [
      for (final (i, segment) in segments.indexed)
        _SegmentDoneRow(
          entry: entry,
          parentNumber: row + 1,
          segment: segment,
          number: segments
              .take(i + 1)
              .where((s) => s.kind == segment.kind)
              .length,
        ),
      if (open != null)
        _SegmentInputRow(
          key: ValueKey('${entry.id}-seg-${entry.sets.length}'),
          entry: entry,
          row: row,
          parent: parent,
          kind: open.kind,
          onDone: onSegmentDone,
        )
      // As técnicas valem para a última série feita (a que acabou de terminar).
      else if (row == mains.length - 1 && !parent.isWarmup && pending == null)
        _TechniqueBar(
          entry: entry,
          parent: parent,
          busy: busy,
          onOpenSegment: (kind) => onOpenSegment(parent, kind),
          onToggleFailure: () => onToggleFailure(parent),
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rows = entry.rowCount(extra: extraRows);
    final mains = entry.mainSets;
    final previous = entry.previous
        .where((s) => s.kind != SetKind.warmup)
        .map(_describe)
        .join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EvoSpace.lg,
          EvoSpace.md,
          EvoSpace.sm,
          EvoSpace.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      entry.exercise.name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ações de ${entry.exercise.name}',
                  onSelected: (_) => onRemove(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Tirar do treino'),
                    ),
                  ],
                ),
              ],
            ),
            if (previous.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: EvoSpace.md),
                child: Text(
                  'Última vez: $previous',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            const SizedBox(height: EvoSpace.sm),
            for (var row = 0; row < rows; row++) ...[
              _SetRow(
                key: ValueKey('${entry.id}-$row-${entry.sets.length}'),
                entry: entry,
                row: row,
                onLogged: (logged) => onLogged(row, logged),
              ),
              if (row < mains.length) ..._afterRow(row, mains),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: entry.rowCount(extra: extraRows) < 20
                    ? onAddRow
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Série'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "60 kg × 10 (falha) + 45 kg × 6": a série e os segmentos dela.
  static String _describe(PreviousSet s) => [
    '${setValue(reps: s.reps, loadKg: s.loadKg, durationS: s.durationS)}'
        '${s.toFailure ? ' (falha)' : ''}',
    for (final g in s.segments)
      setValue(reps: g.reps, loadKg: g.loadKg, durationS: g.durationS),
  ].join(' + ');
}

/// "60 kg × 10", "12" (sem carga) ou "45 s".
String setValue({int? reps, double? loadKg, int? durationS}) {
  if (durationS != null) return '$durationS s';
  final load = loadKg == null ? '' : '${formatDecimal(loadKg)} kg × ';
  return '$load${reps ?? '—'}';
}

/// "Drop" ou "Rest-pause".
String segmentLabel(String kind) =>
    kind == SetKind.restPause ? 'Rest-pause' : 'Drop';

/// Carga faz sentido para o exercício (não é por tempo nem só com o corpo).
bool _hasLoad(TemplateExercise exercise) =>
    exercise.loadType != 'time' && exercise.loadType != 'bodyweight';

/// Abaixo da última série feita: acrescentar drop ou rest-pause e marcar a falha.
class _TechniqueBar extends StatelessWidget {
  const _TechniqueBar({
    required this.entry,
    required this.parent,
    required this.busy,
    required this.onOpenSegment,
    required this.onToggleFailure,
  });

  final SessionExercise entry;
  final LoggedSet parent;
  final bool busy;
  final ValueChanged<String> onOpenSegment;
  final VoidCallback onToggleFailure;

  @override
  Widget build(BuildContext context) {
    final timed = entry.exercise.timed;
    final name = entry.exercise.name;
    return Padding(
      padding: const EdgeInsets.only(left: EvoSpace.x3xl, bottom: EvoSpace.md),
      child: Wrap(
        spacing: EvoSpace.xs,
        runSpacing: EvoSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Drop tira carga: só em exercício com carga externa.
          if (entry.exercise.loadType == 'external')
            TextButton.icon(
              onPressed: busy ? null : () => onOpenSegment(SetKind.drop),
              icon: const Icon(Icons.south_rounded, size: 18),
              label: Text('Drop', semanticsLabel: 'Acrescentar drop em $name'),
            ),
          if (!timed)
            TextButton.icon(
              onPressed: busy ? null : () => onOpenSegment(SetKind.restPause),
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: Text(
                'Rest-pause',
                semanticsLabel: 'Acrescentar rest-pause em $name',
              ),
            ),
          FilterChip(
            label: const Text('Até a falha'),
            tooltip: 'Última série de $name até a falha',
            selected: parent.toFailure,
            onSelected: busy ? null : (_) => onToggleFailure(),
          ),
        ],
      ),
    );
  }
}

/// Um drop ou rest-pause feito, recuado sob a série: toque para corrigir ou apagar.
class _SegmentDoneRow extends StatelessWidget {
  const _SegmentDoneRow({
    required this.entry,
    required this.parentNumber,
    required this.segment,
    required this.number,
  });

  final SessionExercise entry;
  final int parentNumber;
  final LoggedSet segment;

  /// Posição entre os segmentos do mesmo tipo desta série (Drop 1, Drop 2...).
  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = '${segmentLabel(segment.kind)} $number';
    final value =
        '${setValue(reps: segment.reps, loadKg: segment.loadKg, durationS: segment.durationS)}'
        '${segment.toFailure ? ' · falha' : ''}';
    return Semantics(
      container: true,
      button: true,
      label: '$title da série $parentNumber: $value. Toque para corrigir.',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _EditSetDialog(
            entry: entry,
            set: segment,
            title: '$title da série $parentNumber',
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: evoTouchTargetMin),
          child: Padding(
            padding: const EdgeInsets.only(left: EvoSpace.x3xl),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$title  ',
                          style: theme.textTheme.labelSmall,
                        ),
                        TextSpan(text: value),
                      ],
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(EvoSpace.md),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: EvoColors.success,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha para registrar um drop ou rest-pause, com a sugestão em cinza; ✓ salva
/// (com a sugestão, se nada for digitado) e ✕ desiste.
class _SegmentInputRow extends ConsumerStatefulWidget {
  const _SegmentInputRow({
    super.key,
    required this.entry,
    required this.row,
    required this.parent,
    required this.kind,
    required this.onDone,
  });

  final SessionExercise entry;
  final int row;
  final LoggedSet parent;
  final String kind;
  final void Function(LoggedSet? logged) onDone;

  @override
  ConsumerState<_SegmentInputRow> createState() => _SegmentInputRowState();
}

class _SegmentInputRowState extends ConsumerState<_SegmentInputRow> {
  final _load = TextEditingController();
  final _reps = TextEditingController();
  bool _saving = false;
  String? _error;

  SessionExercise get _entry => widget.entry;

  String get _title {
    final number =
        _entry
            .segmentsOf(widget.parent.id)
            .where((s) => s.kind == widget.kind)
            .length +
        1;
    return '${segmentLabel(widget.kind)} $number';
  }

  @override
  void dispose() {
    _load.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _log() async {
    final suggestion = _entry.segmentSuggestion(
      widget.row,
      widget.parent,
      widget.kind,
    );
    final typedLoad = _load.text.trim();
    final load = typedLoad.isEmpty
        ? suggestion.loadKg
        : parseDecimal(typedLoad);
    if (typedLoad.isNotEmpty && load == null) {
      setState(() => _error = 'Carga inválida.');
      return;
    }
    final reps = int.tryParse(_reps.text.trim()) ?? suggestion.reps;
    if (reps == null || reps < 1) {
      setState(() => _error = 'Informe as repetições.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final logged = await ref.read(sessionProvider.notifier).logSet(
        _entry.id,
        {
          'kind': widget.kind,
          'parent_set_id': widget.parent.id,
          'reps': reps,
          if (_hasLoad(_entry.exercise)) 'load_kg': ?load,
        },
      );
      unawaited(HapticFeedback.lightImpact());
      widget.onDone(logged);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = _entry.segmentSuggestion(
      widget.row,
      widget.parent,
      widget.kind,
    );
    final where =
        '$_title da série ${widget.row + 1} de ${_entry.exercise.name}';
    return Padding(
      padding: const EdgeInsets.only(left: EvoSpace.x3xl, top: EvoSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.kind == SetKind.restPause
                ? '$_title · pausa curta e mais repetições'
                : '$_title · menos carga, sem descanso',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: EvoSpace.md),
          Row(
            children: [
              if (_hasLoad(_entry.exercise)) ...[
                Expanded(
                  child: TextField(
                    controller: _load,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'kg',
                      hintText: suggestion.loadKg == null
                          ? null
                          : formatDecimal(suggestion.loadKg!),
                      isDense: true,
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                ),
                const SizedBox(width: EvoSpace.sm),
              ],
              Expanded(
                child: TextField(
                  controller: _reps,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'reps',
                    hintText: '${suggestion.reps ?? ''}',
                    isDense: true,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Concluir $where',
                onPressed: _saving ? null : _log,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
              ),
              IconButton(
                tooltip: 'Desistir do ${_title.toLowerCase()}',
                onPressed: _saving ? null : () => widget.onDone(null),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: EvoSpace.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$_error Toque em ✓ para tentar de novo.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: EvoColors.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Uma linha de série: feita (com os valores e ✓ preenchido), a próxima (editável,
/// com a sugestão em cinza) ou uma futura (só a sugestão, apagada).
class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({
    super.key,
    required this.entry,
    required this.row,
    required this.onLogged,
  });

  final SessionExercise entry;
  final int row;
  final ValueChanged<LoggedSet> onLogged;

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  final _load = TextEditingController();
  final _reps = TextEditingController();
  late String _kind = widget.entry.suggestion(widget.row).kind;
  bool _saving = false;
  String? _error;

  SessionExercise get _entry => widget.entry;
  bool get _timed => _entry.exercise.timed;
  bool get _done => widget.row < _entry.mainSets.length;
  bool get _isNext => widget.row == _entry.mainSets.length;

  @override
  void dispose() {
    _load.dispose();
    _reps.dispose();
    super.dispose();
  }

  /// O que vai ser salvo: o digitado ou, se vazio, a sugestão (1 toque no ✓).
  Map<String, Object?>? _values() {
    final suggestion = _entry.suggestion(widget.row);
    final typedLoad = _load.text.trim();
    final load = typedLoad.isEmpty
        ? suggestion.loadKg
        : parseDecimal(typedLoad);
    if (typedLoad.isNotEmpty && load == null) {
      setState(() => _error = 'Carga inválida.');
      return null;
    }
    final typedCount = int.tryParse(_reps.text.trim());
    if (_timed) {
      final duration = typedCount ?? suggestion.durationS;
      if (duration == null || duration < 1) {
        setState(() => _error = 'Informe a duração.');
        return null;
      }
      return {'kind': _kind, 'duration_s': duration, 'load_kg': ?load};
    }
    final reps = typedCount ?? suggestion.reps;
    if (reps == null || reps < 1) {
      setState(() => _error = 'Informe as repetições.');
      return null;
    }
    return {'kind': _kind, 'reps': reps, 'load_kg': ?load};
  }

  Future<void> _log() async {
    final values = _values();
    if (values == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final logged = await ref
          .read(sessionProvider.notifier)
          .logSet(_entry.id, values);
      unawaited(HapticFeedback.lightImpact());
      widget.onLogged(logged);
    } on ApiException catch (error) {
      // O erro fica na linha, com os valores, para tentar de novo.
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(LoggedSet set) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EditSetDialog(
        entry: _entry,
        set: set,
        title: 'Série ${widget.row + 1}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = _entry.suggestion(widget.row);
    final number = '${widget.row + 1}';
    final technique = _entry.technique(widget.row);

    if (_done) {
      final set = _entry.mainSets[widget.row];
      final value =
          '${setValue(reps: set.reps, loadKg: set.loadKg, durationS: set.durationS)}'
          '${set.toFailure ? ' · até a falha' : ''}';
      return Semantics(
        container: true,
        button: true,
        label: 'Série $number feita: $value. Toque para corrigir.',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => _edit(set),
          child: SizedBox(
            height: evoTouchTargetMin,
            child: Row(
              children: [
                _KindBadge(number: number, warmup: set.isWarmup),
                const SizedBox(width: EvoSpace.md),
                Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
                const Padding(
                  padding: EdgeInsets.all(EvoSpace.md),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: EvoColors.success,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isNext) {
      // Série futura: só a referência, sem campos (as séries são feitas em ordem).
      final hint =
          '${_timed ? '${suggestion.durationS ?? '—'} s' : setValue(reps: suggestion.reps, loadKg: suggestion.loadKg)}'
          '${technique == null ? '' : ' · ${segmentLabel(technique).toLowerCase()}'}';
      return SizedBox(
        height: evoTouchTargetMin,
        child: Row(
          children: [
            _KindBadge(
              number: number,
              warmup: suggestion.kind == SetKind.warmup,
              faded: true,
            ),
            const SizedBox(width: EvoSpace.md),
            Flexible(
              child: Text(
                hint,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: EvoColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Nó próprio: sem isso o TalkBack junta o rótulo com os campos ao lado.
            Semantics(
              container: true,
              button: true,
              label: _kind == SetKind.warmup
                  ? 'Série $number de ${_entry.exercise.name}, aquecimento. '
                        'Toque para marcar como válida.'
                  : 'Série $number de ${_entry.exercise.name}, válida. '
                        'Toque para marcar como aquecimento.',
              excludeSemantics: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(
                  () => _kind = _kind == SetKind.warmup
                      ? SetKind.working
                      : SetKind.warmup,
                ),
                child: SizedBox.square(
                  dimension: evoTouchTargetMin,
                  child: Center(
                    child: _KindBadge(
                      number: number,
                      warmup: _kind == SetKind.warmup,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: EvoSpace.sm),
            if (_entry.exercise.loadType != 'time' &&
                _entry.exercise.loadType != 'bodyweight') ...[
              Expanded(
                child: TextField(
                  controller: _load,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'kg',
                    hintText: suggestion.loadKg == null
                        ? null
                        : formatDecimal(suggestion.loadKg!),
                    isDense: true,
                    // Rótulo sempre no alto: a sugestão (dica em cinza) aparece
                    // sem precisar tocar no campo.
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
              const SizedBox(width: EvoSpace.sm),
            ],
            Expanded(
              child: TextField(
                controller: _reps,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _timed ? 'seg' : 'reps',
                  hintText:
                      '${(_timed ? suggestion.durationS : suggestion.reps) ?? ''}',
                  isDense: true,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Concluir série $number de ${_entry.exercise.name}',
              onPressed: _saving ? null : _log,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
            ),
          ],
        ),
        if (technique != null)
          Padding(
            padding: const EdgeInsets.only(
              left: EvoSpace.x3xl,
              bottom: EvoSpace.xs,
            ),
            child: Text(
              technique == SetKind.drop
                  ? 'Drop set nesta série: depois do ✓, registre o drop.'
                  : 'Rest-pause nesta série: depois do ✓, pausa curta e mais repetições.',
              style: theme.textTheme.labelSmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(
              left: EvoSpace.x3xl,
              bottom: EvoSpace.sm,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                '$_error Toque em ✓ para tentar de novo.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: EvoColors.danger,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({
    required this.number,
    required this.warmup,
    this.faded = false,
  });

  final String number;
  final bool warmup;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    // Aquecimento: "A" no lugar do número (não só a cor).
    final text = warmup ? 'A' : number;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: warmup || faded ? EvoColors.bgElevated : EvoColors.accent,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: warmup || faded ? EvoColors.textPrimary : EvoColors.onAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EditSetDialog extends ConsumerStatefulWidget {
  const _EditSetDialog({
    required this.entry,
    required this.set,
    required this.title,
  });

  final SessionExercise entry;
  final LoggedSet set;
  final String title;

  @override
  ConsumerState<_EditSetDialog> createState() => _EditSetDialogState();
}

class _EditSetDialogState extends ConsumerState<_EditSetDialog> {
  late final _load = TextEditingController(
    text: widget.set.loadKg == null ? '' : formatDecimal(widget.set.loadKg!),
  );
  late final _count = TextEditingController(
    text:
        '${(widget.entry.exercise.timed ? widget.set.durationS : widget.set.reps) ?? ''}',
  );
  late bool _toFailure = widget.set.toFailure;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _load.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _apply(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timed = widget.entry.exercise.timed;
    final controller = ref.read(sessionProvider.notifier);
    final segments = widget.entry.segmentsOf(widget.set.id).length;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasLoad(widget.entry.exercise))
            TextField(
              controller: _load,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Carga',
                suffixText: 'kg',
              ),
            ),
          const SizedBox(height: EvoSpace.md),
          TextField(
            controller: _count,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: timed ? 'Duração (s)' : 'Repetições',
            ),
          ),
          if (!widget.set.isWarmup)
            CheckboxListTile(
              value: _toFailure,
              onChanged: (v) => setState(() => _toFailure = v ?? false),
              title: const Text('Até a falha'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          if (segments > 0)
            Text(
              segments == 1
                  ? 'Apagar esta série apaga também o drop ou rest-pause dela.'
                  : 'Apagar esta série apaga também os $segments drops ou rest-pauses dela.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          if (_error != null) ...[
            const SizedBox(height: EvoSpace.sm),
            Text(_error!, style: const TextStyle(color: EvoColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => _apply(
                  () => controller.deleteSet(widget.entry.id, widget.set.id),
                ),
          style: TextButton.styleFrom(foregroundColor: EvoColors.danger),
          child: const Text('Apagar'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () {
                  final count = int.tryParse(_count.text);
                  if (count == null || count < 1) {
                    setState(
                      () => _error = 'Informe um número maior que zero.',
                    );
                    return;
                  }
                  final load = _load.text.trim().isEmpty
                      ? null
                      : parseDecimal(_load.text);
                  _apply(
                    () => controller.updateSet(widget.entry.id, widget.set.id, {
                      if (timed) 'duration_s': count else 'reps': count,
                      if (_hasLoad(widget.entry.exercise)) 'load_kg': load,
                      if (_toFailure != widget.set.toFailure) ...{
                        'to_failure': _toFailure,
                        // Até a falha não sobra repetição em reserva.
                        if (_toFailure && (widget.set.rir ?? 0) > 0)
                          'rir': null,
                      },
                    }),
                  );
                },
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, evoTouchTargetMin),
          ),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Barra do descanso: contagem, −15 s, +15 s e pular. Avisa (vibração e leitor de tela)
/// quando termina.
class _RestBar extends ConsumerStatefulWidget {
  const _RestBar();

  @override
  ConsumerState<_RestBar> createState() => _RestBarState();
}

class _RestBarState extends ConsumerState<_RestBar> {
  RestTimer? _announcedFor;

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(restTimerProvider);
    if (timer == null) return const SizedBox.shrink();
    final now = ref.watch(clockTickProvider).value ?? DateTime.now();
    final left = timer.remainingAt(now);
    final controller = ref.read(restTimerProvider.notifier);
    final theme = Theme.of(context);

    if (left == 0 && _announcedFor != timer) {
      _announcedFor = timer;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.heavyImpact();
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Descanso terminado',
          TextDirection.ltr,
        );
      });
    }

    return Container(
      width: double.infinity,
      color: EvoColors.accent,
      padding: const EdgeInsets.symmetric(
        horizontal: EvoSpace.lg,
        vertical: EvoSpace.sm,
      ),
      // Texto e botões quebram de linha com fonte grande (Wrap), sem estourar.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            liveRegion: left == 0,
            child: Text(
              left == 0
                  ? 'Descanso terminado'
                  : 'Descanso ${formatElapsed(Duration(seconds: left))}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: EvoColors.onAccent,
              ),
            ),
          ),
          Wrap(
            children: [
              for (final (label, tooltip, action) in [
                ('−15', 'Menos 15 segundos', () => controller.adjust(-15)),
                ('+15', 'Mais 15 segundos', () => controller.adjust(15)),
              ])
                Tooltip(
                  message: tooltip,
                  excludeFromSemantics: true,
                  child: Semantics(
                    button: true,
                    label: tooltip,
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: action,
                      style: TextButton.styleFrom(
                        foregroundColor: EvoColors.onAccent,
                      ),
                      child: Text(label),
                    ),
                  ),
                ),
              TextButton(
                onPressed: controller.skip,
                style: TextButton.styleFrom(
                  foregroundColor: EvoColors.onAccent,
                ),
                child: Text(left == 0 ? 'Fechar' : 'Pular'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinishSheet extends StatefulWidget {
  const _FinishSheet();

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  int? _effort;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            EvoSpace.xl,
            0,
            EvoSpace.xl,
            EvoSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Finalizar treino',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: EvoSpace.lg),
              const EvoFieldLabel(
                'Esforço percebido',
                hint: 'Opcional. 1 = muito leve, 10 = máximo.',
              ),
              EvoChipGroup(
                single: true,
                options: [for (var i = 1; i <= 10; i++) ('$i', '$i')],
                selected: {if (_effort != null) '$_effort'},
                onChanged: (v) {
                  final value = int.parse(v.first);
                  setState(() => _effort = _effort == value ? null : value);
                },
              ),
              const SizedBox(height: EvoSpace.xl),
              TextField(
                controller: _notes,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Como foi? (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: EvoSpace.lg),
              EvoButton(
                label: 'Salvar treino',
                onPressed: () =>
                    Navigator.of(context).pop((_effort, _notes.text.trim())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
