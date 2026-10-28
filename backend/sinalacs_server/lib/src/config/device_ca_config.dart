/// CA de aparelhos (#94): a CA operada pelo backend que assina o certificado de
/// cliente MQTT de cada aparelho do ACS e publica a CRL que o broker consulta.
///
/// Lido de `DEVICE_CA_CERT_PATH`, `DEVICE_CA_KEY_PATH` e `DEVICE_CRL_PATH`, que
/// vêm as três juntas ou não vêm — mesma regra de `ApiTlsConfig`. Sem as três,
/// o ambiente não tem CA de aparelhos (o Render, por exemplo) e a emissão de
/// certificado responde que está indisponível; com um subconjunto, o boot falha
/// em vez de cair num estado meio configurado sem ninguém notar.
///
/// `DEVICE_CERT_DAYS` (validade da folha) e `DEVICE_CRL_DAYS` (intervalo até o
/// `nextUpdate` da CRL) são opcionais, 30 por padrão, e precisam ser inteiros
/// positivos.
class DeviceCaConfig {
  const DeviceCaConfig({
    required this.caCertPath,
    required this.caKeyPath,
    required this.crlPath,
    required this.certDays,
    required this.crlDays,
  });

  final String caCertPath;
  final String caKeyPath;
  final String crlPath;
  final int certDays;
  final int crlDays;

  static const _caminhos = [
    'DEVICE_CA_CERT_PATH',
    'DEVICE_CA_KEY_PATH',
    'DEVICE_CRL_PATH',
  ];

  static const _diasPadrao = 30;

  static String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value;

  static DeviceCaConfig? fromEnvironment(Map<String, String> env) {
    final valores = [for (final v in _caminhos) _blankToNull(env[v])];
    final presentes = valores.whereType<String>().length;
    if (presentes == 0) return null;
    if (presentes != _caminhos.length) {
      throw StateError(
        'DEVICE_CA_CERT_PATH, DEVICE_CA_KEY_PATH e DEVICE_CRL_PATH devem vir '
        'juntas: a CA de aparelhos precisa do certificado, da chave e do '
        'caminho da CRL que o broker lê.',
      );
    }
    return DeviceCaConfig(
      caCertPath: valores[0]!,
      caKeyPath: valores[1]!,
      crlPath: valores[2]!,
      certDays: _dias(env, 'DEVICE_CERT_DAYS'),
      crlDays: _dias(env, 'DEVICE_CRL_DAYS'),
    );
  }

  static int _dias(Map<String, String> env, String variavel) {
    final bruto = _blankToNull(env[variavel]);
    if (bruto == null) return _diasPadrao;
    final dias = int.tryParse(bruto.trim());
    if (dias == null || dias <= 0) {
      throw StateError('$variavel deve ser um inteiro positivo de dias.');
    }
    return dias;
  }
}
