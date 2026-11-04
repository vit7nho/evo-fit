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
import '../../goals/presentation/goal_format.dart';
import '../../profile/application/profile_actions.dart';
import '../../profile/domain/profile.dart' show ConsentKinds;
import '../application/activities_controller.dart';
import '../data/activities_api.dart';
import '../domain/activity.dart';

/// Lê a duração: "mm:ss", "h:mm:ss" ou só minutos ("45"). Nulo se inválida.
int? parseActivityDuration(String text) {
  final trimmed = text.trim();
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return int.parse(trimmed) * 60;
  return parseDuration(trimmed);
}

/// Registro de uma atividade nova ou correção de uma existente.
///
/// Mesmas regras da API (duração de 1 min a 24 h, data até agora, distância até o
/// limite da modalidade), para avisar antes de enviar.
class ActivityFormPage extends ConsumerWidget {
  const ActivityFormPage.create({super.key}) : activityId = null;

  const ActivityFormPage.edit({super.key, required String this.activityId});

  final String? activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(activityOptionsProvider);
    final activity = activityId == null
        ? null
        : ref.watch(activityProvider(activityId!));

    final error = options.error ?? activity?.error;
    if (error != null) {
      final notFound = error is ApiException && error.statusCode == 404;
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(EvoSpace.xl),
            child: EvoErrorView(
              title: notFound
                  ? 'Atividade não encontrada'
                  : 'Não foi possível carregar a atividade',
              message: notFound
                  ? 'Ela pode ter sido excluída. Volte para a lista.'
                  : error is ApiException
                  ? error.message
                  : 'Erro inesperado.',
              onRetry: notFound
                  ? null
                  : () {
                      ref.invalidate(activityOptionsProvider);
                      if (activityId != null) {
                        ref.invalidate(activityProvider(activityId!));
                      }
                    },
            ),
          ),
        ),
      );
    }
    final loadedOptions = options.value;
    if (loadedOptions == null || (activity != null && !activity.hasValue)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      );
    }
    return _ActivityForm(options: loadedOptions, activity: activity?.value);
  }
}

class _ActivityForm extends ConsumerStatefulWidget {
  const _ActivityForm({required this.options, required this.activity});

  final ActivityOptions options;
  final Activity? activity;

  @override
  ConsumerState<_ActivityForm> createState() => _ActivityFormState();
}

class _ActivityFormState extends ConsumerState<_ActivityForm> {
  final _formKey = GlobalKey<FormState>();
  final _duration = TextEditingController();
  final _distance = TextEditingController();
  final _laps = TextEditingController();
  final _notes = TextEditingController();
  final _elevation = TextEditingController();
  final _avgHr = TextEditingController();
  final _maxHr = TextEditingController();
  late String _modality;
  late DateTime _startedAt;
  int? _effort;
  bool _indoor = false;
  int? _poolLength;
  String? _stroke;
  bool _saving = false;
  bool _dirty = false;
  bool _grantHealth = false;

  /// Aviso local (não vem da API), ex.: falta autorizar a FC.
  String? _hint;
  ApiException? _error;

  Activity? get _activity => widget.activity;
  bool get _isNew => _activity == null;
  bool get _swim => _modality == Modalities.swim;

  /// Na piscina a distância sai das voltas; o campo só aparece em águas abertas.
  bool get _distanceFromLaps => _swim && _poolLength != null;

  @override
  void initState() {
    super.initState();
    final activity = _activity;
    _modality = activity?.modality ?? Modalities.run;
    final now = DateTime.now();
    _startedAt =
        activity?.startedAt ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    if (activity != null) {
      _duration.text = formatDuration(activity.durationS);
      _effort = activity.perceivedEffort;
      _notes.text = activity.notes ?? '';
      _elevation.text = activity.elevationGainM?.toString() ?? '';
      _avgHr.text = activity.avgHr?.toString() ?? '';
      _maxHr.text = activity.maxHr?.toString() ?? '';
      _indoor = activity.indoor ?? false;
      _poolLength = activity.poolLengthM;
      _stroke = activity.stroke;
      _laps.text = activity.laps?.toString() ?? '';
      if (activity.distanceM case final meters?) {
        _distance.text = _swim ? '$meters' : formatDecimal(meters / 1000);
      }
    }
  }

