import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/profile_actions.dart';
import '../data/profile_api.dart';
import '../domain/profile.dart';
import 'profile_sections.dart';

/// Primeiro acesso: objetivo, atividades, rotina e saúde (docs/UX_FLOWS.md §2).
///
/// Todos os passos podem ser pulados; ao fim, as respostas vão em um único PATCH /me
/// e o roteador leva ao início.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _Step {
  const _Step(this.section, this.title, this.subtitle);

  final ProfileSection section;
  final String title;
  final String subtitle;
}

const _steps = [
  _Step(
    ProfileSection.objectives,
    'Qual é o seu\nobjetivo?',
    'Isso ajusta o painel e as sugestões. Dá para mudar depois no perfil.',
  ),
  _Step(
    ProfileSection.activity,
    'Como você se\nexercita?',
    'Mostramos só o que faz sentido para você.',
  ),
  _Step(
    ProfileSection.routine,
    'Sua rotina',
    'Para sugerir treinos que cabem na sua semana.',
  ),
  _Step(
    ProfileSection.health,
    'Alguma limitação\nfísica?',
    'Opcional. Ajuda a evitar sugestões inadequadas.',
  ),
];

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pages = PageController();
  final _note = TextEditingController();
  late final ProfileDraft _draft;
  int _index = 0;
  bool _submitting = false;
  ApiException? _error;

  /// Aviso local de seção incompleta (não vem da API).
  String? _hint;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider).value;
    _draft = ProfileDraft.from((auth! as Authenticated).user);
    _note.text = _draft.limitationsNote;
  }

  @override
  void dispose() {
    _pages.dispose();
    _note.dispose();
    super.dispose();
  }

  _Step get _step => _steps[_index];
  bool get _isLast => _index == _steps.length - 1;

  Future<void> _goTo(int index) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _index = index;
      _error = null;
      _hint = null;
    });
    await _pages.animateToPage(
      index,
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : EvoMotion.slow,
      curve: EvoCurves.emphasizedDecelerate,
    );
  }

  Future<void> _advance() => _isLast ? _finish() : _goTo(_index + 1);

  /// "Continuar": avança, ou diz o que falta escolher (ou que dá para pular).
  Future<void> _next() async {
    final missing = _draft.missing(_step.section);
    if (missing != null) {
      setState(() => _hint = '$missing Ou toque em Pular.');
      return;
    }
    await _advance();
  }

  Future<void> _skip() {
    setState(() => _draft.clear(_step.section));
    return _advance();
  }

  Future<void> _finish() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final answers = <String, Object?>{
      for (final step in _steps) ..._draft.changes(step.section),
    }..removeWhere((_, value) => value == null);
    try {
      // Com sucesso, a conta deixa de precisar de onboarding e o roteador leva ao início.
      await ref
          .read(profileActionsProvider)
          .completeOnboarding(answers, grantHealthData: _draft.healthConsent);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(profileOptionsProvider);

    return PopScope(
      // O voltar do Android volta um passo; no primeiro, sai do app normalmente.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_submitting) _goTo(_index - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: options.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(EvoSpace.xl),
              child: EvoLoadingView(lines: 6),
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(EvoSpace.xl),
                child: EvoErrorView(
                  title: 'Não foi possível carregar as opções',
                  message: error is ApiException
                      ? error.message
                      : 'Erro inesperado.',
                  onRetry: () => ref.invalidate(profileOptionsProvider),
                ),
              ),
            ),
            data: _buildSteps,
          ),
        ),
      ),
    );
  }

  Widget _buildSteps(ProfileOptions options) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _Header(
          index: _index,
          total: _steps.length,
          title: _step.title,
          onBack: _index == 0 || _submitting ? null : () => _goTo(_index - 1),
          onSkip: _submitting ? null : _skip,
        ),
        Expanded(
          child: PageView(
            controller: _pages,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final step in _steps)
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    EvoSpace.xl,
                    EvoSpace.lg,
                    EvoSpace.xl,
                    EvoSpace.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EvoEntrance(
                        child: Semantics(
                          header: true,
                          child: Text(
                            step.title,
                            style: theme.textTheme.displaySmall,
                          ),
                        ),
                      ),
                      const SizedBox(height: EvoSpace.sm),
                      EvoEntrance(
                        delay: EvoEntrance.stagger(1),
                        child: Text(
                          step.subtitle,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: EvoColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: EvoSpace.x2xl),
                      EvoEntrance(
                        delay: EvoEntrance.stagger(2),
                        child: _editor(step.section, options),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EvoSpace.xl,
            0,
            EvoSpace.xl,
            EvoSpace.lg,
          ),
          child: ConstrainedBox(
            // Com fonte muito grande o rodapé rola, em vez de espremer o conteúdo.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EvoFormError(message: _hint ?? _error?.message),
                  EvoButton(
                    label: _isLast ? 'Concluir' : 'Continuar',
                    trailingIcon: _isLast
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                    isLoading: _submitting,
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _editor(ProfileSection section, ProfileOptions options) {
    void changed() => setState(() {
      _error = null;
      _hint = null;
    });
    return switch (section) {
      ProfileSection.objectives => ObjectivesEditor(
        draft: _draft,
        options: options,
        onChanged: changed,
      ),
      ProfileSection.activity => ActivityEditor(
        draft: _draft,
        options: options,
        onChanged: changed,
      ),
      ProfileSection.routine => RoutineEditor(
        draft: _draft,
        options: options,
        onChanged: changed,
      ),
      ProfileSection.health => HealthEditor(
        draft: _draft,
        options: options,
        onChanged: changed,
        noteController: _note,
      ),
      ProfileSection.basics => const SizedBox.shrink(),
    };
  }
}

/// Voltar, progresso ("2 de 4") e pular.
class _Header extends StatelessWidget {
  const _Header({
    required this.index,
    required this.total,
    required this.title,
    required this.onBack,
    required this.onSkip,
  });

  final int index;
  final int total;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EvoSpace.sm,
        EvoSpace.sm,
        EvoSpace.sm,
        0,
      ),
      child: Row(
        children: [
          // No primeiro passo o voltar some também para o TalkBack (o espaço fica).
          Visibility(
            visible: onBack != null,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: IconButton(
              tooltip: 'Passo anterior',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
            ),
          ),
          const SizedBox(width: EvoSpace.sm),
          Expanded(
            // Região viva: ao trocar de passo, o TalkBack anuncia o novo passo.
            child: Semantics(
              liveRegion: true,
              label:
                  'Passo ${index + 1} de $total: '
                  '${title.replaceAll('\n', ' ')}',
              excludeSemantics: true,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (index + 1) / total),
                duration: evoDuration(context, EvoMotion.slow),
                curve: EvoCurves.emphasizedDecelerate,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(EvoRadius.pill),
                  child: LinearProgressIndicator(value: value, minHeight: 6),
                ),
              ),
            ),
          ),
          const SizedBox(width: EvoSpace.sm),
          TextButton(onPressed: onSkip, child: const Text('Pular')),
        ],
      ),
    );
  }
}
