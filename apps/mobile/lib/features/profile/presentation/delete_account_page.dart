import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../application/profile_actions.dart';

/// Exclusão da conta (5.6, ADR-063): explica o que some, sugere exportar antes e pede
/// a senha e uma confirmação explícita. Ao concluir, o app volta para o login.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _password = TextEditingController();
  bool _understood = false;
  bool _obscure = true;
  bool _deleting = false;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _passwordError = 'Digite a sua senha.');
      return;
    }
    setState(() {
      _deleting = true;
      _passwordError = null;
      _error = null;
    });
    try {
      // Ao concluir, a sessão sai e o roteador leva ao login.
      await ref.read(profileActionsProvider).deleteAccount(_password.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _passwordError = error.fieldErrors['password'];
        _error = _passwordError == null ? error.message : null;
        _deleting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const lost = [
      'perfil, metas e consentimentos',
      'fichas, treinos, séries e recordes',
      'corridas, caminhadas e planos',
      'refeições, metas nutricionais, peso e medidas',
      'conversas com o assistente',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Excluir conta')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(EvoSpace.xl),
          children: [
            Text(
              'Isto apaga a sua conta e tudo o que está nela, de forma definitiva.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: EvoSpace.md),
            Text('Saem do servidor:', style: theme.textTheme.bodyMedium),
            const SizedBox(height: EvoSpace.xs),
            for (final item in lost)
              Padding(
                padding: const EdgeInsets.only(bottom: EvoSpace.xs),
                child: Text('• $item', style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: EvoSpace.md),
            Text(
              'Não há como desfazer. Se quiser guardar uma cópia, volte e use '
              '"Exportar meus dados" antes.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: EvoSpace.xl),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Sua senha',
                errorText: _passwordError,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            CheckboxListTile(
              value: _understood,
              onChanged: _deleting
                  ? null
                  : (value) => setState(() => _understood = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Entendo que a conta e os dados serão apagados para sempre.',
              ),
            ),
            const SizedBox(height: EvoSpace.lg),
            EvoFormError(message: _error),
            FilledButton(
              onPressed: _understood && !_deleting ? _delete : null,
              style: FilledButton.styleFrom(
                backgroundColor: EvoColors.danger,
                foregroundColor: EvoColors.onAccent,
                minimumSize: const Size.fromHeight(evoTouchTargetMin + 8),
              ),
              child: _deleting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EvoColors.onAccent,
                      ),
                    )
                  : const Text('Excluir conta definitivamente'),
            ),
            const SizedBox(height: EvoSpace.sm),
            EvoButton(
              label: 'Cancelar',
              variant: EvoButtonVariant.secondary,
              onPressed: _deleting ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
