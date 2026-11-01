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
import '../application/templates_controller.dart';
import '../data/templates_api.dart';
import '../domain/template.dart';
import '../domain/template_draft.dart';
import 'exercise_picker_page.dart';
import 'item_editor_page.dart';

/// Cria ou edita uma ficha. Tudo é montado aqui e salvo de uma vez.
class TemplateEditorPage extends ConsumerWidget {
  const TemplateEditorPage.create({super.key}) : templateId = null;

  const TemplateEditorPage.edit({super.key, required String this.templateId});

  final String? templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(workoutOptionsProvider);
    final templates = templateId == null ? null : ref.watch(templatesProvider);

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

    final error = options.error ?? templates?.error;
    if (error != null) {
      return message(
        'Não foi possível carregar a ficha',
        error is ApiException ? error.message : 'Erro inesperado.',
        retry: () {
          ref.invalidate(workoutOptionsProvider);
          if (templateId != null) ref.invalidate(templatesProvider);
        },
      );
    }
    final loaded = options.value;
    if (loaded == null || (templateId != null && templates?.value == null)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      );
    }
    WorkoutTemplate? template;
    if (templateId != null) {
      template = templates!.value!.where((t) => t.id == templateId).firstOrNull;
      if (template == null) {
        return message(
          'Ficha não encontrada',
          'Ela pode ter sido excluída. Volte para a lista de fichas.',
        );
      }
    }
    return _Editor(template: template, options: loaded);
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.template, required this.options});

  final WorkoutTemplate? template;
  final WorkoutOptions options;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _formKey = GlobalKey<FormState>();
  late final TemplateDraft _draft = widget.template == null
      ? TemplateDraft()
      : TemplateDraft.from(widget.template!);
  late final _name = TextEditingController(text: _draft.name);
  late final _notes = TextEditingController(text: _draft.notes);
  bool _saving = false;
  bool _dirty = false;
  ApiException? _error;

  bool get _isNew => widget.template == null;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _notes]) {
      final initial = controller.text;
      // O controlador também avisa mudanças de cursor; só texto conta.
      controller.addListener(() {
        if (controller.text != initial) _changed(() {});
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Aplica uma mudança no rascunho e marca a ficha como alterada.
  void _changed(VoidCallback change) => setState(() {
    change();
    _dirty = true;
    _error = null;
  });

  Future<void> _addExercises() async {
    final picked = await Navigator.of(context).push<List<TemplateExercise>>(
      MaterialPageRoute(builder: (_) => const ExercisePickerPage()),
    );
    if (picked == null || picked.isEmpty) return;
    _changed(() => _draft.add(picked));
  }

  Future<void> _editItem(int index) async {
    final edited = await Navigator.of(context).push<DraftItem>(
      MaterialPageRoute(
        builder: (_) => ItemEditorPage(
          item: _draft.items[index].copy(),
          options: widget.options,
        ),
      ),
    );
    if (edited != null) _changed(() => _draft.items[index] = edited);
  }

  Future<void> _editGroup(DraftGroup group) async {
    final size = _draft.membersOf(group).length;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
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
                if (size == 2) ...[
                  const EvoFieldLabel(
                    'Tipo',
                    hint:
                        'Bi-set: mesmo músculo. Supersérie: músculos opostos.',
                  ),
                  EvoChipGroup(
                    single: true,
                    options: [
                      for (final code in ['biset', 'superset'])
                        (code, widget.options.groupLabel(code)),
                    ],
                    selected: {group.kind},
                    onChanged: (v) {
                      setSheet(() {});
                      _changed(() => group.kind = v.first);
                    },
                  ),
                  const SizedBox(height: EvoSpace.xl),
                ],
                const EvoFieldLabel(
                  'Descanso depois da rodada',
                  hint: 'Entre os exercícios do grupo não há descanso.',
                ),
                EvoChipGroup(
                  single: true,
                  options: [for (final s in restOptions) ('$s', restLabel(s))],
                  selected: {'${group.restAfterS ?? 0}'},
                  onChanged: (v) {
                    final seconds = int.parse(v.first);
                    setSheet(() {});
                    _changed(
                      () => group.restAfterS = seconds == 0 ? null : seconds,
                    );
                  },
                ),
                const SizedBox(height: EvoSpace.xl),
                EvoButton(
                  label: 'Desfazer grupo',
                  icon: Icons.link_off_rounded,
                  variant: EvoButtonVariant.secondary,
                  onPressed: () {
                    _changed(() => _draft.ungroup(group));
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !validateAndFocusFirstError(_formKey.currentState!)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    _draft
      ..name = _name.text
      ..notes = _notes.text;
    final controller = ref.read(templatesProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isNew) {
        await controller.create(_draft.toJson());
      } else {
        await controller.replace(widget.template!.id, _draft.toJson());
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_isNew ? 'Ficha criada' : 'Ficha salva')),
      );
      _dirty = false;
      context.pop();
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
        title: const Text('Excluir ficha?'),
        content: Text(
          '“${widget.template!.name}” some da sua lista. Não dá para desfazer.',
        ),
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
      await ref.read(templatesProvider.notifier).delete(widget.template!.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Ficha excluída')));
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
        content: const Text('O que você mudou nesta ficha não será salvo.'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const <String, String>{};

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(title: Text(_isNew ? 'Nova ficha' : 'Editar ficha')),
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
                        TextFormField(
                          controller: _name,
                          maxLength: 60,
                          textCapitalization: TextCapitalization.sentences,
                          forceErrorText: fieldErrors['name'],
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Dê um nome à ficha.';
                            if (text.length < 2) {
                              return 'Use pelo menos 2 caracteres.';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Nome da ficha',
                            hintText: 'Ex.: Treino A — Peito e tríceps',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: EvoSpace.lg),
                        TextFormField(
                          controller: _notes,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Anotações (opcional)',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: EvoSpace.x2xl),
                        Semantics(
                          header: true,
                          child: Text(
                            _draft.items.isEmpty
                                ? 'Exercícios'
                                : 'Exercícios (${_draft.items.length})',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: EvoSpace.md),
                        if (_draft.items.isEmpty)
                          Text(
                            'Adicione exercícios da biblioteca. Depois dá para '
                            'ajustar séries e descanso, mudar a ordem e juntar '
                            'em bi-set.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ..._blocks(),
                        const SizedBox(height: EvoSpace.md),
                        if (_draft.items.length < TemplateDraft.maxItems)
                          EvoButton(
                            label: 'Adicionar exercícios',
                            icon: Icons.add_rounded,
                            variant: EvoButtonVariant.secondary,
                            onPressed: _saving ? null : _addExercises,
                          ),
                        if (!_isNew) ...[
                          const SizedBox(height: EvoSpace.x2xl),
                          TextButton(
                            onPressed: _saving ? null : _delete,
                            style: TextButton.styleFrom(
                              foregroundColor: EvoColors.danger,
                            ),
                            child: const Text('Excluir ficha'),
                          ),
                        ],
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
                    EvoSpace.sm,
                    EvoSpace.xl,
                    EvoSpace.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EvoFormError(message: _error?.message),
                      EvoButton(
                        label: _isNew ? 'Criar ficha' : 'Salvar',
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

  /// Exercícios em blocos: avulsos soltos, grupos dentro de um contorno com cabeçalho.
  List<Widget> _blocks() {
    final widgets = <Widget>[];
    var index = 0;
    while (index < _draft.items.length) {
      final group = _draft.items[index].group;
      if (group == null) {
        widgets.add(_itemTile(index));
        index++;
        continue;
      }
      final members = _draft.membersOf(group);
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: EvoSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EvoRadius.card),
            border: Border.all(color: EvoColors.accent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GroupHeader(
                label: widget.options.groupLabel(group.kind),
                rest: group.restAfterS,
                onTap: () => _editGroup(group),
              ),
              for (final member in members)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: EvoSpace.sm),
                  child: _itemTile(member, inGroup: true),
                ),
              const SizedBox(height: EvoSpace.sm),
            ],
          ),
        ),
      );
      index = members.last + 1;
    }
    return widgets;
  }

  Widget _itemTile(int index, {bool inGroup = false}) {
    final item = _draft.items[index];
    final theme = Theme.of(context);
    final rest = item.restS;
    final summary = [
      setsSummary(item.plannedSets),
      if (!inGroup && rest != null) 'descanso ${restLabel(rest)}',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.only(bottom: inGroup ? 0 : EvoSpace.sm),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: EvoSpace.md),
          shape: inGroup
              ? null
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EvoRadius.card),
                  side: const BorderSide(color: EvoColors.borderSubtle),
                ),
          tileColor: inGroup ? null : EvoColors.bgSurface,
          onTap: _saving ? null : () => _editItem(index),
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: EvoColors.bgElevated,
            child: Text(
              '${index + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: EvoColors.textPrimary,
              ),
            ),
          ),
          title: Text(item.exercise.name, style: theme.textTheme.titleMedium),
          subtitle: Text(
            item.exercise.isActive ? summary : '$summary · arquivado',
            style: theme.textTheme.bodyMedium,
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Ações de ${item.exercise.name}',
            onSelected: (action) => _onAction(action, index),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Séries e descanso'),
              ),
              if (index > 0)
                const PopupMenuItem(
                  value: 'up',
                  child: Text('Mover para cima'),
                ),
              if (index < _draft.items.length - 1)
                const PopupMenuItem(
                  value: 'down',
                  child: Text('Mover para baixo'),
                ),
              if (_draft.canJoinNext(index))
                const PopupMenuItem(
                  value: 'join',
                  child: Text('Juntar com o próximo'),
                ),
              if (_draft.isFirstOfGroup(index) || _draft.isLastOfGroup(index))
                const PopupMenuItem(
                  value: 'leave',
                  child: Text('Tirar do grupo'),
                ),
              const PopupMenuItem(value: 'remove', child: Text('Remover')),
            ],
          ),
        ),
      ),
    );
  }

  void _onAction(String action, int index) {
    switch (action) {
      case 'edit':
        _editItem(index);
      case 'up':
        _changed(() => _draft.moveUp(index));
      case 'down':
        _changed(() => _draft.moveDown(index));
      case 'join':
        _changed(() => _draft.joinNext(index));
      case 'leave':
        _changed(() => _draft.leaveGroup(index));
      case 'remove':
        _changed(() => _draft.remove(index));
    }
  }
}

/// "3 × 8–12", "1 aquec. + 3 × 10" ou "4 séries" quando os alvos variam.
String setsSummary(List<PlannedSet> sets) {
  final warmups = sets.where((s) => s.isWarmup).length;
  final working = sets.where((s) => !s.isWarmup).toList();
  final targets = {for (final s in working) s.target};
  final main = working.isEmpty
      ? ''
      : targets.length == 1
      ? '${working.length} × ${targets.first}'
      : '${working.length} séries';
  final prefix = warmups == 0 ? '' : '$warmups aquec.';
  return [prefix, main].where((s) => s.isNotEmpty).join(' + ');
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.rest,
    required this.onTap,
  });

  final String label;
  final int? rest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Ajustar $label',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(EvoRadius.card),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: evoTouchTargetMin),
          padding: const EdgeInsets.symmetric(
            horizontal: EvoSpace.lg,
            vertical: EvoSpace.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.link_rounded, size: 18),
              const SizedBox(width: EvoSpace.sm),
              Expanded(
                child: Text(
                  rest == null
                      ? label
                      : '$label · descanso ${restLabel(rest!)} após a rodada',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.tune_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
