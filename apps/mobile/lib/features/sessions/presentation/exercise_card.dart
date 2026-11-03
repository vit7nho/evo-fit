import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../goals/presentation/goal_format.dart';
import '../../training/domain/template.dart';
import '../../training/presentation/item_editor_page.dart'
    show restLabel, restOptions;
import '../application/session_controller.dart';
import '../domain/session.dart';
import '../domain/set_rows.dart';

/// Pausa curta do rest-pause, entre a série e as repetições extras.
const restPauseS = 15;

/// Até quantas linhas um exercício mostra (a API aceita 20 séries).
const _maxRows = 20;

/// "60 kg × 10", "12" (sem carga) ou "45 s".
String setValue({int? reps, double? loadKg, int? durationS}) {
  if (durationS != null) return '$durationS s';
  final load = loadKg == null ? '' : '${formatDecimal(loadKg)} kg × ';
  return '$load${reps ?? '—'}';
}

/// Carga faz sentido para o exercício (não é por tempo nem só com o corpo).
bool hasLoad(TemplateExercise exercise) =>
    exercise.loadType != 'time' && exercise.loadType != 'bodyweight';

/// Cartão de um exercício no treino: tabela SÉRIE · ANTERIOR · KG · REPS · ✓.
///
/// Todas as linhas ficam editáveis, com a sugestão em cinza; um toque no ✓ salva
/// (com a sugestão, se nada foi digitado) e outro desfaz. O tipo (aquecimento,
/// válida, falha, drop, rest-pause) muda tocando no número. As linhas vivem aqui,
/// na ordem da tela; a API guarda as séries feitas.
class ExerciseCard extends ConsumerStatefulWidget {
  const ExerciseCard({
    super.key,
    required this.session,
    required this.index,
    required this.onRemove,
  });

  final WorkoutSession session;

  /// Posição do exercício em [WorkoutSession.exercises].
  final int index;
  final VoidCallback onRemove;

