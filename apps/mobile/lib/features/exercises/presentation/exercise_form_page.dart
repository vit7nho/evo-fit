import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../../shared/widgets/form_focus.dart';
import '../application/exercises_controller.dart';
import '../data/exercises_api.dart';
import '../domain/exercise.dart';

/// Cria ou edita um exercício próprio (os do catálogo são só leitura).
class ExerciseFormPage extends ConsumerWidget {
  const ExerciseFormPage.create({super.key}) : exerciseId = null;

  const ExerciseFormPage.edit({super.key, required String this.exerciseId});

  final String? exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(exerciseOptionsProvider);
    final exercises = exerciseId == null ? null : ref.watch(exercisesProvider);

    Widget message(String title, String text, {VoidCallback? retry}) =>
        Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(title: title, message: text, onRetry: retry),
            ),
          ),
        );

    final error = options.error ?? exercises?.error;
    if (error != null) {
      return message(
        'Não foi possível carregar',
        error is ApiException ? error.message : 'Erro inesperado.',
        retry: () {
          ref.invalidate(exerciseOptionsProvider);
          if (exerciseId != null) ref.invalidate(exercisesProvider);
        },
      );
    }
    final loaded = options.value;
    if (loaded == null || (exerciseId != null && exercises?.value == null)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      );
    }
    Exercise? exercise;
    if (exerciseId != null) {
      exercise = exercises!.value!.where((e) => e.id == exerciseId).firstOrNull;
      if (exercise == null || !exercise.isCustom) {
        return message(
          'Exercício não encontrado',
          'Só os exercícios criados por você podem ser editados.',
        );
      }
    }
    return _ExerciseForm(exercise: exercise, options: loaded);
  }
}

class _ExerciseForm extends ConsumerStatefulWidget {
  const _ExerciseForm({required this.exercise, required this.options});

  final Exercise? exercise;
  final ExerciseOptions options;

  @override
  ConsumerState<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<_ExerciseForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _instructions = TextEditingController();
  String? _equipment;
  String? _mechanics;
  String? _loadType;
  bool _unilateral = false;
  Set<String> _primary = {};
  Set<String> _secondary = {};
  bool _saving = false;
  bool _dirty = false;
  ApiException? _error;
  String? _hint;

  bool get _isNew => widget.exercise == null;

