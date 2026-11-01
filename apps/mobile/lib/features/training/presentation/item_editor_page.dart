import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/form_focus.dart';
import '../../goals/presentation/goal_format.dart';
import '../domain/template.dart';
import '../domain/template_draft.dart';

/// Opções de descanso, em segundos (0 = sem descanso definido).
const restOptions = [0, 30, 45, 60, 90, 120, 180, 240];

String restLabel(int seconds) => switch (seconds) {
  0 => 'Livre',
  < 60 => '$seconds s',
  _ when seconds % 60 == 0 => '${seconds ~/ 60} min',
  _ => '${seconds ~/ 60} min ${seconds % 60} s',
};

/// Séries, descanso e anotações de um exercício da ficha.
///
/// Recebe uma cópia do item e devolve a versão editada ao salvar (ou nada ao voltar).
class ItemEditorPage extends StatefulWidget {
  const ItemEditorPage({super.key, required this.item, required this.options});

  final DraftItem item;
  final WorkoutOptions options;

  @override
  State<ItemEditorPage> createState() => _ItemEditorPageState();
}

class _SetFields {
  _SetFields(PlannedSet set)
    : kind = set.kind,
      min = TextEditingController(text: set.repsMin?.toString() ?? ''),
      max = TextEditingController(text: set.repsMax?.toString() ?? ''),
      duration = TextEditingController(text: set.durationS?.toString() ?? ''),
      load = TextEditingController(
        text: set.loadKg == null ? '' : formatDecimal(set.loadKg!),
      ),
      rir = set.rirTarget;

  String kind;
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController duration;
  final TextEditingController load;
  int? rir;

  void dispose() {
    for (final c in [min, max, duration, load]) {
      c.dispose();
    }
  }
}