  @override
  void dispose() {
    _duration.dispose();
    _distance.dispose();
    _laps.dispose();
    _notes.dispose();
    _elevation.dispose();
    _avgHr.dispose();
    _maxHr.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  // --- valores ---

  int? get _distanceMeters {
    final text = _distance.text.trim();
    if (text.isEmpty) return null;
    if (_swim) return int.tryParse(text);
    final km = parseDecimal(text);
    return km == null ? null : (km * 1000).round();
  }

  String? _validateDistance(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final meters = _distanceMeters;
    if (meters == null || meters < 1) return 'Distância inválida.';
    final max = widget.options.modality(_modality)?.maxDistanceM;
    if (max != null && meters > max) {
      return 'Acima do limite (${max ~/ 1000} km).';
    }
    return null;
  }

  String? _validateDuration(String? value) {
    final seconds = parseActivityDuration(value ?? '');
    if ((value ?? '').trim().isEmpty) return 'Informe a duração.';
    if (seconds == null) return 'Use minutos ou h:mm:ss.';
    if (seconds < 60) return 'Pelo menos 1 minuto.';
    if (seconds > 24 * 3600) return 'No máximo 24 horas.';
    return null;
  }

  bool get _hasHealthConsent {
    final auth = ref.read(authControllerProvider).value;
    return auth is Authenticated &&
        auth.user.hasConsent(ConsentKinds.healthData);
  }

  bool get _sendsHeartRate =>
      _avgHr.text.trim().isNotEmpty || _maxHr.text.trim().isNotEmpty;

  /// Faixa inteira opcional (vazio passa).
  String? Function(String?) _range(int min, int max, String unit) => (value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    if (n == null || n < min || n > max) return 'Entre $min e $max $unit.';
    return null;
  };

  String? _validateMaxHr(String? value) {
    final error = _range(30, 250, 'bpm')(value);
    if (error != null) return error;
    final peak = int.tryParse(value?.trim() ?? '');
    final avg = int.tryParse(_avgHr.text.trim());
    if (peak != null && avg != null && peak < avg) {
      return 'Não pode ser menor que a média.';
    }
    return null;
  }

  Map<String, Object?> _body() {
    final laps = int.tryParse(_laps.text.trim());
    final notes = _notes.text.trim();
    return {
      'started_at': _startedAt.toUtc().toIso8601String(),
      'duration_s': parseActivityDuration(_duration.text),
      // Na piscina, sem distância: a API calcula pelas voltas.
      'distance_m': _distanceFromLaps ? null : _distanceMeters,
      'perceived_effort': _effort,
      'notes': notes.isEmpty ? null : notes,
      'avg_hr': int.tryParse(_avgHr.text.trim()),
      'max_hr': int.tryParse(_maxHr.text.trim()),
      if (!_swim) 'elevation_gain_m': int.tryParse(_elevation.text.trim()),
      if (_modality == Modalities.cycle) 'indoor': _indoor,
      if (_swim) ...{
        'pool_length_m': _poolLength,
        'laps': _poolLength == null ? null : laps,
        'stroke': _stroke,
      },
    };
  }

  // --- gravação ---

  Future<void> _save() async {
    if (_saving || !validateAndFocusFirstError(_formKey.currentState!)) return;
    final needsConsent = _sendsHeartRate && !_hasHealthConsent;
    if (needsConsent && !_grantHealth) {
      setState(() => _hint = 'Autorize os dados de saúde para salvar a FC.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _hint = null;
    });
    final controller = ref.read(activitiesProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (needsConsent) {
        await ref
            .read(profileActionsProvider)
            .setConsent(ConsentKinds.healthData, granted: true);
      }
      if (_isNew) {
        await controller.create({'modality': _modality, ..._body()});
      } else {
        await controller.updateActivity(_activity!.id, _body());
        ref.invalidate(activityProvider(_activity!.id));
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isNew ? 'Atividade registrada' : 'Atividade atualizada',
          ),
        ),
      );
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
        title: const Text('Excluir atividade?'),
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
      await ref.read(activitiesProvider.notifier).delete(_activity!.id);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Atividade excluída')),
      );
      _dirty = false;
      context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 5 * 365)),
      lastDate: now,
      initialDate: _startedAt.isAfter(now) ? now : _startedAt,
      helpText: 'Dia da atividade',
    );
    if (picked == null) return;
    setState(
      () => _startedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startedAt.hour,
        _startedAt.minute,
      ),
    );
    _changed();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
      helpText: 'Hora do início',
    );
    if (picked == null) return;
    setState(
      () => _startedAt = DateTime(
        _startedAt.year,
        _startedAt.month,
        _startedAt.day,
        picked.hour,
        picked.minute,
      ),
    );
    _changed();
  }

  // --- saída com alterações não salvas ---

  Future<void> _onPopInvoked(bool didPop, Object? _) async {
    if (didPop) return;
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
    if (!(confirmed ?? false) || !mounted) return;
    setState(() => _dirty = false);
    context.pop();
  }

  // --- tela ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final errors = _error?.fieldErrors ?? const <String, String>{};
    final options = widget.options;
    final laps = int.tryParse(_laps.text.trim());
    final fromLaps = _poolLength != null && laps != null
        ? _poolLength! * laps
        : null;
    final rhythm = liveRhythm(
      _modality,
      _distanceFromLaps ? fromLaps : _distanceMeters,
      parseActivityDuration(_duration.text),
    );
    final needsConsent = _sendsHeartRate && !_hasHealthConsent;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Registrar atividade' : 'Editar atividade'),
          actions: [
            if (!_isNew)
              IconButton(
                tooltip: 'Excluir atividade',
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(EvoSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isNew) ...[
                          const EvoFieldLabel('Modalidade'),
                          EvoChipGroup(
                            single: true,
                            options: [
                              for (final m in options.modalities)
                                (m.code, m.label),
                            ],
                            selected: {_modality},
                            onChanged: (selected) {
                              final next = selected.first;
                              if (next == _modality) return;
                              setState(() {
                                // Metros na natação, km nas outras: o número não vale mais.
                                if ((next == Modalities.swim) != _swim) {
                                  _distance.clear();
                                }
                                _modality = next;
                              });
                              _changed();
                            },
                          ),
                        ] else
                          Row(
                            children: [
                              Icon(modalityIcon(_modality), size: 22),
                              const SizedBox(width: EvoSpace.sm),
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    options.modalityLabel(_modality),
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: EvoSpace.xl),
                        const EvoFieldLabel('Quando começou'),
                        Wrap(
                          spacing: EvoSpace.sm,
                          runSpacing: EvoSpace.sm,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                formatGoalDate(context, _startedAt),
                                semanticsLabel:
                                    'Dia: ${localizations.formatFullDate(_startedAt)}. Alterar',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickTime,
                              icon: const Icon(Icons.schedule_rounded),
                              label: Text(
                                localizations.formatTimeOfDay(
                                  TimeOfDay.fromDateTime(_startedAt),
                                ),
                                semanticsLabel:
                                    'Hora: ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(_startedAt))}. Alterar',
                              ),
                            ),
                          ],
                        ),
                        if (errors['started_at'] case final message?)
                          _ServerError(message),
                        const SizedBox(height: EvoSpace.xl),
                        TextFormField(
                          controller: _duration,
                          keyboardType: TextInputType.datetime,
                          textInputAction: TextInputAction.next,
                          forceErrorText: errors['duration_s'],
                          validator: _validateDuration,
                          onChanged: (_) {
                            setState(() {});
                            _changed();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Duração',
                            hintText: 'Ex.: 45 (min) ou 1:05:30',
                          ),
                        ),
                        if (_modality == Modalities.cycle) ...[
                          const SizedBox(height: EvoSpace.lg),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _indoor,
                            onChanged: (value) {
                              setState(() => _indoor = value);
                              _changed();
                            },
                            title: const Text('Em ambiente fechado'),
                            subtitle: const Text(
                              'Rolo ou bicicleta de academia',
                            ),
                          ),
                        ],
                        if (_swim) ...[
                          const SizedBox(height: EvoSpace.xl),
                          const EvoFieldLabel('Piscina'),
                          EvoChipGroup(
                            single: true,
                            options: [
                              for (final length in options.poolLengthsM)
                                ('$length', '$length m'),
                              ('', 'Águas abertas'),
                            ],
                            selected: {'${_poolLength ?? ''}'},
                            onChanged: (selected) {
                              setState(
                                () =>
                                    _poolLength = int.tryParse(selected.first),
                              );
                              _changed();
                            },
                          ),
                          if (errors['pool_length_m'] case final message?)
                            _ServerError(message),
                          if (_poolLength != null) ...[
                            const SizedBox(height: EvoSpace.lg),
                            TextFormField(
                              controller: _laps,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textInputAction: TextInputAction.next,
                              forceErrorText: errors['laps'],
                              onChanged: (_) {
                                setState(() {});
                                _changed();
                              },
                              validator: (value) {
                                final n = int.tryParse(value?.trim() ?? '');
                                if (n == null || n < 1) {
                                  return 'Informe as voltas.';
                                }
                                if (n > 2000) return 'No máximo 2000 voltas.';
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: 'Voltas',
                                helperText: fromLaps == null
                                    ? 'Uma volta = um comprimento da piscina.'
                                    : 'Distância: $fromLaps m',
                              ),
                            ),
                          ],
                        ],
                        if (!_distanceFromLaps) ...[
                          const SizedBox(height: EvoSpace.lg),
                          TextFormField(
                            controller: _distance,
                            keyboardType: _swim
                                ? TextInputType.number
                                : const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            inputFormatters: _swim
                                ? [FilteringTextInputFormatter.digitsOnly]
                                : null,
                            textInputAction: TextInputAction.next,
                            forceErrorText: errors['distance_m'],
                            validator: _validateDistance,
                            onChanged: (_) {
                              setState(() {});
                              _changed();
                            },
                            decoration: InputDecoration(
                              labelText: 'Distância (opcional)',
                              suffixText: _swim ? 'm' : 'km',
                            ),
                          ),
                        ] else if (errors['distance_m'] case final message?)
                          _ServerError(message),
                        if (rhythm != null)
                          Padding(
                            padding: const EdgeInsets.only(top: EvoSpace.sm),
                            child: Text(
                              _modality == Modalities.cycle
                                  ? 'Velocidade média: $rhythm'
                                  : 'Pace: $rhythm',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        if (_swim) ...[
                          const SizedBox(height: EvoSpace.xl),
                          const EvoFieldLabel('Estilo', hint: 'Opcional.'),
                          EvoChipGroup(
                            single: true,
                            options: [
                              for (final s in options.strokes)
                                (s.code, s.label),
                            ],
                            selected: {?_stroke},
                            onChanged: (selected) {
                              final code = selected.first;
                              setState(
                                () => _stroke = code == _stroke ? null : code,
                              );
                              _changed();
                            },
                          ),
                        ],
                        const SizedBox(height: EvoSpace.lg),
                        ExpansionTile(
                          // Mantidos montados: o Form valida mesmo recolhidos.
                          maintainState: true,
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          initiallyExpanded:
                              _activity?.avgHr != null ||
                              _activity?.maxHr != null ||
                              _activity?.elevationGainM != null,
                          title: Text(
                            'Mais detalhes',
                            style: theme.textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            _swim
                                ? 'Frequência cardíaca'
                                : 'Frequência cardíaca e elevação',
                            style: theme.textTheme.bodyMedium,
                          ),
                          children: [
                            // Espaço para o rótulo flutuante do primeiro campo.
                            const SizedBox(height: EvoSpace.sm),
                            if (!_swim) ...[
                              _NumberField(
                                controller: _elevation,
                                label: 'Ganho de elevação (opcional)',
                                suffix: 'm',
                                error: errors['elevation_gain_m'],
                                validator: _range(0, 10000, 'm'),
                                onChanged: _changed,
                              ),
                              const SizedBox(height: EvoSpace.lg),
                            ],
                            _NumberField(
                              controller: _avgHr,
                              label: 'FC média (opcional)',
                              suffix: 'bpm',
                              error: errors['avg_hr'],
                              validator: _range(30, 230, 'bpm'),
                              onChanged: () {
                                setState(() {});
                                _changed();
                              },
                            ),
                            const SizedBox(height: EvoSpace.lg),
                            _NumberField(
                              controller: _maxHr,
                              label: 'FC máxima (opcional)',
                              suffix: 'bpm',
                              error: errors['max_hr'],
                              validator: _validateMaxHr,
                              onChanged: () {
                                setState(() {});
                                _changed();
                              },
                            ),
                            if (needsConsent) ...[
                              const SizedBox(height: EvoSpace.lg),
                              Card(
                                child: SwitchListTile(
                                  value: _grantHealth,
                                  onChanged: (value) {
                                    setState(() => _grantHealth = value);
                                    _changed();
                                  },
                                  title: Text(
                                    'Autorizo o uso dos meus dados de saúde',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(
                                      top: EvoSpace.xs,
                                    ),
                                    child: Text(
                                      'Frequência cardíaca é dado de saúde. Você pode '
                                      'revogar no perfil a qualquer momento — a FC das '
                                      'atividades é apagada junto.',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
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
                          onChanged: (selected) {
                            final value = int.parse(selected.first);
                            setState(
                              () => _effort = _effort == value ? null : value,
                            );
                            _changed();
                          },
                        ),
                        const SizedBox(height: EvoSpace.xl),
                        TextFormField(
                          controller: _notes,
                          maxLength: 1000,
                          minLines: 2,
                          maxLines: 4,
                          forceErrorText: errors['notes'],
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => _changed(),
                          decoration: const InputDecoration(
                            labelText: 'Como foi? (opcional)',
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
                        label: _isNew ? 'Registrar' : 'Salvar',
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

class _ServerError extends StatelessWidget {
  const _ServerError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: EvoSpace.sm),
      child: Text(message, style: const TextStyle(color: EvoColors.danger)),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.error,
    required this.validator,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final String? error;
  final String? Function(String?) validator;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.next,
      forceErrorText: error,
      validator: validator,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }
}
