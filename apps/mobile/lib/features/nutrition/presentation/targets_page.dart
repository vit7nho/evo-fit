import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../application/nutrition_controller.dart';
import '../data/nutrition_api.dart';
import '../domain/nutrition.dart';

/// Metas nutricionais (5.2, ADR-059): valem a partir de hoje, dentro dos limites
/// de segurança que a API informa.
class TargetsPage extends ConsumerWidget {
  const TargetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(nutritionTargetsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Metas do dia')),
      body: SafeArea(
        top: false,
        child: info.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 4),
          ),
          error: (error, _) => EvoErrorView(
            title: 'Não foi possível carregar as metas',
            message: error is ApiException ? error.message : 'Erro inesperado.',
            onRetry: () => ref.invalidate(nutritionTargetsProvider),
          ),
          data: (data) => _TargetsForm(info: data),
        ),
      ),
    );
  }
}

class _Field {
  _Field(this.key, this.label, this.unit, this.range, int? value)
    : controller = TextEditingController(text: value?.toString() ?? '');

  final String key;
  final String label;
  final String unit;
  final TargetRange range;
  final TextEditingController controller;

  /// Vazio = sem meta; texto que não é número fica como -1 (inválido).
  int? get value {
    final text = controller.text.trim();
    return text.isEmpty ? null : int.tryParse(text) ?? -1;
  }
}

class _TargetsForm extends ConsumerStatefulWidget {
  const _TargetsForm({required this.info});

  final TargetsInfo info;

  @override
  ConsumerState<_TargetsForm> createState() => _TargetsFormState();
}

class _TargetsFormState extends ConsumerState<_TargetsForm> {
  late final List<_Field> _fields;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  bool _saving = false;

  TargetLimits get _limits => widget.info.limits;
  _Field get _kcal => _fields[0];

  @override
  void initState() {
    super.initState();
    final current = widget.info.current;
    _fields = [
      _Field('kcal', 'Calorias', 'kcal', _limits.kcal, current?.kcal),
      _Field('protein_g', 'Proteína', 'g', _limits.proteinG, current?.proteinG),
      _Field('carbs_g', 'Carboidratos', 'g', _limits.carbsG, current?.carbsG),
      _Field('fat_g', 'Gordura', 'g', _limits.fatG, current?.fatG),
    ];
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.controller.dispose();
    }
    super.dispose();
  }

  /// Os limites conferidos aqui, para a resposta ser imediata; a API confere de
  /// novo (e confere a soma dos macronutrientes).
  Map<String, String> _check() => {
    for (final field in _fields)
      if (field.value case final value? when !field.range.contains(value))
        field.key:
            'Entre ${formatInt(field.range.min)} e '
            '${formatInt(field.range.max)} ${field.unit}.',
  };

  Future<void> _save({bool clear = false}) async {
    final local = clear ? const <String, String>{} : _check();
    if (local.isNotEmpty) {
      setState(() {
        _fieldErrors = local;
        _error = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _fieldErrors = const {};
      _error = null;
    });
    try {
      await ref
          .read(nutritionApiProvider)
          .saveTargets(
            kcal: clear || !_limits.kcalAllowed ? null : _kcal.value,
            proteinG: clear ? null : _fields[1].value,
            carbsG: clear ? null : _fields[2].value,
            fatG: clear ? null : _fields[3].value,
          );
      ref
        ..invalidate(nutritionTargetsProvider)
        ..invalidate(dailyNutritionProvider);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = error.fieldErrors;
        _error =
            error.fieldErrors['__root__'] ??
            (error.fieldErrors.isEmpty ? error.message : null);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover as metas?'),
        content: const Text(
          'A partir de hoje o dia fica sem metas. Os dias anteriores continuam '
          'com as metas que valiam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _save(clear: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.labelSmall?.copyWith(
      color: EvoColors.textSecondary,
    );
    int? grams(int index) => switch (_fields[index].value) {
      final v? when v >= 0 => v,
      _ => null,
    };
    final fromMacros = macrosKcal(grams(1), grams(2), grams(3));
    final history = widget.info.history;
    final localizations = MaterialLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(EvoSpace.xl),
      children: [
        Text(
          'Metas diárias para acompanhar o que você come. Deixe em branco o que '
          'não quiser acompanhar. Para definir metas com segurança — '
          'principalmente para perder ou ganhar peso —, procure um nutricionista.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: EvoSpace.xl),
        for (final field in _fields)
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.lg),
            child: TextField(
              controller: field.controller,
              enabled: field.key != 'kcal' || _limits.kcalAllowed,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: field.label,
                suffixText: field.unit,
                helperText: field.key == 'kcal' && !_limits.kcalAllowed
                    ? 'Para menores de 18 anos, a meta de calorias deve ser '
                          'definida com um nutricionista ou médico.'
                    : 'Entre ${formatInt(field.range.min)} e '
                          '${formatInt(field.range.max)} ${field.unit} por dia',
                helperMaxLines: 3,
                errorText: _fieldErrors[field.key],
                errorMaxLines: 4,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (fromMacros != null)
          Text(
            'Os macronutrientes somam ${formatInt(fromMacros)} kcal '
            '(4 kcal por grama de proteína e de carboidrato, 9 por grama de '
            'gordura).',
            style: secondary,
          ),
        const SizedBox(height: EvoSpace.xl),
        EvoFormError(message: _error),
        EvoButton(label: 'Salvar metas', isLoading: _saving, onPressed: _save),
        if (widget.info.current != null) ...[
          const SizedBox(height: EvoSpace.sm),
          EvoButton(
            label: 'Remover metas',
            variant: EvoButtonVariant.secondary,
            onPressed: _saving ? null : _clear,
          ),
        ],
        const SizedBox(height: EvoSpace.sm),
        Text('As metas valem a partir de hoje.', style: secondary),
        if (history.isNotEmpty) ...[
          const SizedBox(height: EvoSpace.x2xl),
          Semantics(
            header: true,
            child: Text('Histórico', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: EvoSpace.sm),
          for (final target in history)
            Padding(
              padding: const EdgeInsets.only(bottom: EvoSpace.sm),
              child: Text(
                'Desde ${localizations.formatShortDate(target.validFrom)}: '
                '${target.description}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ],
    );
  }
}
