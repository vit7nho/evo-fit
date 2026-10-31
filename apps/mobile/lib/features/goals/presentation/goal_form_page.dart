import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../../shared/widgets/form_focus.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/application/profile_actions.dart';
import '../../profile/domain/profile.dart';
import '../application/goals_controller.dart';
import '../data/goals_api.dart';
import '../domain/goal.dart';
import 'goal_format.dart';

/// Formulário de meta: cria uma do tipo escolhido ou edita uma existente.
///
/// Os campos do alvo vêm de GET /goal-options; as regras (faixas, passos,
/// obrigatórios) são as mesmas que a API aplica, para avisar antes de enviar.
class GoalFormPage extends ConsumerWidget {
  const GoalFormPage.create({super.key, required String kind})
    : kindCode = kind,
      goalId = null;

  const GoalFormPage.edit({super.key, required String this.goalId})
    : kindCode = null;

  final String? kindCode;
  final String? goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(goalOptionsProvider);
    final goals = goalId == null ? null : ref.watch(goalsProvider);

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

    final error = options.error ?? goals?.error;
    if (error != null) {
      return message(
        'Não foi possível carregar a meta',
        error is ApiException ? error.message : 'Erro inesperado.',
        retry: () {
          ref.invalidate(goalOptionsProvider);
          if (goalId != null) ref.invalidate(goalsProvider);
        },
      );
    }
    final loadedOptions = options.value;
    final loadedGoals = goals?.value;
    if (loadedOptions == null || (goalId != null && loadedGoals == null)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      );
    }

    Goal? goal;
    if (goalId != null) {
      for (final g in loadedGoals!) {
        if (g.id == goalId) goal = g;
      }
      if (goal == null) {
        return message(
          'Meta não encontrada',
          'Ela pode ter sido excluída. Volte para a lista de metas.',
        );
      }
    }
    final kind = loadedOptions.kind(goal?.kind ?? kindCode!);
    if (kind == null) {
      return message(
        'Tipo de meta desconhecido',
        'Atualize o app para usar este tipo de meta.',
      );
    }
    return _GoalForm(kind: kind, goal: goal, options: loadedOptions);
  }
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({
    required this.kind,
    required this.goal,
    required this.options,
  });

  final GoalKind kind;
  final Goal? goal;
  final GoalOptions options;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _inputs = <String, TextEditingController>{};
  final _choices = <String, String?>{};
  DateTime? _targetDate;
  int _priority = 2;
  bool _grantHealth = false;
  bool _saving = false;
  bool _dirty = false;
  ApiException? _error;

  /// Aviso local (não vem da API), ex.: falta autorizar o peso.
  String? _hint;

  GoalKind get _kind => widget.kind;
  Goal? get _goal => widget.goal;
  bool get _isNew => _goal == null;

  bool get _hasHealthConsent {
    final auth = ref.read(authControllerProvider).value;
    return auth is Authenticated &&
        auth.user.hasConsent(ConsentKinds.healthData);
  }

  @override
  void initState() {
    super.initState();
    final goal = _goal;
    _title.text = goal?.title ?? '';
    _targetDate = goal?.targetDate;
    _priority = goal?.priority ?? 2;
    for (final field in _kind.fields) {
      final value = goal?.target[field.key];
      if (field.type == TargetFieldType.choice) {
        _choices[field.key] = value as String?;
        continue;
      }
      _inputs[field.key] = TextEditingController(
        text: switch (value) {
          null => '',
          final num n when field.type == TargetFieldType.duration =>
            formatDuration(n.toInt()),
          final num n => formatDecimal(n),
          final other => '$other',
        },
      );
    }
    for (final controller in [_title, ..._inputs.values]) {
      final initial = controller.text;
      // O controlador também avisa mudanças de cursor; só texto conta.
      controller.addListener(() {
        if (controller.text != initial) _changed();
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final controller in _inputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {
    _dirty = true;
    _error = null;
    _hint = null;
  });

  // --- validação (as mesmas regras da API) ---

  String _range(TargetField field) {
    final unit = field.unit == null ? '' : ' ${field.unit}';
    if (field.type == TargetFieldType.duration) {
      return 'Informe entre ${formatDuration(field.min!.toInt())} e '
          '${formatDuration(field.max!.toInt())}.';
    }
    return 'Informe um valor entre ${formatDecimal(field.min!)} e '
        '${formatDecimal(field.max!)}$unit.';
  }

  String? _validate(TargetField field, String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return field.required ? 'Campo obrigatório.' : null;
    num? value;
    switch (field.type) {
      case TargetFieldType.text:
        final min = (field.min ?? 0).toInt();
        final max = (field.max ?? 500).toInt();
        if (text.length < min || text.length > max) {
          return 'Use de $min a $max caracteres.';
        }
        return null;
      case TargetFieldType.integer:
        value = int.tryParse(text);
        if (value == null) return 'Informe um número inteiro.';
      case TargetFieldType.duration:
        value = parseDuration(text);
        if (value == null) return 'Use o formato mm:ss ou h:mm:ss.';
      default:
        value = parseDecimal(text);
        if (value == null) return 'Informe um número.';
        final step = field.step;
        if (step != null) {
          final steps = value / step;
          if ((steps - steps.round()).abs() > 1e-6) {
            return 'Use múltiplos de ${formatDecimal(step)}.';
          }
        }
    }
    if ((field.min != null && value < field.min!) ||
        (field.max != null && value > field.max!)) {
      return _range(field);
    }
    return null;
  }

  Map<String, Object?> _target() {
    final target = <String, Object?>{};
    for (final field in _kind.fields) {
      if (field.type == TargetFieldType.choice) {
        final choice = _choices[field.key];
        if (choice != null) target[field.key] = choice;
        continue;
      }
      final text = _inputs[field.key]!.text.trim();
      if (text.isEmpty) continue;
      target[field.key] = switch (field.type) {
        TargetFieldType.integer => int.parse(text),
        TargetFieldType.duration => parseDuration(text),
        TargetFieldType.number => parseDecimal(text),
        _ => text,
      };
    }
    return target;
  }

  // --- gravação ---

  Future<void> _save({String? status}) async {
    if (_saving || !validateAndFocusFirstError(_formKey.currentState!)) return;
    final missingChoice = _kind.fields.where(
      (f) =>
          f.type == TargetFieldType.choice &&
          f.required &&
          _choices[f.key] == null,
    );
    if (missingChoice.isNotEmpty) {
      setState(() => _hint = 'Escolha: ${missingChoice.first.label}.');
      return;
    }
    final needsConsent = _kind.healthData && !_hasHealthConsent;
    if (needsConsent && !_grantHealth) {
      setState(
        () => _hint = 'Autorize o uso do seu peso para salvar esta meta.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _hint = null;
    });
    final controller = ref.read(goalsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (needsConsent) {
        await ref
            .read(profileActionsProvider)
            .setConsent(ConsentKinds.healthData, granted: true);
      }
      final body = <String, Object?>{
        'title': _title.text.trim(),
        'target': _target(),
        'priority': _priority,
        'target_date': _targetDate == null ? null : apiDate(_targetDate!),
      };
      final String done;
      if (_isNew) {
        await controller.create({'kind': _kind.code, ...body});
        done = 'Meta criada';
      } else {
        await controller.updateGoal(_goal!.id, {...body, 'status': ?status});
        done = switch (status) {
          GoalStatus.achieved => 'Meta alcançada. Parabéns!',
          GoalStatus.abandoned => 'Meta abandonada',
          GoalStatus.active => 'Meta reativada',
          _ => 'Meta atualizada',
        };
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(done)));
      _dirty = false;
      context.pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir meta?'),
        content: const Text('Ela some da sua lista. Não dá para desfazer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: EvoColors.danger,
              minimumSize: const Size(88, evoTouchTargetMin),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(goalsProvider.notifier).delete(_goal!.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Meta excluída')));
      _dirty = false;
      context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final start = _goal?.startDate ?? today;
    final first = _isNew ? today : start;
    final last = start.add(const Duration(days: 10 * 365));
    var initial = _targetDate ?? today.add(const Duration(days: 30));
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial,
      helpText: 'Prazo da meta',
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
      _changed();
    }
  }

  // --- saída com alterações não salvas ---

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

  // --- tela ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const <String, String>{};
    final needsConsent = _kind.healthData && !_hasHealthConsent;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(title: Text(_isNew ? 'Nova meta' : 'Editar meta')),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  // Rolagem simples, não ListView: campos fora da tela também
                  // precisam existir para o Form validá-los.
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(EvoSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(goalKindIcon(_kind.code), size: 22),
                            const SizedBox(width: EvoSpace.sm),
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  _kind.label,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: EvoSpace.xs),
                        Text(
                          _kind.description,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: EvoSpace.x2xl),
                        TextFormField(
                          controller: _title,
                          maxLength: 80,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                          forceErrorText: fieldErrors['title'],
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Dê um nome para a meta.';
                            if (text.length < 2) {
                              return 'Use pelo menos 2 caracteres.';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Nome da meta',
                            hintText: 'Ex.: Correr minha primeira prova',
                            counterText: '',
                          ),
                        ),
                        if (needsConsent) ...[
                          const SizedBox(height: EvoSpace.xl),
                          Card(
                            child: SwitchListTile(
                              value: _grantHealth,
                              onChanged: (value) {
                                setState(() => _grantHealth = value);
                                _changed();
                              },
                              title: Text(
                                'Autorizo o uso do meu peso',
                                style: theme.textTheme.titleMedium,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(
                                  top: EvoSpace.xs,
                                ),
                                child: Text(
                                  'Peso é dado de saúde. Você pode revogar no perfil '
                                  'a qualquer momento — as metas de peso são apagadas '
                                  'junto.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ),
                          ),
                        ],
                        for (final field in _kind.fields) ...[
                          const SizedBox(height: EvoSpace.xl),
                          _fieldInput(
                            field,
                            fieldErrors['target.${field.key}'],
                          ),
                        ],
                        const SizedBox(height: EvoSpace.x2xl),
                        _deadline(theme, fieldErrors['target_date']),
                        const SizedBox(height: EvoSpace.xl),
                        const EvoFieldLabel('Prioridade'),
                        EvoChipGroup(
                          single: true,
                          options: [
                            for (final (value, label)
                                in widget.options.priorities)
                              ('$value', label),
                          ],
                          selected: {'$_priority'},
                          onChanged: (selected) {
                            setState(
                              () => _priority = int.parse(selected.first),
                            );
                            _changed();
                          },
                        ),
                        if (!_isNew) ..._statusActions(),
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
                        label: _isNew ? 'Criar meta' : 'Salvar',
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

  Widget _fieldInput(TargetField field, String? serverError) {
    if (field.type == TargetFieldType.choice) {
      final options = [
        // Opcional: "Qualquer" volta ao vazio.
        if (!field.required) ('', 'Qualquer'),
        for (final option in field.options ?? const <Option>[])
          (option.code, option.label),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EvoFieldLabel(field.label),
          EvoChipGroup(
            single: true,
            options: options,
            selected: {_choices[field.key] ?? ''},
            onChanged: (selected) {
              final code = selected.first;
              setState(() => _choices[field.key] = code.isEmpty ? null : code);
              _changed();
            },
          ),
          if (serverError != null)
            Padding(
              padding: const EdgeInsets.only(top: EvoSpace.sm),
              child: Text(
                serverError,
                style: const TextStyle(color: EvoColors.danger),
              ),
            ),
        ],
      );
    }

    final isText = field.type == TargetFieldType.text;
    return TextFormField(
      controller: _inputs[field.key],
      forceErrorText: serverError,
      validator: (value) => _validate(field, value),
      textInputAction: TextInputAction.next,
      maxLength: isText ? field.max?.toInt() : null,
      maxLines: isText && (field.max ?? 0) > 120 ? 4 : 1,
      minLines: 1,
      textCapitalization: isText
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      keyboardType: switch (field.type) {
        TargetFieldType.integer => TextInputType.number,
        TargetFieldType.number => const TextInputType.numberWithOptions(
          decimal: true,
        ),
        TargetFieldType.duration => TextInputType.datetime,
        _ => TextInputType.text,
      },
      inputFormatters: field.type == TargetFieldType.integer
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(
        labelText: field.required ? field.label : '${field.label} (opcional)',
        suffixText: field.unit,
        hintText: field.type == TargetFieldType.duration ? 'mm:ss' : null,
        counterText: '',
      ),
    );
  }

  Widget _deadline(ThemeData theme, String? serverError) {
    final date = _targetDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EvoFieldLabel('Prazo', hint: 'Opcional.'),
        Row(
          children: [
            const Icon(Icons.event_outlined, color: EvoColors.textSecondary),
            const SizedBox(width: EvoSpace.sm),
            Expanded(
              child: Text(
                date == null
                    ? 'Sem prazo'
                    : 'Até ${formatGoalDate(context, date)}',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
        // Botões numa linha própria que quebra: com fonte grande não espremem a data.
        Wrap(
          spacing: EvoSpace.sm,
          children: [
            TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: Text(date == null ? 'Definir prazo' : 'Alterar prazo'),
            ),
            if (date != null)
              TextButton.icon(
                onPressed: () {
                  setState(() => _targetDate = null);
                  _changed();
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Remover prazo'),
              ),
          ],
        ),
        if (serverError != null)
          Text(serverError, style: const TextStyle(color: EvoColors.danger)),
      ],
    );
  }

  List<Widget> _statusActions() {
    final active = _goal!.isActive;
    return [
      const SizedBox(height: EvoSpace.x2xl),
      const Divider(),
      const SizedBox(height: EvoSpace.lg),
      if (active) ...[
        EvoButton(
          label: 'Marcar como alcançada',
          icon: Icons.check_rounded,
          variant: EvoButtonVariant.secondary,
          onPressed: _saving ? null : () => _save(status: GoalStatus.achieved),
        ),
        const SizedBox(height: EvoSpace.sm),
        TextButton(
          onPressed: _saving ? null : () => _save(status: GoalStatus.abandoned),
          child: const Text('Abandonar meta'),
        ),
      ] else
        EvoButton(
          label: 'Reativar meta',
          icon: Icons.replay_rounded,
          variant: EvoButtonVariant.secondary,
          onPressed: _saving ? null : () => _save(status: GoalStatus.active),
        ),
      TextButton(
        onPressed: _saving ? null : _delete,
        style: TextButton.styleFrom(foregroundColor: EvoColors.danger),
        child: const Text('Excluir meta'),
      ),
    ];
  }
}
