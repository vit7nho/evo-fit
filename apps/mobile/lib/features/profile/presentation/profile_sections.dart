import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../auth/domain/current_user.dart';
import '../domain/profile.dart';

/// Seções do perfil. As mesmas telas servem ao onboarding e à edição no perfil.
enum ProfileSection {
  basics('dados', 'Dados pessoais'),
  objectives('objetivos', 'Objetivos'),
  activity('atividades', 'Atividades'),
  routine('rotina', 'Rotina'),
  health('saude', 'Saúde');

  const ProfileSection(this.path, this.title);

  final String path;
  final String title;

  static ProfileSection fromPath(String path) => ProfileSection.values
      .firstWhere((s) => s.path == path, orElse: () => ProfileSection.basics);
}

/// Ícone de cada objetivo (apresentação; o vocabulário vem da API).
IconData objectiveIcon(String code) => switch (code) {
  'gain_muscle' => Icons.fitness_center_rounded,
  'lose_weight' => Icons.local_fire_department_outlined,
  'maintain' => Icons.balance_rounded,
  'run' => Icons.directions_run_rounded,
  'walk_habit' => Icons.directions_walk_rounded,
  'general_health' => Icons.favorite_border_rounded,
  _ => Icons.flag_outlined,
};

/// Respostas em edição. Mutável de propósito: as telas chamam setState após mudar.
class ProfileDraft {
  ProfileDraft.from(CurrentUser user)
    : displayName = user.profile.displayName,
      birthYear = user.profile.birthYear,
      sexForCalculations = user.profile.sexForCalculations,
      unitSystem = user.profile.unitSystem,
      primaryObjective = user.profile.primaryObjective,
      secondaryObjectives = {...user.profile.secondaryObjectives},
      modalities = {...user.profile.preferredModalities},
      experienceLevel = user.profile.experienceLevel,
      daysPerWeek = user.profile.weeklyAvailability?.daysPerWeek,
      minutesPerSession = user.profile.weeklyAvailability?.minutesPerSession,
      equipment = {...user.profile.equipment},
      healthConsent = user.hasConsent(ConsentKinds.healthData),
      limitationTags = {...user.profile.limitationTags},
      limitationsNote = user.profile.limitationsNote ?? '';

  String displayName;
  int? birthYear;
  String? sexForCalculations;
  String unitSystem;
  String? primaryObjective;
  Set<String> secondaryObjectives;
  Set<String> modalities;
  String? experienceLevel;
  int? daysPerWeek;
  int? minutesPerSession;
  Set<String> equipment;
  bool healthConsent;
  Set<String> limitationTags;
  String limitationsNote;

  /// Opções de duração por sessão, em minutos.
  static const sessionMinutes = [20, 30, 45, 60, 90];

  bool isComplete(ProfileSection section) => switch (section) {
    ProfileSection.basics => displayName.trim().isNotEmpty,
    ProfileSection.objectives => primaryObjective != null,
    ProfileSection.activity => modalities.isNotEmpty,
    ProfileSection.routine => daysPerWeek != null && minutesPerSession != null,
    ProfileSection.health => true,
  };

  /// Descarta as respostas de uma seção (botão "Pular" do onboarding).
  void clear(ProfileSection section) {
    switch (section) {
      case ProfileSection.basics:
        break;
      case ProfileSection.objectives:
        primaryObjective = null;
        secondaryObjectives = {};
      case ProfileSection.activity:
        modalities = {};
        experienceLevel = null;
      case ProfileSection.routine:
        daysPerWeek = null;
        minutesPerSession = null;
        equipment = {};
      case ProfileSection.health:
        healthConsent = false;
        limitationTags = {};
        limitationsNote = '';
    }
  }

  /// Campos de PATCH /me de uma seção. Dados de saúde só vão com consentimento.
  Map<String, Object?> changes(ProfileSection section) => switch (section) {
    ProfileSection.basics => {
      'display_name': displayName.trim(),
      'birth_year': birthYear,
      'sex_for_calculations': sexForCalculations,
      'unit_system': unitSystem,
    },
    ProfileSection.objectives => {
      'primary_objective': primaryObjective,
      'secondary_objectives': secondaryObjectives
          .where((o) => o != primaryObjective)
          .toList(),
    },
    ProfileSection.activity => {
      'preferred_modalities': modalities.toList(),
      'experience_level': experienceLevel,
    },
    ProfileSection.routine => {
      'weekly_availability': daysPerWeek == null || minutesPerSession == null
          ? null
          : WeeklyAvailability(
              daysPerWeek: daysPerWeek!,
              minutesPerSession: minutesPerSession!,
            ).toJson(),
      'equipment': equipment.toList(),
    },
    ProfileSection.health =>
      healthConsent
          ? {
              'limitation_tags': limitationTags.toList(),
              'limitations_note': limitationsNote.trim(),
            }
          : const {},
  };
}

