/// Formato aceito para o `deviceId` de um aparelho do ACS (#94, achado C1 da
/// revisão final): UUID em hex minúsculo, como o app gera
/// (`generateDeviceId` em `apps/acs`).
///
/// O `deviceId` chega do cliente no `auth.loginInstitutional`, vai para o JWT
/// e de lá para o SAN da folha MQTT (`urn:sinalacs:device:<deviceId>`), que o
/// OpenSSL lê de um arquivo de configuração. Texto livre ali deixava o cliente
/// injetar `${ENV::...}`; fechado neste formato, nenhum metacaractere passa.
final RegExp deviceIdFormat = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

bool isDeviceIdFormat(String value) => deviceIdFormat.hasMatch(value);
