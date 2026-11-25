import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../data/nutrition_api.dart';
import '../domain/nutrition.dart';

/// O que a tela recebe: o dia escolhido e, na edição, a refeição.
class MealFormArgs {
  const MealFormArgs({required this.day, this.meal});

  final DateTime day;
  final Meal? meal;
}

/// "150" ou "12,5" → número (nulo se não for um número positivo).
double? parseGrams(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  return value == null || value <= 0 ? null : value;
}

class _Line {
  _Line({
    required this.foodId,
    required this.name,
    required this.per100g,
    required double grams,
  }) : grams = TextEditingController(text: formatGrams(grams));

  /// Nulo: o alimento foi apagado depois do registro (não dá para regravar).
  final String? foodId;
  final String name;
  final Nutrients per100g;
  final TextEditingController grams;
}

/// Registrar ou editar uma refeição: tipo, horário e alimentos com as quantidades.
class MealFormPage extends ConsumerStatefulWidget {
  const MealFormPage({super.key, required this.args});

  final MealFormArgs args;

  @override
  ConsumerState<MealFormPage> createState() => _MealFormPageState();
}

class _MealFormPageState extends ConsumerState<MealFormPage> {
  late String _type;
  late TimeOfDay _time;
  final _lines = <_Line>[];
  bool _saving = false;
  String? _error;

  Meal? get _meal => widget.args.meal;

  @override
  void initState() {
    super.initState();
    final meal = _meal;
    if (meal != null) {
      _type = meal.mealType;
      _time = TimeOfDay.fromDateTime(meal.localTime);
      for (final item in meal.items) {
        _lines.add(
          _Line(
            foodId: item.foodId,
            name: item.foodName,
            // A cópia gravada (de quantityG gramas) dá os valores por 100 g para a
            // prévia: scaled(g) multiplica por g/100, então g = 100 × 100 / quantityG.
            per100g: item.nutrients.scaled(10000 / item.quantityG),
            grams: item.quantityG,
          ),
        );
      }
    } else {
      final now = TimeOfDay.now();
      _time = now;
      _type = switch (now.hour) {
        < 10 => 'breakfast',
        < 15 => 'lunch',
        < 18 => 'snack',
        _ => 'dinner',
      };
    }
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.grams.dispose();
    }
    super.dispose();
  }

  Nutrients get _preview => _lines.fold(
    Nutrients.zero,
    (sum, line) => sum + line.per100g.scaled(parseGrams(line.grams.text) ?? 0),
  );

  Future<void> _addFood() async {
    final food = await context.push<Food>(AppRoutes.nutritionFoods);
    if (food == null || !mounted) return;
    setState(
      () => _lines.add(
        _Line(
          foodId: food.id,
          name: food.name,
          per100g: food.per100g,
          grams: (food.defaultPortionG ?? 100).toDouble(),
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'Adicione pelo menos um alimento.');
      return;
    }
    if (_lines.any((l) => l.foodId == null)) {
      setState(
        () => _error =
            'Um alimento desta refeição foi apagado. Remova-o para salvar.',
      );
      return;
    }
    final items = <(String, double)>[];
    for (final line in _lines) {
      final grams = parseGrams(line.grams.text);
      if (grams == null || grams > 5000) {
        setState(
          () => _error = 'Informe a quantidade de ${line.name} (até 5000 g).',
        );
        return;
      }
      items.add((line.foodId!, grams));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final day = widget.args.day;
    try {
      await ref
          .read(nutritionApiProvider)
          .saveMeal(
            id: _meal?.id,
            eatenAt: DateTime(
              day.year,
              day.month,
              day.day,
              _time.hour,
              _time.minute,
            ),
            mealType: _type,
            items: items,
            notes: _meal?.notes,
          );
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar refeição?'),
        content: const Text('A refeição e os alimentos dela saem do dia.'),
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
      await ref.read(nutritionApiProvider).deleteMeal(_meal!.id);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(_meal == null ? 'Registrar refeição' : 'Editar refeição'),
        actions: [
          if (_meal != null)
            IconButton(
              tooltip: 'Apagar refeição',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(EvoSpace.xl),
          children: [
            Wrap(
              spacing: EvoSpace.sm,
              runSpacing: EvoSpace.sm,
              children: [
                for (final MapEntry(key: code, value: label)
                    in mealTypeLabels.entries)
                  ChoiceChip(
                    label: Text(label),
                    selected: _type == code,
                    onSelected: (_) => setState(() => _type = code),
                  ),
              ],
            ),
            const SizedBox(height: EvoSpace.lg),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule_rounded),
              label: Text('Horário: ${_time.format(context)}'),
            ),
            const SizedBox(height: EvoSpace.xl),
            Semantics(
              header: true,
              child: Text('Alimentos', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: EvoSpace.sm),
            for (final (index, line) in _lines.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: EvoSpace.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.name, style: theme.textTheme.bodyLarge),
                          Text(
                            line.foodId == null
                                ? 'Alimento apagado'
                                : '${line.per100g.scaled(parseGrams(line.grams.text) ?? 0).kcal.round()} kcal',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: line.grams,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Gramas de ${line.name}',
                          suffixText: 'g',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover ${line.name}',
                      onPressed: () => setState(
                        () => _lines.removeAt(index).grams.dispose(),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: _addFood,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar alimento'),
            ),
            const SizedBox(height: EvoSpace.xl),
            Text(
              'Total: ${preview.kcal.round()} kcal · ${describeMacros(preview)}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: EvoSpace.lg),
            EvoFormError(message: _error),
            EvoButton(
              label: 'Salvar refeição',
              isLoading: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: EvoSpace.sm),
            Text(
              'Valores calculados pelos alimentos; o total final é o que fica '
              'gravado.',
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
