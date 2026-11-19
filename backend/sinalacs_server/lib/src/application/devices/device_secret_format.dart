/// Formato aceito para o `deviceSecret` de uma credencial de dispositivo do
/// participante (C-05, RF24): base64url **sem padding** com exatamente 43
/// caracteres — 32 bytes de `Random.secure()`, como `generateDeviceSecret`
/// produz no app.
///
/// O servidor guarda só o SHA-256 de `sinalacs-pdc-v1:<segredo>`, e hash
/// rápido só é seguro porque o segredo tem 256 bits. Quem garantia a entropia
/// era só o app; um cliente com defeito (ou alternativo) gravava `"1"` ou uma
/// string vazia, e um vazamento do banco quebraria essa credencial por força
/// bruta em segundos. Fechado neste formato na borda do endpoint, antes de
/// consumir o convite — a mesma disciplina do `deviceId` (#94, achado C1).
final RegExp deviceSecretFormat = RegExp(r'^[A-Za-z0-9_-]{43}$');

bool isDeviceSecretFormat(String value) => deviceSecretFormat.hasMatch(value);
