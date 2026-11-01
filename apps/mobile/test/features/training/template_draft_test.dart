import 'package:evofit/features/training/domain/template.dart';
import 'package:evofit/features/training/domain/template_draft.dart';
import 'package:flutter_test/flutter_test.dart';

TemplateExercise _exercise(String name, {bool timed = false}) =>
    TemplateExercise(
      id: name,
      name: name,
      equipment: 'barbell',
      loadType: timed ? 'time' : 'external',
    );

TemplateDraft _draft(List<String> names) =>
    TemplateDraft(name: 'Treino A')..add([for (final n in names) _exercise(n)]);

List<String> _names(TemplateDraft draft) => [
  for (final i in draft.items) i.exercise.name,
];

/// Ex.: "A B | C D | E" — barras separam blocos; letras juntas estão no mesmo grupo.
String _layout(TemplateDraft draft) {
  final parts = <String>[];
  for (var i = 0; i < draft.items.length; i++) {
    final item = draft.items[i];
    final sameAsPrevious =
        i > 0 && item.group != null && draft.items[i - 1].group == item.group;
    parts.add(
      sameAsPrevious ? '+${item.exercise.name}' : ' ${item.exercise.name}',
    );
  }
  return parts.join().trim();
}

void main() {
  test(
    'exercícios entram com 3 séries e descanso padrão; por tempo, duração',
    () {
      final draft = TemplateDraft()
        ..add([_exercise('Supino'), _exercise('Prancha', timed: true)]);

      expect(draft.items[0].plannedSets, hasLength(3));
      expect(draft.items[0].plannedSets.first.target, '8–12');
      expect(draft.items[0].restS, TemplateDraft.defaultRestS);
      expect(draft.items[1].plannedSets.first.target, '30 s');
    },
  );

  test('juntar cria bi-set, depois tri-set e série gigante', () {
    final draft = _draft(['A', 'B', 'C', 'D', 'E']);

    draft.joinNext(0);
    expect(_layout(draft), 'A+B C D E');
    expect(draft.items[0].group!.kind, 'biset');

    draft.joinNext(1);
    expect(_layout(draft), 'A+B+C D E');
    expect(draft.items[0].group!.kind, 'triset');

    draft.joinNext(2);
    expect(draft.items[0].group!.kind, 'giant_set');
  });

  test('juntar dois grupos vizinhos os une; o limite é 6', () {
    final draft = _draft(['A', 'B', 'C', 'D', 'E', 'F', 'G']);
    draft
      ..joinNext(0)
      ..joinNext(2);
    expect(_layout(draft), 'A+B C+D E F G');

    draft.joinNext(1);
    expect(_layout(draft), 'A+B+C+D E F G');
    draft
      ..joinNext(3)
      ..joinNext(4);
    expect(draft.canJoinNext(5), isFalse);
    draft.joinNext(5);
    expect(_layout(draft), 'A+B+C+D+E+F G');
  });

  test('a supersérie continua supersérie enquanto tiver 2 itens', () {
    final draft = _draft(['A', 'B', 'C'])..joinNext(0);
    draft.items[0].group!.kind = 'superset';

    draft.moveUp(1); // troca dentro do grupo
    expect(draft.items[0].group!.kind, 'superset');
    draft.joinNext(1);
    expect(draft.items[0].group!.kind, 'triset');
  });

  test('remover um item de um bi-set desfaz o grupo', () {
    final draft = _draft(['A', 'B', 'C'])..joinNext(0);
    draft.remove(1);
    expect(_layout(draft), 'A C');
    expect(draft.items.every((i) => i.group == null), isTrue);
  });

  test('um item avulso pula o grupo inteiro ao mover', () {
    final draft = _draft(['A', 'B', 'C'])..joinNext(0);

    draft.moveUp(2);
    expect(_layout(draft), 'C A+B');

    draft.moveDown(0);
    expect(_layout(draft), 'A+B C');
  });

  test('na ponta do grupo, mover primeiro tira o item do grupo', () {
    final draft = _draft(['X', 'A', 'B', 'C'])
      ..joinNext(1)
      ..joinNext(2);
    expect(_layout(draft), 'X A+B+C');

    draft.moveUp(1); // A sai do grupo e fica no lugar
    expect(_layout(draft), 'X A B+C');
    expect(draft.items[2].group!.kind, 'biset');

    draft.moveUp(1); // agora sobe de verdade
    expect(_names(draft), ['A', 'X', 'B', 'C']);
  });

  test('sair do grupo só vale nas pontas', () {
    final draft = _draft(['A', 'B', 'C'])
      ..joinNext(0)
      ..joinNext(1);

    draft.leaveGroup(1);
    expect(_layout(draft), 'A+B+C');
    draft.leaveGroup(2);
    expect(_layout(draft), 'A+B C');
  });

  test(
    'o JSON segue o formato da API, com grupos na ordem em que aparecem',
    () {
      final draft = _draft(['A', 'B', 'C', 'D'])
        ..joinNext(2)
        ..joinNext(0);
      draft.items[2].group!.restAfterS = 60;
      draft.items[0].notes = '  pegada aberta ';

      final json = draft.toJson();
      expect(json['name'], 'Treino A');
      expect(json['notes'], isNull);
      expect(json['groups'], [
        {'kind': 'biset', 'rest_after_s': null},
        {'kind': 'biset', 'rest_after_s': 60},
      ]);
      final items = json['items']! as List;
      expect([for (final i in items) (i as Map)['group']], [0, 0, 1, 1]);
      expect((items.first as Map)['notes'], 'pegada aberta');
      expect((items.first as Map)['planned_sets'], [
        {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
        {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
        {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
      ]);
    },
  );

  test('ler da API e voltar ao JSON preserva a estrutura', () {
    final template = WorkoutTemplate.fromJson({
      'id': 't1',
      'name': 'Treino B',
      'notes': null,
      'position': 1,
      'groups': [
        {'id': 'g1', 'kind': 'superset', 'rest_after_s': 90},
      ],
      'items': [
        for (final (name, group) in [('A', 0), ('B', 0), ('C', null)])
          {
            'id': name,
            'exercise': {
              'id': name,
              'name': name,
              'equipment': 'barbell',
              'load_type': 'external',
              'is_active': true,
              'primary_muscles': ['chest'],
            },
            'planned_sets': [
              {'kind': 'working', 'reps_min': 10, 'reps_max': 10},
            ],
            'rest_s': 60,
            'notes': null,
            'group': group,
          },
      ],
      'exercise_count': 3,
      'set_count': 3,
      'muscles': ['chest'],
    });

    final json = TemplateDraft.from(template).toJson();
    expect(json['groups'], [
      {'kind': 'superset', 'rest_after_s': 90},
    ]);
    expect(
      [for (final i in json['items']! as List) (i as Map)['group']],
      [0, 0, null],
    );
  });
}
