import 'package:dio/dio.dart';
import 'package:evofit/core/auth/session_store.dart';

import 'fake_http_adapter.dart';

/// Armazenamento de tokens em memória (o Keystore não existe nos testes).
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this.value]);

  String? value;

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> writeRefreshToken(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

/// Imitação da API de autenticação com as mesmas regras de tokens do backend:
/// cada login/refresh gera um par novo e invalida o anterior.
class FakeAuthServer {
  FakeAuthServer({this.validRefreshToken});

  static const email = 'ana@exemplo.com';
  static const password = 'cavalo bateria grampo';

  late final adapter = FakeHttpAdapter(_handle);

  String? validAccessToken;
  String? validRefreshToken;
  bool offline = false;

  /// E-mail devolvido em /me e corpo de /profile-options (trocáveis nos testes).
  String accountEmail = email;
  Map<String, Object> profileOptions = options;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int _counter = 0;

  /// Perfil da conta. A conta padrão já concluiu o onboarding; o cadastro cria uma nova.
  Map<String, Object?> profile = onboardedProfile();
  Set<String> consents = {'terms_privacy'};

  /// Corpos de PATCH /me recebidos e consentimentos alterados, na ordem.
  final patches = <Map<String, Object?>>[];
  final consentCalls = <String>[];

  static Map<String, Object?> onboardedProfile() => {
    ...newProfile(),
    'primary_objective': 'gain_muscle',
    'preferred_modalities': ['strength'],
    'weekly_availability': {'days_per_week': 3, 'minutes_per_session': 45},
    'onboarding_completed_at': '2026-10-30T12:00:00Z',
  };

  static Map<String, Object?> newProfile() => {
    'display_name': 'Ana',
    'timezone': 'America/Sao_Paulo',
    'unit_system': 'metric',
    'secondary_objectives': <String>[],
    'preferred_modalities': <String>[],
    'equipment': <String>[],
    'dietary_preferences': <String>[],
    'limitation_tags': <String>[],
    'onboarding_completed_at': null,
  };

  static const options = {
    'objectives': [
      {'code': 'gain_muscle', 'label': 'Ganhar massa muscular'},
      {'code': 'lose_weight', 'label': 'Emagrecer'},
      {'code': 'general_health', 'label': 'Saúde geral'},
    ],
    'modalities': [
      {'code': 'strength', 'label': 'Musculação'},
      {'code': 'walk', 'label': 'Caminhada'},
    ],
    'equipment': [
      {'code': 'gym', 'label': 'Academia completa'},
      {'code': 'bands', 'label': 'Elásticos'},
    ],
    'dietary_preferences': <Object>[],
    'limitation_tags': [
      {'code': 'knee', 'label': 'Joelho'},
      {'code': 'lower_back', 'label': 'Lombar'},
    ],
    'experience_levels': [
      {'code': 'beginner', 'label': 'Iniciante'},
      {'code': 'advanced', 'label': 'Avançado'},
    ],
    'unit_systems': [
      {'code': 'metric', 'label': 'Métrico (kg, km)'},
    ],
    'sex_for_calculations': [
      {'code': 'unspecified', 'label': 'Prefiro não informar'},
    ],
  };

  /// Atividades guardadas (como a API devolve) e o que chegou nas gravações.
  List<Map<String, Object?>> activities = [];
  final activityBodies = <Map<String, Object?>>[];
  final activityCalls = <String>[];
  int activityListCalls = 0;

  /// Próxima gravação de atividade responde 422 neste campo.
  String? rejectActivityField;

  Map<String, Object?> activityOptions = {
    'modalities': [
      {'code': 'run', 'label': 'Corrida', 'max_distance_m': 300000},
      {'code': 'walk', 'label': 'Caminhada', 'max_distance_m': 150000},
      {'code': 'cycle', 'label': 'Ciclismo', 'max_distance_m': 1000000},
      {'code': 'swim', 'label': 'Natação', 'max_distance_m': 30000},
    ],
    'strokes': [
      {'code': 'freestyle', 'label': 'Crawl'},
      {'code': 'breaststroke', 'label': 'Peito'},
      {'code': 'backstroke', 'label': 'Costas'},
      {'code': 'butterfly', 'label': 'Borboleta'},
      {'code': 'mixed', 'label': 'Variado'},
    ],
    'pool_lengths_m': [25, 50],
  };

  /// Planos oferecidos (como a API devolve) e os planos guardados (com as sessões).
  List<Map<String, Object?>> planTemplates = [
    planTemplate('walk_habit', 'Hábito de caminhada', 'walk', weeks: 8),
    planTemplate('run_5k', 'Primeiros 5 km', 'run', weeks: 9),
    planTemplate(
      'run_10k',
      'Rumo aos 10 km',
      'run',
      weeks: 8,
      note: 'Para o 10 km, o ideal é já correr 5 km sem parar.',
    ),
  ];
  final plans = <Map<String, Object?>>[];
  final planBodies = <Map<String, Object?>>[];
  final planCalls = <String>[];

  /// Respostas do motor de análise (como a API devolve) e as consultas recebidas.
  Map<String, Object?> analyticsOverview = overview();
  Map<String, Map<String, Object?>> comparisons = {
    'sessions': comparison(0, 0),
    'duration_s': comparison(0, 0),
  };
  Map<String, Object?> runEndurance = endurance();

  /// Resistência das outras modalidades (a corrida usa [runEndurance]).
  Map<String, Map<String, Object?>> enduranceByModality = {};

  /// Visão geral por período (`from`), para os Comparativos; sem entrada, usa
  /// [analyticsOverview].
  Map<String, Map<String, Object?>> overviewByFrom = {};

  /// Painel do Início (3.8) como a API devolve; padrão: conta sem registros.
  Map<String, Object?> dashboard = emptyDashboard();
  int dashboardCalls = 0;

  /// O próximo GET /dashboard responde 500.
  bool failDashboard = false;

  static Map<String, Object?> dashboardWeek({
    int sessions = 0,
    int activeDays = 0,
    int durationS = 0,
    int? weeklyTarget,
    int previousSessions = 0,
    int previousActiveDays = 0,
    int streakWeeks = 0,
  }) => {
    'from_date': '2026-11-09',
    'to_date': '2026-11-11',
    'sessions': sessions,
    'active_days': activeDays,
    'duration_s': durationS,
    'weekly_target': weeklyTarget,
    'previous_sessions': previousSessions,
    'previous_active_days': previousActiveDays,
    'streak_weeks': streakWeeks,
  };

  static Map<String, Object?> emptyDashboard({
    String? objective,
    String? objectiveLabel,
    Map<String, Object?>? week,
    List<Map<String, Object?>> focus = const [],
    List<Map<String, Object?>> goals = const [],
    int? activeGoals,
    Map<String, Object?>? lastRecord,
  }) => {
    'objective': objective,
    'objective_label': objectiveLabel,
    'today': '2026-11-11',
    'week': week ?? dashboardWeek(),
    'focus': focus,
    'goals': goals,
    'active_goals': activeGoals ?? goals.length,
    'last_record': lastRecord,
  };
  final analyticsQueries = <String>[];

  /// Meu Corpo (3.6): séries por semana de cada músculo (ausente = 0) e os
  /// detalhes devolvidos por músculo.
  Map<String, double> bodyPerWeek = {};
  Map<String, Map<String, Object?>> muscleDetails = {};

  static const muscleCatalog = [
    ('chest', 'Peito', 'front'),
    ('delts', 'Ombros', 'both'),
    ('biceps', 'Bíceps', 'front'),
    ('triceps', 'Tríceps', 'back'),
    ('forearms', 'Antebraços', 'both'),
    ('lats', 'Dorsais', 'back'),
    ('traps', 'Trapézio', 'back'),
    ('abs', 'Abdômen', 'front'),
    ('obliques', 'Oblíquos', 'front'),
    ('glutes', 'Glúteos', 'back'),
    ('quads', 'Quadríceps', 'front'),
    ('hamstrings', 'Posteriores de coxa', 'back'),
    ('calves', 'Panturrilhas', 'back'),
  ];

  /// Faixas da metodologia v2 (`none` só para zero).
  static String bandOf(double perWeek) => perWeek == 0
      ? 'none'
      : perWeek < 6
      ? 'low'
      : perWeek < 12
      ? 'mid'
      : 'high';

  static Map<String, Object?> muscleOut(
    String id,
    double perWeek, {
    int days = 30,
  }) {
    final (_, name, view) = muscleCatalog.firstWhere((m) => m.$1 == id);
    return {
      'muscle_id': id,
      'name': name,
      'view': view,
      'weighted_sets': (perWeek * days / 7 * 100).round() / 100,
      'weighted_sets_per_week': perWeek,
      'band': bandOf(perWeek),
      'frequency': perWeek == 0 ? 0 : 2,
      'volume_load_kg': perWeek == 0 ? 0 : 1200,
    };
  }

  static const bodyNotice =
      'As faixas são uma referência geral de volume registrado, não '
      'diagnóstico nem prescrição.';

  Map<String, Object?> _body() => {
    'methodology_version': 'v2',
    'from_date': '2026-10-06',
    'to_date': '2026-11-04',
    'period_days': 30,
    'bands': {
      'high': [12, null],
      'low': [0, 6],
      'mid': [6, 12],
      'none': [0, 0],
    },
    'notice': bodyNotice,
    'muscles': [
      for (final (id, _, _) in muscleCatalog)
        muscleOut(id, bodyPerWeek[id] ?? 0),
    ],
  };

  Map<String, Object?> _muscleDetail(String id) =>
      muscleDetails[id] ??
      {
        'methodology_version': 'v2',
        'from_date': '2026-10-06',
        'to_date': '2026-11-04',
        'period_days': 30,
        'notice': bodyNotice,
        'muscle': muscleOut(id, bodyPerWeek[id] ?? 0),
        'exercises': <Object?>[],
        'loads': <Object?>[],
        'previous': null,
      };

  static Map<String, Object?> overview({
    int days = 30,
    int sessions = 0,
    int activeDays = 0,
    int durationS = 0,
    int? weeklyTarget,
    int weeks = 5,
    int activeWeeks = 0,
    int? weeksOnTarget,
    int streak = 0,
    List<Map<String, Object?>> modalities = const [],
    List<int>? weekSessions,
    List<int>? weekSets,
    List<double>? weekVolume,
  }) => {
    'from_date': '2026-10-06',
    'to_date': '2026-11-04',
    'days': days,
    'sessions': sessions,
    'active_days': activeDays,
    'duration_s': durationS,
    'weekly_target': weeklyTarget,
    'consistency': {
      'weeks': weeks,
      'active_weeks': activeWeeks,
      'weeks_on_target': weeksOnTarget,
      'current_streak_weeks': streak,
    },
    'weeks': [
      for (var i = 0; i < weeks; i++)
        {
          'week_start': DateTime(
            2026,
            10,
            5 + i * 7,
          ).toIso8601String().substring(0, 10),
          'active_days': i < activeWeeks ? 2 : 0,
          'sessions': weekSessions?[i] ?? (i < activeWeeks ? 2 : 0),
          'duration_s': i < activeWeeks ? 3600 : 0,
          'strength_sets': weekSets?[i] ?? 0,
          'strength_volume_kg': weekVolume?[i] ?? 0,
        },
    ],
    'modalities': modalities,
  };

  static const metricLabels = {
    'sessions': 'Treinos e atividades',
    'active_days': 'Dias ativos',
    'duration_s': 'Tempo total',
    'strength_sets': 'Séries de musculação',
    'strength_volume_kg': 'Volume de musculação',
    'distance_m': 'Distância',
    'pace_s_per_km': 'Pace médio',
  };

  static Map<String, Object?> comparison(
    num? previous,
    num? current, {
    num? percent,
    String? better,
    String metric = 'sessions',
    String? modality,
  }) => {
    'metric': metric,
    'label': metricLabels[metric],
    'modality': modality,
    'higher_is_better': metric != 'pace_s_per_km',
    'a': {
      'from_date': '2026-09-06',
      'to_date': '2026-10-05',
      'value': previous,
    },
    'b': {'from_date': '2026-10-06', 'to_date': '2026-11-04', 'value': current},
    'difference': previous == null || current == null
        ? null
        : current - previous,
    'percent': percent,
    'better':
        better ??
        (previous == null || current == null
            ? null
            : current == previous
            ? 'same'
            : (current > previous) == (metric != 'pace_s_per_km')
            ? 'b'
            : 'a'),
  };

  static Map<String, Object?> endurance({
    String modality = 'run',
    int sessions = 0,
    int distanceM = 0,
    int? paceSPerKm,
    double? speedKmh,
    int? paceSPer100m,
    String? trend,
    List<Map<String, Object?>> weeks = const [],
  }) => {
    'modality': modality,
    'sessions': sessions,
    'distance_m': distanceM,
    'pace_s_per_km': paceSPerKm,
    'speed_kmh': speedKmh,
    'pace_s_per_100m': paceSPer100m,
    'distance_trend': {'direction': trend, 'per_week': null},
    'weeks': weeks,
  };

  /// Uma semana de resistência como a API devolve.
  static Map<String, Object?> enduranceWeek(
    String weekStart, {
    int sessions = 1,
    int distanceM = 0,
    int? paceSPerKm,
    double? speedKmh,
    int? paceSPer100m,
  }) => {
    'week_start': weekStart,
    'sessions': sessions,
    'duration_s': 0,
    'distance_m': distanceM,
    'pace_s_per_km': paceSPerKm,
    'speed_kmh': speedKmh,
    'pace_s_per_100m': paceSPer100m,
  };

  /// Próxima marcação de sessão responde 422 com esta mensagem.
  String? rejectPlanLink;

  static Map<String, Object?> planTemplate(
    String kind,
    String title,
    String modality, {
    required int weeks,
    String? note,
    List<String> adaptations = const [],
  }) => {
    'kind': kind,
    'version': 1,
    'title': title,
    'summary': '$weeks semanas, 3 sessões por semana.',
    'modality': modality,
    'prerequisite': modality == 'run'
        ? 'Para quem já caminha 30 minutos sem desconforto.'
        : null,
    'sessions_per_week': 3,
    'weeks': weeks,
    'adaptations': adaptations,
    'note': note,
  };

  static Map<String, Object?> run({
    String id = 'corrida-1',
    String startedAt = '2026-11-02T09:00:00Z',
    int durationS = 1800,
    int? distanceM = 5000,
  }) => _derived({
    'id': id,
    'modality': 'run',
    'started_at': startedAt,
    'ended_at': startedAt,
    'duration_s': durationS,
    'distance_m': distanceM,
    'perceived_effort': 6,
    'notes': null,
    'indoor': null,
    'pool_length_m': null,
    'laps': null,
    'stroke': null,
    'elevation_gain_m': null,
    'avg_hr': null,
    'max_hr': null,
  });

  /// Metas guardadas (como a API devolve) e o que chegou nas gravações.
  List<Map<String, Object?>> goals = [];
  final goalBodies = <Map<String, Object?>>[];
  final goalCalls = <String>[];
  int goalListCalls = 0;

  /// Próxima criação de meta responde com o limite de metas ativas (409).
  bool goalLimitReached = false;

  static Map<String, Object?> strengthGoal({
    String id = 'meta-1',
    String status = 'active',
  }) => {
    'id': id,
    'kind': 'strength',
    'title': 'Supino de 80 kg',
    'target': {'exercise': 'Supino', 'load_kg': 80, 'reps': 5},
    'summary': 'Supino: 80 kg × 5',
    'start_date': '2026-10-30',
    'target_date': null,
    'status': status,
    'priority': 2,
    'closed_at': status == 'active' ? null : '2026-10-31T12:00:00Z',
  };

  static Map<String, Object?> _field(
    String key,
    String label,
    String type, {
    bool required = true,
    num? min,
    num? max,
    num? step,
    String? unit,
    List<Map<String, String>>? options,
  }) => {
    'key': key,
    'label': label,
    'type': type,
    'required': required,
    'min': min,
    'max': max,
    'step': step,
    'unit': unit,
    'options': options,
  };

  /// Subconjunto dos tipos reais: um de cada tipo de campo e um de saúde.
  static final goalOptions = {
    'kinds': [
      {
        'code': 'strength',
        'label': 'Força',
        'description': 'Levantar uma carga num exercício.',
        'health_data': false,
        'fields': [
          _field('exercise', 'Exercício', 'text', min: 2, max: 80),
          _field(
            'load_kg',
            'Carga',
            'number',
            min: 1,
            max: 500,
            step: 0.5,
            unit: 'kg',
          ),
          _field('reps', 'Repetições', 'int', min: 1, max: 30),
        ],
      },
      {
        'code': 'weight_loss',
        'label': 'Perder peso',
        'description': 'Chegar a um peso menor.',
        'health_data': true,
        'fields': [
          _field(
            'target_weight_kg',
            'Peso desejado',
            'number',
            min: 30,
            max: 300,
            step: 0.1,
            unit: 'kg',
          ),
        ],
      },
      {
        'code': 'run_time',
        'label': 'Tempo de corrida',
        'description': 'Correr uma distância em até um tempo.',
        'health_data': false,
        'fields': [
          _field(
            'distance_km',
            'Distância',
            'number',
            min: 0.1,
            max: 100,
            step: 0.1,
            unit: 'km',
          ),
          _field('time_s', 'Tempo', 'duration', min: 60, max: 86400),
        ],
      },
      {
        'code': 'frequency',
        'label': 'Frequência',
        'description': 'Treinar um número de vezes por semana.',
        'health_data': false,
        'fields': [
          _field(
            'sessions_per_week',
            'Treinos por semana',
            'int',
            min: 1,
            max: 14,
          ),
          _field(
            'modality',
            'Modalidade',
            'choice',
            required: false,
            options: [
              {'code': 'strength', 'label': 'Musculação'},
              {'code': 'walk', 'label': 'Caminhada'},
            ],
          ),
        ],
      },
    ],
    'statuses': [
      {'code': 'active', 'label': 'Ativa'},
      {'code': 'achieved', 'label': 'Alcançada'},
      {'code': 'abandoned', 'label': 'Abandonada'},
    ],
    'priorities': [
      {'value': 1, 'label': 'Alta'},
      {'value': 2, 'label': 'Média'},
      {'value': 3, 'label': 'Baixa'},
    ],
  };

  /// Biblioteca: catálogo (só leitura) + exercícios próprios, e as gravações recebidas.
  List<Map<String, Object?>> exercises = [
    _catalogExercise('ex-agachamento', 'Agachamento livre', 'barbell', [
      'quads',
      'glutes',
    ]),
    _catalogExercise('ex-flexao', 'Flexão de braços', 'bodyweight', ['chest']),
    _catalogExercise('ex-supino', 'Supino reto com barra', 'barbell', [
      'chest',
    ]),
    _catalogExercise('ex-triceps', 'Tríceps francês', 'dumbbells', ['triceps']),
  ];
  final exerciseBodies = <Map<String, Object?>>[];
  final exerciseCalls = <String>[];

  static const _muscleNames = {
    'chest': 'Peito',
    'triceps': 'Tríceps',
    'lats': 'Dorsais',
    'quads': 'Quadríceps',
    'glutes': 'Glúteos',
  };

  static Map<String, Object?> _catalogExercise(
    String id,
    String name,
    String equipment,
    List<String> primary,
  ) => {
    'id': id,
    'name': name,
    'instructions': 'Orientação de execução de $name.',
    'mechanics': 'compound',
    'equipment': equipment,
    'load_type': 'external',
    'unilateral': false,
    'is_custom': false,
    'is_active': true,
    // Só o agachamento tem fotos, para testar os dois casos.
    'images': id == 'ex-agachamento'
        ? [
            '/api/v1/media/exercises/agachamento-livre/0.jpg',
            '/api/v1/media/exercises/agachamento-livre/1.jpg',
          ]
        : <String>[],
    'muscles': [
      for (final m in primary)
        {'id': m, 'name': _muscleNames[m], 'role': 'primary'},
    ],
  };

  static const exerciseOptions = {
    'muscle_groups': [
      {'id': 'chest', 'name': 'Peito', 'body_region': 'upper', 'view': 'front'},
      {
        'id': 'triceps',
        'name': 'Tríceps',
        'body_region': 'upper',
        'view': 'back',
      },
      {'id': 'lats', 'name': 'Dorsais', 'body_region': 'upper', 'view': 'back'},
      {
        'id': 'quads',
        'name': 'Quadríceps',
        'body_region': 'lower',
        'view': 'front',
      },
      {
        'id': 'glutes',
        'name': 'Glúteos',
        'body_region': 'lower',
        'view': 'back',
      },
    ],
    'equipment': [
      {'code': 'barbell', 'label': 'Barra e anilhas'},
      {'code': 'dumbbells', 'label': 'Halteres'},
      {'code': 'bodyweight', 'label': 'Sem equipamento'},
    ],
    'mechanics': [
      {'code': 'compound', 'label': 'Multiarticular'},
      {'code': 'isolation', 'label': 'Isolado'},
    ],
    'load_types': [
      {'code': 'external', 'label': 'Carga externa'},
      {'code': 'bodyweight', 'label': 'Peso do corpo'},
    ],
  };

  /// Fichas guardadas (como a API devolve) e os corpos recebidos.
  List<Map<String, Object?>> templates = [];
  final templateBodies = <Map<String, Object?>>[];
  final templateCalls = <String>[];

  static const workoutOptions = {
    'group_kinds': [
      {'code': 'biset', 'label': 'Bi-set', 'min_size': 2, 'max_size': 2},
      {'code': 'superset', 'label': 'Supersérie', 'min_size': 2, 'max_size': 2},
      {'code': 'triset', 'label': 'Tri-set', 'min_size': 3, 'max_size': 3},
      {
        'code': 'giant_set',
        'label': 'Série gigante',
        'min_size': 4,
        'max_size': 6,
      },
    ],
    'set_kinds': [
      {'code': 'warmup', 'label': 'Aquecimento'},
      {'code': 'working', 'label': 'Válida'},
      {'code': 'drop', 'label': 'Drop set'},
      {'code': 'rest_pause', 'label': 'Rest-pause'},
    ],
  };

  /// Monta a ficha como a API devolve, a partir do corpo enviado pelo app.
  Map<String, Object?> templateFrom(
    String id,
    int position,
    Map<String, Object?> body,
  ) {
    final items = <Map<String, Object?>>[];
    final muscles = <String>{};
    var sets = 0;
    for (final raw in body['items'] as List? ?? const []) {
      final item = Map<String, Object?>.from(raw as Map);
      final exercise = exercises.firstWhere(
        (e) => e['id'] == item['exercise_id'],
      );
      final primary = [
        for (final m in exercise['muscles']! as List)
          if ((m as Map)['role'] == 'primary') m['id']! as String,
      ];
      muscles.addAll(primary);
      final planned = [
        for (final p in item['planned_sets']! as List)
          Map<String, Object?>.from(p as Map),
      ];
      sets += planned.where((p) => p['kind'] != 'warmup').length;
      items.add({
        'id': 'item-${items.length}',
        'exercise': {
          'id': exercise['id'],
          'name': exercise['name'],
          'equipment': exercise['equipment'],
          'load_type': exercise['load_type'],
          'is_active': exercise['is_active'],
          'primary_muscles': primary,
        },
        'planned_sets': planned,
        'rest_s': item['rest_s'],
        'notes': item['notes'],
        'group': item['group'],
      });
    }
    return {
      'id': id,
      'name': body['name'],
      'notes': body['notes'],
      'position': position,
      'groups': [
        for (final (i, g) in (body['groups'] as List? ?? const []).indexed)
          {'id': 'grupo-$i', ...Map<String, Object?>.from(g as Map)},
      ],
      'items': items,
      'exercise_count': items.length,
      'set_count': sets,
      'muscles': muscles.toList(),
      'created_at': '2026-11-01T12:00:00Z',
      'updated_at': '2026-11-01T12:00:00Z',
    };
  }

  /// Treino aberto (como a API devolve), concluídos e chamadas recebidas.
  Map<String, Object?>? session;
  final finishedSessions = <Map<String, Object?>>[];
  final sessionCalls = <String>[];
  final setBodies = <Map<String, Object?>>[];
  final exerciseUpdates = <Map<String, Object?>>[];

  /// Séries "da última vez" por exercício, para o pré-preenchimento.
  Map<String, List<Map<String, Object?>>> previousSets = {};

  /// Histórico: resumos dos treinos concluídos (do mais recente), treinos
  /// completos para o detalhe, recordes e histórico por exercício.
  List<Map<String, Object?>> historyItems = [];
  List<Map<String, Object?>> pastSessions = [];
  List<Map<String, Object?>> records = [];
  Map<String, Map<String, Object?>> exerciseHistories = {};

  /// A próxima série é salva, mas a resposta não chega ao app.
  bool loseNextSetResponse = false;

  /// Séries reenviadas com um client_id já salvo (devolvidas sem duplicar).
  int resentSets = 0;

  /// Recordes que o próximo treino finalizado bate.
  List<Map<String, Object?>> finishRecords = [];

  /// Itens por página do histórico (a API usa 20).
  int historyPageSize = 20;
  final historyCursors = <String?>[];

  Map<String, Object?> _historyPage(Map<String, dynamic> query) {
    final before = query['before'] as String?;
    historyCursors.add(before);
    final start = before == null ? 0 : int.parse(before);
    final end = (start + historyPageSize).clamp(0, historyItems.length);
    return {
      'items': historyItems.sublist(start, end),
      'next_before': end < historyItems.length ? '$end' : null,
    };
  }

  ResponseBody _exerciseHistory(String exerciseId) {
    final history = exerciseHistories[exerciseId];
    if (history != null) return FakeHttpAdapter.json(200, history);
    final exercise = exercises.where((e) => e['id'] == exerciseId).firstOrNull;
    if (exercise == null) {
      return _problem(404, 'not_found', 'Exercício não encontrado.');
    }
    return FakeHttpAdapter.json(200, {
      'exercise': {
        'id': exercise['id'],
        'name': exercise['name'],
        'equipment': exercise['equipment'],
        'load_type': exercise['load_type'],
        'is_active': true,
        'primary_muscles': <String>[],
      },
      'records': <Object>[],
      'rep_records': <Object>[],
      'sessions': <Object>[],
      'next_before': null,
    });
  }

  /// A próxima série registrada falha (para testar o erro na linha).
  bool failNextSet = false;

  /// Monta um treino como a API devolve, a partir de uma ficha (ou livre).
  Map<String, Object?> sessionFrom(Map<String, Object?>? template) {
    final items = template == null
        ? const <Object>[]
        : template['items']! as List;
    return {
      'id': 'treino-${sessionCalls.length}',
      'name': template?['name'] ?? 'Treino livre',
      'template_id': template?['id'],
      'status': 'in_progress',
      'started_at': '2026-11-01T10:00:00Z',
      'paused_at': null,
      'paused_total_s': 0,
      'ended_at': null,
      'elapsed_s': 0,
      'perceived_effort': null,
      'notes': null,
      'groups': template?['groups'] ?? const <Object>[],
      'exercises': [
        for (final (i, raw) in items.indexed) _sessionEntry(i, raw as Map),
      ],
      'set_count': 0,
      'volume_kg': 0,
    };
  }

  Map<String, Object?> _sessionEntry(int index, Map<dynamic, dynamic> item) {
    final exercise = Map<String, Object?>.from(item['exercise']! as Map);
    return {
      'id': 'entrada-$index-${exercise['id']}',
      'exercise': exercise,
      'position': index,
      'group': item['group'],
      'planned_sets': item['planned_sets'],
      'rest_s': item['rest_s'],
      'notes': null,
      'sets': <Object>[],
      'previous': previousSets[exercise['id']] ?? const <Object>[],
      'previous_at': previousSets.containsKey(exercise['id'])
          ? '2026-10-29T10:00:00Z'
          : null,
    };
  }

  /// Faz o access token atual expirar (o próximo uso recebe 401).
  void expireAccessToken() => validAccessToken = 'expirado';

  ResponseBody _handle(RequestOptions options) {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'sem rede (teste)',
      );
    }
    final body = options.data is Map ? options.data as Map : const {};
    return switch ((options.method, options.path)) {
      ('POST', '/auth/login') =>
        body['email'] == email && body['password'] == password
            ? _issueTokens()
            : _problem(
                401,
                'invalid_credentials',
                'E-mail ou senha incorretos.',
              ),
      ('POST', '/auth/register') =>
        body['password'] == '1234567890'
            ? _problem(
                422,
                'validation_error',
                'Verifique os campos informados.',
                errors: [
                  {
                    'field': 'password',
                    'message': 'Essa senha é muito comum. Escolha outra.',
                  },
                ],
              )
            : _register(),
      ('POST', '/auth/refresh') => _refresh(body['refresh_token']),
      ('POST', '/auth/logout') => _logout(),
      ('GET', '/me') => _authorized(options) ? _me() : _invalidToken(),
      ('PATCH', '/me') =>
        _authorized(options)
            ? _patch(body.cast<String, Object?>())
            : _invalidToken(),
      ('GET', '/profile-options') => FakeHttpAdapter.json(200, profileOptions),
      ('GET', '/goal-options') => FakeHttpAdapter.json(200, goalOptions),
      ('GET', '/workout-options') => FakeHttpAdapter.json(200, workoutOptions),
      ('GET', '/workout-sessions') =>
        _authorized(options)
            ? FakeHttpAdapter.json(200, _historyPage(options.queryParameters))
            : _invalidToken(),
      ('GET', '/analytics/records') =>
        _authorized(options)
            ? FakeHttpAdapter.json(200, records)
            : _invalidToken(),
      ('GET', final path)
          when path.startsWith('/exercises/') && path.endsWith('/history') =>
        _authorized(options)
            ? _exerciseHistory(path.split('/')[2])
            : _invalidToken(),
      ('GET', '/workout-sessions/current') =>
        !_authorized(options)
            ? _invalidToken()
            : session == null
            ? ResponseBody.fromString('', 204)
            : FakeHttpAdapter.json(200, session!),
      ('POST', '/workout-sessions') =>
        _authorized(options)
            ? _startSession(body.cast<String, Object?>())
            : _invalidToken(),
      (final method, final path) when path.startsWith('/workout-sessions/') =>
        _authorized(options)
            ? _sessionRoute(method, path, body.cast<String, Object?>())
            : _invalidToken(),
      ('GET', '/workout-templates') =>
        _authorized(options)
            ? FakeHttpAdapter.json(200, templates)
            : _invalidToken(),
      ('POST', '/workout-templates') =>
        _authorized(options)
            ? _createTemplate(body.cast<String, Object?>())
            : _invalidToken(),
      ('PUT', '/workout-templates/order') =>
        _authorized(options)
            ? _reorderTemplates(body.cast<String, Object?>())
            : _invalidToken(),
      (final method, final path) when path.startsWith('/workout-templates/') =>
        _authorized(options)
            ? _template(
                method,
                path.split('/').last,
                body.cast<String, Object?>(),
              )
            : _invalidToken(),
      ('GET', '/exercise-options') => FakeHttpAdapter.json(
        200,
        exerciseOptions,
      ),
      ('GET', '/exercises') =>
        _authorized(options)
            ? FakeHttpAdapter.json(200, _sortedExercises())
            : _invalidToken(),
      ('POST', '/exercises') =>
        _authorized(options)
            ? _createExercise(body.cast<String, Object?>())
            : _invalidToken(),
      ('PATCH', final path) when path.startsWith('/exercises/') =>
        _authorized(options)
            ? _updateExercise(
                path.split('/').last,
                body.cast<String, Object?>(),
              )
            : _invalidToken(),
      ('GET', '/activity-options') => FakeHttpAdapter.json(
        200,
        activityOptions,
      ),
      ('GET', '/activities') =>
        _authorized(options)
            ? FakeHttpAdapter.json(200, _sortedActivities(count: true))
            : _invalidToken(),
      ('POST', '/activities') =>
        _authorized(options)
            ? _createActivity(body.cast<String, Object?>())
            : _invalidToken(),
      (final method, final path) when path.startsWith('/activities/') =>
        _authorized(options)
            ? _activity(
                method,
                path.split('/').last,
                body.cast<String, Object?>(),
              )
            : _invalidToken(),
      ('GET', '/dashboard') =>
        _authorized(options) ? _dashboard() : _invalidToken(),
      ('GET', '/analytics/overview') =>
        _authorized(options)
            ? _analytics(
                options,
                overviewByFrom[options.queryParameters['from']] ??
                    analyticsOverview,
              )
            : _invalidToken(),
      ('GET', '/analytics/compare') =>
        _authorized(options) ? _compare(options) : _invalidToken(),
      ('GET', '/analytics/endurance') =>
        _authorized(options)
            ? _analytics(options, switch (options.queryParameters['modality']) {
                'run' || null => runEndurance,
                final m =>
                  enduranceByModality[m] ?? endurance(modality: m as String),
              })
            : _invalidToken(),
      ('GET', '/analytics/muscles') =>
        _authorized(options) ? _analytics(options, _body()) : _invalidToken(),
      ('GET', final p) when p.startsWith('/analytics/muscles/') =>
        _authorized(options)
            ? _analytics(options, _muscleDetail(p.split('/').last))
            : _invalidToken(),
      ('GET', '/training-plan-templates') =>
        _authorized(options)
            ? FakeHttpAdapter.json(200, planTemplates)
            : _invalidToken(),
      ('GET', '/training-plans') =>
        _authorized(options)
            ? FakeHttpAdapter.json(200, [
                for (final plan in plans.reversed)
                  {..._planOut(plan)}..remove('sessions'),
              ])
            : _invalidToken(),
      ('POST', '/training-plans') =>
        _authorized(options)
            ? _createPlan(body.cast<String, Object?>())
            : _invalidToken(),
      (final method, final path) when path.startsWith('/training-plans/') =>
        _authorized(options)
            ? _planRoute(method, path, body.cast<String, Object?>())
            : _invalidToken(),
      ('GET', '/goals') =>
        _authorized(options) ? _listGoals() : _invalidToken(),
      ('POST', '/goals') =>
        _authorized(options)
            ? _createGoal(body.cast<String, Object?>())
            : _invalidToken(),
      (final method, final path) when path.startsWith('/goals/') =>
        _authorized(options)
            ? _goal(method, path.split('/').last, body.cast<String, Object?>())
            : _invalidToken(),
      (final method, final path) when path.startsWith('/me/consents/') =>
        _authorized(options)
            ? _consent(method, path.split('/').last)
            : _invalidToken(),
      ('GET', '/health') => FakeHttpAdapter.json(200, {
        'status': 'ok',
        'database': 'ok',
        'version': '0.1.0',
        'environment': 'test',
      }),
      _ => _problem(404, 'not_found', 'Rota não encontrada no servidor falso.'),
    };
  }

  bool _authorized(RequestOptions options) =>
      options.headers['Authorization'] == 'Bearer $validAccessToken';

  ResponseBody _invalidToken() =>
      _problem(401, 'invalid_token', 'Sessão inválida ou expirada.');

  ResponseBody _register() {
    profile = newProfile();
    consents = {'terms_privacy'};
    return _issueTokens();
  }

  ResponseBody _me() => FakeHttpAdapter.json(200, {
    'id': '0192f0c0-0000-7000-8000-000000000001',
    'email': accountEmail,
    'status': 'active',
    'created_at': '2026-10-30T12:00:00Z',
    'profile': profile,
    'consents': [
      for (final kind in consents)
        {
          'kind': kind,
          'version': '2026-10',
          'granted_at': '2026-10-30T12:00:00Z',
        },
    ],
  });

  /// Mesma regra da API: dado de saúde novo só com o consentimento ativo.
  ResponseBody _patch(Map<String, Object?> body) {
    patches.add(body);
    final changes = {...body};
    final addsHealth =
        (changes['limitation_tags'] as List<dynamic>? ?? const []).isNotEmpty ||
        ((changes['limitations_note'] as String?) ?? '').isNotEmpty;
    if (addsHealth && !consents.contains('health_data')) {
      return _problem(403, 'consent_required', 'Autorize os dados de saúde.');
    }
    final completed = changes.remove('onboarding_completed') == true;
    profile = {...profile, ...changes};
    if (completed) {
      profile['onboarding_completed_at'] ??= '2026-10-31T12:00:00Z';
    }
    return _me();
  }

  ResponseBody _startSession(Map<String, Object?> body) {
    sessionCalls.add('POST start');
    if (session != null) {
      return _problem(
        409,
        'session_in_progress',
        'Você já tem um treino em andamento.',
        errors: [
          {'field': 'session_id', 'message': session!['id']! as String},
        ],
      );
    }
    final templateId = body['template_id'];
    final template = templateId == null
        ? null
        : templates.firstWhere((t) => t['id'] == templateId);
    session = sessionFrom(template);
    return FakeHttpAdapter.json(201, session!);
  }

  /// Mesmas regras da API: treino encerrado não muda; finalizar exige uma série.
  ResponseBody _sessionRoute(
    String method,
    String path,
    Map<String, Object?> body,
  ) {
    final parts = path.split('/'); // ['', 'workout-sessions', id, ...]
    // Treino concluído: só leitura, como no histórico.
    if (method == 'GET' && parts.length == 3) {
      for (final done in [...finishedSessions, ...pastSessions]) {
        if (done['id'] == parts[2]) return FakeHttpAdapter.json(200, done);
      }
    }
    final current = session;
    if (current == null || current['id'] != parts[2]) {
      return _problem(404, 'not_found', 'Treino não encontrado.');
    }
    final rest = parts.sublist(3).join('/');
    sessionCalls.add('$method ${rest.isEmpty ? 'get' : rest.split('/').first}');
    final entries = (current['exercises']! as List)
        .cast<Map<String, Object?>>();
    Map<String, Object?> entry(String id) =>
        entries.firstWhere((e) => e['id'] == id);

    switch ((method, parts.length)) {
      case ('GET', 3):
        return FakeHttpAdapter.json(200, current);
      case ('POST', 4) when parts[3] == 'pause':
        current['status'] = 'paused';
        return FakeHttpAdapter.json(200, current);
      case ('POST', 4) when parts[3] == 'resume':
        current['status'] = 'in_progress';
        return FakeHttpAdapter.json(200, current);
      case ('POST', 4) when parts[3] == 'finish':
        final sets = entries.expand((e) => e['sets']! as List).toList();
        if (sets.isEmpty) {
          return _problem(
            422,
            'session_empty',
            'Registre pelo menos uma série.',
          );
        }
        final finished = {
          ...current,
          'status': 'completed',
          'elapsed_s': 1800,
          'perceived_effort': body['perceived_effort'],
          'notes': body['notes'],
          'set_count': sets.where((s) => (s as Map)['kind'] != 'warmup').length,
          'records': finishRecords,
        };
        finishedSessions.add(finished);
        session = null;
        return FakeHttpAdapter.json(200, finished);
      case ('POST', 4) when parts[3] == 'discard':
        session = null;
        return ResponseBody.fromString('', 204);
      case ('POST', 4) when parts[3] == 'exercises':
        final exercise = exercises.firstWhere(
          (e) => e['id'] == body['exercise_id'],
        );
        entries.add(
          _sessionEntry(entries.length, {
            'exercise': {
              'id': exercise['id'],
              'name': exercise['name'],
              'equipment': exercise['equipment'],
              'load_type': exercise['load_type'],
              'is_active': true,
              'primary_muscles': <String>[],
            },
            'group': null,
            'planned_sets': null,
            'rest_s': 90,
          }),
        );
        return FakeHttpAdapter.json(201, current);
      case ('PATCH', 5):
        exerciseUpdates.add(body);
        final updated = entry(parts[4]);
        if (body.containsKey('rest_s')) updated['rest_s'] = body['rest_s'];
        if (body.containsKey('notes')) {
          final note = body['notes'] as String?;
          updated['notes'] = note == null || note.isEmpty ? null : note;
        }
        return FakeHttpAdapter.json(200, current);
      case ('DELETE', 5):
        entries.removeWhere((e) => e['id'] == parts[4]);
        return ResponseBody.fromString('', 204);
      case ('POST', 6):
        final sets = entry(parts[4])['sets']! as List;
        // Como a API: o mesmo client_id devolve a série já salva (envio idempotente)
        // e o pai pode vir pelo id do app (parent_client_id).
        final clientId = body['client_id'] as String?;
        final existing = sets.cast<Map<String, Object?>>().where(
          (s) => clientId != null && s['client_id'] == clientId,
        );
        if (existing.isNotEmpty) {
          resentSets++;
          return FakeHttpAdapter.json(201, existing.first);
        }
        final parentClientId = body['parent_client_id'] as String?;
        final parentId = parentClientId == null
            ? body['parent_set_id']
            : sets.cast<Map<String, Object?>>().firstWhere(
                (s) => s['client_id'] == parentClientId,
              )['id'];
        // Nos testes, o corpo fica como antes: sem o id do app e com o pai pelo
        // id do servidor.
        setBodies.add({
          for (final e in body.entries)
            if (e.key != 'client_id' && e.key != 'parent_client_id')
              e.key: e.value,
          'parent_set_id': ?parentId,
        });
        if (failNextSet) {
          failNextSet = false;
          return _problem(
            500,
            'internal_error',
            'O servidor encontrou um problema.',
          );
        }
        final logged = {
          'id': 'serie-${setBodies.length}',
          'client_id': clientId,
          'position': sets.length,
          'kind': body['kind'] ?? 'working',
          'parent_set_id': parentId,
          'reps': body['reps'],
          'load_kg': body['load_kg'],
          'duration_s': body['duration_s'],
          'rir': null,
          'rpe': null,
          'to_failure': body['to_failure'] ?? false,
          'completed_at': '2026-11-01T10:05:00Z',
        };
        sets.add(logged);
        if (loseNextSetResponse) {
          // Salvou, mas a resposta "se perdeu" no caminho (o app vê falta de rede).
          loseNextSetResponse = false;
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: path),
            reason: 'resposta perdida (teste)',
          );
        }
        return FakeHttpAdapter.json(201, logged);
      case ('PATCH', 7):
        setBodies.add(body);
        final sets = (entry(parts[4])['sets']! as List)
            .cast<Map<String, Object?>>();
        final index = sets.indexWhere((s) => s['id'] == parts[6]);
        sets[index] = {...sets[index], ...body};
        return FakeHttpAdapter.json(200, sets[index]);
      case ('DELETE', 7):
        // Como a API: a série leva os segmentos dela.
        (entry(parts[4])['sets']! as List).removeWhere(
          (s) => (s as Map)['id'] == parts[6] || s['parent_set_id'] == parts[6],
        );
        return ResponseBody.fromString('', 204);
    }
    return _problem(404, 'not_found', 'Rota não encontrada no servidor falso.');
  }

  ResponseBody _createTemplate(Map<String, Object?> body) {
    templateCalls.add('POST');
    templateBodies.add(body);
    final template = templateFrom(
      'ficha-${templateCalls.length}',
      templates.length + 1,
      body,
    );
    templates.add(template);
    return FakeHttpAdapter.json(201, template);
  }

  ResponseBody _template(String method, String id, Map<String, Object?> body) {
    final index = templates.indexWhere((t) => t['id'] == id);
    if (index < 0) return _problem(404, 'not_found', 'Ficha não encontrada.');
    templateCalls.add('$method $id');
    if (method == 'DELETE') {
      templates.removeAt(index);
      return ResponseBody.fromString('', 204);
    }
    if (method == 'PUT') {
      templateBodies.add(body);
      templates[index] = templateFrom(
        id,
        templates[index]['position']! as int,
        body,
      );
    }
    return FakeHttpAdapter.json(200, templates[index]);
  }

  ResponseBody _reorderTemplates(Map<String, Object?> body) {
    templateCalls.add('PUT order');
    final ids = (body['template_ids']! as List).cast<String>();
    templates = [
      for (final (i, id) in ids.indexed)
        {...templates.firstWhere((t) => t['id'] == id), 'position': i + 1},
    ];
    return FakeHttpAdapter.json(200, templates);
  }

  List<Map<String, Object?>> _sortedExercises() => [...exercises]
    ..sort((a, b) => (a['name']! as String).compareTo(b['name']! as String));

  Map<String, Object?> _exerciseFrom(String id, Map<String, Object?> body) => {
    'id': id,
    'name': body['name'],
    'instructions': (body['instructions'] as String?)?.isEmpty ?? true
        ? null
        : body['instructions'],
    'mechanics': body['mechanics'],
    'equipment': body['equipment'],
    'load_type': body['load_type'],
    'unilateral': body['unilateral'] ?? false,
    'is_custom': true,
    'is_active': body['is_active'] ?? true,
    'muscles': [
      for (final m in body['muscles']! as List)
        {
          'id': (m as Map)['muscle_group_id'],
          'name': _muscleNames[m['muscle_group_id']],
          'role': m['role'],
        },
    ],
  };

  /// Mesma regra da API: o nome é único entre os exercícios do próprio usuário.
  ResponseBody _createExercise(Map<String, Object?> body) {
    exerciseCalls.add('POST');
    exerciseBodies.add(body);
    final name = (body['name']! as String).toLowerCase();
    final duplicate = exercises.any(
      (e) =>
          e['is_custom'] == true &&
          (e['name']! as String).toLowerCase() == name,
    );
    if (duplicate) {
      return _problem(
        409,
        'exercise_exists',
        'Você já tem um exercício com esse nome.',
        errors: [
          {
            'field': 'name',
            'message': 'Você já tem um exercício com esse nome.',
          },
        ],
      );
    }
    final exercise = _exerciseFrom('ex-proprio-${exerciseCalls.length}', body);
    exercises.add(exercise);
    return FakeHttpAdapter.json(201, exercise);
  }

  ResponseBody _updateExercise(String id, Map<String, Object?> body) {
    final index = exercises.indexWhere((e) => e['id'] == id);
    if (index < 0) {
      return _problem(404, 'not_found', 'Exercício não encontrado.');
    }
    if (exercises[index]['is_custom'] != true) {
      return _problem(403, 'exercise_read_only', 'Exercício do catálogo.');
    }
    exerciseCalls.add('PATCH $id');
    exerciseBodies.add(body);
    final current = exercises[index];
    final updated = body.containsKey('muscles')
        ? _exerciseFrom(id, {...current, ...body})
        : {...current, ...body};
    exercises[index] = updated;
    return FakeHttpAdapter.json(200, updated);
  }

  List<Map<String, Object?>> _sortedActivities({bool count = false}) {
    if (count) activityListCalls++;
    return _sortActivities();
  }

  List<Map<String, Object?>> _sortActivities() => [...activities]
    ..sort(
      (a, b) =>
          (b['started_at']! as String).compareTo(a['started_at']! as String),
    );

  ResponseBody? _rejectActivity() {
    final field = rejectActivityField;
    if (field == null) return null;
    rejectActivityField = null;
    return _problem(
      422,
      'validation_error',
      'Verifique os campos informados.',
      errors: [
        {'field': field, 'message': 'Recusado pelo servidor.'},
      ],
    );
  }

  /// Como a API: natação na piscina sem distância = voltas × tamanho; pace e
  /// velocidade calculados com distância e duração.
  static Map<String, Object?> _derived(Map<String, Object?> a) {
    final pool = a['pool_length_m'] as int?;
    final laps = a['laps'] as int?;
    final withDistance = a['distance_m'] == null && pool != null && laps != null
        ? {...a, 'distance_m': pool * laps}
        : a;
    final distance = withDistance['distance_m'] as int?;
    final duration = withDistance['duration_s']! as int;
    final swim = withDistance['modality'] == 'swim';
    return {
      ...withDistance,
      'pace_s_per_km': distance == null || swim
          ? null
          : (duration / distance * 1000).round(),
      'speed_kmh': distance == null || swim
          ? null
          : double.parse((distance / duration * 3.6).toStringAsFixed(1)),
      'pace_s_per_100m': distance == null || !swim
          ? null
          : (duration / distance * 100).round(),
    };
  }

  /// FC é dado de saúde: sem o consentimento, a API recusa (403).
  ResponseBody? _heartRateWithoutConsent(Map<String, Object?> body) =>
      (body['avg_hr'] != null || body['max_hr'] != null) &&
          !consents.contains('health_data')
      ? _problem(403, 'consent_required', 'Autorize os dados de saúde.')
      : null;

  ResponseBody _createActivity(Map<String, Object?> body) {
    activityCalls.add('POST');
    activityBodies.add(body);
    if (_rejectActivity() case final rejected?) return rejected;
    if (_heartRateWithoutConsent(body) case final refused?) return refused;
    final activity = _derived({
      'id': 'atividade-${activityCalls.length}',
      'ended_at': body['started_at'],
      'distance_m': null,
      'perceived_effort': null,
      'notes': null,
      'elevation_gain_m': null,
      'avg_hr': null,
      'max_hr': null,
      'indoor': body['modality'] == 'cycle' ? false : null,
      'pool_length_m': null,
      'laps': null,
      'stroke': null,
      ...body,
    });
    activities.add(activity);
    return FakeHttpAdapter.json(201, activity);
  }

  ResponseBody _activity(String method, String id, Map<String, Object?> body) {
    final index = activities.indexWhere((a) => a['id'] == id);
    if (index < 0) {
      return _problem(404, 'not_found', 'Atividade não encontrada.');
    }
    activityCalls.add('$method $id');
    switch (method) {
      case 'DELETE':
        activities.removeAt(index);
        return ResponseBody.fromString('', 204);
      case 'PATCH':
        activityBodies.add(body);
        if (_rejectActivity() case final rejected?) return rejected;
        if (_heartRateWithoutConsent(body) case final refused?) return refused;
        activities[index] = _derived({...activities[index], ...body});
        return FakeHttpAdapter.json(200, activities[index]);
      default:
        return FakeHttpAdapter.json(200, activities[index]);
    }
  }

  ResponseBody _listGoals() {
    goalListCalls++;
    int rank(Map<String, Object?> g) => g['status'] == 'active' ? 0 : 1;
    final sorted = [...goals]..sort((a, b) => rank(a).compareTo(rank(b)));
    return FakeHttpAdapter.json(200, sorted);
  }

  static String _summary(String kind, Map<String, Object?> target) =>
      switch (kind) {
        'strength' =>
          '${target['exercise']}: ${target['load_kg']} kg × ${target['reps']}',
        'weight_loss' => '${target['target_weight_kg']} kg',
        'frequency' => '${target['sessions_per_week']}x por semana',
        _ => '',
      };

  /// Mesmas regras da API que o app precisa respeitar: peso exige health_data.
  ResponseBody _createGoal(Map<String, Object?> body) {
    goalCalls.add('POST');
    goalBodies.add(body);
    if (goalLimitReached) {
      return _problem(409, 'goal_limit', 'Você já tem 30 metas ativas.');
    }
    if (body['kind'] == 'weight_loss' && !consents.contains('health_data')) {
      return _problem(403, 'consent_required', 'Autorize os dados de saúde.');
    }
    final target = Map<String, Object?>.from(body['target']! as Map);
    final goal = <String, Object?>{
      'id': 'meta-nova-${goalCalls.length}',
      'kind': body['kind'],
      'title': body['title'],
      'target': target,
      'summary': _summary(body['kind']! as String, target),
      'start_date': '2026-10-31',
      'target_date': body['target_date'],
      'status': 'active',
      'priority': body['priority'] ?? 2,
      'closed_at': null,
    };
    goals.add(goal);
    return FakeHttpAdapter.json(201, goal);
  }

  ResponseBody _goal(String method, String id, Map<String, Object?> body) {
    final index = goals.indexWhere((g) => g['id'] == id);
    if (index < 0) return _problem(404, 'not_found', 'Meta não encontrada.');
    goalCalls.add('$method $id');
    switch (method) {
      case 'DELETE':
        goals.removeAt(index);
        return ResponseBody.fromString('', 204);
      case 'PATCH':
        goalBodies.add(body);
        final goal = {...goals[index], ...body};
        if (body.containsKey('target')) {
          goal['summary'] = _summary(
            goal['kind']! as String,
            Map<String, Object?>.from(body['target']! as Map),
          );
        }
        goals[index] = goal;
        return FakeHttpAdapter.json(200, goal);
      default:
        return FakeHttpAdapter.json(200, goals[index]);
    }
  }

  ResponseBody _consent(String method, String kind) {
    consentCalls.add('$method $kind');
    if (method == 'PUT') {
      consents.add(kind);
      return FakeHttpAdapter.json(200, {
        'kind': kind,
        'version': '2026-10',
        'granted_at': '2026-10-31T12:00:00Z',
      });
    }
    consents.remove(kind);
    if (kind == 'health_data') {
      goals.removeWhere((g) => g['kind'] == 'weight_loss');
      for (final plan in plans) {
        plan['adaptations'] = <String>[];
      }
      profile = {
        ...profile,
        'limitation_tags': <String>[],
        'limitations_note': null,
      };
    }
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _refresh(Object? token) {
    refreshCalls++;
    if (token == null || token != validRefreshToken) {
      return _problem(401, 'invalid_refresh_token', 'Sessão expirada.');
    }
    return _issueTokens();
  }

  ResponseBody _logout() {
    logoutCalls++;
    validRefreshToken = null;
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _issueTokens() {
    _counter++;
    validAccessToken = 'access-$_counter';
    validRefreshToken = 'refresh-$_counter';
    return FakeHttpAdapter.json(200, {
      'access_token': validAccessToken,
      'refresh_token': validRefreshToken,
      'token_type': 'bearer',
      'expires_in': 900,
      'refresh_expires_in': 2592000,
    });
  }

  static ResponseBody _problem(
    int status,
    String code,
    String detail, {
    List<Map<String, String>> errors = const [],
  }) => FakeHttpAdapter.json(status, {
    'type': 'https://evofit.local/errors/$code',
    'title': 'Erro',
    'status': status,
    'code': code,
    'detail': detail,
    'errors': errors,
    'request_id': 'teste',
  });

  // --- planos ---

  /// Como a API: contagens, próxima sessão e sessões ligadas a atividades que
  /// ainda existem.
  Map<String, Object?> _planOut(Map<String, Object?> plan) {
    final ids = {for (final a in activities) a['id']};
    final sessions = [
      for (final s in plan['sessions']! as List<Map<String, Object?>>)
        {
          ...s,
          if (!ids.contains(s['completed_activity_id']))
            'completed_activity_id': null,
        },
    ];
    final next = sessions
        .where((s) => s['completed_activity_id'] == null)
        .firstOrNull;
    return {
      ...plan,
      'sessions': sessions,
      'completed_sessions': sessions
          .where((s) => s['completed_activity_id'] != null)
          .length,
      'next_session_id': plan['status'] == 'active' ? (next?['id']) : null,
      'current_week': next?['week'] ?? plan['weeks'],
    };
  }

  ResponseBody _createPlan(Map<String, Object?> body) {
    planCalls.add('POST');
    planBodies.add(body);
    final active = plans.where((p) => p['status'] == 'active').firstOrNull;
    if (active != null) {
      return _problem(409, 'plan_in_progress', 'Você já tem um plano.');
    }
    final template = planTemplates.firstWhere((t) => t['kind'] == body['kind']);
    final weeks = template['weeks']! as int;
    final start = DateTime.parse(body['start_date']! as String);
    final id = 'plano-${plans.length + 1}';
    final runs = template['modality'] == 'run';
    plans.add({
      'id': id,
      'kind': body['kind'],
      'title': template['title'],
      'modality': template['modality'],
      'template_version': 1,
      'status': 'active',
      'start_date': body['start_date'],
      'weekdays': body['weekdays'],
      'weeks': weeks,
      'total_sessions': weeks * 3,
      'adaptations': template['adaptations'],
      'created_at': '2026-11-04T10:00:00Z',
      'ended_at': null,
      'sessions': <Map<String, Object?>>[
        for (var i = 0; i < weeks * 3; i++)
          {
            'id': '$id-sessao-${i + 1}',
            'position': i + 1,
            'week': i ~/ 3 + 1,
            'day_index': i % 3 + 1,
            'scheduled_date': start
                .add(Duration(days: i * 2))
                .toIso8601String()
                .substring(0, 10),
            'blocks': const <Object?>[],
            'total_s': 1800 + (i ~/ 3) * 60,
            'summary': runs
                ? 'Semana ${i ~/ 3 + 1}: 5 min caminhando · 8x (1 min '
                      'correndo + 1:30 caminhando) · 5 min caminhando'
                : 'Semana ${i ~/ 3 + 1}: 20 min caminhando em ritmo firme',
            'completed_activity_id': null,
            'completed_at': null,
          },
      ],
    });
    return FakeHttpAdapter.json(201, _planOut(plans.last));
  }

  ResponseBody _planRoute(
    String method,
    String path,
    Map<String, Object?> body,
  ) {
    final parts = path.split('/'); // '', training-plans, id, ...
    final index = plans.indexWhere((p) => p['id'] == parts[2]);
    if (index < 0) return _problem(404, 'not_found', 'Plano não encontrado.');
    final plan = plans[index];
    planCalls.add('$method ${parts.skip(2).join('/')}');
    if (parts.length == 3 && method == 'GET') {
      return FakeHttpAdapter.json(200, _planOut(plan));
    }
    if (plan['status'] != 'active') {
      return _problem(409, 'plan_closed', 'Este plano já foi encerrado.');
    }
    if (parts.length == 4 && parts[3] == 'end' && method == 'POST') {
      plan['status'] = 'ended';
      plan['ended_at'] = '2026-11-04T12:00:00Z';
      return FakeHttpAdapter.json(200, _planOut(plan));
    }
    if (parts.length == 6 && parts[3] == 'sessions') {
      final sessions = plan['sessions']! as List<Map<String, Object?>>;
      final session = sessions.where((s) => s['id'] == parts[4]).firstOrNull;
      if (session == null) {
        return _problem(404, 'not_found', 'Sessão não encontrada.');
      }
      if (method == 'DELETE') {
        session['completed_activity_id'] = null;
        session['completed_at'] = null;
        return FakeHttpAdapter.json(200, _planOut(plan));
      }
      planBodies.add(body);
      if (rejectPlanLink case final message?) {
        rejectPlanLink = null;
        return _problem(
          422,
          'validation_error',
          'Verifique os campos informados.',
          errors: [
            {'field': 'activity_id', 'message': message},
          ],
        );
      }
      session['completed_activity_id'] = body['activity_id'];
      session['completed_at'] = '2026-11-04T12:00:00Z';
      if (_planOut(plan)['completed_sessions'] == sessions.length) {
        plan['status'] = 'completed';
      }
      return FakeHttpAdapter.json(200, _planOut(plan));
    }
    return _problem(404, 'not_found', 'Rota não encontrada no servidor falso.');
  }

  ResponseBody _dashboard() {
    dashboardCalls++;
    if (failDashboard) {
      failDashboard = false;
      return _problem(500, 'internal_error', 'Falha simulada.');
    }
    return FakeHttpAdapter.json(200, dashboard);
  }

  /// Comparação de um indicador: `metric` ou `metric:modality` em [comparisons].
  ResponseBody _compare(RequestOptions options) {
    final metric = options.queryParameters['metric'] as String;
    final modality = options.queryParameters['modality'] as String?;
    final key = modality == null ? metric : '$metric:$modality';
    return _analytics(
      options,
      comparisons[key] ??
          comparison(null, null, metric: metric, modality: modality),
    );
  }

  ResponseBody _analytics(RequestOptions options, Map<String, Object?> body) {
    final query = options.queryParameters.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    analyticsQueries.add('${options.path.split('/').last}?$query');
    return FakeHttpAdapter.json(200, body);
  }
}