  @override
  ConsumerState<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<ExerciseCard> {
  var _nextId = 0;
  late List<SetRowDraft> _rows = buildRows(_entry, _newId);

  /// O que foi digitado em cada linha por fazer (texto cru), pelo id da linha.
  final _typed = <int, ({String load, String count})>{};
  final _errors = <int, String>{};
  final _saving = <int>{};

  SessionExercise get _entry => widget.session.exercises[widget.index];
  bool get _timed => _entry.exercise.timed;
  String get _name => _entry.exercise.name;

  int _newId() => _nextId++;

  @override
  void didUpdateWidget(ExerciseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rows = reconcileRows(_rows, _entry, _newId);
  }

  LoggedSet? _logged(SetRowDraft row) {
    for (final s in _entry.sets) {
      if (s.id == row.loggedId) return s;
    }
    return null;
  }

  /// Valores da linha [i]: os salvos, se feita; senão o digitado ou a sugestão.
  RowSuggestion _valuesOf(int i) {
    final row = _rows[i];
    final logged = _logged(row);
    if (logged != null) {
      return (
        reps: logged.reps,
        loadKg: logged.loadKg,
        durationS: logged.durationS,
      );
    }
    final suggestion = _suggestion(i);
    final typed = _typed[row.id];
    final count = int.tryParse(typed?.count.trim() ?? '');
    final load = parseDecimal(typed?.load.trim() ?? '');
    return (
      reps: _timed ? null : count ?? suggestion.reps,
      loadKg: load ?? suggestion.loadKg,
      durationS: _timed ? count ?? suggestion.durationS : null,
    );
  }

  RowSuggestion _suggestion(int i) =>
      suggestRow(_entry, _rows, i, valuesOf: _valuesOf);

  /// "série 2", "aquecimento", "drop da série 2": nome da linha para o leitor de tela.
  String _rowName(int i) {
    final kind = _rows[i].kind;
    if (kind == RowKind.warmup) return 'série de aquecimento';
    if (kind.isMainWorking) return 'série ${_mainNumber(i)}';
    final parent = parentRowOf(_rows, i);
    final of = parent != null && _rows[parent].kind.isMainWorking
        ? ' da série ${_mainNumber(parent)}'
        : '';
    return '${kind.label.toLowerCase()}$of';
  }

  int _mainNumber(int i) =>
      _rows.take(i + 1).where((r) => r.kind.isMainWorking).length;

  Future<void> _guard(int rowId, Future<void> Function() action) async {
    setState(() {
      _saving.add(rowId);
      _errors.remove(rowId);
    });
    try {
      await action();
    } on ApiException catch (error) {
      // O erro fica na linha, com os valores, para tentar de novo.
      if (mounted) setState(() => _errors[rowId] = error.message);
    } finally {
      if (mounted) setState(() => _saving.remove(rowId));
    }
  }

  void _fail(int rowId, String message) =>
      setState(() => _errors[rowId] = message);

  Future<void> _complete(int i) async {
    final row = _rows[i];
    final typed = _typed[row.id];
    if ((typed?.load.trim() ?? '').isNotEmpty &&
        parseDecimal(typed!.load.trim()) == null) {
      return _fail(row.id, 'Carga inválida.');
    }
    final values = _valuesOf(i);
    final body = <String, Object?>{...row.kind.apiFields};
    if (_timed) {
      if (values.durationS == null || values.durationS! < 1) {
        return _fail(row.id, 'Informe a duração.');
      }
      body['duration_s'] = values.durationS;
    } else {
      if (values.reps == null || values.reps! < 1) {
        return _fail(row.id, 'Informe as repetições.');
      }
      body['reps'] = values.reps;
    }
    if (hasLoad(_entry.exercise) && values.loadKg != null) {
      body['load_kg'] = values.loadKg;
    }
    if (row.kind.isSegment) {
      final parent = parentRowOf(_rows, i);
      final parentRow = parent == null ? null : _rows[parent];
      if (parentRow == null || !parentRow.kind.isMainWorking) {
        return _fail(
          row.id,
          '${row.kind.label} continua uma série válida: '
          'deixe uma acima dele.',
        );
      }
      if (!parentRow.isDone) {
        return _fail(row.id, 'Conclua a série acima primeiro.');
      }
      body['parent_set_id'] = parentRow.loggedId;
    }
    await _guard(row.id, () async {
      final logged = await ref
          .read(sessionProvider.notifier)
          .logSet(_entry.id, body);
      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final r in _rows)
            r.id == row.id ? r.copyWith(loggedId: logged.id) : r,
        ];
        _typed.remove(row.id);
      });
      _startRest(_rows.indexWhere((r) => r.id == row.id));
    });
  }

  /// Depois de uma linha: se a próxima é um drop, segue sem descanso; se é um
  /// rest-pause, pausa curta; senão, o descanso do exercício (ou do grupo).
  void _startRest(int i) {
    final timer = ref.read(restTimerProvider.notifier);
    final next = i + 1 < _rows.length ? _rows[i + 1] : null;
    if (next != null && !next.isDone && next.kind.isSegment) {
      if (next.kind == RowKind.drop) {
        timer.skip();
      } else {
        timer.start(restPauseS);
      }
      return;
    }
    final rest = widget.session.restAfter(widget.index);
    if (rest != null && rest > 0) timer.start(rest);
  }

  /// Desfaz uma linha feita: apaga a série (e os segmentos dela, na API) e a
  /// linha volta a ficar por fazer, com os valores digitados.
  Future<void> _undo(int i) async {
    final row = _rows[i];
    final logged = _logged(row);
    if (logged == null) return;
    await _guard(row.id, () async {
      await ref.read(sessionProvider.notifier).deleteSet(_entry.id, logged.id);
      if (!mounted) return;
      setState(() {
        _typed[row.id] = (
          load: logged.loadKg == null ? '' : formatDecimal(logged.loadKg!),
          count: '${(_timed ? logged.durationS : logged.reps) ?? ''}',
        );
      });
    });
  }

  /// Correção de uma linha feita (campo editado e deixado).
  Future<void> _edit(int i, String load, String count) async {
    final row = _rows[i];
    final logged = _logged(row);
    if (logged == null) return;
    final newCount = int.tryParse(count.trim());
    final newLoad = load.trim().isEmpty ? null : parseDecimal(load.trim());
    if (load.trim().isNotEmpty && newLoad == null) {
      return _fail(row.id, 'Carga inválida.');
    }
    if (newCount == null || newCount < 1) {
      return _fail(row.id, 'Informe um número maior que zero.');
    }
    final changes = <String, Object?>{
      if (_timed && newCount != logged.durationS) 'duration_s': newCount,
      if (!_timed && newCount != logged.reps) 'reps': newCount,
      if (hasLoad(_entry.exercise) && newLoad != logged.loadKg)
        'load_kg': newLoad,
    };
    if (changes.isEmpty) return;
    await _guard(
      row.id,
      () => ref
          .read(sessionProvider.notifier)
          .updateSet(_entry.id, logged.id, changes),
    );
  }

  Future<void> _changeKind(int i) async {
    final row = _rows[i];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _KindSheet(
        current: row.kind,
        badge: rowBadge(_rows, i),
        disabledReason: (kind) => _disabledReason(i, kind),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _removeRow) return _remove(i);
    final kind = choice as RowKind;
    if (kind == row.kind) return;
    if (!row.isDone) {
      setState(() {
        _rows = [
          for (final r in _rows) r.id == row.id ? r.copyWith(kind: kind) : r,
        ];
        _errors.remove(row.id);
      });
      return;
    }
    final logged = _logged(row)!;
    await _guard(row.id, () async {
      await ref.read(sessionProvider.notifier).updateSet(_entry.id, logged.id, {
        'kind': kind.apiFields['kind'],
        'to_failure': kind == RowKind.failure,
        // Até a falha não sobra repetição em reserva.
        if (kind == RowKind.failure && (logged.rir ?? 0) > 0) 'rir': null,
      });
      if (mounted) {
        setState(
          () => _rows = [
            for (final r in _rows) r.id == row.id ? r.copyWith(kind: kind) : r,
          ],
        );
      }
    });
  }

  /// Por que o tipo [kind] não vale para a linha [i] (nulo = vale).
  String? _disabledReason(int i, RowKind kind) {
    final row = _rows[i];
    if (kind == row.kind) return null;
    if (kind == RowKind.drop && _entry.exercise.loadType != 'external') {
      return 'Drop tira carga: só em exercício com carga.';
    }
    if (kind.isSegment && _timed) return 'Não vale para exercício por tempo.';
    if (row.isDone && row.kind.isSegment) {
      return 'Desfaça a linha (✓) para mudar o tipo.';
    }
    if (row.isDone && kind.isSegment) {
      return 'Desfaça a série (✓) para transformar em ${kind.label.toLowerCase()}.';
    }
    if (kind.isSegment) {
      final parent = parentRowOf(_rows, i);
      if (parent == null || !_rows[parent].kind.isMainWorking) {
        return 'Precisa de uma série válida acima.';
      }
    }
    if (row.isDone &&
        kind == RowKind.warmup &&
        i + 1 < _rows.length &&
        _rows[i + 1].kind.isSegment &&
        _rows[i + 1].isDone) {
      return 'Esta série tem drop ou rest-pause: desfaça-os antes.';
    }
    return null;
  }

  Future<void> _remove(int i) async {
    final row = _rows[i];
    final logged = _logged(row);
    if (logged != null) {
      await _guard(
        row.id,
        () =>
            ref.read(sessionProvider.notifier).deleteSet(_entry.id, logged.id),
      );
      if (!mounted || _logged(row) != null) return;
    }
    setState(() {
      _rows = [
        for (final r in _rows)
          if (r.id != row.id) r,
      ];
      _typed.remove(row.id);
      _errors.remove(row.id);
    });
  }

  void _addRow() => setState(
    () => _rows = [
      ..._rows,
      SetRowDraft(id: _newId(), kind: kindForNewRow(_entry, _rows)),
    ],
  );

  Future<void> _pickRest() async {
    final current = _entry.restS ?? 0;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Descanso de $_name',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              const SizedBox(height: EvoSpace.sm),
              for (final seconds in restOptions)
                ListTile(
                  title: Text(
                    seconds == 0 ? 'Sem descanso' : restLabel(seconds),
                  ),
                  trailing: seconds == current
                      ? const Icon(Icons.check_rounded)
                      : null,
                  selected: seconds == current,
                  onTap: () => Navigator.of(context).pop(seconds),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    await _guardCard(
      () => ref.read(sessionProvider.notifier).updateExercise(_entry.id, {
        'rest_s': picked,
      }),
    );
  }

  Future<void> _editNote() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(exercise: _name, initial: _entry.notes ?? ''),
    );
    if (note == null || note == (_entry.notes ?? '') || !mounted) return;
    await _guardCard(
      () => ref.read(sessionProvider.notifier).updateExercise(_entry.id, {
        'notes': note,
      }),
    );
  }

  Future<void> _guardCard(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _entry;
    final rest = entry.restS ?? 0;
    // Com fonte grande ou tela estreita, a coluna "Anterior" desce para baixo
    // dos campos e os campos ganham rótulo próprio.
    final compact =
        MediaQuery.textScalerOf(context).scale(10) > 13 ||
        MediaQuery.sizeOf(context).width < 360;

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
                    child: Text(_name, style: theme.textTheme.titleMedium),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ações de $_name',
                  onSelected: (_) => widget.onRemove(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Tirar do treino'),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: EvoSpace.sm),
              child: Wrap(
                spacing: EvoSpace.sm,
                runSpacing: EvoSpace.xs,
                children: [
                  // No grupo, quem manda é o descanso após a rodada.
                  if (entry.group == null)
                    ActionChip(
                      avatar: const Icon(Icons.timer_outlined, size: 18),
                      label: Text(
                        rest == 0
                            ? 'Sem descanso'
                            : 'Descanso: ${restLabel(rest)}',
                      ),
                      tooltip: 'Mudar o descanso de $_name',
                      onPressed: _pickRest,
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(entry.notes == null ? 'Nota' : 'Editar nota'),
                    tooltip: 'Nota de $_name',
                    onPressed: _editNote,
                  ),
                ],
              ),
            ),
            if (entry.notes != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: EvoSpace.xs,
                  right: EvoSpace.sm,
                ),
                child: Text(entry.notes!, style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: EvoSpace.md),
            if (!compact)
              _HeaderRow(timed: _timed, load: hasLoad(entry.exercise)),
            for (final (i, row) in _rows.indexed)
              _SetRowTile(
                key: ValueKey('${entry.id}-${row.id}'),
                exercise: entry.exercise,
                row: row,
                logged: _logged(row),
                badge: rowBadge(_rows, i),
                name: '${_rowName(i)} de $_name',
                kindLabel: row.kind.label.toLowerCase(),
                previous: _previousText(i),
                suggestion: _suggestion(i),
                typed: _typed[row.id],
                error: _errors[row.id],
                saving: _saving.contains(row.id),
                compact: compact,
                onTyped: (load, count) =>
                    _typed[row.id] = (load: load, count: count),
                onCheck: () => row.isDone ? _undo(i) : _complete(i),
                onBadge: () => _changeKind(i),
                onEdit: (load, count) => _edit(i, load, count),
              ),
            const SizedBox(height: EvoSpace.sm),
            Padding(
              padding: const EdgeInsets.only(right: EvoSpace.sm),
              child: EvoButton(
                label: 'Adicionar série',
                icon: Icons.add_rounded,
                variant: EvoButtonVariant.secondary,
                onPressed: _rows.length < _maxRows ? _addRow : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _previousText(int i) {
    final p = previousAt(_entry, i);
    if (p == null) return '—';
    return '${setValue(reps: p.reps, loadKg: p.loadKg, durationS: p.durationS)}'
        '${p.toFailure ? ' (F)' : ''}';
  }
}

/// Valor que o menu do tipo devolve para "Remover série".
const _removeRow = #remove;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.timed, required this.load});

  final bool timed;
  final bool load;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    Widget cell(String text, {int flex = 2}) => Expanded(
      flex: flex,
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
    // Cabeçalho só para quem vê: cada campo já tem nome para o leitor de tela.
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: EvoSpace.xs),
        child: Row(
          children: [
            SizedBox(
              width: evoTouchTargetMin,
              child: Text('SÉRIE', style: style, textAlign: TextAlign.center),
            ),
            cell('ANTERIOR', flex: 3),
            if (load) cell('KG'),
            cell(timed ? 'SEG' : 'REPS'),
            SizedBox(
              width: evoTouchTargetMin,
              child: Icon(Icons.check_rounded, size: 18, color: style?.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma linha da tabela. Por fazer: campos com a sugestão em cinza e ✓ vazado.
/// Feita: fundo destacado, ✓ preenchido (toque desfaz) e campos que corrigem a
/// série ao sair deles.
class _SetRowTile extends StatefulWidget {
  const _SetRowTile({
    super.key,
    required this.exercise,
    required this.row,
    required this.logged,
    required this.badge,
    required this.name,
    required this.kindLabel,
    required this.previous,
    required this.suggestion,
    required this.typed,
    required this.error,
    required this.saving,
    required this.compact,
    required this.onTyped,
    required this.onCheck,
    required this.onBadge,
    required this.onEdit,
  });

  final TemplateExercise exercise;
  final SetRowDraft row;
  final LoggedSet? logged;
  final String badge;

  /// "série 2 de Supino reto com barra".
  final String name;
  final String kindLabel;
  final String previous;
  final RowSuggestion suggestion;
  final ({String load, String count})? typed;
  final String? error;
  final bool saving;
  final bool compact;
  final void Function(String load, String count) onTyped;
  final VoidCallback onCheck;
  final VoidCallback onBadge;
  final void Function(String load, String count) onEdit;

  @override
  State<_SetRowTile> createState() => _SetRowTileState();
}

class _SetRowTileState extends State<_SetRowTile> {
  late final _load = TextEditingController();
  late final _count = TextEditingController();
  final _loadFocus = FocusNode();
  final _countFocus = FocusNode();

  bool get _done => widget.logged != null;
  bool get _timed => widget.exercise.timed;

  @override
  void initState() {
    super.initState();
    _fill();
    for (final node in [_loadFocus, _countFocus]) {
      node.addListener(_maybeCommit);
    }
  }

  /// Feita: os valores salvos. Por fazer: o que estava digitado (ou vazio, e a
  /// sugestão aparece em cinza).
  void _fill() {
    final logged = widget.logged;
    if (logged != null) {
      _load.text = logged.loadKg == null ? '' : formatDecimal(logged.loadKg!);
      _count.text = '${(_timed ? logged.durationS : logged.reps) ?? ''}';
    } else {
      _load.text = widget.typed?.load ?? '';
      _count.text = widget.typed?.count ?? '';
    }
  }

  @override
  void didUpdateWidget(_SetRowTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        (oldWidget.logged == null) != (widget.logged == null) ||
        (_done &&
            !_loadFocus.hasFocus &&
            !_countFocus.hasFocus &&
            oldWidget.logged != widget.logged);
    if (changed) _fill();
  }

  void _maybeCommit() {
    if (_done && !_loadFocus.hasFocus && !_countFocus.hasFocus) {
      widget.onEdit(_load.text, _count.text);
    }
  }

  @override
  void dispose() {
    _load.dispose();
    _count.dispose();
    _loadFocus.dispose();
    _countFocus.dispose();
    super.dispose();
  }

  Widget _field({
    required TextEditingController controller,
    required FocusNode focus,
    required String label,
    required String? hint,
    required String semantics,
    required bool decimal,
  }) {
    return Semantics(
      label: semantics,
      textField: true,
      child: TextField(
        controller: controller,
        focusNode: focus,
        textAlign: TextAlign.center,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        inputFormatters: decimal
            ? null
            : [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) {
          if (!_done) widget.onTyped(_load.text, _count.text);
        },
        decoration: InputDecoration(
          labelText: widget.compact ? label : null,
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: _done ? EvoColors.bgSurface : EvoColors.bgElevated,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: EvoSpace.xs,
            vertical: EvoSpace.md,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.suggestion;
    final showLoad = hasLoad(widget.exercise);
    final countHint = _timed ? s.durationS : s.reps;

    final badge = Semantics(
      container: true,
      button: true,
      label:
          '${widget.name[0].toUpperCase()}${widget.name.substring(1)}, '
          '${widget.kindLabel}. Toque para mudar o tipo.',
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: widget.saving ? null : widget.onBadge,
        child: SizedBox.square(
          dimension: evoTouchTargetMin,
          child: Center(
            child: KindBadge(text: widget.badge, done: _done),
          ),
        ),
      ),
    );

    final load = showLoad
        ? _field(
            controller: _load,
            focus: _loadFocus,
            label: 'kg',
            hint: s.loadKg == null ? null : formatDecimal(s.loadKg!),
            semantics: 'Carga em kg, ${widget.name}',
            decimal: true,
          )
        : null;
    final count = _field(
      controller: _count,
      focus: _countFocus,
      label: _timed ? 'seg' : 'reps',
      hint: countHint == null ? null : '$countHint',
      semantics: '${_timed ? 'Segundos' : 'Repetições'}, ${widget.name}',
      decimal: false,
    );

    // Guardada no aparelho, esperando conexão: relógio no lugar do ✓ verde (a forma
    // muda, não só a cor), e o leitor de tela diz que ainda não foi enviada.
    final pending = widget.logged?.pending ?? false;
    final check = IconButton(
      tooltip: _done
          ? 'Desfazer ${widget.name}${pending ? ', guardada no aparelho' : ''}'
          : 'Concluir ${widget.name}',
      onPressed: widget.saving ? null : widget.onCheck,
      style: _done
          ? IconButton.styleFrom(
              backgroundColor: pending
                  ? EvoColors.textSecondary
                  : EvoColors.success,
              foregroundColor: EvoColors.onAccent,
            )
          : null,
      icon: widget.saving
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Icon(
              !_done
                  ? Icons.check_circle_outline_rounded
                  : pending
                  ? Icons.schedule_rounded
                  : Icons.check_rounded,
            ),
    );

    final previous = Text(
      widget.previous,
      textAlign: widget.compact ? TextAlign.start : TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: EvoColors.textSecondary,
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: EvoSpace.xs),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: _done ? EvoColors.bgElevated : null,
        borderRadius: BorderRadius.circular(EvoRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              badge,
              if (!widget.compact)
                Expanded(flex: 3, child: ExcludeSemantics(child: previous)),
              if (load != null) ...[
                Expanded(flex: 2, child: load),
                const SizedBox(width: EvoSpace.xs),
              ],
              Expanded(flex: 2, child: count),
              check,
            ],
          ),
          if (widget.compact && widget.previous != '—')
            Padding(
              padding: const EdgeInsets.only(
                left: evoTouchTargetMin,
                bottom: EvoSpace.xs,
              ),
              child: Text(
                'Anterior: ${widget.previous}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(
                left: evoTouchTargetMin,
                bottom: EvoSpace.sm,
                right: EvoSpace.sm,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '${widget.error} Toque em ✓ para tentar de novo.',
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

/// Número da série ou letra do tipo (A, F, D, RP): o tipo não depende só de cor.
class KindBadge extends StatelessWidget {
  const KindBadge({super.key, required this.text, this.done = false});

  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final letter = int.tryParse(text) == null;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: letter ? EvoColors.bgSurface : EvoColors.accent,
        border: letter ? Border.all(color: EvoColors.borderStrong) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: letter ? EvoColors.textPrimary : EvoColors.onAccent,
          fontWeight: FontWeight.w700,
          fontSize: text.length > 1 && letter ? 12 : 14,
        ),
      ),
    );
  }
}

/// Menu do tipo da linha: cada opção com a letra, o nome e para que serve.
class _KindSheet extends StatelessWidget {
  const _KindSheet({
    required this.current,
    required this.badge,
    required this.disabledReason,
  });

  final RowKind current;
  final String badge;
  final String? Function(RowKind kind) disabledReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
              child: Semantics(
                header: true,
                child: Text('Tipo da série', style: theme.textTheme.titleLarge),
              ),
            ),
            const SizedBox(height: EvoSpace.sm),
            for (final kind in RowKind.values)
              Builder(
                builder: (context) {
                  final reason = disabledReason(kind);
                  return ListTile(
                    enabled: reason == null,
                    leading: KindBadge(
                      text: kind == RowKind.working
                          ? (int.tryParse(badge) != null ? badge : '1')
                          : kind.letter,
                    ),
                    title: Text(kind.label),
                    subtitle: Text(reason ?? kind.description),
                    trailing: kind == current
                        ? const Icon(Icons.check_rounded)
                        : null,
                    selected: kind == current,
                    onTap: () => Navigator.of(context).pop(kind),
                  );
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: EvoColors.danger,
              ),
              title: const Text(
                'Remover série',
                style: TextStyle(color: EvoColors.danger),
              ),
              onTap: () => Navigator.of(context).pop(_removeRow),
            ),
            const SizedBox(height: EvoSpace.sm),
          ],
        ),
      ),
    );
  }
}

/// Nota do exercício neste treino (o controlador vive com o diálogo).
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.exercise, required this.initial});

  final String exercise;
  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Nota de ${widget.exercise}'),
    scrollable: true,
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 500,
      minLines: 2,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Ex.: banco no 3, pegada fechada',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, evoTouchTargetMin),
        ),
        child: const Text('Salvar'),
      ),
    ],
  );
}