List<(String, String)> _pairs(List<Option> options) => [
  for (final o in options) (o.code, o.label),
];

// --- editores (controlados pelo rascunho) ---

class ObjectivesEditor extends StatelessWidget {
  const ObjectivesEditor({
    super.key,
    required this.draft,
    required this.options,
    required this.onChanged,
  });

  final ProfileDraft draft;
  final ProfileOptions options;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final secondary = options.objectives
        .where((o) => o.code != draft.primaryObjective)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Linhas de dois cartões com altura natural (rótulos longos ou fonte
        // ampliada quebram linha sem estourar), iguais dentro de cada linha.
        for (var i = 0; i < options.objectives.length; i += 2) ...[
          if (i > 0) const SizedBox(height: EvoSpace.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (j, o)
                    in options.objectives.skip(i).take(2).indexed) ...[
                  if (j > 0) const SizedBox(width: EvoSpace.md),
                  Expanded(
                    child: EvoOptionCard(
                      label: o.label,
                      icon: objectiveIcon(o.code),
                      selected: draft.primaryObjective == o.code,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        draft
                          ..primaryObjective = o.code
                          ..secondaryObjectives.remove(o.code);
                        onChanged();
                      },
                    ),
                  ),
                ],
                if (options.objectives.length - i == 1) ...[
                  const SizedBox(width: EvoSpace.md),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
        // Os secundários só aparecem depois da escolha principal.
        AnimatedSize(
          duration: EvoMotion.base,
          curve: EvoCurves.standard,
          alignment: Alignment.topCenter,
          child: draft.primaryObjective == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: EvoSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const EvoFieldLabel(
                        'Também quer',
                        hint: 'Opcional. Escolha quantos quiser.',
                      ),
                      EvoChipGroup(
                        options: _pairs(secondary),
                        selected: draft.secondaryObjectives,
                        onChanged: (value) {
                          draft.secondaryObjectives = value;
                          onChanged();
                        },
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class ActivityEditor extends StatelessWidget {
  const ActivityEditor({
    super.key,
    required this.draft,
    required this.options,
    required this.onChanged,
  });

  final ProfileDraft draft;
  final ProfileOptions options;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EvoFieldLabel('Modalidades', hint: 'Escolha uma ou mais.'),
        EvoChipGroup(
          options: _pairs(options.modalities),
          selected: draft.modalities,
          onChanged: (value) {
            draft.modalities = value;
            onChanged();
          },
        ),
        const SizedBox(height: EvoSpace.x2xl),
        const EvoFieldLabel('Experiência com treino'),
        EvoChipGroup(
          single: true,
          options: _pairs(options.experienceLevels),
          selected: {?draft.experienceLevel},
          onChanged: (value) {
            draft.experienceLevel = value.single;
            onChanged();
          },
        ),
      ],
    );
  }
}

class RoutineEditor extends StatelessWidget {
  const RoutineEditor({
    super.key,
    required this.draft,
    required this.options,
    required this.onChanged,
  });

  final ProfileDraft draft;
  final ProfileOptions options;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EvoFieldLabel('Dias de treino por semana'),
        EvoNumberPicker(
          min: 1,
          max: 7,
          value: draft.daysPerWeek,
          semanticsSuffix: 'dias por semana',
          onChanged: (value) {
            HapticFeedback.selectionClick();
            draft.daysPerWeek = value;
            onChanged();
          },
        ),
        const SizedBox(height: EvoSpace.xl),
        const EvoFieldLabel('Tempo por treino'),
        EvoChipGroup(
          single: true,
          options: [
            for (final m in ProfileDraft.sessionMinutes) ('$m', '$m min'),
          ],
          selected: {
            if (draft.minutesPerSession != null) '${draft.minutesPerSession}',
          },
          onChanged: (value) {
            draft.minutesPerSession = int.parse(value.single);
            onChanged();
          },
        ),
        const SizedBox(height: EvoSpace.x2xl),
        const EvoFieldLabel(
          'Equipamentos disponíveis',
          hint: 'Usado para sugerir exercícios que você consegue fazer.',
        ),
        EvoChipGroup(
          options: _pairs(options.equipment),
          selected: draft.equipment,
          onChanged: (value) {
            draft.equipment = value;
            onChanged();
          },
        ),
      ],
    );
  }
}