  @override
  void initState() {
    super.initState();
    final exercise = widget.exercise;
    if (exercise != null) {
      _name.text = exercise.name;
      _instructions.text = exercise.instructions ?? '';
      _equipment = exercise.equipment;
      _mechanics = exercise.mechanics;
      _loadType = exercise.loadType;
      _unilateral = exercise.unilateral;
      _primary = {for (final m in exercise.primaryMuscles) m.id};
      _secondary = {for (final m in exercise.secondaryMuscles) m.id};
    }
    for (final controller in [_name, _instructions]) {
      final initial = controller.text;
      // O controlador também avisa mudanças de cursor; só texto conta.
      controller.addListener(() {
        if (controller.text != initial) _changed();
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _dirty = true;
    _error = null;
    _hint = null;
  });

  String? _missing() {
    if (_equipment == null) return 'Escolha o equipamento.';
    if (_mechanics == null) return 'Escolha o tipo de movimento.';
    if (_loadType == null) return 'Escolha o tipo de carga.';
    if (_primary.isEmpty) return 'Escolha pelo menos um músculo principal.';
    return null;
  }

  Future<void> _save() async {
    if (_saving || !validateAndFocusFirstError(_formKey.currentState!)) return;
    final missing = _missing();
    if (missing != null) {
      setState(() => _hint = missing);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(exercisesProvider.notifier);
    final body = <String, Object?>{
      'name': _name.text.trim(),
      'instructions': _instructions.text.trim(),
      'equipment': _equipment,
      'mechanics': _mechanics,
      'load_type': _loadType,
      'unilateral': _unilateral,
      'muscles': [
        for (final id in _primary)
          {'muscle_group_id': id, 'role': MuscleRole.primary},
        for (final id in _secondary)
          {'muscle_group_id': id, 'role': MuscleRole.secondary},
      ],
    };
    try {
      if (_isNew) {
        await controller.create(body);
      } else {
        await controller.updateExercise(widget.exercise!.id, body);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isNew ? 'Exercício criado' : 'Exercício atualizado'),
        ),
      );
      _dirty = false;
      context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text('O que você preencheu não será salvo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, evoTouchTargetMin),
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _onPopInvoked(bool didPop, Object? _) async {
    if (didPop || !await _confirmDiscard() || !mounted) return;
    setState(() => _dirty = false);
    context.pop();
  }

  Widget _single(
    String label,
    List<(String, String)> options,
    String? selected,
    ValueChanged<String> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EvoFieldLabel(label),
      EvoChipGroup(
        single: true,
        options: options,
        selected: {?selected},
        onChanged: (value) {
          onChanged(value.first);
          _changed();
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final fieldErrors = _error?.fieldErrors ?? const <String, String>{};
    final muscles = [for (final m in options.muscleGroups) (m.id, m.name)];

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Novo exercício' : 'Editar exercício'),
        ),
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
                        TextFormField(
                          controller: _name,
                          maxLength: 80,
                          textCapitalization: TextCapitalization.sentences,
                          forceErrorText: fieldErrors['name'],
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Dê um nome ao exercício.';
                            if (text.length < 2) {
                              return 'Use pelo menos 2 caracteres.';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Nome',
                            hintText: 'Ex.: Remada no TRX',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: EvoSpace.x2xl),
                        _single(
                          'Equipamento',
                          [
                            for (final o in options.equipment)
                              (o.code, o.label),
                          ],
                          _equipment,
                          (v) => _equipment = v,
                        ),
                        const SizedBox(height: EvoSpace.xl),
                        _single(
                          'Movimento',
                          [
                            for (final o in options.mechanics)
                              (o.code, o.label),
                          ],
                          _mechanics,
                          (v) => _mechanics = v,
                        ),
                        const SizedBox(height: EvoSpace.xl),
                        _single(
                          'Carga',
                          [
                            for (final o in options.loadTypes)
                              (o.code, o.label),
                          ],
                          _loadType,
                          (v) => _loadType = v,
                        ),
                        const SizedBox(height: EvoSpace.lg),
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            value: _unilateral,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) {
                              setState(() => _unilateral = value);
                              _changed();
                            },
                            title: const Text('Um lado por vez'),
                            subtitle: const Text(
                              'Ex.: remada com um braço, afundo.',
                            ),
                          ),
                        ),
                        const SizedBox(height: EvoSpace.xl),
                        const EvoFieldLabel(
                          'Músculos principais',
                          hint: 'Os que mais trabalham. Pelo menos um.',
                        ),
                        EvoChipGroup(
                          options: muscles,
                          selected: _primary,
                          onChanged: (selected) {
                            setState(() {
                              _primary = selected;
                              // Um músculo não pode ser principal e secundário ao mesmo tempo.
                              _secondary = _secondary.difference(selected);
                            });
                            _changed();
                          },
                        ),
                        const SizedBox(height: EvoSpace.xl),
                        const EvoFieldLabel(
                          'Também trabalha',
                          hint: 'Opcional.',
                        ),
                        EvoChipGroup(
                          options: [
                            for (final m in muscles)
                              if (!_primary.contains(m.$1)) m,
                          ],
                          selected: _secondary,
                          onChanged: (selected) {
                            setState(() => _secondary = selected);
                            _changed();
                          },
                        ),
                        const SizedBox(height: EvoSpace.x2xl),
                        TextFormField(
                          controller: _instructions,
                          maxLength: 2000,
                          minLines: 3,
                          maxLines: 8,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Como fazer (opcional)',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                // Com fonte muito grande o rodapé rola, em vez de espremer o conteúdo.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    EvoSpace.xl,
                    0,
                    EvoSpace.xl,
                    EvoSpace.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EvoFormError(message: _hint ?? _error?.message),
                      EvoButton(
                        label: _isNew ? 'Criar exercício' : 'Salvar',
                        isLoading: _saving,
                        onPressed: _save,
                      ),
                    ],
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
