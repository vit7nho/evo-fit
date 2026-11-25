import 'package:evofit/features/coach/domain/coach.dart';
import 'package:flutter_test/flutter_test.dart';

String plain(List<AnswerRun> runs) => runs.map((r) => r.text).join();
List<String> bold(List<AnswerRun> runs) => [
  for (final r in runs)
    if (r.bold) r.text,
];

void main() {
  test('negrito e itens de lista, como o Gemini responde', () {
    final runs = answerRuns(
      'Sua última sessão foi um **Treino livre**.\n\n'
      'Nesse treino, você realizou:\n'
      '*   **Supino fechado**: 2 séries de 10\n'
      '- Remada: 3 séries',
    );
    expect(
      plain(runs),
      'Sua última sessão foi um Treino livre.\n\n'
      'Nesse treino, você realizou:\n'
      '• Supino fechado: 2 séries de 10\n'
      '• Remada: 3 séries',
    );
    expect(bold(runs), ['Treino livre', 'Supino fechado']);
  });

  test('título vira linha em negrito; texto sem Markdown fica igual', () {
    final runs = answerRuns('## Resumo\nVocê treinou 3 vezes.');
    expect(plain(runs), 'Resumo\nVocê treinou 3 vezes.');
    expect(bold(runs), ['Resumo\n']);
    expect(plain(answerRuns('5 * 3 = 15 e 2*2')), '5 * 3 = 15 e 2*2');
    expect(answerRuns(''), isEmpty);
  });
}
