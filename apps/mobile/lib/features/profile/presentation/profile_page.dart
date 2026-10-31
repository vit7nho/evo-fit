import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/current_user.dart';
import '../application/profile_actions.dart';
import '../data/profile_api.dart';
import '../domain/profile.dart';
import 'profile_sections.dart';

/// Resumo do perfil por seção; cada cartão abre a edição daquela seção.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).value;
    if (auth is! Authenticated) return const Scaffold();
    final user = auth.user;
    // Sem as opções, os cartões mostram os códigos; os rótulos chegam em seguida.
    final options = ref.watch(profileOptionsProvider).value;
    final theme = Theme.of(context);

    final sections = [
      for (final section in ProfileSection.values)
        _SectionCard(
          section: section,
          summary: _summary(section, user, options),
          onTap: () => context.push(AppRoutes.profileEdit(section.path)),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(EvoSpace.xl),
          children: [
            EvoEntrance(child: _Identity(user: user)),
            const SizedBox(height: EvoSpace.x2xl),
            for (final (i, card) in sections.indexed) ...[
              EvoEntrance(delay: EvoEntrance.stagger(i + 1), child: card),
              const SizedBox(height: EvoSpace.md),
            ],
            const SizedBox(height: EvoSpace.lg),
            EvoEntrance(
              delay: EvoEntrance.stagger(sections.length + 1),
              child: const _AiConsentCard(),
            ),
            const SizedBox(height: EvoSpace.x2xl),
            EvoButton(
              label: 'Sair da conta',
              icon: Icons.logout_rounded,
              variant: EvoButtonVariant.secondary,
              onPressed: () => _confirmLogout(context, ref),
            ),
            const SizedBox(height: EvoSpace.lg),
            Text(
              'Conectado como ${user.email}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(
    ProfileSection section,
    CurrentUser user,
    ProfileOptions? options,
  ) {
    final p = user.profile;
    String label(List<Option> Function(ProfileOptions) list, String? code) =>
        options == null
        ? (code ?? '')
        : ProfileOptions.labelOf(list(options), code);
    String labels(
      List<Option> Function(ProfileOptions) list,
      List<String> codes,
    ) => codes.map((c) => label(list, c)).join(', ');

    return switch (section) {
      ProfileSection.basics => [
        p.displayName,
        label((o) => o.unitSystems, p.unitSystem),
      ].where((s) => s.isNotEmpty).join(' · '),
      ProfileSection.objectives =>
        p.primaryObjective == null
            ? 'Não definido'
            : [
                label((o) => o.objectives, p.primaryObjective),
                if (p.secondaryObjectives.isNotEmpty)
                  '+${p.secondaryObjectives.length}',
              ].join(' '),
      ProfileSection.activity =>
        p.preferredModalities.isEmpty
            ? 'Não definido'
            : [
                labels((o) => o.modalities, p.preferredModalities),
                if (p.experienceLevel != null)
                  label((o) => o.experienceLevels, p.experienceLevel),
              ].join(' · '),
      ProfileSection.routine =>
        p.weeklyAvailability == null
            ? 'Não definida'
            : '${p.weeklyAvailability!.daysPerWeek}x por semana · '
                  '${p.weeklyAvailability!.minutesPerSession} min',
      ProfileSection.health =>
        !user.hasConsent(ConsentKinds.healthData)
            ? 'Não autorizado'
            : p.limitationTags.isEmpty
            ? 'Autorizado · nenhuma limitação'
            : 'Autorizado · ${labels((o) => o.limitationTags, p.limitationTags)}',
    };
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você precisará entrar de novo com e-mail e senha neste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.user});

  final CurrentUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = user.displayName.isEmpty
        ? '?'
        : user.displayName.characters.first.toUpperCase();
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: EvoColors.accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: EvoColors.onAccent,
              fontSize: EvoFontSize.title,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: EvoSpace.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, style: theme.textTheme.titleLarge),
              Text(user.email, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.summary,
    required this.onTap,
  });

  final ProfileSection section;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Editar ${section.title}',
      child: EvoCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: EvoSpace.md),
            const Icon(
              Icons.chevron_right_rounded,
              color: EvoColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Consentimento de IA: liga e desliga aqui mesmo, com retorno imediato.
class _AiConsentCard extends ConsumerStatefulWidget {
  const _AiConsentCard();

  @override
  ConsumerState<_AiConsentCard> createState() => _AiConsentCardState();
}

class _AiConsentCardState extends ConsumerState<_AiConsentCard> {
  bool _saving = false;

  Future<void> _toggle(bool granted) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(profileActionsProvider)
          .setConsent(ConsentKinds.aiProcessing, granted: granted);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).value;
    final granted =
        auth is Authenticated &&
        auth.user.hasConsent(ConsentKinds.aiProcessing);
    final theme = Theme.of(context);
    return Card(
      child: SwitchListTile(
        value: granted,
        onChanged: _saving ? null : _toggle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EvoSpace.lg + 4,
          vertical: EvoSpace.sm,
        ),
        title: Text('Análises com IA', style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: EvoSpace.xs),
          child: Text(
            'Permite que o assistente (em desenvolvimento) consulte seus '
            'registros para responder perguntas. Pode ser desligado a qualquer '
            'momento.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
