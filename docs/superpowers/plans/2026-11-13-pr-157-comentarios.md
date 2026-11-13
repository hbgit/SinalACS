# PR #157 (C-05, convite QR + PIN): parecer e comentários a publicar

Textos da revisão da PR #157 (`feat/issue-128-login-convite-pin`, base `develop`, commit `bfa5815`). A revisão teve duas partes, servidor (backend, migração, scripts e docs) e app do paciente (PIN e criptografia), fundidas aqui. Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/157/comments` (inlines, um por chamada). Plano: `2026-11-13-prs-156-163-revisao.md`; síntese: `2026-11-13-prs-156-163-sintese.md`.

Veredito proposto: **Pedir mudanças (bloqueante)** (`gh pr review --request-changes`). Um bloqueante, no servidor: a exclusão atendida pela LGPD (#42) não revoga a credencial nova de dispositivo, e o aparelho do titular anonimizado continua entrando (Inline 1). Os demais pedidos são pequenos, mas dois deles, no app, são defeitos reais: a tela de criação do PIN fica presa se a gravação no Keystore falhar (provado com teste) e o PIN digitado entra no `toString` de uma exceção, o que a D3 da #136 proíbe. A PR não toca a triagem (INV-02) nem o caminho do pedido enviado (INV-03). Corrigido o bloqueante e atendidos os pedidos, o parecer passa a **Aprovar com observações**.

---

## Parecer

Revisei a issue #128 (RF24/C-05) dos dois lados: o servidor (a migração `20261109144551146`, os scripts de e2e e a documentação) e o app do paciente, este contra a decisão D3 do plano da #136 (`docs/superpowers/plans/2026-11-03-issue-136-cifra-local-paciente.md`) e contra o que as PRs abertas do paciente acrescentam na mesma tela. A migração está limpa, as duas suítes passam inteiras e o desenho da credencial e do envelope é bom. O problema principal está na fronteira com a #42.

**Critérios da #128, lado servidor:**

| Critério | Evidência |
|---|---|
| Credencial criada na mesma transação do consumo do convite; convite de uso único | `OnboardingEndpoint.completeEnrollment` abre a transação e passa a mesma `Transaction` às duas stores (`alert_runtime.dart`, `onboardingServiceFor`); em `onboarding_endpoint_test.dart`, "segundo uso do mesmo token falha com EnrollmentException" e o teste de corrida ("duas chamadas concorrentes com o mesmo token…", linha 490) conferem uma credencial só; `device_credential_login_test.dart` "deviceId fora do formato UUID não consome o convite". |
| `loginDevice` emite JWT de 1 h com `device_id` e recusa credencial inexistente ou errada | `device_credential_login_test.dart` "convite concluído cria a credencial e auth.loginDevice devolve a sessão" (`tokenLifetime == patientSessionLifetime`, `user.deviceId`) e "segredo errado, aparelho desconhecido e deviceId malformado recebem a MESMA recusa". **A credencial revogada não tem teste** (nenhum código grava `revokedAt`). |
| Backend sobe no perfil do piloto sem `SMS_GATEWAY`; `requestOtp` recusa | `device_credential_login_test.dart` "o backend sobe sem SMS_GATEWAY…" (`AppConfig.fromMap` com `APP_ENV=production` e sem a variável, `health.check` ok, `requestOtp` → `EndpointDisabledException`); `app_config_test.dart`, grupo `SMS_GATEWAY`. **`verifyOtp` sem gateway dá `StateError` (500)**, ver Inline 2. |
| `users.cpfHash` anulável (P-10) sem quebrar o `cpf-hash-seed` | `migration.sql`: só `DROP NOT NULL`; `seed_cpf_hashes.dart` só escreve a coluna, não depende de ela ser obrigatória; o seed do teste grava `cpfHash: null` e a conclusão do convite passa. |
| RF09/RF10 fora | Nenhum campo de endereço ou ponto de referência entrou no modelo, na migração nem nos endpoints. |

**Critérios da #128, lado app:**

| Critério | Evidência |
|---|---|
| Nenhum campo de CPF, telefone ou e-mail no login | `test/device_login_test.dart:28` afirma `cpf_field`, `birth_date_field` e `otp_code_field` ausentes e nenhum texto com "CPF", "e-mail" ou "telefone"; `lib/app/app.dart` não tem mais `_CpfInputFormatter`, `requestOtp` nem `verifyOtp`. |
| Credencial no aparelho protegida pelo PIN e vinculada ao identificador pseudônimo | `lib/core/security/device_credential_store.dart:113-133` (envelope do PIN no `flutter_secure_storage`), `lib/app/app.dart:1077-1088` (envelope gravado antes de `completeEnrollment`, que leva `deviceId` + segredo ao servidor). Testes: `test/device_credential_store_test.dart:23`, `test/onboarding_flow_test.dart:166` e `:248`. |
| Sessão expirada leva à tela de PIN, não ao login completo | `test/device_login_test.dart:181` ("oferece 'Entrar novamente' e volta para a tela do PIN"); texto em `lib/app/app.dart` (`session_expired_notice`) e em `BackendClient._requireToken`. |

**O que rodei** (Linux, worktree limpo em `bfa5815`):

- Migração contra o append-only da #82: `grep` de `audit_logs|audit_exports|audit_chain_checkpoints` em `migration.json` não acha nada. `definition.sql` traz o bloco do trigger e do `REVOKE` (5 linhas; a migração anterior também tem 5, e o bloco é idêntico byte a byte). Fora os comentários, o `diff` contra `20261028025257928/definition.sql` mostra só a tabela nova, os dois índices, `cpfHash` anulável, a FK e a versão. `migration.sql` não toca em auditoria.
- `dart analyze` em `backend/`: 103 issues contra 98 em `develop`. Os 5 novos são `prefer_initializing_formals`, o mesmo lint de 96 dos 98 existentes.
- `docker compose --profile test up -d postgres-test` e `dart test -j 1` no backend: **`+1669: All tests passed!`**.
- `python3 scripts/qa/otp_relay_test.py`: `OK`. Com `-I` o import falha também em `develop`, porque `-I` tira o diretório do script do `sys.path`; não é da PR. `bash scripts/qa/lib_rele_test.sh`: `ok: lib_rele`. `bash scripts/qa/mqtt_resiliencia_e2e_test.sh`: `ok`.
- `bash scripts/qa/check_documentation_links.sh`: só o `graphify-out` de `AGENTS.md`, que já falta em `develop`.
- App do paciente (Flutter 3.44.8, o mesmo da CI): `flutter analyze` só com o aviso `asset_directory_does_not_exist` de `assets/certs/`, o diretório gitignorado; `flutter test` completo: 355 passam. Testes novos um a um: `pin_envelope_test` 7, `pin_policy_test` 8, `device_credential_store_test` 5, `device_login_test` 9, `onboarding_flow_test` 21; `android_backup_manifest_test` 8. Todos verdes.
- Bancada do Argon2id com os parâmetros da D3 (m = 19 MiB, t = 2, p = 1) num desktop x86_64: 84 a 157 ms em JIT e 69 a 85 ms em AOT por derivação.
- Sondas descartáveis, apagadas depois e sem registro no log: (1) `auth.verifyOtp` no perfil do piloto lança `StateError: SMS_GATEWAY ausente…`; (2) depois de `OrmDataSubjectCaseStore.decide(… anonymize: true)`, `DeviceCredentialService.login` com a credencial do titular devolveu login concedido. A prova do bloqueante não depende da sonda: é a leitura de `_anonimizar` em `orm_data_subject_case_store.dart:309-424`, que não toca `patient_device_credentials` (nenhuma referência a `PatientDeviceCredential` no arquivo).
- Teste temporário, apagado depois, com o `failEnroll` que o duplo já oferece: ver Inline 11.

**Testes removidos ou encolhidos** (deleções maiores que adições, pelo `--stat` do diff): `test/passwordless_login_test.dart` (−230, apagado: a tela de OTP saiu e os 2 testes de sessão expirada passam para `device_login_test.dart`); `test/e2e_login_test.dart` (+48/−60); `test/support/e2e_login_core.dart` (+20/−78), `test/support/fake_patient_backend.dart` (+33/−49) e `integration_test/support/e2e_login.dart` (+5/−7), que são suporte. `backend_client_otp_test.dart` foi renomeado para `backend_client_device_login_test.dart`. Nenhum outro arquivo de teste tem mais deleções que adições. As remoções fazem sentido, mas o corpo da PR não as explica (ver Geral).

**Lista fechada da criptografia (D3 da #136):**

| Item | Onde |
|---|---|
| Argon2id com parâmetros nomeados (memória, iterações, paralelismo) | `lib/core/security/pin_envelope.dart:36-41` (`memory: 19456`, `iterations: 2`, `parallelism: 1`, `hashLength: 32`), iguais à D3. |
| Salt aleatório de 16 B ou mais | `pin_envelope.dart:57`: 16 B de `Random.secure()` (`:31`, `:134-135`), sorteado **por envelope**, não só por aparelho, o que é mais forte. Teste: `test/pin_envelope_test.dart:32`. |
| AES-GCM com nonce aleatório de 12 B por cifra, nunca reutilizado para a mesma chave | `pin_envelope.dart:62-68` (`AesGcm.with256bits()`, nonce de 12 B). Cada envelope deriva uma chave nova (salt novo), então cada chave cifra uma vez só e o nonce não se repete. Teste: `pin_envelope_test.dart:32`. |
| Segredo cifrado e salt no `flutter_secure_storage`, nunca em `shared_preferences` | `lib/core/security/device_credential_store.dart:86-92` (`encryptedSharedPreferences: true`, Keychain `first_unlock_this_device`) e `:123-131`; o salt vai dentro do envelope (`pin_envelope.dart:69-75`). `shared_preferences` continua só em `lib/core/services/theme_controller.dart`. |
| PIN nunca gravado nem logado | Não é gravado: `device_credential_store.dart:122-131` grava só o envelope, e o teste `device_credential_store_test.dart:35-40` confere o registro cru. Nenhum `print`/`debugPrint`/`log` em `lib/core/security` nem nas telas novas. **Mas** `pin_envelope.dart:54` e `device_credential_store.dart:120` põem o PIN no `toString` de `ArgumentError.value` (Inline 10). |
| PIN de 6+ dígitos com as proibições da D3 (repetido, sequência, alternância), com teste | `lib/core/security/pin_policy.dart:23-41`; teste `test/pin_policy_test.dart` (8 casos, incluindo os que **não** devem ser barrados, como `112233`). Defesa em profundidade na cifra: `pin_envelope.dart:52-55`. |
| Bloqueio 5 tentativas → 30 s dobrando até 15 min, no aparelho | Limiar: `device_credential_store.dart:64` e `:179`. Prazo: `:70-75`. **Contador:** persistido no `flutter_secure_storage` (`_attemptsKey`, `:97`, gravado em `:185-191`), então sobrevive a reiniciar o app; não fica só em RAM. **Teto:** 30 × 2⁵ = 960 s = **16 min**, não 15 (Inline 9). Sem teste da progressão. |
| `cryptography` é a única dependência nova e está em `spec/stack.md` | É a única direta nova (`pubspec.yaml:25`; resolve para 2.9.0). `spec/stack.md:85` a cita, mas só para o backend (`health_data_cipher.dart`); o uso no app não está registrado (Inline 17). |

**Pontos que conferi no código e aprovo:**

*Servidor:*

- O servidor guarda só `SHA-256("sinalacs-pdc-v1:" + segredo)`. Um vazamento do banco não permite login, desde que o segredo tenha os 256 bits que o app sorteia (o app gera 32 bytes de `Random.secure()` em base64url). Hash rápido é aceitável nessa condição, o mesmo parecer do `tokenHash` do convite. A comparação é em tempo constante.
- Recusa uniforme: segredo errado, aparelho desconhecido e credencial revogada recebem a mesma `DeviceCredentialException` com a mesma mensagem, e o `deviceId` malformado é recusado com ela antes do banco.
- A microárea do JWT é relida de `users` no login (`JOIN`), nunca vem de parâmetro (INV-01). O `LIMIT 2` funciona como asserção barata do índice único.
- `touchLastUsed` não ressuscita credencial revogada.
- Trilha: `granted`, `denied_credential` (só com titular conhecido) e `denied_no_territory` entram em `audit_logs` por `recordSafely`. O `deviceId` desconhecido não gera linha, porque não há titular a quem atribuí-la; concordo.
- `loginDevice` está na allowlist de `endpoint_auth_posture_test.dart` com justificativa.
- `openssl_device_ca.dart`: o `return await` dentro do `try` corrige uma corrida real com o `finally` que apaga o diretório temporário. Boa correção de passagem.
- Seed de e2e: 6 convites por paciente, só o sha256 no banco, o texto claro só no manifesto 0600, e a recusa a rodar fora de `sinalacs_e2e` continua.
- `backend/CLAUDE.md` descreve `loginDevice`, a criação na mesma transação e o `SMS_GATEWAY` opcional. `.env.example`, `spec/stack.md`, `AGENTS.md`, `inventario-vinculo-institucional.md` (I-31) e `mudancas-de-codigo-recomendadas.md` foram atualizados.
- `spec/lgpd_data_audit.md` classifica as 7 colunas de `patient_device_credentials`.
- `spec/requisitos_piloto.md` já traz RF01 como Futuro e RF24 como Essencial em `develop`, então a PR não precisa mexer nele.

*App:*

- Ordem "envelope local primeiro, servidor depois, desfaz o envelope se o servidor recusar" (`app.dart:1077-1094`): nunca fica credencial local para um convite não consumido. O caso "o servidor gravou e a resposta se perdeu" cai na recuperação por convite novo, sem perda de dado.
- Recusa local de PIN fraco **antes** de gastar o convite (`app.dart:1054-1065`), provada no `full_journey_test.dart` contra o backend real e em `onboarding_flow_test.dart:191`.
- Erro de derivação e envelope corrompido produzem a mesma `WrongPinException` (`pin_envelope.dart:85-121`), com teste.
- O bloqueio é consultado antes de verificar o PIN, e o PIN certo não o fura (`device_credential_store_test.dart:56`).
- Falha de rede no login **não** descarta a credencial (`device_login_test.dart:135`).
- QR: `QrScannerScope` e `parseEnrollmentQr` seguem iguais (`app.dart:771` e `:781`); o formato do convite não muda e `apps/acs` não é tocado.
- O aceite do termo continua obrigatório no cadastro (`app.dart:806`, antes de abrir `PinSetupScreen`), e a checagem pós-login (`_needsTerms`) segue como convite ao aceite, não como portão.
- `PatientLocalDatabase` e `LocalProtectionNotice` (#136) não têm nenhuma linha alterada.
- `android_backup_manifest_test.dart` não é tocado e passa (8/8). O envelope mora em `sharedpref`, que as regras de backup da #136 já excluem da nuvem e da transferência entre aparelhos.
- Acessibilidade: alvos 48×52 e 48×48, `liveRegion` no aviso de bloqueio e no erro do PIN, `dangerOnSurface` no erro sobre `Card`.

**Bloqueante:** a exclusão atendida (#42) não revoga nem apaga a credencial de dispositivo (Inline 1).

**Pedidos (nesta PR):**

- Servidor: `verifyOtp` sem gateway (Inline 2); validar o formato do `deviceSecret` no servidor (Inline 3); `acs_telemetria_e2e.sh` quebrado pela remoção de `/code` (Inline 4); textos que descrevem a C-12 como existente (Inlines 5 e 6); comentário velho do `.env.example` (Inline 7); `PROGRESS.md` (Inline 8).
- App: teto de 16 min sem teste (Inline 9); PIN no `toString` da exceção (Inline 10); tela presa quando o `enroll` lança (Inline 11); credencial apagada por recusa que não é de credencial (Inline 12); links da tela de login só num dos dois estados, que também define onde #155, #156 e #161 entram (Inline 13).
- Rebase sobre as PRs do paciente que entram antes desta (Geral).

**Sugestões (opcionais):** teste da credencial revogada (coberto pelo teste do Inline 1); leitura do Keystore e bloqueio na abertura da tela (Inline 14); Argon2id na thread da UI (Inline 15); lockfile e `spec/stack.md` (Inline 17); auditar a emissão da credencial (Issue 1).

**Registros:** bloqueio medido pelo relógio de parede (Inline 16). O critério "backend sobe sem `SMS_GATEWAY`" é provado por `AppConfig.fromMap` com `overrideConfig` e `health.check` no harness, e não por um boot de processo; é suficiente, porque `fromEnvironment` passa pelo mesmo `fromMap`. A C-12 ficou fora, e o modelo a comporta (`revokedAt` e o índice por `patientId`). O `deviceId` desconhecido responde sem calcular hash (tempo menor); não é oráculo útil, porque o `deviceId` é um UUID aleatório. A contagem de tabelas de domínio no `definition.sql` foi de 29 para 30 (`CREATE TABLE` sem prefixo `serverpod_`); o `CLAUDE.md` da raiz ainda diz 27, número que já estava defasado antes desta PR.

---

## Inline 1 — backend/sinalacs_server/lib/src/application/auth/device_credential_service.dart:106 — bloqueante

Esta guarda só olha `revokedAt`, e hoje nenhum caminho grava essa coluna. Em particular, a exclusão atendida da #42 (`OrmDataSubjectCaseStore._anonimizar`, `orm_data_subject_case_store.dart:309-424`) apaga `user_credentials`, `otp_challenges` e `push_tokens`, mas não toca em `patient_device_credentials`. Logo, depois de `decide(…, anonymize: true)`, a credencial do titular continua válida e o `login` devolve a sessão com o id e a microárea do titular removido (conferi também numa sonda descartável contra o Postgres de teste). O JWT emitido permite abrir "Meus Dados" e criar alerta depois de a exclusão ter sido dada como atendida, o que contradiz o próprio contrato de `_anonimizar` ("some … o que liga aparelho/login a ele").

Peço, nesta PR, na mesma transação da anonimização: `UPDATE patient_device_credentials SET "revokedAt" = now() WHERE "patientId" = @id AND "revokedAt" IS NULL` (ou `deleteWhere`, que bate com o que já se faz com `user_credentials`). Peço também um caso em `data_subject_case_store_test.dart`: depois de `excluir(_pedA1)`, `DeviceCredentialService.login` recusa com a mensagem única. O mesmo teste cobre o ramo de `revokedAt` que hoje está sem prova.

---

## Inline 2 — backend/sinalacs_server/lib/src/runtime/alert_runtime.dart:767 — pedido

"Inalcançável" vale para `requestOtp`, mas não para `verifyOtp`: ele constrói o `PasswordlessAuthService` direto, sem a guarda. No perfil do piloto, `auth.verifyOtp(cpf: …, code: …)` cai aqui e sai `StateError: SMS_GATEWAY ausente…`, um erro interno (500), em vez da recusa explícita (visto numa sonda descartável). Peço a mesma guarda de `requestOtp` no começo de `verifyOtp` (`EndpointDisabledException`) e um caso a mais no grupo "perfil do piloto" de `device_credential_login_test.dart`.

---

## Inline 3 — backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart:53 — pedido

O SHA-256 rápido de `credentialHash` só é seguro porque o segredo tem 256 bits, e quem garante isso hoje é o app. O servidor aceita qualquer `deviceSecret`, inclusive `"1"` ou uma string vazia. Um cliente com defeito, ou um cliente alternativo, gravaria uma credencial que um vazamento do banco quebraria por força bruta em segundos. Peço validar o formato no servidor, antes de consumir o convite e com a mesma recusa do `deviceId`: base64url sem padding com exatamente 43 caracteres, que é o que `generateDeviceSecret` produz. Em `auth.loginDevice` a mesma checagem pode devolver a `DeviceCredentialException` única. Basta um teste por endpoint.

---

## Inline 4 — scripts/qa/acs_telemetria_e2e.sh:12 — pedido

O relé perdeu `/code` nesta PR, mas `apps/acs/integration_test/telemetry_e2e.dart:144` (`_dispararAlerta`) ainda faz `requestOtp` + `_rele('/code', …)` + `verifyOtp` para o paciente `telemetry` disparar o alerta. Com o relé novo esse pedido recebe 404 quarenta vezes, e o teste para em "o relé não devolveu o código do OTP". O script não roda na CI, por isso o `android-e2e` verde não pegou a quebra. Peço trocar o login do paciente nesse teste por um convite do manifesto (`inviteTokens`) com `completeEnrollment`, como fizeram `mqtt_resiliencia_e2e.sh` e o `live_check.dart`, e acertar o comentário desta linha.

---

## Inline 5 — backend/sinalacs_server/lib/src/models/patient_device_credential.spy.yaml:12 — pedido

O texto está no presente ("um convite novo vinculado ao mesmo paciente **revoga** as credenciais anteriores"), mas isso é a C-12 (#133) e não existe no código: nada grava `revokedAt`. Quem ler o modelo vai supor que a reemissão já invalida o aparelho antigo. Peço o futuro, como o próprio campo `revokedAt` já diz mais abaixo ("Preenchido pela C-12"). Algo como: "`revokedAt` é a invalidação que a C-12 (#133) vai preencher; hoje nenhum caminho a grava — ver a anonimização da #42".

---

## Inline 6 — spec/lgpd_data_audit.md:47 — pedido

Vale o mesmo do Inline 5: "A reemissão de convite para o mesmo identificador revoga as credenciais anteriores (C-12)" descreve como entregue algo que não está. Peço "revogará (C-12, #133; ainda não implementado)". Se a correção do Inline 1 entrar, vale acrescentar que a exclusão atendida (#42) revoga a credencial. A linha da `patients`/`users` em §1 também deveria citar `patient_device_credentials` entre o que a anonimização apaga ou revoga.

---

## Inline 7 — .env.example:213 — pedido

As linhas 212–215 ("Limite atual: fora de development o servidor ainda exige este campo para subir…; retirar essa exigência é a mudança C-05") ficaram, e o bloco novo logo abaixo diz o contrário. Peço trocar as quatro linhas por uma só: "Não usado no piloto (P-10 em spec/escopo_projeto.md: sem CPF e sem SMS)."

---

## Inline 8 — PROGRESS.md:1929 — pedido

"Nada commitado ainda (o usuário faz o commit manual)" descreve o estado da máquina do autor antes do commit. Peço "**Estado:** entregue na PR #157." Na linha 1955, o `CONTRIBUTING.md` pede para não gravar contagens de testes nos documentos, porque elas envelhecem a cada PR (aqui já são 1669, não 1667). Basta "suíte completa `dart test` verde".

---

## Inline 9 — apps/patient/lib/core/security/device_credential_store.dart:73 — pedido

O corpo da PR e o comentário acima dizem "30 s dobrando até 15 min", mas `extra.clamp(0, 5)` dá 30 × 2⁵ = 960 s, ou seja, **16 min** de teto. Não é uma falha de segurança: 16 min deixa o bloqueio um pouco mais rígido, não mais fraco. O pedido é pela divergência entre o que a D3 e a PR dizem e o que o código faz, e pela falta de um teste da progressão, que é o que deixaria passar essa diferença. Sugiro limitar pelo prazo, e não pelo expoente, e prender a progressão num teste (ou, se preferir 16 min, corrigir o texto e prender esse valor):

```dart
static Duration lockDuration(int failures) {
  final extra = failures - maxAttempts;
  if (extra < 0) return Duration.zero;
  final seconds = 30 * (1 << extra.clamp(0, 5));
  return Duration(seconds: seconds > 900 ? 900 : seconds);
}
```

```dart
test('5ª falha: 30 s, dobrando até 15 min', () {
  expect(DeviceCredentialStore.lockDuration(4), Duration.zero);
  expect(DeviceCredentialStore.lockDuration(5), const Duration(seconds: 30));
  expect(DeviceCredentialStore.lockDuration(9), const Duration(minutes: 8));
  expect(DeviceCredentialStore.lockDuration(10), const Duration(minutes: 15));
  expect(DeviceCredentialStore.lockDuration(50), const Duration(minutes: 15));
});
```

---

## Inline 10 — apps/patient/lib/core/security/pin_envelope.dart:54 — pedido

`ArgumentError.value(pin, 'pin', weakness)` guarda o PIN na exceção, e o `toString` dela sai como `Invalid argument (pin): <motivo>: "123456"`. A D3 da #136 diz: "A chave, o PIN, a KEK e o salt nunca aparecem em log, em `toString` de exceção". O mesmo vale para `device_credential_store.dart:120`.

Hoje a tela valida antes, então essa exceção só sobe se a validação da tela e a de `enroll` divergirem (uma mudança futura na política, por exemplo). Mas o caminho até um log é concreto: a exceção sobe por `_concluir`, que não tem `catch` para ela (Inline 11), e o Android grava no logcat as exceções Dart não tratadas, também em build release. Basta não passar o valor:

```dart
throw ArgumentError(weakness, 'pin');
```

E um caso no teste de quem lança (`pin_envelope_test.dart` e `device_credential_store_test.dart`), como `expect(() => …, throwsA(predicate((e) => !e.toString().contains('123456'))))`.

---

## Inline 11 — apps/patient/lib/app/app.dart:1121 — pedido

`_concluir` só captura `BackendFailure`. Se `store.enroll` lançar (uma `PlatformException` do Keystore ou do EncryptedSharedPreferences, o caso transitório que a D2 da #136 descreve; ou o `ArgumentError` do Inline 10), ou se `completeEnrollment` lançar algo que não seja `BackendFailure`, a exceção escapa. Então `_busy` fica `true`, o botão "Concluir cadastro" fica desabilitado com o indicador girando e nenhuma mensagem aparece. A pessoa fica presa na tela, e a exceção vai para o log do sistema.

Provei com um teste temporário que usa o `failEnroll` que `FakeDeviceCredentialStore` já tem (nenhum teste o usa): `StateError` não tratado, `pin_setup_confirm_button` com `onPressed == null` e `pin_setup_error` ausente. Sugestão, com uma mensagem neutra, que vale tanto para a falha local quanto para a do servidor, e sem interpolar a exceção:

```dart
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível concluir o cadastro agora. Tente de novo.';
      });
    }
```

Acrescente um teste em `onboarding_flow_test.dart` com `failEnroll = true`: a mensagem aparece, o botão volta e `completeEnrollment` **não** é chamado (o convite continua utilizável). O mesmo cuidado vale para `_entrarComPin` (`:441`): `unlock` pode lançar algo além de `WrongPinException` se a gravação do contador falhar.

---

## Inline 12 — apps/patient/lib/app/app.dart:475 — pedido

`credentialRefused` apaga a credencial local em **qualquer** `DeviceCredentialException`. No servidor, porém, essa mesma exceção também sai para "Este acesso não está vinculado a uma microárea" (`backend/sinalacs_server/lib/src/application/auth/device_credential_service.dart:133`, `denied_no_territory`). Esse é um estado administrativo do paciente, não uma credencial inválida, e pode ser transitório (troca de microárea, por exemplo). Do jeito que está, o aparelho perde a credencial e a pessoa precisa de um convite novo, que pela C-12 revoga a anterior. Proposta: o servidor distingue os dois casos (um campo na exceção ou uma exceção própria para o território), e o app só destrói a credencial na recusa de credencial. Acrescente um teste de widget para cada lado.

---

## Inline 13 — apps/patient/lib/app/app.dart:660 — pedido

A tela tem agora dois estados. "Política de Privacidade e Termo de Uso" só existe em `_camposDoConvite()` (`:652`). Quem já tem credencial vê só o PIN e "Esqueceu o PIN?", sem o link legal, que antes ficava sempre na tela inicial. Além disso, as PRs abertas acrescentam à tela de login exatamente no bloco que esta PR apaga (`if (_step == _LoginStep.credenciais) ...[ start_onboarding_button, login_legal_link ]`):

- #155: link `login_about_link` "Sobre o SinalACS" logo depois de `login_legal_link`, e o `EducationalNoticeGate` em volta de `home: PatientLoginScreen(...)`, a mesma linha que esta PR reindenta dentro do `DeviceCredentialScope`;
- #156: botão `login_library_button` "Biblioteca de saúde (sem cadastro)", ancorado no rótulo "Escanear QR Code do ACS", que esta PR troca;
- #161: botão `login_self_assessment_button` "Autoavaliação (sem cadastro)", com a mesma âncora.

Esses links do pilar A e o "Sobre" valem para quem tem credencial também: quem esqueceu o PIN ainda pode ler a biblioteca e fazer a autoavaliação (RNF07/RNF09: o pilar A não depende de conta nem de lembrar o PIN). Sugiro tirar o link legal de `_camposDoConvite()` e pôr um bloco comum **depois** dos dois estados, por exemplo `..._linksDaTelaInicial()`, renderizado sempre que `_loaded`. Assim o rebase sobre #155, #156 e #161 tem um único lugar onde entrar. E acrescentar, no teste do estado do PIN em `device_login_test.dart`, a afirmação de `login_legal_link` (e, depois do rebase, das três chaves acima).

---

## Inline 14 — apps/patient/lib/app/app.dart:386 — sugestão

Duas coisas na carga da tela:

1. Uma leitura do Keystore que lança, ou que passa de 5 s, vira "sem credencial", e a tela manda pedir um convite novo. A D2 da #136 tratou o mesmo caso no banco local como "falha fechada, tenta de novo, nunca destrói sozinho". Aqui nada é apagado, mas a pessoa é orientada a pedir um convite que revoga a credencial que ainda existe (C-12). Vale distinguir "indisponível" de "ausente" (`_readCredentialRecord` engole a exceção em `device_credential_store.dart:206`) e mostrar "Não foi possível ler o acesso deste aparelho. Tente de novo." com um botão de tentar de novo.
2. O bloqueio só é lido no toque. Quem reabre o app durante o bloqueio vê o botão "Entrar" habilitado e só recebe a contagem depois de tocar. Chamar `_refreshLockout()` ao fim de `_carregarCredencial` quando houver credencial resolve isso.

---

## Inline 15 — apps/patient/lib/core/security/pin_envelope.dart:36 — sugestão

O `package:cryptography` sem o `cryptography_flutter` roda o Argon2id em Dart puro e, com `parallelism: 1`, na thread da UI. Medi 69 a 85 ms por derivação em AOT num desktop x86_64. Num Android de entrada isso pode passar de 1 s, com o indicador "girando" congelado na criação do PIN e a cada login. A D3 pede bancada no aparelho e, acima de 2 s, `cryptography_flutter`, sem reduzir os parâmetros. Não pude medir (sem emulador nem aparelho). Proposta barata: derivar dentro de `Isolate.run`, que não muda o formato do envelope. A medida em aparelho fica na Issue 2.

---

## Inline 16 — apps/patient/lib/core/security/device_credential_store.dart:170 — registro

Só para deixar escrito no residual (`spec/lgpd_design.md` §0, junto do "com root"):

- `lockedUntilMs` é comparado com o relógio de parede, e trocar a data do aparelho nas Configurações (sem root) encerra o bloqueio.
- `_readAttempts` (`:218-232`) falha **aberto**: uma leitura que lança ou um registro ilegível valem "sem bloqueio".

Com Argon2id na casa de 1 s por tentativa, o custo de 10⁶ PINs digitados no app continua alto. Mesmo assim, o comentário de `lockDuration` ("contra a digitação insistida com o aparelho em mãos sem root") promete um pouco mais do que entrega.

---

## Inline 17 — apps/patient/pubspec.yaml:25 — sugestão

Duas coisas pequenas da dependência nova:

1. O `pubspec.lock` da PR sobe `matcher` 0.12.19 → 0.12.20, `meta` 1.18.0 → 1.19.0 e `test_api` 0.7.11 → 0.7.12, que são fixados pelo SDK. No Flutter 3.44.8 da CI, `flutter pub get` desfaz os três, e o lock fica modificado no worktree. Parece gerado com outro Flutter. Sugiro regerar com o 3.44.8, para o diff ficar só com `cryptography` (e `vector_math`, se o 3.44.8 o mantiver).
2. `spec/stack.md:85` registra `package:cryptography ^2.7.0` só no backend. Uma linha dizendo que o app do paciente o usa para o envelope do PIN (D3) fecha o rastro.

---

## Geral — bloqueante e migração

**Bloqueante (resumo do Inline 1).** A credencial de dispositivo é o novo "o que liga aparelho/login ao titular", e a exclusão atendida da #42 precisa revogá-la na mesma transação. Sem isso, o titular anonimizado continua com acesso. A correção é de poucas linhas e tem teste óbvio.

**Migração.** Nada a pedir: `migration.json` não cita nenhuma tabela de auditoria, o `definition.sql` mantém o bloco append-only da #82 idêntico ao da migração anterior, e o SQL de upgrade é aditivo (tabela, índices, FK e `DROP NOT NULL`). A FK `ON DELETE NO ACTION` para `patients` é coerente com a anonimização da #42, que não apaga a linha de `patients`.

**CI e e2e (registro).** O `PROGRESS.md` diz que, sem manifesto, o `android-e2e` segue pelo fallback `developmentLogin`. Ou seja, o fluxo de convite + `loginDevice` não passa por nenhum e2e da CI, só pela integração do backend e pelos scripts manuais. `full_journey_test.dart` cobre convite → PIN → painel contra o backend real, mas nenhum teste de integração **reentra pelo PIN** (`auth.loginDevice` a partir do app); fica na Issue 3.

## Geral — corpo da PR e mensagem do commit

- A #128 pede que remoções de teste sejam explicadas. Sugiro uma linha no corpo: "`passwordless_login_test.dart` apagado (a tela de OTP saiu; os 2 testes de sessão expirada foram para `device_login_test.dart`); `backend_client_otp_test.dart` renomeado para `backend_client_device_login_test.dart`; `e2e_login_core.dart`/`fake_patient_backend.dart` encolhem porque o relé de OTP do paciente saiu".
- A mensagem do commit `bfa5815` perdeu os identificadores entre crases ("o servidor cria  na mesma transação", "anulável (P-10)" sem `users.cpfHash`), provavelmente por substituição do shell. Vale corrigir no squash.
- "Apagar e recomeçar" (#136) não apaga a credencial de dispositivo: são custódias separadas, e "Esqueceu o PIN?" é o caminho para isso. Acho certo; só registro para a C-10.

## Geral — rebase sobre as PRs do paciente que entram antes desta

Pela ordem de merge proposta (`#162 → #163 → #158 → #159 → #155 → #156 → #160 → #161 → #157`), esta PR entra por último no app do paciente e precisa de rebase sobre `develop` depois da #161. O `git merge-tree` dá conflito com #155, #156, #158, #159, #160, #161 e #163, em `apps/patient/lib/app/app.dart`, `patient_app_mvp_test.dart`, `integration_test/full_journey_test.dart` e `PROGRESS.md` (este só por acréscimo no mesmo ponto: manter as duas seções). Além do que o `git` aponta, há quebras que não aparecem como conflito:

1. **Testes novos das outras PRs entram pelo login por CPF/OTP**, que esta PR remove. São arquivos novos, então o merge é limpo e a suíte quebra: `apps/patient/test/educational_notice_test.dart:151` e `:155` (#155), `apps/patient/test/educational_library_test.dart:284` e `:288` (#156), `apps/patient/test/main_notification_permission_test.dart:68` (#159, que espera `cpf_field` como prova de que a tela inicial foi desenhada), `apps/patient/test/call_192_test.dart:55` e `:59` (#160) e `apps/patient/test/local_self_assessment_test.dart:79`, `:135` e `:139` (#161, testes 2 e 5). No rebase, trocar a entrada por CPF/OTP pelo PIN (ou por uma chave que exista nos dois estados da tela, como `start_onboarding_button` ou `login_library_button`).
2. **Botões do pilar A e "Sobre" na tela de login** (#155, #156, #161): entram no bloco comum do Inline 13, visível com ou sem credencial, mantendo as chaves `login_about_link`, `login_library_button` e `login_self_assessment_button`.
3. **Escopos em volta de `home:`/`MaterialApp`:** `EducationalNoticeGate` (#155) e `Call192Scope` (#160) envolvem a mesma linha que esta PR põe dentro do `DeviceCredentialScope`; o conflito se resolve aninhando os três.
4. **Texto da tela de OTP da #158:** o hunk que troca "enviado pela sua unidade de saúde" por "que você recebeu" fica obsoleto, porque esta PR apaga a frase inteira e os textos novos dizem "agente de saúde", sem "UBS". No conflito, fica a versão desta PR. As outras trocas da #158 no paciente (diálogo de exclusão e consentimento de avisos, hoje "A equipe da UBS analisa…" e "Avisos da UBS…" nesta branch) não conflitam e devem permanecer.
5. **Pedido de permissão de notificação (#159):** se a #159 passar a pedir `POST_NOTIFICATIONS` ao conceder o consentimento de avisos no cadastro, esse ponto, que hoje está na tela de onboarding, passa nesta PR para `PinSetupScreen._concluir`, junto do `registerPushDevice`. Conferir que o pedido continua lá, sem `await`, depois do rebase.

---

## Issues de continuação

### Issue 1 — Auditar a emissão da credencial de dispositivo do participante (C-05)

**Contexto.** Desde a #128 (PR #157), `onboarding.completeEnrollment` cria em `patient_device_credentials` uma credencial de longa duração, que é a única prova do login do participante (`auth.loginDevice`). O login já é auditado (`granted`/`denied_credential`/`denied_no_territory`), mas a **emissão** não: o fluxo de onboarding não chama `AuditTrail` (`spec/lgpd_data_audit.md`, linha de `enrollment_tokens.createdByAcsId`). Para comparar: o token de envio diferido do ACS audita `upload_token_issued`.

**O que fazer.**
- Gravar em `audit_logs`, na mesma transação do consumo do convite, uma linha `write`/`patient_device_credential`/`issued` com o titular e o id da credencial (nunca o segredo nem o hash).
- Quando a C-12 (#133) e a anonimização da #42 revogarem credenciais, auditar `revoked` com o motivo.
- Atualizar `spec/lgpd_data_audit.md` (a frase "o fluxo de onboarding não escreve em `audit_logs`") e `backend/CLAUDE.md`.

**Critério de aceite.** Teste de integração: concluir um convite deixa exatamente uma linha `issued` encadeada em `audit_logs`, e uma recusa que desfaz a transação não deixa nenhuma.

**Refs:** #128, #133, #42.

### Issue 2 — Medir o Argon2id do envelope do PIN em aparelho de entrada e tirá-lo da thread da UI

**Contexto.** A PR #157 (C-05) deriva a chave do envelope do PIN com Argon2id (m = 19 MiB, t = 2, p = 1; D3 do plano da #136) pelo `package:cryptography` em Dart puro, na thread da UI, a cada criação do PIN e a cada login. Num desktop x86_64 em AOT, cada derivação leva 69 a 85 ms. Em Android de entrada isso não foi medido.

**O que fazer.**
- Medir a derivação num aparelho de entrada (ou no emulador API 24/36 como aproximação) em build release.
- Derivar dentro de `Isolate.run`, sem mudar o formato `{v, salt, nonce, ct, mac}`.
- Se passar de 2 s, adotar `cryptography_flutter` (implementação nativa), como a D3 manda, **sem** reduzir os parâmetros.

**Critérios de aceite.**
- [ ] Tempo medido registrado no `PROGRESS.md`, com aparelho/API e build.
- [ ] Indicador de progresso anima durante a criação do PIN e o login (derivação fora da thread da UI).
- [ ] Parâmetros do Argon2id inalterados; envelopes existentes continuam abrindo.

**Refs:** #128, #136.

### Issue 3 — e2e: reentrar pelo PIN contra o backend real

**Contexto.** Na #157, `integration_test/full_journey_test.dart` cobre convite → criação do PIN → painel. Nenhum teste de integração exercita `auth.loginDevice` a partir do app, que é o caminho diário do participante (reentrada depois da sessão de 1 h).

**O que fazer.** Depois do cadastro, voltar à tela de login ("Entrar novamente" ou reabertura), digitar o PIN e chegar ao painel; também PIN errado não entra e não gasta convite.

**Critérios de aceite.**
- [ ] Passo novo no `full_journey_test.dart` (ou arquivo próprio) verde em `scripts/qa/patient_full_e2e.sh`.
- [ ] Só dados sintéticos; PIN e segredo nunca impressos.

**Refs:** #128.
