/// Validações locais: evitam uma ida à API por erros óbvios. A API valida de novo.
abstract final class AuthValidators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static const passwordMinLength = 10;

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Informe seu e-mail.';
    if (!_email.hasMatch(email)) return 'Informe um e-mail válido.';
    return null;
  }

  static String? loginPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Informe sua senha.' : null;

  static String? newPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Crie uma senha.';
    if (password.length < passwordMinLength) {
      return 'A senha deve ter pelo menos $passwordMinLength caracteres.';
    }
    return null;
  }

  static String? displayName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Informe seu nome ou apelido.';
    if (name.length > 60) return 'Use no máximo 60 caracteres.';
    return null;
  }
}
