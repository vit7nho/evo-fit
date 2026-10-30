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
import 'terms_summary_dialog.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _acceptTerms = false;
  bool _showTermsError = false;
  bool _submitting = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearServerError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final fieldsOk = _formKey.currentState!.validate();
    setState(() => _showTermsError = !_acceptTerms);
    if (!fieldsOk || !_acceptTerms) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            email: _email.text.trim(),
            password: _password.text,
            displayName: _name.text.trim(),
            acceptTerms: _acceptTerms,
          );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const <String, String>{};
    // Erros de campo aparecem no próprio campo; o aviso do topo mostra o resumo.
    final termsError = _showTermsError
        ? 'É preciso aceitar para criar a conta.'
        : fieldErrors['accept_terms'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: EvoColors.bgBase,
        leading: IconButton(
          tooltip: 'Voltar para o login',
          icon: const Icon(Icons.arrow_back),
          onPressed: _submitting ? null : () => context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              EvoSpace.xl,
              0,
              EvoSpace.xl,
              EvoSpace.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Criar conta', style: theme.textTheme.displaySmall),
                      const SizedBox(height: EvoSpace.sm),
                      Text(
                        'Leva menos de um minuto. O restante do perfil você '
                        'completa depois.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: EvoColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: EvoSpace.xl),
                      if (_error != null) ...[
                        EvoFormError(message: _error!.message),
                        const SizedBox(height: EvoSpace.lg),
                      ],
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.givenName],
                        textInputAction: TextInputAction.next,
                        maxLength: 60,
                        validator: AuthValidators.displayName,
                        onChanged: _clearServerError,
                        forceErrorText: fieldErrors['display_name'],
                        decoration: const InputDecoration(
                          labelText: 'Como quer ser chamado',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: EvoSpace.lg),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: AuthValidators.email,
                        onChanged: _clearServerError,
                        forceErrorText: fieldErrors['email'],
                        decoration: const InputDecoration(labelText: 'E-mail'),
                      ),
                      const SizedBox(height: EvoSpace.lg),
                      PasswordField(
                        controller: _password,
                        label: 'Senha',
                        helperText:
                            'Mínimo de ${AuthValidators.passwordMinLength} '
                            'caracteres. Uma frase com algumas palavras é '
                            'forte e fácil de lembrar.',
                        validator: AuthValidators.newPassword,
                        serverError: fieldErrors['password'],
                        autofillHints: const [AutofillHints.newPassword],
                        onChanged: _clearServerError,
                        onSubmitted: _submit,
                      ),
                      const SizedBox(height: EvoSpace.lg),
                      _TermsCheckbox(
                        value: _acceptTerms,
                        errorText: termsError,
                        onChanged: (value) => setState(() {
                          _acceptTerms = value;
                          if (value) _showTermsError = false;
                        }),
                      ),
                      const SizedBox(height: EvoSpace.xl),
                      EvoButton(
                        label: 'Criar conta',
                        isLoading: _submitting,
                        onPressed: _submit,
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

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: value,
          onChanged: (checked) => onChanged(checked ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Li e aceito os Termos de Uso e a Política de Privacidade',
            style: theme.textTheme.bodyLarge,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => showTermsSummaryDialog(context),
            child: const Text('Ler o resumo dos termos'),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: EvoSpace.md),
            child: Text(
              errorText!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: EvoColors.danger,
              ),
            ),
          ),
      ],
    );
  }
}
