import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../application/auth_controller.dart';
import 'form_validators.dart';
import 'password_field.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  ApiException? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// O erro da API some assim que a pessoa corrige algum campo.
  void _clearServerError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Em caso de sucesso, o roteador leva à tela inicial.
      await ref
          .read(authControllerProvider.notifier)
          .login(email: _email.text.trim(), password: _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(EvoSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('EvoFit', style: theme.textTheme.displaySmall),
                      const SizedBox(height: EvoSpace.sm),
                      Text(
                        'Entre para acompanhar sua evolução.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: EvoColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: EvoSpace.x2xl),
                      if (_error != null) ...[
                        EvoFormError(message: _error!.message),
                        const SizedBox(height: EvoSpace.lg),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: AuthValidators.email,
                        onChanged: _clearServerError,
                        forceErrorText: _error?.fieldErrors['email'],
                        decoration: const InputDecoration(labelText: 'E-mail'),
                      ),
                      const SizedBox(height: EvoSpace.lg),
                      PasswordField(
                        controller: _password,
                        label: 'Senha',
                        validator: AuthValidators.loginPassword,
                        serverError: _error?.fieldErrors['password'],
                        onChanged: _clearServerError,
                        onSubmitted: _submit,
                      ),
                      const SizedBox(height: EvoSpace.xl),
                      EvoButton(
                        label: 'Entrar',
                        isLoading: _submitting,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: EvoSpace.md),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => context.go(AppRoutes.register),
                        child: const Text('Ainda não tem conta? Criar conta'),
                      ),
                      TextButton(
                        onPressed: () => context.push(AppRoutes.status),
                        child: const Text('Status do servidor'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
