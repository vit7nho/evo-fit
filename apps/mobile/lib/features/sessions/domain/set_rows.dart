import 'package:flutter/foundation.dart';

import '../../training/domain/template.dart';
import 'session.dart';

/// Tipo de uma linha da tabela de séries, como o usuário escolhe no número.
///
/// "Até a falha" é um tipo para quem treina, mas na API é uma série válida com
/// `to_failure`. Drop e rest-pause viram segmentos da série principal logo acima.
enum RowKind {
  warmup('A', 'Aquecimento', 'Não conta como série válida.'),
  working('', 'Válida', 'Série normal, conta no volume.'),
  failure('F', 'Até a falha', 'Série válida levada até não conseguir mais.'),
  drop(
    'D',
    'Drop set',
    'Continua a série acima, com menos carga e sem descanso.',
  ),
  restPause(
    'RP',
    'Rest-pause',
    'Continua a série acima depois de uma pausa curta, com a mesma carga.',
  );

  const RowKind(this.letter, this.label, this.description);

  final String letter;
  final String label;
  final String description;

  bool get isSegment => this == drop || this == restPause;

  /// Conta como série principal válida (numerada).
  bool get isMainWorking => this == working || this == failure;

  /// Corpo da API para este tipo.
  Map<String, Object?> get apiFields => switch (this) {
    warmup => {'kind': SetKind.warmup},
    working => {'kind': SetKind.working},
    failure => {'kind': SetKind.working, 'to_failure': true},
    drop => {'kind': SetKind.drop},
    restPause => {'kind': SetKind.restPause},
  };

  static RowKind fromSet(String kind, {bool toFailure = false}) =>
      switch (kind) {
        SetKind.warmup => warmup,
        SetKind.drop => drop,
        SetKind.restPause => restPause,
        _ => toFailure ? failure : working,
      };
}

/// Uma linha da tabela: feita ([loggedId] preenchido) ou por fazer, com o que
/// foi digitado. As linhas guardam a ordem da tela, então dá para concluir fora
/// de ordem sem a lista pular.
@immutable
class SetRowDraft {
  const SetRowDraft({
    required this.id,
    required this.kind,
    this.loggedId,
    this.plan,
  });

  /// Identidade local e estável (chave do widget).
  final int id;
  final RowKind kind;
  final String? loggedId;

  /// Série planejada que originou a linha (para a sugestão).
  final PlannedSet? plan;

  bool get isDone => loggedId != null;

  SetRowDraft copyWith({
    RowKind? kind,
    String? loggedId,
    bool clearLogged = false,
  }) => SetRowDraft(
    id: id,
    kind: kind ?? this.kind,
    loggedId: clearLogged ? null : (loggedId ?? this.loggedId),
    plan: plan,
  );
}

/// Valores sugeridos para uma linha por fazer.
typedef RowSuggestion = ({int? reps, double? loadKg, int? durationS});

/// Monta as linhas de um exercício: as séries feitas (cada principal seguida dos
/// segmentos dela) e o que falta do plano. Série planejada como drop ou
/// rest-pause vira uma linha válida seguida da linha do segmento. Sem plano,
/// sobra uma linha em branco.
List<SetRowDraft> buildRows(SessionExercise entry, int Function() nextId) {
  final rows = <SetRowDraft>[];
  for (final main in entry.mainSets) {
    rows.add(
      SetRowDraft(
        id: nextId(),
        kind: RowKind.fromSet(main.kind, toFailure: main.toFailure),
        loggedId: main.id,
      ),
    );
    for (final segment in entry.segmentsOf(main.id)) {
      rows.add(
        SetRowDraft(
          id: nextId(),
          kind: RowKind.fromSet(segment.kind),
          loggedId: segment.id,
        ),
      );
    }
  }
  final plan = entry.plannedSets ?? const <PlannedSet>[];
  for (final planned in plan.skip(entry.mainSets.length)) {
    switch (planned.kind) {
      case SetKind.drop || SetKind.restPause:
        rows
          ..add(SetRowDraft(id: nextId(), kind: RowKind.working, plan: planned))
          ..add(
            SetRowDraft(
              id: nextId(),
              kind: RowKind.fromSet(planned.kind),
              plan: planned,
            ),
          );
      case _:
        rows.add(
          SetRowDraft(
            id: nextId(),
            kind: RowKind.fromSet(planned.kind),
            plan: planned,
          ),
        );
    }
  }
  if (rows.every((r) => r.isDone)) {
    rows.add(SetRowDraft(id: nextId(), kind: RowKind.working));
  }
  return rows;
}

