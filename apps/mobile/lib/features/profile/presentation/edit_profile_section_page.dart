import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/profile_actions.dart';
import '../data/profile_api.dart';
import '../domain/profile.dart';
import 'profile_sections.dart';

/// Edita uma seção do perfil com o mesmo editor do onboarding.
class EditProfileSectionPage extends ConsumerStatefulWidget {
  const EditProfileSectionPage({super.key, required this.section});

  final ProfileSection section;

  @override
  ConsumerState<EditProfileSectionPage> createState() =>
      _EditProfileSectionPageState();
}

class _EditProfileSectionPageState
    extends ConsumerState<EditProfileSectionPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _birthYear = TextEditingController();
  final _note = TextEditingController();
  late final ProfileDraft _draft;
  late final bool _hadHealthConsent;
  bool _saving = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    final user =
        (ref.read(authControllerProvider).value! as Authenticated).user;
    _draft = ProfileDraft.from(user);
    _hadHealthConsent = _draft.healthConsent;
    _name.text = _draft.displayName;
    _birthYear.text = _draft.birthYear?.toString() ?? '';
    _note.text = _draft.limitationsNote;
  }

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? true)) return;
    final actions = ref.read(profileActionsProvider);
    final revokingHealth =
        widget.section == ProfileSection.health &&
        _hadHealthConsent &&
        !_draft.healthConsent;
    if (revokingHealth && !await _confirmHealthRevocation()) return;
    if (!mounted) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (revokingHealth) {
        // A API apaga os dados de saúde junto com o consentimento.
        await actions.setConsent(ConsentKinds.healthData, granted: false);
      } else {
        if (widget.section == ProfileSection.health &&
            _draft.healthConsent &&
            !_hadHealthConsent) {
          await actions.setConsent(ConsentKinds.healthData, granted: true);
        }
        await actions.save(_draft.changes(widget.section));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Perfil atualizado')));
      context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmHealthRevocation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar dados de saúde?'),
        content: const Text(
          'Suas limitações e observações serão apagadas. Você pode informá-las '
          'de novo quando quiser.',
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
              minimumSize: const Size(88, 44),
            ),
            child: const Text('Revogar e apagar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(profileOptionsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.section.title)),
      body: SafeArea(
        top: false,
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
          data: (options) => Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(EvoSpace.xl),
                    child: _editor(options),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  EvoSpace.xl,
                  0,
                  EvoSpace.xl,
                  EvoSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EvoFormError(message: _error?.message),
                    EvoButton(
                      label: 'Salvar',
                      isLoading: _saving,
                      onPressed: _draft.isComplete(widget.section)
                          ? _save
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editor(ProfileOptions options) {
    void changed() => setState(() => _error = null);
    return switch (widget.section) {
      ProfileSection.basics => BasicsEditor(
        draft: _draft,
        options: options,
        onChanged: changed,
        nameController: _name,
        birthYearController: _birthYear,
      ),
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
    };
  }
}
