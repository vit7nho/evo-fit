import 'template.dart';

/// Grupo em edição. Os itens apontam para o objeto (identidade), não para um índice:
/// mover e remover itens não exige renumerar nada.
class DraftGroup {
  DraftGroup({required this.kind, this.restAfterS});

  String kind;
  int? restAfterS;
}

class DraftItem {
  DraftItem({
    required this.exercise,
    required this.plannedSets,
    this.restS,
    this.notes,
    this.group,
  });

  final TemplateExercise exercise;
  List<PlannedSet> plannedSets;
  int? restS;
  String? notes;
  DraftGroup? group;

  DraftItem copy() => DraftItem(
    exercise: exercise,
    plannedSets: [...plannedSets],
    restS: restS,
    notes: notes,
    group: group,
  );
}

/// Ficha em edição: regras de agrupar, mover e remover, e a conversão para a API.
///
/// Invariantes mantidos por todas as operações (os mesmos que a API confere):
/// os membros de um grupo ficam em sequência; um grupo tem de 2 a [maxGroupSize]
/// itens; o tipo acompanha o tamanho (2 = bi-set ou supersérie, 3 = tri-set,
/// 4 ou mais = série gigante).
class TemplateDraft {
  TemplateDraft({this.name = '', this.notes = '', List<DraftItem>? items})
    : items = items ?? [];

  factory TemplateDraft.from(WorkoutTemplate template) {
    final groups = [
      for (final g in template.groups)
        DraftGroup(kind: g.kind, restAfterS: g.restAfterS),
    ];
    return TemplateDraft(
      name: template.name,
      notes: template.notes ?? '',
      items: [
        for (final item in template.items)
          DraftItem(
            exercise: item.exercise,
            plannedSets: [...item.plannedSets],
            restS: item.restS,
            notes: item.notes,
            group: item.group == null ? null : groups[item.group!],
          ),
      ],
    );
  }

  static const maxGroupSize = 6;
  static const maxItems = 30;
  static const maxSets = 10;
  static const defaultRestS = 90;

  String name;
  String notes;
  final List<DraftItem> items;

  /// Séries iniciais de um exercício recém-adicionado.
  static List<PlannedSet> defaultSets(TemplateExercise exercise) => List.filled(
    3,
    exercise.timed
        ? const PlannedSet(durationS: 30)
        : const PlannedSet(repsMin: 8, repsMax: 12),
  );

  void add(List<TemplateExercise> exercises) {
    for (final exercise in exercises) {
      if (items.length >= maxItems) return;
      items.add(
        DraftItem(
          exercise: exercise,
          plannedSets: defaultSets(exercise),
          restS: defaultRestS,
        ),
      );
    }
  }

  void remove(int index) {
    items.removeAt(index);
    _normalize();
  }

  List<int> membersOf(DraftGroup group) => [
    for (var i = 0; i < items.length; i++)
      if (items[i].group == group) i,
  ];

  bool isFirstOfGroup(int index) {
    final group = items[index].group;
    return group != null && (index == 0 || items[index - 1].group != group);
  }

  bool isLastOfGroup(int index) {
    final group = items[index].group;
    return group != null &&
        (index == items.length - 1 || items[index + 1].group != group);
  }

  /// Pode juntar o item com o seguinte num grupo (sem passar do tamanho máximo)?
  bool canJoinNext(int index) {
    if (index >= items.length - 1) return false;
    final a = items[index].group;
    final b = items[index + 1].group;
    if (a != null && a == b) return false;
    final size =
        (a == null ? 1 : membersOf(a).length) +
        (b == null ? 1 : membersOf(b).length);
    return size <= maxGroupSize;
  }

  /// Junta o item com o seguinte: cria um grupo, entra no do vizinho ou une os dois.
  void joinNext(int index) {
    if (!canJoinNext(index)) return;
    final current = items[index];
    final next = items[index + 1];
    final target = current.group ?? next.group ?? DraftGroup(kind: 'biset');
    // Sem o null: itens avulsos não fazem parte de nenhum grupo a absorver.
    final absorbed = {?current.group, ?next.group}..remove(target);
    for (final item in items) {
      if (item == current || item == next || absorbed.contains(item.group)) {
        item.group = target;
      }
    }
    _normalize();
  }

  /// Tira o item do grupo. Só nas pontas, para os demais continuarem em sequência.
  void leaveGroup(int index) {
    if (!isFirstOfGroup(index) && !isLastOfGroup(index)) return;
    items[index].group = null;
    _normalize();
  }

  void ungroup(DraftGroup group) {
    for (final item in items) {
      if (item.group == group) item.group = null;
    }
  }

  /// Sobe um item. Dentro do grupo, troca com o vizinho; na ponta de cima do grupo,
  /// primeiro sai dele; um item avulso pula o grupo de cima inteiro.
  void moveUp(int index) {
    if (index <= 0) return;
    final item = items[index];
    if (item.group != null && items[index - 1].group == item.group) {
      _swap(index, index - 1);
    } else if (item.group != null) {
      item.group = null;
    } else {
      final above = items[index - 1].group;
      final target = above == null ? index - 1 : membersOf(above).first;
      items
        ..removeAt(index)
        ..insert(target, item);
    }
    _normalize();
  }

  /// Desce um item (espelho de [moveUp]).
  void moveDown(int index) {
    if (index >= items.length - 1) return;
    final item = items[index];
    if (item.group != null && items[index + 1].group == item.group) {
      _swap(index, index + 1);
    } else if (item.group != null) {
      item.group = null;
    } else {
      final below = items[index + 1].group;
      final target = below == null ? index + 1 : membersOf(below).last;
      items
        ..removeAt(index)
        ..insert(target, item);
    }
    _normalize();
  }

  void _swap(int a, int b) {
    final item = items[a];
    items[a] = items[b];
    items[b] = item;
  }

  /// Desfaz grupos com menos de 2 itens e ajusta o tipo ao tamanho.
  void _normalize() {
    final seen = <DraftGroup>{};
    for (final item in items) {
      final group = item.group;
      if (group == null || !seen.add(group)) continue;
      final size = membersOf(group).length;
      if (size < 2) {
        ungroup(group);
      } else if (size == 2) {
        if (group.kind != 'superset') group.kind = 'biset';
      } else {
        group.kind = size == 3 ? 'triset' : 'giant_set';
      }
    }
  }

  /// Corpo de POST/PUT /workout-templates: grupos na ordem em que aparecem.
  Map<String, Object?> toJson() {
    final groups = <DraftGroup>[];
    for (final item in items) {
      final group = item.group;
      if (group != null && !groups.contains(group)) groups.add(group);
    }
    return {
      'name': name.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'groups': [
        for (final g in groups) {'kind': g.kind, 'rest_after_s': g.restAfterS},
      ],
      'items': [
        for (final item in items)
          {
            'exercise_id': item.exercise.id,
            'planned_sets': [for (final s in item.plannedSets) s.toJson()],
            'rest_s': item.restS,
            'notes': (item.notes ?? '').trim().isEmpty
                ? null
                : item.notes!.trim(),
            'group': item.group == null ? null : groups.indexOf(item.group!),
          },
      ],
    };
  }
}
