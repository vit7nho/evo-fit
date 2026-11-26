import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../goals/presentation/goal_format.dart'
    show formatDecimal, parseDecimal;
import '../application/measurements_controller.dart';
import '../data/measurements_api.dart';
import '../domain/measurements.dart';

/// Registrar ou editar peso e medidas ([measurement] nulo = novo registro).
class MeasurementFormPage extends ConsumerWidget {
  const MeasurementFormPage({super.key, this.measurement});

  final Measurement? measurement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(metricOptionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(measurement == null ? 'Registrar medida' : 'Editar medida'),
      ),
      body: SafeArea(
        top: false,
        child: options.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 4),
          ),
          error: (error, _) => EvoErrorView(
            title: 'Não foi possível abrir o formulário',
            message: error is ApiException ? error.message : 'Erro inesperado.',
            onRetry: () => ref.invalidate(metricOptionsProvider),
          ),
          data: (infos) => _Form(infos: infos, measurement: measurement),
        ),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.infos, this.measurement});

  final List<MetricInfo> infos;
  final Measurement? measurement;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late DateTime _at;

  /// A pessoa escolheu a data ou a hora. Sem isso, um registro novo vai com o
  /// instante de agora (achado no emulador: com o aparelho em outro fuso, o
  /// "agora" do relógio lido no fuso do perfil caía no futuro).
  bool _timeChosen = false;
  late final Map<String, TextEditingController> _fields;
  late final TextEditingController _notes;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  bool _saving = false;

  Measurement? get _editing => widget.measurement;

  @override
  void initState() {
    super.initState();
    final editing = _editing;
    final now = DateTime.now();
    _at =
        editing?.localTime ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _fields = {
      for (final info in widget.infos)
        info.metric: TextEditingController(
          text: switch (editing?.values[info.metric]) {
            final v? => formatDecimal(v),
            null => '',
          },
        ),
    };
    _notes = TextEditingController(text: editing?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _timeChosen = true;
        _at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _at.hour,
          _at.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (picked != null) {
      setState(() {
        _timeChosen = true;
        _at = DateTime(
          _at.year,
          _at.month,
          _at.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    final values = <String, double>{};
    final errors = <String, String>{};
    for (final info in widget.infos) {
      final text = _fields[info.metric]!.text.trim();
      if (text.isEmpty) continue;
      final value = parseDecimal(text);
      if (value == null || value < info.min || value > info.max) {
        errors[info.metric] =
            'Entre ${formatDecimal(info.min)} e ${formatDecimal(info.max)} '
            '${info.unit}.';
      } else {
        values[info.metric] = value;
      }
    }
    if (errors.isNotEmpty || values.isEmpty) {
      setState(() {
        _fieldErrors = errors;
        _error = values.isEmpty && errors.isEmpty
            ? 'Informe ao menos uma medida.'
            : null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _fieldErrors = const {};
      _error = null;
    });
    try {
      final notes = _notes.text.trim();
      await ref
          .read(measurementsApiProvider)
          .save(
            id: _editing?.id,
            measuredAt: _editing == null && !_timeChosen
                ? DateTime.now().toUtc()
                : _at,
            values: values,
            notes: notes.isEmpty ? null : notes,
          );
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = error.fieldErrors;
        _error =
            error.fieldErrors['__root__'] ??
            error.fieldErrors['measured_at'] ??
            (error.fieldErrors.isEmpty ? error.message : null);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar medida?'),
        content: const Text('O registro sai do histórico e da tendência.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(measurementsApiProvider).delete(_editing!.id);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    // O botão fica fixo no rodapé, como nos outros formulários: quem só
    // registra o peso não precisa rolar pelas medidas vazias (piloto da 5.7).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _fieldsList(theme, localizations)),
        ConstrainedBox(
          // Com fonte muito grande o rodapé rola, em vez de espremer a lista.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              EvoSpace.xl,
              EvoSpace.sm,
              EvoSpace.xl,
              EvoSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EvoFormError(message: _error),
                EvoButton(
                  label: 'Salvar medida',
                  isLoading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldsList(ThemeData theme, MaterialLocalizations localizations) {
    return ListView(
      padding: const EdgeInsets.all(EvoSpace.xl),
      children: [
        Text(
          'Preencha só o que mediu. Para comparar melhor, meça nas mesmas '
          'condições — por exemplo, de manhã, em jejum.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: EvoSpace.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded),
                label: Text(localizations.formatMediumDate(_at)),
              ),
            ),
            const SizedBox(width: EvoSpace.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  localizations.formatTimeOfDay(TimeOfDay.fromDateTime(_at)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: EvoSpace.xl),
        for (final info in widget.infos)
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.lg),
            child: TextField(
              controller: _fields[info.metric],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: info.label,
                suffixText: info.unit,
                helperText: info.estimate
                    ? 'Estimativa da balança ou das dobras cutâneas'
                    : null,
                errorText: _fieldErrors[info.metric],
              ),
            ),
          ),
        TextField(
          controller: _notes,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Observação (opcional)'),
        ),
        if (_editing != null) ...[
          const SizedBox(height: EvoSpace.sm),
          EvoButton(
            label: 'Apagar medida',
            variant: EvoButtonVariant.secondary,
            onPressed: _saving ? null : _delete,
          ),
        ],
      ],
    );
  }
}
