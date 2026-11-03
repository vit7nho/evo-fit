import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../goals/presentation/goal_format.dart';
import '../../training/data/templates_api.dart';
import '../../training/domain/template.dart';
import '../../training/presentation/exercise_picker_page.dart';
import '../../training/presentation/item_editor_page.dart' show restLabel;
import '../application/session_controller.dart';
import '../domain/session.dart';
import 'exercise_card.dart';

/// Treino em andamento: resumo no topo, uma tabela de séries por exercício,
/// descanso e finalização.
class SessionPage extends ConsumerWidget {
  const SessionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(EvoSpace.xl),
            child: EvoErrorView(
              title: 'Não foi possível carregar o treino',
              message: error is ApiException
                  ? error.message
                  : 'Erro inesperado.',
              onRetry: () => ref.invalidate(sessionProvider),
            ),
          ),
        ),
      ),
      data: (session) => session == null
          ? Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(EvoSpace.xl),
                  child: EvoEmptyView(
                    icon: Icons.fitness_center_rounded,
                    title: 'Nenhum treino em andamento',
                    message: 'Comece um treino a partir de uma ficha.',
                    actionLabel: 'Ver fichas',
                    onAction: () => context.go(AppRoutes.templates),
                  ),
                ),
              ),
            )
          : _SessionView(session: session),
    );
  }
}

class _SessionView extends ConsumerStatefulWidget {
  const _SessionView({required this.session});

  final WorkoutSession session;

