/// Endereços do backend e do broker, configuráveis em tempo de compilação.
///
/// Os defaults apontam para o host da máquina de desenvolvimento visto de
/// dentro do emulador Android (`10.0.2.2`). Para outros alvos:
///
///   flutter run --dart-define=SINALACS_HOST=https://localhost/ \
///               --dart-define=SINALACS_MQTT_HOST=localhost
///
/// O RPC é **HTTPS na 443** (RNF04/L-08): a porta 8080 em texto claro deixou de
/// ser publicada e quem termina TLS é o Traefik, com um certificado de
/// desenvolvimento assinado por [rpcCaAsset]. A exceção de cleartext que existia
/// em android/app/src/debug/res/xml/network_security_config.xml foi REMOVIDA,
/// não restringida: não há mais caminho sem criptografia para liberar.
///
/// A senha do broker **não tem default**: ela é um segredo por máquina. Use
/// `scripts/dev/run_acs.sh`, que lê o `.env` e preenche os dart-defines. Em
/// produção o ACS não deveria carregar segredo do broker embutido no binário —
/// ver a lacuna de mTLS registrada em spec/.
class BackendConfig {
  const BackendConfig._();

  /// A barra final é exigida pelo cliente Serverpod.
  ///
  /// O default é **https na 443**: a porta 8080 em texto claro deixou de ser
  /// publicada (RNF04/L-08), e quem termina TLS é o Traefik. Continua sendo o
  /// host da máquina de desenvolvimento visto de dentro do emulador.
  static const String host = String.fromEnvironment(
    'SINALACS_HOST',
    defaultValue: 'https://10.0.2.2/',
  );

  static const String mqttHost = String.fromEnvironment(
    'SINALACS_MQTT_HOST',
    defaultValue: '10.0.2.2',
  );

  /// 8883 é a única porta que o broker publica: TLS, sem WebSocket.
  static const int mqttPort = int.fromEnvironment(
    'SINALACS_MQTT_PORT',
    defaultValue: 8883,
  );

  static const String mqttUsername = String.fromEnvironment(
    'SINALACS_MQTT_USER',
    defaultValue: 'acs-area-12',
  );

  /// Senha do broker. **Sem valor padrão.**
  ///
  /// **`String.fromEnvironment` é resolvido em tempo de COMPILAÇÃO**: este valor
  /// vira uma constante dentro do binário e é extraível de qualquer APK.
  ///
  /// O default anterior (`'development-acs-password'`) nunca funcionou: o
  /// broker local cria o usuário `acs-area-12` com `MQTT_ACS_PASSWORD`, um
  /// segredo aleatório **por máquina** gerado por scripts/dev/bootstrap_env.sh
  /// e aplicado por infra/docker/mosquitto/init.sh. Nenhum valor embutido no
  /// código poderia acertá-lo, então um `flutter run` sem `--dart-define`
  /// produzia um app que nunca recebia alerta e dizia apenas "sem conexão".
  ///
  /// Vazio é agora um estado legítimo e detectável — ver [mqttPasswordMissing].
  /// Para rodar contra a stack local, use scripts/dev/run_acs.sh.
  ///
  /// Em produção credencial de broker não pode viajar dentro do app. A correção
  /// é credencial por dispositivo / mTLS, lacuna registrada em spec/ — o
  /// mosquitto.conf atual nem sequer tem `require_certificate`.
  static const String mqttPassword =
      String.fromEnvironment('SINALACS_MQTT_PASSWORD');

  /// `true` quando o binário foi compilado sem a senha do broker.
  static bool get mqttPasswordMissing => mqttPassword.isEmpty;

  /// CA que assina o certificado do broker local.
  ///
  /// Copiada para cá por `scripts/dev/sync_dev_ca.sh`; é regerada pelo
  /// mosquitto-init e não é versionada.
  static const String mqttCaAsset = 'assets/certs/dev_ca.crt';

  /// CA que assina o certificado do Traefik em :443 (RNF04).
  ///
  /// Não confundir com [mqttCaAsset], que é a CA do broker. São duas, e o
  /// `sync_dev_ca.sh` copia as duas.
  static const String rpcCaAsset = 'assets/certs/dev_rpc_ca.crt';
}