class _ItemEditorPageState extends State<ItemEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final List<_SetFields> _sets = [
    for (final s in widget.item.plannedSets) _SetFields(s),
  ];
  late int _rest = widget.item.restS ?? 0;
  late final _notes = TextEditingController(text: widget.item.notes ?? '');

  bool get _timed => widget.item.exercise.timed;

  @override
  void dispose() {
    for (final s in _sets) {
      s.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _addSet() {
    final last = _sets.isEmpty
        ? PlannedSet(
            durationS: _timed ? 30 : null,
            repsMin: _timed ? null : 8,
            repsMax: _timed ? null : 12,
          )
        : _toSet(_sets.last);
    setState(() => _sets.add(_SetFields(last)));
  }

  PlannedSet _toSet(_SetFields f) {
    final min = int.tryParse(f.min.text);
    final max = int.tryParse(f.max.text);
    return PlannedSet(
      kind: f.kind,
      repsMin: _timed ? null : min ?? max,
      repsMax: _timed ? null : max ?? min,
      durationS: _timed ? int.tryParse(f.duration.text) : null,
      loadKg: parseDecimal(f.load.text),
      rirTarget: f.rir,
    );
  }

  void _save() {
    if (!validateAndFocusFirstError(_formKey.currentState!)) return;
    if (_sets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A ficha precisa de pelo menos uma série.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      widget.item.copy()
        ..plannedSets = [for (final s in _sets) _toSet(s)]
        ..restS = _rest == 0 ? null : _rest
        ..notes = _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
  }

  // --- validação (as mesmas faixas da API) ---

  String? _int(String? value, int min, int max, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Obrigatório.' : null;
    final number = int.tryParse(text);
    if (number == null) return 'Número inteiro.';
    if (number < min || number > max) return 'De $min a $max.';
    return null;
  }

  String? _load(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = parseDecimal(text);
    if (number == null) return 'Número.';
    if (number < 0 || number > 1000) return 'De 0 a 1000.';
    if ((number * 4) != (number * 4).roundToDouble()) {
      return 'Múltiplos de 0,25.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final inGroup = widget.item.group != null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.exercise.name)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                // Rolagem simples: campos fora da tela precisam existir para validar.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(EvoSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, set) in _sets.indexed) ...[
                        _SetCard(
                          number: index + 1,
                          fields: set,
                          timed: _timed,
                          options: widget.options,
                          validateInt: _int,
                          validateLoad: _load,
                          onChanged: () => setState(() {}),
                          onRemove: _sets.length == 1
                              ? null
                              : () => setState(() {
                                  _sets.removeAt(index).dispose();
                                }),
                        ),
                        const SizedBox(height: EvoSpace.md),
                      ],
                      if (_sets.length < TemplateDraft.maxSets)
                        EvoButton(
                          label: 'Adicionar série',
                          icon: Icons.add_rounded,
                          variant: EvoButtonVariant.secondary,
                          onPressed: _addSet,
                        ),
                      const SizedBox(height: EvoSpace.x2xl),
                      EvoFieldLabel(
                        'Descanso entre as séries',
                        hint: inGroup
                            ? 'No grupo, o descanso vale depois da rodada; este '
                                  'é usado se o exercício sair do grupo.'
                            : null,
                      ),
                      EvoChipGroup(
                        single: true,
                        options: [
                          for (final s in restOptions) ('$s', restLabel(s)),
                        ],
                        selected: {'$_rest'},
                        onChanged: (v) =>
                            setState(() => _rest = int.parse(v.first)),
                      ),
                      const SizedBox(height: EvoSpace.x2xl),
                      TextFormField(
                        controller: _notes,
                        maxLength: 300,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Anotações (opcional)',
                          hintText: 'Ex.: pegada aberta, banco no 3',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EvoSpace.xl,
                EvoSpace.sm,
                EvoSpace.xl,
                EvoSpace.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: EvoButton(label: 'Aplicar', onPressed: _save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.number,
    required this.fields,
    required this.timed,
    required this.options,
    required this.validateInt,
    required this.validateLoad,
    required this.onChanged,
    required this.onRemove,
  });

  final int number;
  final _SetFields fields;
  final bool timed;
  final WorkoutOptions options;
  final String? Function(String?, int, int, {bool required}) validateInt;
  final String? Function(String?) validateLoad;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EvoSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Série $number',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remover série $number',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: EvoSpace.sm),
            EvoChipGroup(
              single: true,
              options: [for (final k in options.setKinds) (k.code, k.label)],
              selected: {fields.kind},
              onChanged: (v) {
                fields.kind = v.first;
                onChanged();
              },
            ),
            const SizedBox(height: EvoSpace.lg),
            if (timed)
              TextFormField(
                controller: fields.duration,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                validator: (v) => validateInt(v, 5, 3600),
                decoration: const InputDecoration(
                  labelText: 'Duração',
                  suffixText: 's',
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: fields.min,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      validator: (v) => validateInt(v, 1, 100),
                      decoration: const InputDecoration(labelText: 'Reps mín.'),
                    ),
                  ),
                  const SizedBox(width: EvoSpace.md),
                  Expanded(
                    child: TextFormField(
                      controller: fields.max,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      validator: (v) {
                        final error = validateInt(v, 1, 100, required: false);
                        if (error != null) return error;
                        final min = int.tryParse(fields.min.text);
                        final max = int.tryParse(v ?? '');
                        if (min != null && max != null && max < min) {
                          return 'Menor que o mínimo.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(labelText: 'Reps máx.'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: EvoSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: fields.load,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: validateLoad,
                    decoration: const InputDecoration(
                      labelText: 'Carga',
                      suffixText: 'kg',
                    ),
                  ),
                ),
                const SizedBox(width: EvoSpace.md),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: fields.rir,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'RIR'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (var r = 0; r <= 5; r++)
                        DropdownMenuItem(
                          value: r,
                          child: Text(r == 0 ? '0 (falha)' : '$r'),
                        ),
                    ],
                    onChanged: (v) => fields.rir = v,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