class HealthEditor extends StatelessWidget {
  const HealthEditor({
    super.key,
    required this.draft,
    required this.options,
    required this.onChanged,
    required this.noteController,
  });

  final ProfileDraft draft;
  final ProfileOptions options;
  final VoidCallback onChanged;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Consentimento específico e destacado (LGPD art. 11, I).
        // Material próprio: o efeito de toque do SwitchListTile fica visível.
        Material(
          color: EvoColors.bgSurface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EvoRadius.card),
            side: BorderSide(
              color: draft.healthConsent
                  ? EvoColors.accent
                  : EvoColors.borderSubtle,
            ),
          ),
          child: SwitchListTile(
            value: draft.healthConsent,
            onChanged: (value) {
              draft.healthConsent = value;
              onChanged();
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: EvoSpace.lg,
              vertical: EvoSpace.xs,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EvoRadius.card),
            ),
            title: Text(
              'Autorizo o uso dos meus dados de saúde',
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: EvoSpace.xs),
              child: Text(
                'Só para evitar sugestões de treino inadequadas. Você pode '
                'revogar no perfil a qualquer momento — os dados são apagados.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: EvoMotion.base,
          curve: EvoCurves.standard,
          alignment: Alignment.topCenter,
          child: !draft.healthConsent
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: EvoSpace.x2xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const EvoFieldLabel('Onde você sente limitação?'),
                      EvoChipGroup(
                        options: _pairs(options.limitationTags),
                        selected: draft.limitationTags,
                        onChanged: (value) {
                          draft.limitationTags = value;
                          onChanged();
                        },
                      ),
                      const SizedBox(height: EvoSpace.xl),
                      TextField(
                        controller: noteController,
                        maxLines: 3,
                        maxLength: 1000,
                        onChanged: (value) => draft.limitationsNote = value,
                        decoration: const InputDecoration(
                          labelText: 'Observações (opcional)',
                          hintText: 'Ex.: dor no joelho direito ao agachar',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class BasicsEditor extends StatelessWidget {
  const BasicsEditor({
    super.key,
    required this.draft,
    required this.options,
    required this.onChanged,
    required this.nameController,
    required this.birthYearController,
  });

  final ProfileDraft draft;
  final ProfileOptions options;
  final VoidCallback onChanged;
  final TextEditingController nameController;
  final TextEditingController birthYearController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          onChanged: (value) {
            draft.displayName = value;
            onChanged();
          },
          validator: (value) => (value ?? '').trim().isEmpty
              ? 'Informe como quer ser chamado.'
              : null,
          decoration: const InputDecoration(
            labelText: 'Como quer ser chamado',
            prefixIcon: Icon(Icons.person_outline_rounded),
            counterText: '',
          ),
        ),
        const SizedBox(height: EvoSpace.lg),
        TextFormField(
          controller: birthYearController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: (value) {
            draft.birthYear = int.tryParse(value);
            onChanged();
          },
          validator: (value) {
            if (value == null || value.isEmpty) return null;
            final year = int.tryParse(value);
            final now = DateTime.now().year;
            if (year == null || year < now - 100 || year > now - 13) {
              return 'Informe um ano entre ${now - 100} e ${now - 13}.';
            }
            return null;
          },
          decoration: const InputDecoration(
            labelText: 'Ano de nascimento (opcional)',
            helperText: 'Só o ano: usado em estimativas, nunca exibido.',
            prefixIcon: Icon(Icons.cake_outlined),
          ),
        ),
        const SizedBox(height: EvoSpace.xl),
        const EvoFieldLabel(
          'Sexo para cálculos',
          hint: 'Opcional. Usado só em estimativas de gasto calórico.',
        ),
        EvoChipGroup(
          single: true,
          options: _pairs(options.sexForCalculations),
          selected: {?draft.sexForCalculations},
          onChanged: (value) {
            draft.sexForCalculations = value.single;
            onChanged();
          },
        ),
        const SizedBox(height: EvoSpace.xl),
        const EvoFieldLabel('Unidades'),
        EvoChipGroup(
          single: true,
          options: _pairs(options.unitSystems),
          selected: {draft.unitSystem},
          onChanged: (value) {
            draft.unitSystem = value.single;
            onChanged();
          },
        ),
      ],
    );
  }
}
