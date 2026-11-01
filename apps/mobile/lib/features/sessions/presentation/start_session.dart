import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../application/session_controller.dart';

/// Começa um treino (de uma ficha ou livre) e abre a tela dele.
///
/// Se já houver um treino aberto, a API recusa com `session_in_progress`: em vez de
/// um erro, o app abre o treino que já existe e avisa.
Future<void> startSession(
  BuildContext context,
  WidgetRef ref, {
  String? templateId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final controller = ref.read(sessionProvider.notifier);
  try {
    await controller.start(templateId: templateId);
    ref.read(restTimerProvider.notifier).skip();
    unawaited(router.push(AppRoutes.session));
  } on ApiException catch (error) {
    if (error.code == 'session_in_progress') {
      await controller.reload();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Você já tem um treino em andamento. Continue por aqui.',
          ),
        ),
      );
      unawaited(router.push(AppRoutes.session));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
