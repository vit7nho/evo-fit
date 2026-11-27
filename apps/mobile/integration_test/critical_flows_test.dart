// Fluxos críticos de ponta a ponta (Fase 6.2, ADR-066): o app de verdade, no emulador,
// falando com a API de verdade. Uma conta nova por execução, apagada no fim pelo
// próprio app (e, se o teste cair no meio, pela limpeza no tearDown).
//
// Requisitos: a API rodando com AI_PROVIDER=demo e o emulador ligado. Rodar com
//   flutter test integration_test -d emulator-5554
// e, para conferir também a conta de demonstração (6.1):
//   flutter test integration_test -d emulator-5554 --dart-define=DEMO_PASSWORD="..."
//
// O treino tem um cronômetro na tela: nada aqui usa pumpAndSettle, só esperas com limite.

import 'package:dio/dio.dart';
import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _password = 'cavalo bateria grampo';
const _demoPassword = String.fromEnvironment('DEMO_PASSWORD');
final _api = '${AppConfig.fromEnvironment().apiBaseUrl}/api/v1';

/// Espera o [finder] aparecer, bombeando quadros; falha com o nome do que faltou.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Não apareceu em ${timeout.inSeconds} s: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await settle(tester, 300);
  await tester.tap(finder.first);
  await settle(tester);
}

Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  await waitFor(tester, field);
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await settle(tester, 300);
}

/// Rola a primeira lista da tela até o [finder] ficar à vista (listas montam aos
/// poucos): primeiro para baixo, depois para cima (ao voltar, a lista pode estar no meio).
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  for (final dy in [-300.0, 300.0]) {
    for (var i = 0; i < 20 && finder.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(Scrollable).first,
        Offset(0, dy),
        warnIfMissed: false,
      );
      await settle(tester, 300);
    }
  }
  await waitFor(tester, finder);
}

Future<void> back(WidgetTester tester) =>
    tapOn(tester, find.byTooltip('Voltar'));

Finder field(String label) => find.widgetWithText(TextField, label);

Future<void> startApp(WidgetTester tester) async {
  await const FlutterSecureStorage()
      .deleteAll(); // sem sessão nem rascunho de antes
  await tester.pumpWidget(
    const ProviderScope(retry: noAutomaticRetry, child: EvoFitApp()),
  );
  await settle(tester, 1500);
}

