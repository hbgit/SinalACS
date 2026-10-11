/// Rótulos minimizados do backoffice (spec/lgpd_design.md): o admin identifica,
/// não qualifica. Nunca recebe nem devolve nome, CPF ou contato de paciente.
abstract final class AdminLabels {
  static String _sufixo(String id) {
    final limpo = id.replaceAll('-', '');
    return limpo.length < 4
        ? '????'
        : limpo.substring(limpo.length - 4).toUpperCase();
  }

  /// `#` + 4 hex finais do UUID. É rótulo, não identificador: não volta à pessoa.
  static String patient(String patientId) => '#${_sufixo(patientId)}';

  static const _papeis = {
    'admin': 'Administrador',
    'coordinator': 'Coordenador',
    'acs': 'ACS',
    'patient': 'Paciente',
  };

  static String user({
    required String role,
    required String id,
    String? enrollmentId,
  }) {
    final papel = _papeis[role] ?? role;
    if (role == 'patient') return 'Paciente ${patient(id)}';
    if (enrollmentId != null && enrollmentId.isNotEmpty)
      return '$enrollmentId ($papel)';
    return '$papel ${patient(id)}';
  }
}
