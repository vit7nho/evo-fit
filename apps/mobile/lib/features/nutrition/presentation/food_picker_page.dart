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

/// Escolher um alimento (catálogo ou próprio) ou criar um novo. Devolve o alimento.
class FoodPickerPage extends ConsumerStatefulWidget {
  const FoodPickerPage({super.key});

  @override
  ConsumerState<FoodPickerPage> createState() => _FoodPickerPageState();
}

class _FoodPickerPageState extends ConsumerState<FoodPickerPage> {
  String _query = '';

  Future<void> _create() async {
    final food = await showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FoodForm(initialName: _query),
    );
    if (food != null && mounted) context.pop(food);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(foodSearchProvider(_query));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar alimento')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EvoSpace.xl,
                EvoSpace.md,
                EvoSpace.xl,
                EvoSpace.sm,
              ),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Buscar alimento',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar alimento'),
                ),
              ),
            ),
            Expanded(
              child: results.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(EvoSpace.xl),
                  child: EvoLoadingView(lines: 3),
                ),
                error: (error, _) => EvoErrorView(
                  title: 'Não foi possível buscar',
                  message: error is ApiException
                      ? error.message
                      : 'Erro inesperado.',
                  onRetry: () => ref.invalidate(foodSearchProvider(_query)),
                ),
                data: (foods) => foods.isEmpty
                    ? EvoEmptyView(
                        icon: Icons.search_off_rounded,
                        title: _query.isEmpty
                            ? 'Nenhum alimento ainda'
                            : 'Nada com “$_query”',
                        message:
                            'Crie o alimento com os valores da embalagem '
                            '(por 100 g).',
                        actionLabel: 'Criar alimento',
                        onAction: _create,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: EvoSpace.xl,
                        ),
                        itemCount: foods.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final food = foods[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(food.name),
                            subtitle: Text(
                              '${food.per100g.kcal.round()} kcal por 100 g · '
                              '${food.sourceLabel}',
                              style: theme.textTheme.bodySmall,
                            ),
                            onTap: () => context.pop(food),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alimento próprio com os valores por 100 g (os da embalagem).
class _FoodForm extends ConsumerStatefulWidget {
  const _FoodForm({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends ConsumerState<_FoodForm> {
  late final _name = TextEditingController(text: widget.initialName);
  final _fields = {
    for (final key in const [
      'kcal',
      'protein_g',
      'carbs_g',
      'fat_g',
      'fiber_g',
      'default_portion_g',
    ])
      key: TextEditingController(),
  };
  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  static const _labels = {
    'kcal': 'Calorias (kcal)',
    'protein_g': 'Proteína (g)',
    'carbs_g': 'Carboidratos (g)',
    'fat_g': 'Gordura (g)',
    'fiber_g': 'Fibras (g, opcional)',
    'default_portion_g': 'Porção comum (g, opcional)',
  };

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, Object?>{'name': _name.text.trim()};
    final errors = <String, String>{};
    for (final MapEntry(key: key, value: controller) in _fields.entries) {
      final text = controller.text.trim();
      final optional = key == 'fiber_g' || key == 'default_portion_g';
      if (text.isEmpty) {
        if (!optional) errors[key] = 'Informe o valor.';
        continue;
      }
      // Zero vale (ex.: frango sem carboidrato).
      final value = double.tryParse(text.replaceAll(',', '.'));
      if (value == null || value < 0) {
        errors[key] = 'Use um número.';
        continue;
      }
      body[key] = key == 'default_portion_g' ? value.round() : value;
    }
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final food = await ref.read(nutritionApiProvider).createFood(body);
      if (mounted) Navigator.of(context).pop(food);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _fieldErrors = error.fieldErrors;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
            Text('Novo alimento', style: theme.textTheme.titleLarge),
            const SizedBox(height: EvoSpace.xs),
            Text(
              'Valores por 100 g, como na tabela da embalagem.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: EvoSpace.lg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nome',
                errorText: _fieldErrors['name'],
              ),
            ),
            for (final MapEntry(key: key, value: controller)
                in _fields.entries) ...[
              const SizedBox(height: EvoSpace.md),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: _labels[key],
                  errorText: _fieldErrors[key],
                ),
              ),
            ],
            const SizedBox(height: EvoSpace.lg),
            EvoFormError(message: _fieldErrors['__root__'] ?? _error),
            EvoButton(
              label: 'Salvar alimento',
              isLoading: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: EvoSpace.sm),
            Text(
              'Só você vê os alimentos que cria.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: EvoColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
