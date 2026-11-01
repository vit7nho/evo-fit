import 'package:evofit/features/exercises/domain/exercise.dart';
import 'package:flutter_test/flutter_test.dart';

Exercise _exercise(
  String name, {
  String equipment = 'barbell',
  List<String> primary = const ['chest'],
  List<String> secondary = const [],
  bool custom = false,
}) => Exercise(
  id: name,
  name: name,
  mechanics: 'compound',
  equipment: equipment,
  loadType: 'external',
  isCustom: custom,
  muscles: [
    for (final m in primary) ExerciseMuscle(id: m, name: m, role: 'primary'),
    for (final m in secondary)
      ExerciseMuscle(id: m, name: m, role: 'secondary'),
  ],
);

void main() {
  final library = [
    _exercise('Supino reto com barra', secondary: ['triceps']),
    _exercise('Supino reto com halteres', equipment: 'dumbbells'),
    _exercise('Tríceps francês', equipment: 'dumbbells', primary: ['triceps']),
    _exercise('Flexão de braços', equipment: 'bodyweight'),
    _exercise(
      'Remada no TRX',
      equipment: 'bodyweight',
      primary: ['lats'],
      custom: true,
    ),
  ];

  List<String> names(List<Exercise> list) => [for (final e in list) e.name];

  test('a chave de busca ignora acentos, caixa e espaços extras', () {
    expect(searchKey('  Tríceps   FRANCÊS '), 'triceps frances');
    expect(searchKey('Elevação pélvica'), 'elevacao pelvica');
  });

  test('a busca exige todas as palavras, sem acentos', () {
    expect(names(filterExercises(library, query: 'triceps')), [
      'Tríceps francês',
    ]);
    expect(names(filterExercises(library, query: 'supino HALTERES')), [
      'Supino reto com halteres',
    ]);
    expect(filterExercises(library, query: '   '), hasLength(5));
  });

  test('o filtro de músculo considera principais e secundários', () {
    expect(names(filterExercises(library, muscle: 'triceps')), [
      'Supino reto com barra',
      'Tríceps francês',
    ]);
  });

  test('"meus" mostra só os criados pelo usuário', () {
    expect(names(filterExercises(library, mineOnly: true)), ['Remada no TRX']);
  });

  test(
    'equipamentos disponíveis vêm do perfil, com o peso do corpo sempre',
    () {
      expect(availableEquipment(const []), isNull);
      expect(availableEquipment(const ['gym', 'bands']), isNull);
      expect(availableEquipment(const ['dumbbells', 'treadmill']), {
        'dumbbells',
        'bodyweight',
      });

      final atHome = filterExercises(
        library,
        equipment: availableEquipment(const ['dumbbells']),
      );
      expect(names(atHome), [
        'Supino reto com halteres',
        'Tríceps francês',
        'Flexão de braços',
        'Remada no TRX',
      ]);
    },
  );
}
