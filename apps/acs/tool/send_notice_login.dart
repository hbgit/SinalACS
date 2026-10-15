/// Credencial institucional do ACS para as ferramentas de linha de comando.
///
/// Vem de `ACS_MATRICULA` e `ACS_PASSWORD` no ambiente, e não de flags: um
/// argumento de linha de comando aparece em `ps` para qualquer usuário da
/// máquina. Sem nenhuma das duas, a ferramenta usa o login de desenvolvimento
/// (stack com `ENABLE_DEV_LOGIN=true`).
class AcsCredentials {
  const AcsCredentials({required this.matricula, required this.password});

  final String matricula;
  final String password;

  @override
  String toString() => 'AcsCredentials($matricula)'; // nunca a senha
}

AcsCredentials? acsCredentialsFromEnv(Map<String, String> env) {
  final matricula = env['ACS_MATRICULA'] ?? '';
  final password = env['ACS_PASSWORD'] ?? '';
  if (matricula.isEmpty && password.isEmpty) return null;
  if (matricula.isEmpty) throw ArgumentError('defina também ACS_MATRICULA (só ACS_PASSWORD veio).');
  if (password.isEmpty) throw ArgumentError('defina também ACS_PASSWORD (só ACS_MATRICULA veio).');
  return AcsCredentials(matricula: matricula, password: password);
}