/// Acerta as linhas com as séries do servidor: linha cuja série sumiu volta a
/// ficar por fazer; série que não está em nenhuma linha entra no fim — menos as
/// de [registering], que uma linha está concluindo e vai receber em seguida.
List<SetRowDraft> reconcileRows(
  List<SetRowDraft> rows,
  SessionExercise entry,
  int Function() nextId, {
  Set<String> registering = const {},
}) {
  final ids = {for (final s in entry.sets) s.id};
  final result = [
    for (final row in rows)
      if (row.loggedId != null && !ids.contains(row.loggedId))
        row.copyWith(clearLogged: true)
      else
        row,
  ];
  final known = {for (final r in result) ?r.loggedId};
  for (final set in entry.sets) {
    if (!known.contains(set.id) && !registering.contains(set.id)) {
      result.add(
        SetRowDraft(
          id: nextId(),
          kind: RowKind.fromSet(set.kind, toFailure: set.toFailure),
          loggedId: set.id,
        ),
      );
    }
  }
  return result;
}

/// Linha principal (não segmento) mais próxima acima de [index]: a série que um
/// drop ou rest-pause continua.
int? parentRowOf(List<SetRowDraft> rows, int index) {
  for (var i = index - 1; i >= 0; i--) {
    if (!rows[i].kind.isSegment) return i;
  }
  return null;
}

/// O que aparece no número da linha: "A", "F", "D", "RP" ou o número da série
/// válida (aquecimentos e segmentos não contam).
String rowBadge(List<SetRowDraft> rows, int index) {
  final kind = rows[index].kind;
  if (kind != RowKind.working) return kind.letter;
  return '${rows.take(index + 1).where((r) => r.kind.isMainWorking).length}';
}

/// Séries da última vez na ordem da tabela (cada principal e seus segmentos).
List<PreviousSet> flatPrevious(SessionExercise entry) => [
  for (final p in entry.previous) ...[p, ...p.segments],
];

/// A série da última vez na mesma linha, se houver.
PreviousSet? previousAt(SessionExercise entry, int index) {
  final flat = flatPrevious(entry);
  return index < flat.length ? flat[index] : null;
}

/// Sugestão para a linha [index]: a da última vez na mesma linha; senão o plano;
/// senão a linha de cima (o drop tira 20% da carga, múltiplo de 2,5 kg; o
/// rest-pause repete a carga e não inventa repetições).
RowSuggestion suggestRow(
  SessionExercise entry,
  List<SetRowDraft> rows,
  int index, {
  required RowSuggestion Function(int index) valuesOf,
}) {
  final row = rows[index];
  final last = previousAt(entry, index);
  final plan = row.plan;
  final above = index > 0 ? valuesOf(index - 1) : null;
  if (row.kind.isSegment) {
    final aboveLoad = above?.loadKg;
    double? load = aboveLoad;
    if (row.kind == RowKind.drop && aboveLoad != null) {
      final dropped = (aboveLoad * 0.8 / 2.5).round() * 2.5;
      load = dropped < aboveLoad ? dropped : aboveLoad - 2.5;
      if (load <= 0) load = null;
    }
    final sameKind = last != null && RowKind.fromSet(last.kind) == row.kind;
    return (
      reps: sameKind ? last.reps : null,
      loadKg: sameKind ? last.loadKg ?? load : load,
      durationS: null,
    );
  }
  return (
    reps: last?.reps ?? plan?.repsMin ?? above?.reps,
    loadKg: last?.loadKg ?? plan?.loadKg ?? above?.loadKg,
    durationS: last?.durationS ?? plan?.durationS ?? above?.durationS,
  );
}

/// Tipo sugerido para uma linha nova no fim: válida (aquecimento só por escolha).
RowKind kindForNewRow(SessionExercise entry, List<SetRowDraft> rows) {
  final last = previousAt(entry, rows.length);
  if (last == null) return RowKind.working;
  final kind = RowKind.fromSet(last.kind, toFailure: last.toFailure);
  return kind.isSegment && rows.isEmpty ? RowKind.working : kind;
}