  @override
  ConsumerState<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends ConsumerState<_SessionView> {
  bool _busy = false;

  WorkoutSession get _session => widget.session;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExercises() async {
    final picked = await Navigator.of(context).push<List<TemplateExercise>>(
      MaterialPageRoute(builder: (_) => const ExercisePickerPage()),
    );
    if (picked == null || picked.isEmpty) return;
    await _run(
      () => ref.read(sessionProvider.notifier).addExercises([
        for (final e in picked) e.id,
      ]),
    );
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar treino?'),
        content: const Text(
          'As séries registradas neste treino serão apagadas. Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar treinando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: EvoColors.danger,
              minimumSize: const Size(88, evoTouchTargetMin),
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    final router = GoRouter.of(context);
    await _run(() async {
      await ref.read(sessionProvider.notifier).discard();
      ref.read(restTimerProvider.notifier).skip();
      router.go(AppRoutes.home);
    });
  }

  Future<void> _finish() async {
    final result = await showModalBottomSheet<(int?, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _FinishSheet(),
    );
    if (result == null || !mounted) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _run(() async {
      final finished = await ref
          .read(sessionProvider.notifier)
          .finish(
            effort: result.$1,
            notes: result.$2.isEmpty ? null : result.$2,
          );
      ref.read(restTimerProvider.notifier).skip();
      final minutes = (finished.elapsedS / 60).round();
      final sets = finished.setCount == 1
          ? '1 série'
          : '${finished.setCount} séries';
      final records = switch (finished.records.length) {
        0 => '',
        1 => ' · 1 recorde',
        final n => ' · $n recordes',
      };
      messenger.showSnackBar(
        SnackBar(content: Text('Treino salvo: $sets em $minutes min$records')),
      );
      // Abre o resumo do treino (com os recordes); voltar leva ao Início.
      router.go(AppRoutes.home);
      unawaited(router.push(AppRoutes.workoutDetail(finished.id)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paused = _session.isPaused;
    final options = ref.watch(workoutOptionsProvider).value;
    // Com fonte grande, o resumo (e o aviso de séries guardadas) rola junto com a
    // lista: fixo, somado à barra de descanso e ao botão de finalizar, não cabe em
    // tela pequena.
    final summaryScrolls = MediaQuery.textScalerOf(context).scale(10) > 13;
    final summary = _SummaryStrip(session: _session);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _session.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: paused ? 'Retomar treino' : 'Pausar treino',
            icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            onPressed: _busy
                ? null
                : () => _run(
                    () => paused
                        ? ref.read(sessionProvider.notifier).resume()
                        : ref.read(sessionProvider.notifier).pause(),
                  ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (_) => _discard(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'discard', child: Text('Descartar treino')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (!summaryScrolls) ...[summary, const _SyncBanner()],
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(EvoSpace.lg),
                children: [
                  if (summaryScrolls) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(EvoRadius.input),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [summary, const _SyncBanner()],
                      ),
                    ),
                    const SizedBox(height: EvoSpace.md),
                  ],
                  if (_session.exercises.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EvoSpace.lg),
                      child: Text(
                        'Treino livre: acrescente os exercícios que for fazer.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ..._cards(options),
                  const SizedBox(height: EvoSpace.sm),
                  EvoButton(
                    label: 'Adicionar exercício',
                    icon: Icons.add_rounded,
                    variant: EvoButtonVariant.secondary,
                    onPressed: _busy ? null : _addExercises,
                  ),
                ],
              ),
            ),
            const _RestBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EvoSpace.xl,
                EvoSpace.sm,
                EvoSpace.xl,
                EvoSpace.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: EvoButton(
                  label: 'Finalizar treino',
                  icon: Icons.flag_rounded,
                  isLoading: _busy,
                  onPressed: _finish,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cartões dos exercícios; os de um grupo ficam juntos, com uma barra lateral.
  List<Widget> _cards(WorkoutOptions? options) {
    final widgets = <Widget>[];
    var index = 0;
    while (index < _session.exercises.length) {
      final group = _session.exercises[index].group;
      // Os membros de um grupo são consecutivos (a API garante).
      final block = group == null
          ? [index]
          : [
              for (var i = index; i < _session.exercises.length; i++)
                if (_session.exercises[i].group == group) i,
            ];
      final cards = [for (final i in block) _card(i)];
      widgets.add(
        group == null
            ? cards.single
            : _GroupBlock(
                label:
                    options?.groupLabel(_session.groups[group].kind) ??
                    _session.groups[group].kind,
                rest: _session.groups[group].restAfterS,
                children: cards,
              ),
      );
      index = block.last + 1;
    }
    return widgets;
  }

  Widget _card(int index) {
    final entry = _session.exercises[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: EvoSpace.md),
      child: ExerciseCard(
        key: ValueKey(entry.id),
        session: _session,
        index: index,
        onRemove: () => _run(
          () => ref.read(sessionProvider.notifier).removeExercise(entry.id),
        ),
      ),
    );
  }
}

/// Resumo ao vivo: duração, volume e séries válidas.
/// Séries guardadas no aparelho (sem conexão) e o envio delas. Some quando a fila
/// esvazia; uma série recusada pelo servidor aparece aqui até ser dispensada.
class _SyncBanner extends ConsumerWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(sessionSyncProvider);
    final theme = Theme.of(context);
    final controller = ref.read(sessionProvider.notifier);
    if (sync.pending == 0 && sync.error == null) return const SizedBox.shrink();

    final count = sync.pending == 1
        ? '1 alteração guardada no aparelho'
        : '${sync.pending} alterações guardadas no aparelho';
    final String text;
    final IconData icon;
    if (sync.error != null && sync.pending == 0) {
      icon = Icons.error_outline_rounded;
      text = 'Uma série guardada não foi aceita pelo servidor: ${sync.error}';
    } else if (sync.syncing) {
      icon = Icons.cloud_upload_outlined;
      text = 'Enviando: $count…';
    } else if (sync.offline) {
      icon = Icons.cloud_off_rounded;
      text = 'Sem conexão · $count. Enviamos quando a internet voltar.';
    } else {
      icon = Icons.cloud_upload_outlined;
      text = '$count, esperando envio.';
    }

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: EvoColors.bgElevated,
        padding: const EdgeInsets.fromLTRB(
          EvoSpace.xl,
          EvoSpace.xs,
          EvoSpace.sm,
          EvoSpace.xs,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: EvoSpace.sm,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: EvoSpace.sm),
                Flexible(child: Text(text, style: theme.textTheme.bodyMedium)),
              ],
            ),
            if (sync.pending > 0 && !sync.syncing)
              TextButton(
                onPressed: () => controller.flush(),
                child: const Text('Tentar agora'),
              )
            else if (sync.error != null && sync.pending == 0)
              TextButton(
                onPressed: controller.dismissSyncError,
                child: const Text('Entendi'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStrip extends ConsumerWidget {
  const _SummaryStrip({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockTickProvider).value ?? DateTime.now();
    final time = formatElapsed(session.elapsedAt(now));
    final sets = session.liveSetCount;
    Widget stat(String label, String value) => Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      color: EvoColors.bgElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: EvoSpace.xl,
        vertical: EvoSpace.sm,
      ),
      // Com fonte grande, os três quebram de linha em vez de estourar.
      child: Wrap(
        spacing: EvoSpace.x2xl,
        runSpacing: EvoSpace.xs,
        children: [
          stat('Duração', session.isPaused ? 'Pausado · $time' : time),
          stat('Volume', '${formatDecimal(session.liveVolumeKg)} kg'),
          stat('Séries', '$sets'),
        ],
      ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.label,
    required this.rest,
    required this.children,
  });

  final String label;
  final int? rest;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: EvoSpace.md),
      padding: const EdgeInsets.only(left: EvoSpace.md),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: EvoColors.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.sm),
            child: Semantics(
              header: true,
              child: Text(
                rest == null
                    ? '$label · sem descanso entre os exercícios'
                    : '$label · descanso ${restLabel(rest!)} após a rodada',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _RestBar extends ConsumerStatefulWidget {
  const _RestBar();

  @override
  ConsumerState<_RestBar> createState() => _RestBarState();
}

class _RestBarState extends ConsumerState<_RestBar> {
  RestTimer? _announcedFor;

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(restTimerProvider);
    if (timer == null) return const SizedBox.shrink();
    final now = ref.watch(clockTickProvider).value ?? DateTime.now();
    final left = timer.remainingAt(now);
    final controller = ref.read(restTimerProvider.notifier);
    final theme = Theme.of(context);

    if (left == 0 && _announcedFor != timer) {
      _announcedFor = timer;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.heavyImpact();
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Descanso terminado',
          TextDirection.ltr,
        );
      });
    }

    return Container(
      width: double.infinity,
      color: EvoColors.accent,
      padding: const EdgeInsets.symmetric(
        horizontal: EvoSpace.lg,
        vertical: EvoSpace.sm,
      ),
      // Texto e botões quebram de linha com fonte grande (Wrap), sem estourar.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            liveRegion: left == 0,
            child: Text(
              left == 0
                  ? 'Descanso terminado'
                  : 'Descanso ${formatElapsed(Duration(seconds: left))}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: EvoColors.onAccent,
              ),
            ),
          ),
          Wrap(
            children: [
              for (final (label, tooltip, action) in [
                ('−15', 'Menos 15 segundos', () => controller.adjust(-15)),
                ('+15', 'Mais 15 segundos', () => controller.adjust(15)),
              ])
                Tooltip(
                  message: tooltip,
                  excludeFromSemantics: true,
                  child: Semantics(
                    button: true,
                    label: tooltip,
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: action,
                      style: TextButton.styleFrom(
                        foregroundColor: EvoColors.onAccent,
                      ),
                      child: Text(label),
                    ),
                  ),
                ),
              TextButton(
                onPressed: controller.skip,
                style: TextButton.styleFrom(
                  foregroundColor: EvoColors.onAccent,
                ),
                child: Text(left == 0 ? 'Fechar' : 'Pular'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinishSheet extends StatefulWidget {
  const _FinishSheet();

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  int? _effort;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
              Semantics(
                header: true,
                child: Text(
                  'Finalizar treino',
                  style: theme.textTheme.titleLarge,
                ),
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
                onChanged: (v) {
                  final value = int.parse(v.first);
                  setState(() => _effort = _effort == value ? null : value);
                },
              ),
              const SizedBox(height: EvoSpace.xl),
              TextField(
                controller: _notes,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Como foi? (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: EvoSpace.lg),
              EvoButton(
                label: 'Salvar treino',
                onPressed: () =>
                    Navigator.of(context).pop((_effort, _notes.text.trim())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
