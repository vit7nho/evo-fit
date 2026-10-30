import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';

/// Resumo honesto do tratamento de dados (docs/SECURITY_PRIVACY.md).
///
/// O texto jurídico completo ainda não existe: o EvoFit é um projeto acadêmico, e os
/// termos definitivos dependem de revisão jurídica antes de qualquer lançamento.
Future<void> showTermsSummaryDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      const items = [
        'Seus dados são usados só para o funcionamento do app: registrar '
            'treinos, calcular sua evolução e personalizar recomendações.',
        'Cada conta só enxerga os próprios dados.',
        'Sua senha é guardada com hash (Argon2id); nem a equipe consegue lê-la.',
        'Dados de saúde (como limitações físicas) e o uso de IA só serão '
            'tratados com consentimentos separados, pedidos à parte.',
        'O EvoFit não substitui profissionais de saúde, Educação Física ou '
            'Nutrição.',
      ];
      return AlertDialog(
        title: const Text('Resumo dos termos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Versão provisória de um projeto acadêmico (TCC). O texto '
                'completo será publicado antes de qualquer lançamento.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: EvoSpace.md),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: EvoSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: EvoSpace.sm),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: EvoColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(item, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      );
    },
  );
}
