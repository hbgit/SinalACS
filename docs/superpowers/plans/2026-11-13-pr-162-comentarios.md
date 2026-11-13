# PR #162 (#152, dataExtractionRules do ACS): parecer e comentários a publicar

Veredito proposto: **Aprovar com observações**

## Parecer

Escopo: 3 arquivos, +64/−0. Reproduz no app do ACS a regra que o paciente já usa desde a #136.

### Critério da issue → evidência

| Critério da #152 | Evidência |
|---|---|
| `android:dataExtractionRules` e `android:fullBackupContent="false"` no `<application>` | `apps/acs/android/app/src/main/AndroidManifest.xml` linhas 13-14; testes "fullBackupContent=\"false\"..." e "dataExtractionRules aponta para @xml/data_extraction_rules" em `apps/acs/test/android_manifest_test.dart` |
| Cinco domínios excluídos nas duas seções | `data_extraction_rules.xml`: `root`, `file`, `database`, `sharedpref`, `external` em `<cloud-backup>` e `<device-transfer>` |
| Teste cobre atributos e regras e recusa `<include>` | terceiro teste novo (regex por seção e por domínio; falha se houver `<include`) |

### O que rodei

- `flutter test test/android_manifest_test.dart` (apps/acs): `All tests passed!` (14 testes).
- `flutter analyze` (apps/acs): `No issues found!`.
- Suíte completa do ACS (`flutter test`): `+816: All tests passed!` (segundo o corpo da PR o autor não a rodou; aqui passou).
- `diff` do XML do ACS contra o do paciente: só o comentário de cabeçalho difere; as regras são idênticas.
- `bash scripts/qa/check_documentation_links.sh`: só o aviso `graphify-out` ausente no worktree, que não é da PR (a PR não toca `.md`).
- `build.gradle.kts` do ACS: `minSdk = 24`, `targetSdk = 36`, então o atributo `dataExtractionRules` vale e a premissa do texto (targetSdk 31+) é verdadeira.

### Pontos que conferi e aprovo

- Corpo da PR coerente: conforme descrito pelo autor, a tabela do `bmgr` (sem regras o Android mediu `sinalacs_acs.db`, `FlutterSecureStorage.xml`, `FlutterSharedPreferences.xml`, `sinalacs_keystore_vault.xml`; com regras, nada em `/data/data/...`) é o resultado esperado para as regras; não pude reproduzir (sem emulador).
- `flutter_secure_storage` com `encryptedSharedPreferences: true` (`secure_upload_token_store.dart`, `database_key_store.dart`, `secure_device_certificate_store.dart`) fica fora da transferência. É o desejado: a chave do Keystore não migra, e um arquivo cifrado copiado sem ela seria inútil ou geraria estado inconsistente. O aparelho novo começa limpo, com `deviceId` próprio.
- A relação com a #81 (diário de limpeza com `deviceId` antigo reenviando `confirmWipe` no aparelho novo) está bem descrita e é fechada pela exclusão.
- Exclusão total de `external` e `root` não prejudica nada: o app não guarda dado que precise sobreviver à troca de aparelho (a fila offline é por aparelho; visitas pendentes não enviadas se perdem na troca, o que já é a política de dado local).

### Pedidos

Nenhum.

### Sugestões

- O teste valida só texto do XML/manifesto. A prova real continua sendo o `bmgr` do corpo da PR; seria útil guardar esse roteiro (ou um script em `scripts/qa/`) para repetir após atualizações de AGP/targetSdk. Não bloqueia.

### Registros

- Não verifiquei em aparelho/emulador (nenhum ligado nesta máquina); a evidência do `bmgr` é a do autor.
- `apps/admin` não tem `res/xml/data_extraction_rules.xml` nem `allowBackup` no manifesto (conferido só por `ls`/`grep`; fora do escopo da #152, fica como nota).

## Geral — aprovação

Aprovo com observações: regras idênticas às do paciente, atributos corretos, testes cobrindo atributos, cinco domínios nas duas seções e ausência de `<include>`; 14/14 no arquivo, suíte do ACS 816/816 e `flutter analyze` limpo. A única ressalva é a sugestão de registrar o roteiro `bmgr` para reaproveitar.

## Issues de continuação

nenhuma
