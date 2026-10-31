import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/form_focus.dart';
import '../application/auth_controller.dart';
import 'auth_layout.dart';
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
    final fieldsOk = validateAndFocusFirstError(_formKey.currentState!);
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
    final fieldErrors = _error?.fieldErrors ?? const <String, String>{};
    // Erros de campo aparecem no próprio campo; o aviso do topo mostra o resumo.
    final termsError = _showTermsError
        ? 'É preciso aceitar para criar a conta.'
        : fieldErrors['accept_terms'];

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: AuthLayout(
          title: 'Crie sua\nconta.',
          subtitle:
              'Leva menos de um minuto. O restante do perfil você completa '
              'depois.',
          leading: IconButton.outlined(
            tooltip: 'Voltar para o login',
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              side: const BorderSide(color: EvoColors.borderSubtle),
              backgroundColor: EvoColors.bgSurface,
            ),
            onPressed: _submitting ? null : _back,
          ),
          children: [
            EvoFormError(message: _error?.message),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.nickname],
              textInputAction: TextInputAction.next,
              maxLength: 60,
              validator: AuthValidators.displayName,
              onChanged: _clearServerError,
              forceErrorText: fieldErrors['display_name'],
              decoration: const InputDecoration(
                labelText: 'Seu nome ou apelido',
                prefixIcon: Icon(Icons.person_outline_rounded),
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
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: EvoSpace.lg),
            PasswordField(
              controller: _password,
              label: 'Senha',
              helperText:
                  'Mínimo de ${AuthValidators.passwordMinLength} caracteres. '
                  'Uma frase com algumas palavras é forte e fácil de lembrar.',
              validator: AuthValidators.newPassword,
              serverError: fieldErrors['password'],
              autofillHints: const [AutofillHints.newPassword],
              onChanged: _clearServerError,
              onSubmitted: _submit,
            ),
            const SizedBox(height: EvoSpace.md),
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
              trailingIcon: Icons.arrow_forward_rounded,
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  /// Volta com a transição reversa quando veio do login; senão, abre o login.
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
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
          // O erro faz parte do controle: o TalkBack o lê junto com a caixa.
          isError: errorText != null,
          subtitle: errorText == null
              ? null
              : Text(
                  errorText!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: EvoColors.danger,
                  ),
                ),
          title: Text(
            'Li e aceito os Termos de Uso e a Política de Privacidade',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: EvoColors.textPrimary,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => showTermsSummaryDialog(context),
            child: const Text('Ler o resumo dos termos'),
          ),
        ),
      ],
    );
  }
}