/// Limpeza de segurança: apaga a conta pela API se o teste parou antes de excluí-la.
Future<void> deleteIfLeft(String email) async {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  final login = await dio.post<Map<String, dynamic>>(
    '$_api/auth/login',
    data: {'email': email, 'password': _password},
  );
  if (login.statusCode != 200) return; // já excluída
  await dio.delete<void>(
    '$_api/me',
    data: {'password': _password},
    options: Options(
      headers: {'Authorization': 'Bearer ${login.data!['access_token']}'},
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'cadastro → ficha com bi-set → treino com drop set → caminhada → peso → '
    'assistente → exclusão da conta',
    (tester) async {
      final email = 'e2e.${DateTime.now().millisecondsSinceEpoch}@evofit.local';
      addTearDown(() => deleteIfLeft(email));
      await startApp(tester);

      // 1. Cadastro e objetivo.
      await tapOn(tester, find.text('Criar conta'));
      await typeInto(tester, field('Seu nome ou apelido'), 'E2E');
      await typeInto(tester, field('E-mail'), email);
      await typeInto(tester, field('Senha'), _password);
      await tapOn(tester, find.byType(Checkbox));
      await tapOn(tester, find.text('Criar conta'));
      await tapOn(tester, find.text('Ganhar massa muscular'));
      await tapOn(tester, find.text('Continuar'));
      // Perfil completo (com "Pular", o Início pede para completar o perfil).
      await tapOn(tester, find.text('Musculação'));
      await tapOn(tester, find.text('Intermediário'));
      await tapOn(tester, find.text('Continuar'));
      await tapOn(tester, find.bySemanticsLabel('4 dias por semana'));
      await tapOn(tester, find.text('60 min'));
      await tapOn(tester, find.text('Academia completa'));
      await tapOn(tester, find.text('Continuar'));
      await tapOn(tester, find.text('Concluir'));
      await waitFor(tester, find.text('Seu foco: Ganhar massa muscular.'));

      // 2. Ficha com um bi-set.
      await scrollTo(tester, find.text('Fichas de treino'));
      await tapOn(tester, find.text('Fichas de treino'));
      await tapOn(tester, find.text('Criar ficha'));
      await typeInto(tester, field('Nome da ficha'), 'Treino E2E');
      await tapOn(tester, find.text('Adicionar exercícios'));
      for (final name in [
        'Supino inclinado com halteres',
        'Crucifixo com halteres',
      ]) {
        await typeInto(tester, find.byType(TextField), name);
        // O item da lista, não o campo de busca com o mesmo texto.
        await tapOn(
          tester,
          find.descendant(of: find.byType(ListView), matching: find.text(name)),
        );
      }
      await tapOn(tester, find.text('Adicionar (2)'));
      await tapOn(
        tester,
        find.byTooltip('Ações de Supino inclinado com halteres'),
      );
      await tapOn(tester, find.text('Juntar com o próximo'));
      await waitFor(tester, find.text('Bi-set'));
      await tapOn(tester, find.text('Criar ficha'));

      // 3. Treino: duas séries e um drop set.
      await tapOn(tester, find.byTooltip('Iniciar Treino E2E'));
      await waitFor(
        tester,
        find.text('Bi-set · sem descanso entre os exercícios'),
      );
      const supino = 'Supino inclinado com halteres';
      await typeInto(tester, find.byType(TextField).at(0), '20');
      await tapOn(tester, find.byTooltip('Concluir série 1 de $supino'));
      await waitFor(tester, find.byTooltip('Desfazer série 1 de $supino'));
      await tapOn(tester, find.byTooltip('Concluir série 2 de $supino'));
      await waitFor(tester, find.byTooltip('Desfazer série 2 de $supino'));
      await tapOn(tester, find.text('3'));
      await tapOn(tester, find.text('Drop set'));
      // Só a carga: as repetições do drop vêm sugeridas da série de cima (6.4).
      await typeInto(tester, find.byType(TextField).at(4), '14');
      await tapOn(
        tester,
        find.byTooltip('Concluir drop set da série 2 de $supino'),
      );
      await waitFor(
        tester,
        find.byTooltip('Desfazer drop set da série 2 de $supino'),
      );
      // O contador mostra o drop ao lado das séries válidas (6.4).
      expect(find.bySemanticsLabel('Séries: 2 + 1 drop'), findsOneWidget);
      await tapOn(tester, find.text('Finalizar treino'));
      await tapOn(tester, find.text('Salvar treino'));
      // No resumo, cada série é lida pelo leitor de tela como "Série 1: 20 kg × 8".
      await waitFor(tester, find.bySemanticsLabel('Drop set: 14 kg × 8'));
      expect(find.bySemanticsLabel('Série 1: 20 kg × 8'), findsOneWidget);
      await back(tester);

      // 4. Caminhada.
      await scrollTo(tester, find.text('Atividades'));
      await tapOn(tester, find.text('Atividades'));
      await tapOn(tester, find.text('Registrar atividade'));
      await tapOn(tester, find.text('Caminhada'));
      await typeInto(tester, field('Duração'), '30');
      await typeInto(tester, field('Distância (opcional)'), '2.5');
      await tapOn(tester, find.text('Registrar'));
      await waitFor(tester, find.textContaining('30:00 · 2,5 km'));
      await back(tester);

      // 5. Peso, passando pela autorização de dados de saúde.
      await scrollTo(tester, find.text('Peso e medidas'));
      await tapOn(tester, find.text('Peso e medidas'));
      await tapOn(tester, find.text('Autorizar e continuar'));
      await tapOn(tester, find.text('Registrar medida'));
      await typeInto(tester, field('Peso'), '72.4');
      await tapOn(tester, find.text('Salvar medida'));
      await waitFor(tester, find.textContaining('72,4 kg'));
      await back(tester);

      // 6. Assistente (modo demonstração na API), passando pela autorização de IA.
      await scrollTo(tester, find.text('Assistente'));
      await tapOn(tester, find.text('Assistente'));
      await tapOn(tester, find.text('Nova conversa'));
      await tapOn(tester, find.text('Autorizar e continuar'));
      await tapOn(tester, find.text('O que fiz na minha última sessão?'));
      await waitFor(
        tester,
        find.textContaining('Sua última sessão foi Treino E2E'),
        timeout: const Duration(seconds: 40),
      );
      await back(tester);
      await back(tester);

      // 7. Exclusão da conta pelo Perfil; volta ao login e a conta some da API.
      await tapOn(tester, find.byTooltip('Perfil'));
      await scrollTo(tester, find.text('Excluir minha conta'));
      await tapOn(tester, find.text('Excluir minha conta'));
      await typeInto(tester, find.byType(TextField), _password);
      await tapOn(tester, find.byType(Checkbox));
      await tapOn(tester, find.text('Excluir conta definitivamente'));
      await waitFor(tester, find.text('Entrar'));
      final login = await Dio(BaseOptions(validateStatus: (_) => true))
          .post<void>(
            '$_api/auth/login',
            data: {'email': email, 'password': _password},
          );
      expect(login.statusCode, 401);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'conta de demonstração: Início, plano e Meu Corpo com os dados do seed',
    (tester) async {
      await startApp(tester);
      await typeInto(tester, field('E-mail'), 'demo@evofit.local');
      await typeInto(tester, field('Senha'), _demoPassword);
      await tapOn(tester, find.text('Entrar'));
      await waitFor(tester, find.text('Olá, Demo!'));
      await waitFor(tester, find.text('Seu foco: Ganhar massa muscular.'));
      await scrollTo(tester, find.textContaining('Rumo aos 10 km'));
      await scrollTo(tester, find.textContaining('Supino reto com 80 kg'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await settle(tester);
      await tapOn(tester, find.textContaining('Meu Corpo · 30 dias'));
      await waitFor(tester, find.textContaining('Panturrilhas'));
      await back(tester);
      await const FlutterSecureStorage()
          .deleteAll(); // não deixa a sessão no aparelho
    },
    skip: _demoPassword.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
