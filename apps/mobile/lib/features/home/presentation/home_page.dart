import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_logo.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../goals/application/goals_controller.dart';
import '../../goals/domain/goal.dart';
import '../../sessions/application/session_controller.dart';
import '../../sessions/domain/session.dart';
import '../../activities/domain/activity.dart';
import '../../analytics/domain/compare.dart';
import '../../training/application/templates_controller.dart';
import '../application/dashboard_controller.dart';
import '../domain/dashboard.dart';
import 'dashboard_sections.dart';

/// Tela inicial de quem entrou: o painel pelo objetivo (3.8) e os atalhos.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).value;
    // O roteador só mostra esta tela com sessão ativa; o retorno vazio cobre a transição
    // de saída (logout), quando o estado já mudou e a tela ainda está sendo removida.
    if (auth is! Authenticated) return const Scaffold();
    final user = auth.user;
    final theme = Theme.of(context);
    final goals = ref.watch(goalsProvider);
    final templates = ref.watch(templatesProvider);
    final session = ref.watch(sessionProvider).value;
    final now = session == null
        ? DateTime.now()
        : ref.watch(clockTickProvider).value ?? DateTime.now();
    // Quem pulou passos do onboarding é convidado a completar o perfil.
    final profile = user.profile;
    final dashboard = ref.watch(dashboardProvider);
    // Abre outra tela e, na volta, refaz o painel: o que mudou lá (um treino, uma
    // meta) aparece aqui.
    void go(String route) =>
        context.push(route).then((_) => ref.invalidate(dashboardProvider));
    final incomplete =
        profile.primaryObjective == null ||
        profile.preferredModalities.isEmpty ||
        profile.weeklyAvailability == null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: EvoSpace.xl,
        title: const EvoLogo(size: 30),
        actions: [
          IconButton(
            tooltip: 'Perfil',
            onPressed: () => go(AppRoutes.profile),
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: EvoColors.accent,
              child: Text(
                user.displayName.isEmpty
                    ? '?'
                    : user.displayName.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: EvoColors.onAccent,
                  fontSize: EvoFontSize.bodySm,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: EvoSpace.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            EvoSpace.xl,
            EvoSpace.xl,
            EvoSpace.xl,
            EvoSpace.xl,
          ),
          children: [
            EvoEntrance(
              child: Semantics(
                header: true,
                child: Text(
                  'Olá, ${user.displayName}!',
                  style: theme.textTheme.displayMedium,
                ),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(1),
              child: Text(
                incomplete
                    ? 'Complete seu perfil para receber sugestões que '
                          'combinam com você.'
                    : switch (dashboard.value?.objectiveLabel) {
                        final label? => 'Seu foco: $label.',
                        _ =>
                          'Bora treinar? Monte uma ficha ou comece um treino '
                              'livre.',
                      },
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: EvoColors.textSecondary,
                ),
              ),
            ),
            if (incomplete) ...[
              const SizedBox(height: EvoSpace.xl),
              EvoEntrance(
                delay: EvoEntrance.stagger(1),
                child: EvoButton(
                  label: 'Completar perfil',
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: () => go(AppRoutes.profile),
                ),
              ),
            ],
            const SizedBox(height: EvoSpace.x2xl),
            // Treino aberto (inclusive depois de fechar e reabrir o app): retomar.
            if (session != null) ...[
              EvoEntrance(
                delay: EvoEntrance.stagger(2),
                child: _LinkCard(
                  icon: Icons.play_arrow_rounded,
                  title: 'Treino em andamento',
                  subtitle: session.isPaused
                      ? '${session.name} · pausado'
                      : '${session.name} · ${formatElapsed(session.elapsedAt(now))}',
                  onTap: () => go(AppRoutes.session),
                ),
              ),
              const SizedBox(height: EvoSpace.md),
            ],
            ...switch (dashboard) {
              AsyncData(:final value) => _dashboard(value, go),
              AsyncError() => [
                EvoErrorView(
                  title: 'Não foi possível montar o seu painel',
                  message: 'Os atalhos abaixo continuam funcionando.',
                  onRetry: () => ref.invalidate(dashboardProvider),
                ),
                const SizedBox(height: EvoSpace.x2xl),
              ],
              _ => const [
                EvoLoadingView(lines: 4),
                SizedBox(height: EvoSpace.x2xl),
              ],
            },
            const DashboardHeader('Atalhos'),
            EvoEntrance(
              delay: EvoEntrance.stagger(2),
              child: _LinkCard(
                icon: Icons.flag_outlined,
                title: 'Metas',
                subtitle: switch (goals) {
                  AsyncData(:final value) => _goalsSummary(value),
                  AsyncError() => 'Não foi possível carregar. Toque para ver.',
                  _ => 'Carregando…',
                },
                onTap: () => go(AppRoutes.goals),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: _LinkCard(
                icon: Icons.list_alt_rounded,
                title: 'Fichas de treino',
                subtitle: switch (templates) {
                  AsyncData(:final value) => switch (value.length) {
                    0 => 'Monte seu primeiro treino',
                    1 => '1 ficha',
                    final n => '$n fichas',
                  },
                  AsyncError() => 'Não foi possível carregar. Toque para ver.',
                  _ => 'Carregando…',
                },
                onTap: () => go(AppRoutes.templates),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: _LinkCard(
                icon: Icons.directions_run_rounded,
                title: 'Atividades',
                subtitle: 'Corrida, caminhada, ciclismo e natação',
                onTap: () => go(AppRoutes.activities),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: _LinkCard(
                icon: Icons.flag_circle_outlined,
                title: 'Planos',
                subtitle: 'Caminhada, primeiros 5 km e 10 km',
                onTap: () => go(AppRoutes.plans),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: _LinkCard(
                icon: Icons.insights_rounded,
                title: 'Evolução',
                subtitle: 'Gráficos por semana, consistência e comparativos',
                onTap: () => go(AppRoutes.evolution),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: _LinkCard(
                icon: Icons.accessibility_new_rounded,
                title: 'Meu Corpo',
                subtitle: 'Estímulo por músculo, de frente e de costas',
                onTap: () => go(AppRoutes.body),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: _LinkCard(
                icon: Icons.history_rounded,
                title: 'Histórico',
                subtitle: 'Treinos concluídos e recordes',
                onTap: () => go(AppRoutes.history),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(4),
              child: _LinkCard(
                icon: Icons.fitness_center_rounded,
                title: 'Exercícios',
                subtitle: 'Biblioteca com busca por nome e músculo',
                onTap: () => go(AppRoutes.exercises),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(5),
              child: _LinkCard(
                icon: Icons.dns_outlined,
                title: 'Status do servidor',
                subtitle: 'Conexão com a API e o banco de dados',
                onTap: () => go(AppRoutes.status),
              ),
            ),
            const SizedBox(height: EvoSpace.xl),
            EvoEntrance(
              delay: EvoEntrance.stagger(6),
              child: Text(
                'Conectado como ${user.email}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Semana, foco pelo objetivo, metas e o último registro.
  static List<Widget> _dashboard(Dashboard data, void Function(String) go) {
    Widget spaced(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: EvoSpace.md),
      child: child,
    );
    final last = data.lastRecord;
    return [
      spaced(WeekCard(week: data.week, onTap: () => go(AppRoutes.evolution))),
      if (data.focus.isNotEmpty) ...[
        const SizedBox(height: EvoSpace.lg),
        const DashboardHeader('Seu foco'),
        for (final card in data.focus) spaced(_focus(card, go)),
      ],
      if (data.goals.isNotEmpty) ...[
        const SizedBox(height: EvoSpace.lg),
        DashboardHeader(
          'Metas',
          trailing: data.activeGoals > data.goals.length
              ? TextButton(
                  onPressed: () => go(AppRoutes.goals),
                  child: Text('Ver as ${data.activeGoals}'),
                )
              : null,
        ),
        for (final goal in data.goals)
          spaced(
            GoalProgressTile(
              goal: goal,
              onTap: () => go(AppRoutes.goalEdit(goal.id)),
            ),
          ),
      ],
      if (last != null) ...[
        const SizedBox(height: EvoSpace.lg),
        const DashboardHeader('Último registro'),
        spaced(
          FocusTile(
            icon: last.modality == 'strength'
                ? Icons.fitness_center_rounded
                : modalityIcon(last.modality),
            title: lastRecordTitle(last),
            headline: lastRecordDetail(last).isEmpty
                ? 'Registrado'
                : lastRecordDetail(last),
            detail: _dayLabel(last.day, data.today),
            onTap: () => go(
              last.modality == 'strength'
                  ? AppRoutes.history
                  : AppRoutes.activities,
            ),
          ),
        ),
      ],
      const SizedBox(height: EvoSpace.x2xl),
    ];
  }

  static String _dayLabel(DateTime day, DateTime today) =>
      switch (today.difference(day).inDays) {
        0 => 'Hoje',
        1 => 'Ontem',
        final n => 'Há $n dias',
      };

  static Widget _focus(FocusCard card, void Function(String) go) =>
      switch (card) {
        StrengthFocus() => FocusTile(
          icon: Icons.fitness_center_rounded,
          title: 'Musculação · últimos 7 dias',
          headline: strengthHeadline(card),
          detail: strengthDetail(card),
          onTap: () => go(AppRoutes.evolution),
        ),
        BodyFocus() => FocusTile(
          icon: Icons.accessibility_new_rounded,
          title: 'Meu Corpo · ${card.periodDays} dias',
          headline: bodyHeadline(card),
          onTap: () => go(AppRoutes.body),
        ),
        EnduranceFocus() => FocusTile(
          icon: modalityIcon(card.modality),
          title: '${modalityLabel(card.modality)} · últimos 7 dias',
          headline: enduranceHeadline(card),
          detail: enduranceDetail(card),
          onTap: () => go(AppRoutes.activities),
        ),
        PlanFocus() => FocusTile(
          icon: Icons.flag_circle_outlined,
          title: card.title,
          headline: planHeadline(card),
          detail: card.nextSession == null
              ? 'Todas as sessões feitas'
              : 'Próxima: ${card.nextSession!.summary}',
          onTap: () => go(AppRoutes.plan(card.id)),
        ),
      };

  static String _goalsSummary(List<Goal> goals) {
    final active = goals.where((g) => g.isActive).length;
    return switch (active) {
      0 => 'Defina o que quer alcançar',
      1 => '1 meta ativa',
      _ => '$active metas ativas',
    };
  }
}

/// Cartão de atalho do início: ícone, título, resumo e seta.
class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: EvoColors.bgElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: EvoColors.textPrimary, size: 22),
          ),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            color: EvoColors.textPrimary,
            size: 20,
          ),
        ],
      ),
    );
  }
}
