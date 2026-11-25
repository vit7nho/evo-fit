import 'package:evofit/features/coach/domain/coach.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sem IA real, o texto genérico', () {
    for (final info in [
      null,
      const AiProviderInfo(label: 'Respostas simuladas (sem IA real)'),
    ]) {
      final text = aiConsentText(info);
      expect(text, contains('ao provedor de IA do servidor'));
      expect(text, isNot(contains('plano gratuito')));
    }
  });

  test('Gemini gratuito: nomeia a empresa, o exterior e o uso do conteúdo', () {
    final text = aiConsentText(
      AiProviderInfo.fromJson({
        'provider': 'gemini',
        'label': 'Google Gemini',
        'companies': ['Google'],
        'content_used_by': ['Google'],
        'free_tier': true,
        'international_transfer': true,
      }),
    );
    expect(text, contains('à empresa Google (Google Gemini)'));
    expect(text, contains('fora do Brasil'));
    expect(text, contains('a Google pode usar o conteúdo'));
    expect(text, contains('limitações nunca é enviado'));
  });

  test('Groq e Gemini: as duas empresas e o aviso só para a Google', () {
    final text = aiConsentText(
      AiProviderInfo.fromJson({
        'provider': 'groq,gemini',
        'label': 'Groq (GPT-OSS) e Google Gemini',
        'companies': ['Groq', 'Google'],
        'content_used_by': ['Google'],
        'free_tier': true,
        'international_transfer': true,
      }),
    );
    expect(text, contains('às empresas Groq e Google'));
    expect(text, contains('a segunda quando a primeira não estiver'));
    expect(text, contains('a Google pode usar o conteúdo'));
    expect(text, isNot(contains('a Groq pode')));
  });

  test('só o modo demonstração: diz que nada sai do servidor', () {
    final text = aiConsentText(
      AiProviderInfo.fromJson({
        'provider': 'demo',
        'label': 'Modo demonstração (respostas por regras, sem IA externa)',
        'companies': <String>[],
        'content_used_by': <String>[],
        'free_tier': false,
        'international_transfer': false,
        'demo': true,
      }),
    );
    expect(text, contains('modo demonstração'));
    expect(text, contains('Nenhum dado é enviado a empresas de IA'));
    expect(text, isNot(contains('ao provedor de IA do servidor')));
  });

  test('Gemini com o demo de reserva: nomeia a empresa e a reserva', () {
    final text = aiConsentText(
      const AiProviderInfo(
        label: 'Google Gemini',
        companies: ['Google'],
        internationalTransfer: true,
        demo: true,
      ),
    );
    expect(text, contains('à empresa Google (Google Gemini)'));
    expect(text, contains('responde em modo demonstração'));
  });

  test('só o Groq: nomeia a empresa sem o aviso do gratuito', () {
    final text = aiConsentText(
      const AiProviderInfo(
        label: 'Groq (GPT-OSS)',
        companies: ['Groq'],
        internationalTransfer: true,
      ),
    );
    expect(text, contains('à empresa Groq'));
    expect(text, isNot(contains('plano gratuito')));
  });
}
