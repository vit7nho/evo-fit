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
        onAddRow: () => setState(
          () => _extraRows[entry.id] = (_extraRows[entry.id] ?? 0) + 1,
        ),
        onLogged: () {
          final extra = _extraRows[entry.id] ?? 0;
          if (extra > 0 && entry.sets.length + 1 >= entry.rowCount()) {
            _extraRows[entry.id] = extra - 1;
          }
          _afterSet(index);
        },
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
    required this.onAddRow,
    required this.onLogged,
    required this.onRemove,
  });

  final SessionExercise entry;
  final int extraRows;
  final VoidCallback onAddRow;
  final VoidCallback onLogged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rows = entry.rowCount(extra: extraRows);
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
            for (var row = 0; row < rows; row++)
              _SetRow(
                key: ValueKey('${entry.id}-$row-${entry.sets.length}'),
                entry: entry,
                row: row,
                onLogged: onLogged,
              ),
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

  static String _describe(PreviousSet s) {
    if (s.durationS != null) return '${s.durationS} s';
    final load = s.loadKg == null ? '' : '${formatDecimal(s.loadKg!)} kg × ';
    return '$load${s.reps ?? '—'}';
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
  final VoidCallback onLogged;

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
  bool get _done => widget.row < _entry.sets.length;
  bool get _isNext => widget.row == _entry.sets.length;

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
      await ref.read(sessionProvider.notifier).logSet(_entry.id, values);
      unawaited(HapticFeedback.lightImpact());
      widget.onLogged();
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
      builder: (_) => _EditSetDialog(entry: _entry, set: set),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = _entry.suggestion(widget.row);
    final number = '${widget.row + 1}';

    if (_done) {
      final set = _entry.sets[widget.row];
      final value = _timed
          ? '${set.durationS} s'
          : '${set.loadKg == null ? '' : '${formatDecimal(set.loadKg!)} kg × '}${set.reps}';
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
      final hint = _timed
          ? '${suggestion.durationS ?? '—'} s'
          : '${suggestion.loadKg == null ? '' : '${formatDecimal(suggestion.loadKg!)} kg × '}${suggestion.reps ?? '—'}';
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
  const _EditSetDialog({required this.entry, required this.set});

  final SessionExercise entry;
  final LoggedSet set;

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
    return AlertDialog(
      title: Text('Série ${widget.set.position + 1}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!timed)
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
                      if (!timed) 'load_kg': load,
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
