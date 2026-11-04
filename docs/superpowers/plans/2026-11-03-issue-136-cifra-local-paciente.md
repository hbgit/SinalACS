# Issue #136: plano de implementação da cifra local do app do paciente (RNF03)

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa por tarefa. Os passos usam caixas de seleção (`- [ ]`) para acompanhamento.

**Objetivo:** guardar cifrado (SQLCipher, AES-256) o que o app do paciente grava no aparelho. Na Fase 1 (pilar A), a chave fica no Android Keystore. Na Fase 2 (pilar B), a chave é liberada pelo PIN local, que depende da C-05.

**Arquitetura:** um único banco SQLCipher, `sinalacs_patient_local.db`. A chave é aleatória (256 bits), está no formato raw (`x'…'`) e chega ao banco por um `LocalDatabaseKeyProvider`. Na Fase 1, o provedor guarda essa chave no `flutter_secure_storage`, embrulhada pelo Keystore. Na Fase 2, um segundo provedor a embrulha com uma chave derivada do PIN por Argon2id (*envelope*). O banco nunca é rechaveado; só muda quem guarda a chave.

Lembretes e consentimentos saem dos dois arquivos SQLite em claro e passam para esse banco, por uma migração idempotente. A falha de leitura da chave ou de abertura do banco **fecha sem apagar**. Só a chave comprovadamente ausente recomeça o banco sozinha; o resto passa pela confirmação do usuário. Depois de recomeçar, o app volta a pedir a autorização de lembretes. O backup do Android fica desligado, inclusive a transferência entre aparelhos.

**Tecnologias:** Flutter, `sqflite_sqlcipher` (resolvido em 3.2.0 no `pubspec.lock`, com `net.zetetic:sqlcipher-android:4.9.0`; já declarado e ainda sem uso no app do paciente), `flutter_secure_storage` ^9.2.2 (mesma versão do ACS), `sqflite_common_ffi` (testes na VM) e `integration_test` (emulador). Na Fase 2, `package:cryptography` ^2.7.0 para o Argon2id, com `cryptography_flutter` como saída nativa.

**Spec:** issue #136. Fontes: `spec/requisitos_piloto.md` (RNF03, RF24, §INV-03 no piloto), `docs/escopo/mudancas-de-codigo-recomendadas.md` (C-04, C-05, C-10, C-11, C-12) e `spec/lgpd_design.md` §0.

**Revisão 2 (2026-11-03):** foram incorporados os pontos 1 a 5 da revisão e as observações menores. Q1, Q2, Q3 e Q5 estão decididas.
**Revisão 3 (2026-11-04):** o `open_failed` ambíguo deixou de apagar (D2d). Respostas do dono incorporadas: residual do pilar B aceito com condições (D3), recusa gravada com reversão fácil (D8 e T5), comentários só depois do merge e com texto aprovado (T9). Ver "Decisões fechadas na revisão 3".

---

## Contexto verificado no repositório (develop, `db0e00b`)

- **`spec/requisitos_piloto.md`**
  - **RNF03** (linha 59): "Criptografia AES-256 em repouso | Essencial". A linha não menciona PIN nem Keystore.
  - **RF24** (linha 51): "Acesso do participante ao acompanhamento por convite QR + PIN local, identificador pseudônimo, sem e-mail, sem CPF e sem SMS no login; recuperação de acesso por novo convite QR [...] invalidando a sessão do aparelho anterior (C-12) | B | Essencial".
  - A §INV-03 no piloto (linhas 72–74) define o evento "Ligar 192" como "**dado de saúde** [...] Fica só no aparelho, cifrado, é apagado automaticamente após **30 dias** [...] e pode ser apagado [...] pela opção 'Apagar meus dados' (C-10)".
- **C-04, C-05, C-10, C-11 e C-12 não estão em `requisitos_piloto.md`.** O texto delas está em `docs/escopo/mudancas-de-codigo-recomendadas.md`:
  - **C-04** (l.18): "grava um evento numa trilha local cifrada de eventos do aparelho (**inexistente hoje**: criar, cifrada, junto com esta mudança)".
  - **C-05** (l.19): "cria a credencial de dispositivo do participante, vinculada ao identificador pseudônimo e protegida pelo PIN local".
  - **C-10** (l.22): "'Apagar meus dados' [...] apaga banco local, lembretes e a trilha local de eventos [...]; expiração automática dos eventos locais de auditoria em 30 dias".
  - **C-11** (l.23): "No pilar A, a autoavaliação roda **localmente**, sem sessão e sem registro no servidor".
  - **C-12** (l.24): "um aparelho perdido que nunca mais se conecta não é alcançado; nele, o que protege os dados é a cifra local (RNF03) com o PIN".
- **`spec/lgpd_design.md` §0** (linha 19): "Os eventos de auditoria e as respostas da autoavaliação **devem** ficar cifrados — meta, não estado atual [...] Os lembretes ficam em SQLite sem cifra, por decisão registrada no código (`sqflite_reminder_store.dart` [...]); reavaliar se o texto passar a aceitar diagnóstico." O §0 ainda não diz nada sobre o limite "celular desbloqueado".
- **Persistência atual do app do paciente.** São dois arquivos SQLite comuns (`sqflite`, com a `databaseFactory` reexportada de `sqflite_common_ffi`):
  - `sinalacs_patient_reminders.db`, tabela `reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL, hour INTEGER NOT NULL, minute INTEGER NOT NULL, active INTEGER NOT NULL)`, em `apps/patient/lib/core/reminders/sqflite_reminder_store.dart`.
  - `sinalacs_patient_consent.db`, tabela `consent_preferences(purpose TEXT PRIMARY KEY, granted INTEGER NOT NULL)`, em `apps/patient/lib/core/consent/sqflite_consent_preferences.dart`.
  - Os dois são instanciados em `apps/patient/lib/app/app.dart:105` e `:109`.
  - A decisão de manter sem cifra está registrada em `sqflite_reminder_store.dart:7-12` ("**sem** SQLCipher: lembretes [...] não são dado de saúde sensível no mesmo grau [...] Reavaliar se o campo de texto livre passar a aceitar diagnóstico") e repetida em `sqflite_consent_preferences.dart:7-9`.
  - O tema fica em `SharedPreferences` (`lib/core/services/theme_controller.dart:21`).
  - O consentimento de lembretes só é coletado no onboarding (`app.dart:836`) e alinhado a partir do servidor em "Meus Dados" (`app.dart:1847-1856`). Sem linha local, `RemindersScreen._load` (`app.dart:2628-2636`) trata como recusa e desativa os lembretes, **sem pedir de novo**.
- **Keystore, secure storage e PIN.** O app do paciente não tem nenhum dos três. O `pubspec.yaml` do paciente declara `sqflite_sqlcipher: ^3.2.0` (linha 24), mas nenhum arquivo de `lib/` o importa. Não há `flutter_secure_storage` nem PIN. O padrão a reaproveitar está no ACS:
  - `apps/acs/lib/core/database/encrypted_database.dart`: SQLCipher e o flag `allowUnencryptedForTesting`.
  - `apps/acs/lib/core/security/database_key_store.dart`: chave no `flutter_secure_storage` com `encryptedSharedPreferences: true`.
  - O `SqlCipherVisitStore` (ver `apps/CLAUDE.md`) só recupera diante do erro de chave errada (`isWrongDatabaseKeyError`: `SQLITE_NOTADB`, ou o `open_failed` em que o `sqflite_sqlcipher` 3.2.0 o transforma no Android), **repetido** depois de `retryDelay`. Qualquer outro erro é relançado sem apagar nada.
  - `apps/acs/integration_test/encrypted_storage_test.dart`: abre com a chave errada e espera falha; arquivo sem texto em claro.
- **Como o plugin passa a chave.** O `Database.java` do `sqflite_sqlcipher` repassa o `password` (String) direto a `net.zetetic…SQLiteDatabase.openDatabase(path, password, …)`, sem citar nem pôr entre aspas. O formato raw `x'<hex>'` chega, portanto, como material de chave ao `sqlite3_key`, onde o SQLCipher o reconhece. Isso ainda precisa ser **provado no emulador** (T7, teste do salt explícito). Com a chave errada, o plugin tenta `PRAGMA cipher_migrate` antes de lançar; registra só o caminho, não a chave.
- **`open_failed` não quer dizer "chave errada" (verificado no 3.2.0).** O `handleException` (`SqfliteSqlCipherPlugin.java:618-632`) responde `open_failed <path>` em três casos: qualquer `SQLiteCantOpenDatabaseException` (permissão, arquivo inacessível, I/O na abertura); qualquer `SQLiteException` cuja mensagem contenha `could not open database` **ou** `file is not a database`; e falha ao criar o diretório (l.785). A mensagem original se perde. O resultado do `cipher_migrate` também não chega ao Dart: quando ele falha, o plugin relança a mesma exceção, que vira o mesmo `open_failed`. **Do lado do Dart não há como separar chave errada de falha de I/O.** O ACS tem a mesma ambiguidade, mas só põe o arquivo de lado; o paciente apagaria. Ver D2 e Fora de escopo.

## Divergências entre a issue e o repositório

1. **Hoje não há dado de saúde no disco do paciente.** A autoavaliação vai ao servidor e o resultado não é gravado localmente. A trilha local de eventos não existe (é da C-04). A C-11 não exige persistir a autoavaliação. O critério "banco com dado de saúde cifrado" é cumprido pela **infraestrutura** e pelos lembretes (D5), não pela autoavaliação. A tabela `local_events` entra na C-04 como migração aditiva v1→v2. **Proposta:** atualizar o texto da issue #136 nesse sentido (T9, só depois de aprovado).
2. **O backup do Android está ligado no paciente.** O `AndroidManifest.xml` do paciente não declara `android:allowBackup`, e o padrão é `true`; o do ACS declara `false`. Com `allowBackup=false` e `targetSdk 36`, a transferência entre aparelhos (Android 12+) continua acontecendo. Por isso também é preciso `dataExtractionRules`. O ACS tem a mesma lacuna; ver Fora de escopo.
3. **O texto do lembrete vaza para fora do banco.** `reminder_scheduler.dart:155-158` passa `reminder.label` como corpo da notificação. O `flutter_local_notifications` guarda as notificações agendadas, com o corpo, nas `SharedPreferences` dele, em claro, e o texto aparece na tela de bloqueio. Resolvido por D7.
4. **O PRD 4.2.3 prescreve PBKDF2 a partir do PIN.** A Fase 2 usa Argon2id (D3); a divergência é registrada no PRD na T10.
5. **A issue cita o limite do pilar A "no app".** Ainda não existe a tela "Sobre" (#125), e "Meus Dados" fica atrás do login, aonde o usuário do pilar A não chega. O texto vai para a **tela de lembretes** (RF06, do pilar A) e também para "Meus Dados", como widget reutilizável que a #125 vai mostrar.
6. **Nem o app nem o §0 podem afirmar como presente uma mitigação que ainda não existe.** A expiração em 30 dias e o "Apagar meus dados" só chegam na C-10 (#131). Na Fase 1, o texto do app descreve só a cifra e o limite. No §0, a mitigação aparece marcada como dependente da C-10.

---

## Decisões (com a alternativa descartada)

| # | Decisão | Por quê | Descartada |
|---|---|---|---|
| D1 | **SQLCipher pelo `sqflite_sqlcipher`**, banco inteiro, com **chave raw** `x'<64 hex>'`. No SQLCipher 4, isso é AES-256-CBC com HMAC-SHA512 por página; com chave raw, o KDF é dispensado. | Já está declarado e é o mesmo do ACS (INV-04). Cifra também os índices, o esquema e o journal. A chave já tem 256 bits aleatórios, então o PBKDF2 de 256 mil iterações do SQLCipher só acrescentaria custo em cada abertura, num aparelho modesto. O plugin repassa o `password` sem citar (verificado no código); a T7 prova no aparelho. | Cifrar campo a campo: cada consulta teria de cifrar e decifrar, índices sobre o texto cifrado não funcionam e o esquema fica em claro. Passphrase com KDF, como no ACS: custo sem ganho de segurança. Se a T7 falhar, voltamos a ela e o registro fica em `PROGRESS.md`. |
| D2 | **Chave aleatória de 256 bits no `flutter_secure_storage`** (`encryptedSharedPreferences: true`), ou seja, embrulhada por uma chave AES do Keystore **sem** exigir autenticação do usuário. **Três desfechos na leitura:** (a) não há chave e não há arquivo: cria a chave. (b) Não há chave e o arquivo existe: `KeyLost`, o arquivo é apagado e o banco recomeça. (c) **A leitura lança: `KeyUnavailable`, falha fechada.** Nesse caso tenta de novo uma vez depois de `retryDelay` (500 ms); se persistir, `open()` lança `LocalDatabaseUnavailableException`, **nada é apagado** e a próxima abertura tenta de novo. O app **nunca** destrói sozinho por falha de leitura; só o usuário pode pedir "Apagar e recomeçar", com confirmação. **(d) Chave presente mas o banco não abre (qualquer erro, `open_failed` incluído): falha fechada também.** O app espera `retryDelay`, tenta mais uma vez e, se falhar de novo, lança `LocalDatabaseUnavailableException` **sem apagar nada**, como em (c). O recomeço **automático** acontece **só** em (b), quando a custódia responde que não há chave. | Uma falha transitória do Keystore ou do EncryptedSharedPreferences (depois de atualização do sistema, em alguns fabricantes, sob pressão de memória) não pode virar perda irreversível de lembretes e do registro de consentimento. O mesmo vale para (d): o `open_failed` do plugin também embrulha permissão, arquivo inacessível e falha de diretório, e a mensagem que distinguiria a chave errada se perde. Com o backup desligado (D6) e a abertura serializada (T3), "chave presente e errada" não tem causa conhecida no paciente; quando acontecer, quem decide apagar é o usuário. Uma chave do Keystore sem exigência de autenticação não é invalidada por mudança do bloqueio de tela. No `KeyLost` comprovado (b), apagar em vez de pôr de lado (como faz o `moveAside` do ACS) é coerente com o pilar A: nenhum dado que não exista em outro lugar, horizonte de 30 dias, e a C-10 pede eliminação. | Tratar qualquer exceção de leitura como `KeyLost` (versão 1 deste plano): apaga dados por falha transitória. Recomeço automático pelo `isWrongDatabaseKeyError` do ACS (versão 2): no 3.2.0 ele aceita o `open_failed` genérico, e uma falha de I/O repetida duas vezes em 500 ms viraria perda de dados. Usar o `cipher_migrate` como segundo sinal: o resultado dele não chega ao Dart. Ler o cabeçalho do arquivo pelo Dart para descartar I/O: só descarta parte dos casos (não cobre bloqueio nem falha no meio da abertura), e o ganho não paga a regra frágil. Destruir automaticamente depois de N falhas: não há N que separe transitório de permanente. `setUserAuthenticationRequired(true)`: o pilar A não tem segredo do usuário. `moveAside`: guarda dado de saúde ilegível sem titular que possa usá-lo. |
| D3 | **Fase 2: envelope.** `KEK = Argon2id(PIN, salt)` com salt aleatório de 16 bytes, m = 19 MiB, t = 2, p = 1 e saída de 32 bytes. A chave do banco é embrulhada com AES-256-GCM sob a KEK. O registro `{versão, salt, nonce, cifrado}` fica no **mesmo `flutter_secure_storage`**, preso ao Keystore. Na transição A→B: grava o envelope, reabre o banco pelo envelope e só então apaga a entrada em claro. **Risco residual (vai para o §0 e vira requisito da C-05):** com o aparelho em mãos **e root**, o atacante lê o envelope e usa a chave do Keystore, que não exige autenticação. Daí a força bruta do PIN fica offline, e o bloqueio por tentativas da C-05 não ajuda. Ordem de grandeza em um núcleo de CPU de mesa a cerca de 50 ms por tentativa: PIN de 4 dígitos (10⁴) cai em **cerca de 8 min**; PIN de 6 dígitos (10⁶), em **cerca de 14 h**, menos com paralelismo. **Requisitos para a C-05: PIN de 6 dígitos ou mais e uma lista curta de PINs proibidos** (um só dígito repetido, como `000000`; sequências crescentes e decrescentes, como `123456` e `987654`; alternância de dois dígitos, como `121212`). Mesmo assim, o PIN apenas encarece o ataque com root; não o impede. **Residual aceito pelo dono em 2026-11-04.** Fundamento: com o aparelho em mãos e root, nenhum segredo guardado pelo app resiste (é o modelo de ameaça padrão de celular). Obter root num aparelho perdido com o bootloader travado não é trivial. E o dano é limitado: os dados do pilar B estão no servidor, a C-12 invalida a sessão e a C-10 expira o que fica local. **Evolução registrada:** usar `setUserAuthenticationRequired` de forma oportunista, quando o aparelho tiver bloqueio de tela. | Não reescreve o banco, então não há perda se o processo cair no meio. O PIN esquecido cai na recuperação da C-12 (os dados do pilar B estão no servidor). Argon2id resiste a GPU melhor que PBKDF2. O `package:cryptography` roda Argon2id em **Dart puro**: se a bancada da T10 passar de 2 s, a saída é o `cryptography_flutter` (implementação nativa), **não** reduzir os parâmetros. | `PRAGMA rekey` para uma chave derivada do PIN: reescreve o arquivo inteiro, e um PIN curto viraria a chave do arquivo, sujeita a força bruta fora do aparelho sem nem precisar do Keystore. PBKDF2 (PRD 4.2.3): mais fraco a igual custo. Chave do Keystore com autenticação e limite de tentativas no hardware (Gatekeeper ou StrongBox): seria a defesa real contra o root, mas depende de bloqueio de tela, que o público do piloto pode não ter; fica como evolução, fora de escopo. |
| D4 | **Migração dos arquivos antigos:** na abertura, se `sinalacs_patient_reminders.db` ou `sinalacs_patient_consent.db` existir, as linhas são copiadas para o banco cifrado numa transação (`INSERT OR REPLACE`, **preservando o `id`** do lembrete, que é o id da notificação agendada). Depois do commit, os arquivos antigos e os laterais (`-journal`, `-wal`, `-shm`) são apagados. Se o processo cair entre o commit e a exclusão, a próxima abertura repete a cópia, o que é idempotente. | Os dados são do titular. Descartá-los desligaria lembretes ativos sem aviso. | Descartar os arquivos antigos. Apagar antes do commit. |
| D5 | **Lembretes e consentimentos passam para o banco cifrado.** | O `label` é texto livre e na prática aceita medicamento ("tomar losartana"); o próprio §0 manda reavaliar nesse caso, e o art. 11 trata isso como dado de saúde. A C-10 precisa apagar tudo num ponto só. O custo marginal é baixo com a infraestrutura pronta. A decisão é registrada no comentário de classe, substituindo `sqflite_reminder_store.dart:7-12`, e no §0. | Manter sem cifra. |
| D6 | **Backup desligado.** `android:allowBackup="false"`, `android:fullBackupContent="false"` (API ≤ 30) e `android:dataExtractionRules="@xml/data_extraction_rules"` (API 31+), excluindo os domínios `root`, `file`, `database`, `sharedpref` e `external` em `<cloud-backup>` e em `<device-transfer>`. | Um backup restaurado leva o arquivo ilegível e o EncryptedSharedPreferences sem a chave do Keystore, que não é transferida. Sem backup, a restauração entrega um app limpo. | Excluir só o banco: frágil a cada nome novo. |
| D7 | **A notificação do lembrete tem corpo genérico:** título "Lembrete SinalACS", corpo "Você tem um lembrete. Abra o SinalACS para ver.". Depois da migração, os lembretes ativos são **reagendados**, para sobrescrever as cópias antigas com o rótulo que ficaram nas `SharedPreferences` do plugin. | Fecha o vazamento (divergência 3) para o disco e para a tela de bloqueio. A mudança é trivial e reversível. | Manter o rótulo e só registrar o limite: mantém o vazamento por omissão. |
| D8 | **Depois do `KeyLost`, a autorização de lembretes é pedida de novo.** Sempre que `localRemindersGranted()` é `null`, a `RemindersScreen` mostra o cartão de coleta ("Autorizo" / "Não autorizo"), em vez de recusar em silêncio. A resposta é gravada localmente. **Com sessão**, também vai ao servidor pelo mesmo caminho de "Meus Dados" (`patients.updateConsent`, `ConsentPurpose.localReminders`), gerando uma linha nova em `consent_logs`. A SnackBar de recuperação cita lembretes **e** autorização. | O registro de consentimento é evidência LGPD. Perder o espelho local sem nova coleta deixa o titular sem saber por que os lembretes pararam. O cartão também corrige o caso já existente do login por OTP sem espelho. | Só avisar. Restaurar do servidor sem perguntar: não há sessão no pilar A. |

---

## Global Constraints

- Idioma: todo comentário, texto de UI e documento em pt-BR.
- Dependências novas só com entrada em `spec/stack.md` **antes** de mudar o `pubspec.yaml`, como na #94. Fase 1: `flutter_secure_storage: ^9.2.2`. Fase 2: `cryptography: ^2.7.0` (e `cryptography_flutter`, se a bancada exigir).
- INV-04/RNF03: fora de Android/iOS, abrir o banco sem o flag `allowUnencryptedForTesting: true` **lança**. O nome do flag é o mesmo do ACS.
- A chave, o PIN, a KEK e o salt nunca aparecem em log, em `toString` de exceção, em `SharedPreferences` comum nem em arquivo fora do `flutter_secure_storage`. As exceções da custódia são descartadas, não embrulhadas.
- O app nunca apaga o banco sozinho por falha de **leitura** da chave (D2c) nem por **erro de abertura** com a chave presente (D2d). O recomeço automático vale só para a chave comprovadamente ausente (D2b).
- `minSdk = 24` e `targetSdk = 36` (`apps/patient/android/app/build.gradle.kts`).
- Nenhuma tela ou fluxo de alerta espera a abertura do banco. O envio do alerta não lê o banco local (INV-03).
- Commits sem atribuição de IA (CLAUDE.md do repositório).

## Review Focus

1. **Falha transitória do Keystore na leitura.** O app mostra o erro, não apaga nada e abre normalmente na tentativa seguinte. Teste em T3: o provedor lança na 1ª abertura e funciona na 2ª; os dados continuam lá.
2. **Duas aberturas concorrentes na inicialização** (lembretes e consentimento ao mesmo tempo). Cada uma geraria uma chave, e a segunda sobrescreveria a primeira. Esperado: uma chave, um `open`. Teste em T3.
3. **Processo morto entre gravar a chave e criar o arquivo.** A ordem é: grava a chave primeiro, depois cria o arquivo. "Arquivo existe e não há chave" é `KeyLost`. Teste em T3.
4. **Processo morto entre o commit da migração e a exclusão dos arquivos antigos.** Nenhum lembrete duplica e nenhum id muda. Teste em T4.
5. **Chave perdida com lembretes agendados e consentimento gravado.** As notificações órfãs são canceladas e o cartão de autorização reaparece. Teste em T5.

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| Criar `apps/patient/lib/core/storage/local_database_key.dart` | `LocalKeyState` (selada), `LocalDatabaseKeyProvider`, `generateRawDatabaseKey()`, `InMemoryDatabaseKeyProvider` |
| Criar `apps/patient/lib/core/storage/keystore_key_provider.dart` | `KeystoreDatabaseKeyProvider` (Fase 1) |
| Criar `apps/patient/lib/core/storage/patient_local_database.dart` | Abre, esquema v1, falha fechada, recuperação de `KeyLost`, serialização, `deleteEverything` |
| Criar `apps/patient/lib/core/storage/legacy_plain_migration.dart` | Copia e apaga os dois arquivos SQLite antigos |
| Modificar `apps/patient/lib/core/reminders/sqflite_reminder_store.dart` e `.../consent/sqflite_consent_preferences.dart` | Passam a usar `PatientLocalDatabase`; nova decisão no comentário |
| Modificar `apps/patient/lib/core/reminders/reminder_scheduler.dart` | `cancelAll()`, corpo genérico (D7) |
| Modificar `apps/patient/lib/app/app.dart` (l.105-109, `RemindersScreen`, `MyDataScreen`) | Ligação, erro de abertura, aviso de recuperação, cartão de autorização, texto do limite |
| Criar `apps/patient/lib/app/local_protection_notice.dart` e `apps/patient/lib/app/reminder_consent_card.dart` | Widgets |
| Modificar `apps/patient/android/app/src/main/AndroidManifest.xml`; criar `.../res/xml/data_extraction_rules.xml` | D6 |
| Modificar `apps/patient/pubspec.yaml`, `spec/stack.md`, `spec/lgpd_design.md` §0, `PROGRESS.md` | Dependência, decisões, estado |
| Testes: `apps/patient/test/storage/*_test.dart`, `test/android_backup_manifest_test.dart`, `test/reminders/*`, `test/local_protection_notice_test.dart`, `integration_test/encrypted_storage_test.dart` | — |

---

# FASE 1: entregável antes da C-05

### Task 1: Dependência e registro na stack

**Files:** `spec/stack.md` e `apps/patient/pubspec.yaml`.

- [ ] **Passo 1:** em `spec/stack.md`, ao lado do parágrafo da #94 (linha ~113), acrescentar:
  > **App do paciente (#136):** `flutter_secure_storage` ^9.2.2, mesma versão e mesmas opções do ACS (`encryptedSharedPreferences: true`), só para guardar a chave raw do banco SQLCipher local; `sqflite_sqlcipher` já estava declarado e passa a ser usado. **Nota:** o `EncryptedSharedPreferences` depende do `androidx.security:security-crypto`, descontinuado pelo Google. A migração (a linha 10 do `flutter_secure_storage` abandona esse modo) deve ser feita **no ACS e no paciente juntos**, com teste de leitura da chave antiga; fica fora da #136.
- [ ] **Passo 2:** acrescentar `flutter_secure_storage: ^9.2.2` ao `pubspec.yaml` do paciente, com um comentário que aponte para `spec/stack.md`.
- [ ] **Passo 3:** `cd apps/patient && flutter pub get && flutter analyze`. Esperado: `No issues found!`
- [ ] **Passo 4:** commit `chore(patient): flutter_secure_storage para a chave do banco local (#136)`.

### Task 2: Interface do provedor de chave e provedor do Keystore

**Files:** criar `lib/core/storage/local_database_key.dart` e `lib/core/storage/keystore_key_provider.dart`. Teste: `test/storage/keystore_key_provider_test.dart`.

**Interfaces (produz):**
```dart
sealed class LocalKeyState {}
final class KeyAvailable extends LocalKeyState { KeyAvailable(this.rawKey); final String rawKey; // "x'<64 hex>'"
  @override String toString() => 'KeyAvailable(<oculta>)'; }
final class KeyLocked extends LocalKeyState {}       // Fase 2: precisa do PIN. Nunca produzido na Fase 1.
final class KeyLost extends LocalKeyState {}         // custódia respondeu "não há chave" para um banco que existe
final class KeyUnavailable extends LocalKeyState {}  // a leitura LANÇOU: transitório até prova em contrário

abstract interface class LocalDatabaseKeyProvider {
  /// Sem banco e sem chave → cria, grava e devolve KeyAvailable.
  /// Com banco e sem chave → KeyLost (não cria). Leitura que lança → KeyUnavailable (não cria, não apaga).
  Future<LocalKeyState> obtain({required bool databaseExists});
  Future<void> destroy();  // apaga a chave e qualquer envelope
}
String generateRawDatabaseKey(); // "x'" + 64 hex de Random.secure() + "'"
class InMemoryDatabaseKeyProvider implements LocalDatabaseKeyProvider { /* contador de obtain, falhas programáveis por chamada */ }
```
`KeystoreDatabaseKeyProvider({FlutterSecureStorage? storage})`, com a chave de armazenamento `'sinalacs.patient.local_database_key'` e as mesmas `AndroidOptions` e `IOSOptions` de `apps/acs/lib/core/security/database_key_store.dart`. A exceção de `read` é **descartada**, não entra em log nem é embrulhada, e vira `KeyUnavailable`. Uma exceção na escrita da chave nova é relançada como `LocalDatabaseUnavailableException`, sem mensagem de origem.

- [ ] **Passo 1: testes que falham.** O `FlutterSecureStorage` é simulado com `FlutterSecureStorage.setMockInitialValues` e, para os casos de exceção, um mock do canal.
  - `'sem banco e sem chave: cria no formato raw e grava'`: o valor casa com `^x'[0-9a-f]{64}'$`, e uma segunda chamada devolve o mesmo.
  - `'banco existe e chave não: KeyLost, sem criar'`.
  - `'leitura que lança vira KeyUnavailable e não escreve nada'`.
  - `'toString não expõe a chave'`.
  - `'destroy apaga'`: depois dele, `obtain(databaseExists: true)` é `KeyLost`.
- [ ] **Passo 2:** `flutter test test/storage/keystore_key_provider_test.dart`. Esperado: FAIL.
- [ ] **Passo 3:** implementar.
- [ ] **Passo 4:** rodar de novo. Esperado: PASS.
- [ ] **Passo 5:** commit `feat(patient): provedor da chave do banco local no Keystore (#136)`.

### Task 3: `PatientLocalDatabase`: abertura cifrada, falha fechada e recuperação de chave perdida

**Files:** criar `lib/core/storage/patient_local_database.dart`. Teste: `test/storage/patient_local_database_test.dart` (VM, `sqflite_common_ffi` com `allowUnencryptedForTesting: true`).

**Interfaces:**
- Consome: `LocalDatabaseKeyProvider` (T2).
- Produz:
```dart
class PatientLocalDatabase {
  PatientLocalDatabase({required LocalDatabaseKeyProvider keys,
      String databaseName = 'sinalacs_patient_local.db',
      bool allowUnencryptedForTesting = false,
      Duration retryDelay = const Duration(milliseconds: 500),
      Future<void> Function()? onKeyLost});   // T5 liga cancelAll das notificações
  static const schemaVersion = 1;            // C-04 sobe para 2 com local_events
  Future<Database> open();                   // single-flight; uma falha NÃO fica memoizada (a próxima chamada tenta de novo)
  bool get recoveredFromLostKey;             // true se esta execução recomeçou o banco
  Future<void> close();
  Future<void> deleteEverything();           // fecha, apaga arquivo + laterais + chave; usado pelo "Apagar e recomeçar" e pela C-10
}
class LocalDatabaseUnavailableException implements Exception {} // sem mensagem de origem
class LocalDatabaseLockedException implements Exception {}      // KeyLocked; tratado na Fase 2
```
**Não** há `isWrongDatabaseKeyError` no paciente: nenhum erro de abertura leva a apagar (D2d).
Esquema v1: `reminders` e `consent_preferences` com as mesmas colunas de hoje. `onDowngrade: onDatabaseDowngradeDelete`. No celular, o banco abre com `sqlcipher.openDatabase(path, password: rawKey, ...)`. Fora do celular sem o flag, lança `UnsupportedError`.

**Fluxo de `open()`:**

- `KeyUnavailable` → espera `retryDelay` e chama `obtain` de novo. Se continuar indisponível, lança `LocalDatabaseUnavailableException` (nada apagado).
- `KeyLost` → recomeça.
- `KeyAvailable` → abre o banco. Se a abertura falhar com **qualquer** erro, espera `retryDelay` e abre de novo. Se falhar outra vez, lança `LocalDatabaseUnavailableException`, sem apagar arquivo nem chave (D2d). O erro de origem é descartado.
- **Recomeçar** (só a partir de `KeyLost`) é, nesta ordem: `deleteDatabase` (arquivo e laterais), `keys.destroy()`, `onKeyLost?.call()` (falha nele é engolida: cancelar notificação nunca impede abrir), `obtain(databaseExists: false)` e `recoveredFromLostKey = true`.

- [ ] **Passo 1: testes que falham.**
  - `'abre, grava, fecha e reabre com a mesma chave: dado persiste'`.
  - `'fora do celular sem o flag: UnsupportedError'`.
  - `'duas aberturas concorrentes: provedor chamado uma vez e mesma instância'` (Review Focus 2).
  - `'arquivo existe e chave sumiu: recomeça vazio, chama onKeyLost, recoveredFromLostKey'` (Review Focus 3).
  - `'leitura da chave lança duas vezes: LocalDatabaseUnavailableException, arquivo e chave intactos'`.
  - `'leitura lança na 1ª abertura e funciona na 2ª: dados preservados'` (Review Focus 1).
  - `'leitura lança uma vez e passa no retry: abre sem erro'`.
  - `'abertura falha duas vezes com chave presente (DatabaseException open_failed simulada): LocalDatabaseUnavailableException, arquivo e chave intactos, onKeyLost não chamado'`. Na VM, a falha é injetada por um `openDatabaseForTesting` que lança `DatabaseException` com a mensagem `open_failed <path>`, a mesma do plugin.
  - `'abertura falha uma vez e passa no retry: abre sem erro'`.
  - `'KeyLocked: LocalDatabaseLockedException, nada apagado'`.
  - `'deleteEverything: sem arquivo, sem chave; próxima abertura cria banco novo'`.
- [ ] **Passo 2:** `flutter test test/storage/patient_local_database_test.dart`. Esperado: FAIL.
- [ ] **Passo 3:** implementar.
- [ ] **Passo 4:** rodar. Esperado: PASS.
- [ ] **Passo 5:** commit `feat(patient): banco local SQLCipher do paciente com falha fechada (#136)`.

### Task 4: Migração dos dois arquivos SQLite em claro

**Files:** criar `lib/core/storage/legacy_plain_migration.dart`, chamada dentro de `PatientLocalDatabase.open()` depois do `onCreate`/`onUpgrade`. Teste: `test/storage/legacy_plain_migration_test.dart`.

**Interfaces:** `Future<bool> migrateLegacyPlainDatabases(Database encrypted, {String remindersName = 'sinalacs_patient_reminders.db', String consentName = 'sinalacs_patient_consent.db'})` devolve `true` se migrou algo; a T5 usa esse retorno para reagendar. A função abre cada arquivo antigo pela `databaseFactory` comum **só se existir**, copia numa transação do banco cifrado com `INSERT OR REPLACE`, preservando `id`, e só **depois** do commit fecha e apaga o arquivo e os laterais. Falha na migração não impede abrir o banco cifrado: é registrada (sem conteúdo) e repetida na próxima abertura, com os arquivos antigos intactos.

- [ ] **Passo 1: testes que falham.**
  - `'copia lembretes com os mesmos ids e consentimento; apaga os antigos'`: os ids 3 e 7 continuam 3 e 7.
  - `'rodar duas vezes (antigo ainda presente) não duplica'` (Review Focus 4).
  - `'sem arquivos antigos: devolve false e não faz nada'`.
  - `'erro no meio da cópia: rollback, antigos intactos'`. **Gatilho:** o esquema antigo tem `label TEXT NOT NULL`, então não dá para semear `label NULL`. O teste cria um arquivo antigo cuja tabela `reminders` **não tem a coluna `hour`** (esquema divergente) e uma linha de consentimento válida. A leitura falha, o banco cifrado fica sem nenhuma linha (inclusive a de consentimento, já que a transação é única) e os dois arquivos antigos continuam lá.
- [ ] **Passo 2:** rodar. Esperado: FAIL.
- [ ] **Passo 3:** implementar.
- [ ] **Passo 4:** rodar. Esperado: PASS.
- [ ] **Passo 5:** commit `feat(patient): migra lembretes e consentimento para o banco cifrado (#136)`.

### Task 5: Lojas sobre o banco cifrado, notificação genérica, erro de abertura e nova coleta da autorização

**Files:**
- `sqflite_reminder_store.dart` e `sqflite_consent_preferences.dart`: construtor `SqfliteReminderStore(this._database)` e `SqfliteConsentPreferences(this._database)`, com `PatientLocalDatabase`; o `_open()` local é removido. O comentário de classe passa a dizer: "Desde a #136, no banco cifrado: o rótulo é texto livre e pode citar medicamento (dado de saúde, art. 11); a C-10 apaga tudo num ponto só."
- `reminder_scheduler.dart`:
  - `Future<void> cancelAll()` na interface e nas implementações, incluindo o duplo.
  - Corpo da notificação constante `reminderNotificationBody = 'Você tem um lembrete. Abra o SinalACS para ver.'` (D7); o `label` não vai mais ao plugin.
  - `Future<void> rescheduleAll(List<Reminder> active)`: `cancelAll()` e depois `schedule` de cada um.
- `app.dart:105-109`: uma única `PatientLocalDatabase(keys: KeystoreDatabaseKeyProvider(), onKeyLost: scheduler.cancelAll)` alimenta as duas lojas. Depois de uma migração que devolveu `true`, chama `rescheduleAll` com os lembretes ativos e com consentimento.
- Criar `lib/app/reminder_consent_card.dart`: `ReminderConsentCard({required Future<void> Function(bool granted) onDecision})`, com os textos "Autorizar lembretes neste aparelho?", "Autorizo" e "Não autorizo". Alvos ≥ 48 dp e `Semantics(liveRegion: true)` no título.
- `RemindersScreen` (`app.dart:2596`):
  - Com `localRemindersGranted() == null`, mostra o `ReminderConsentCard` no topo. `onDecision` grava localmente e, se houver sessão (`BackendScope` com token), chama `patients.updateConsent(localReminders, granted)` pelo mesmo caminho de "Meus Dados". Uma falha no servidor não desfaz a decisão local (o servidor alinha depois, por `_alignLocalRemindersMirror`).
  - Se `recoveredFromLostKey`, mostra uma vez a SnackBar: "Os lembretes e a autorização de lembretes salvos neste aparelho não puderam ser recuperados e foram apagados. Autorize de novo e cadastre seus lembretes."
  - Com `localRemindersGranted() == false`, mostra a ação `Key('reminders_authorize')` "Autorizar lembretes". Ela leva ao mesmo `onDecision(true)` (grava localmente e, com sessão, chama `updateConsent`). Assim a recusa gravada é fácil de reverter, e o cartão não volta a insistir a cada abertura.
  - Diante de `LocalDatabaseUnavailableException`, mostra "Não foi possível abrir os dados deste aparelho agora. Tente de novo.", com os botões `Key('local_db_retry')` "Tentar de novo" e `Key('local_db_reset')` "Apagar e recomeçar". O segundo pede confirmação ("Isso apaga os lembretes e a autorização salvos neste aparelho. Não dá para desfazer.") e chama `deleteEverything()`.
- Testes existentes `test/reminders/sqflite_reminder_store_test.dart` e `test/consent/sqflite_consent_preferences_test.dart` passam a construir `PatientLocalDatabase(keys: InMemoryDatabaseKeyProvider(), allowUnencryptedForTesting: true)`.

- [ ] **Passo 1: testes que falham.**
  - Os testes existentes das duas lojas, adaptados (falham por compilação).
  - `test/reminders/reminder_scheduler_test.dart`: `'corpo da notificação é genérico e não contém o rótulo'` (o duplo do canal registra o corpo, que é igual a `reminderNotificationBody` e não contém `'losartana'`) e `'rescheduleAll cancela tudo e agenda os ativos'`.
  - `'chave perdida cancela todas as notificações agendadas'` (Review Focus 5).
  - Widget, em `test/patient_app_mvp_test.dart`:
    - `'consentimento ausente mostra o cartão; Autorizo grava true e some'`.
    - `'Não autorizo grava false e nenhum lembrete é agendado'`.
    - `'com recusa gravada, o cartão não aparece e "Autorizar lembretes" grava true'`.
    - `'com sessão, a decisão do cartão chama updateConsent(localReminders)'` (`FakePatientBackend` registra a chamada).
    - `'recuperação mostra a SnackBar que cita lembretes e autorização'`.
    - `'banco indisponível: mensagem, Tentar de novo reabre; Apagar e recomeçar exige confirmação e chama deleteEverything'`.
    - `'cancelar a confirmação não apaga nada'`.
- [ ] **Passo 2:** `flutter test`. Esperado: FAIL nos casos novos e adaptados.
- [ ] **Passo 3:** implementar.
- [ ] **Passo 4:** `flutter test && flutter analyze`. Esperado: tudo PASS e `No issues found!`
- [ ] **Passo 5:** commit `feat(patient): lembretes e consentimento cifrados, notificação genérica e nova coleta da autorização (#136)`.

### Task 6: Backup desligado e nenhuma chave fora da custódia

**Files:** `AndroidManifest.xml` (atributos de D6 no `<application>`), criar `android/app/src/main/res/xml/data_extraction_rules.xml`. Teste: `test/android_backup_manifest_test.dart`, no mesmo idioma de `test/android_push_manifest_test.dart`.

- [ ] **Passo 1: testes que falham.**
  - `'allowBackup="false" no <application>'`.
  - `'fullBackupContent="false"'`.
  - `'dataExtractionRules aponta para @xml/data_extraction_rules'`.
  - `'regras excluem root, file, database, sharedpref e external em cloud-backup e device-transfer'` (5×2).
  - `'shared_preferences só é importado por theme_controller.dart'`.
  - `'nenhum print/debugPrint/log em lib/core/storage'`.
  - `'nenhum catch em lib/core/storage interpola a exceção'`: varre por `$e`, `${e` e `e.toString()` dentro de `catch`.
- [ ] **Passo 2:** rodar. Esperado: FAIL.
- [ ] **Passo 3:** implementar.
- [ ] **Passo 4:** rodar, e também `flutter build apk --debug`. Esperado: PASS, e o build aceita o recurso.
- [ ] **Passo 5:** commit `fix(patient): backup e transferência entre aparelhos desligados (#136)`.

### Task 7: Prova no emulador: arquivo cifrado, chave raw, chave errada e persistência

**Files:** criar `apps/patient/integration_test/encrypted_storage_test.dart`, espelhando o do ACS. O nome de banco é próprio do teste.

- [ ] **Passo 1: escrever os testes.**
  - `'chave raw chega crua ao SQLCipher (salt explícito)'`. Cria o banco com `password: "x'<64 hex chave><32 hex salt>'"` (a forma de 96 hex do SQLCipher, que fixa o salt), grava uma linha e fecha. Os **primeiros 16 bytes do arquivo são o salt dado**. Se o plugin tratasse a string como passphrase, o salt do cabeçalho seria aleatório e o teste falharia. **Se falhar:** D1 volta para passphrase (`generateRawDatabaseKey` passa a gerar só o hex), e o registro vai para `PROGRESS.md`.
  - `'arquivo não começa com "SQLite format 3" e não contém o rótulo do lembrete'` (`'losartana-teste-136'`).
  - `'chave errada pelo PatientLocalDatabase: LocalDatabaseUnavailableException, arquivo intacto (mesmos bytes), chave intacta'`. A chave guardada é trocada por outra raw válida antes de abrir.
  - `'open_failed é ambíguo: chave errada e arquivo sem permissão dão o mesmo erro'`. Registra a evidência da D2d: um arquivo com `chmod 000` (`Process.run('chmod', ...)` no próprio processo do app) e outro aberto com a chave errada levam à mesma `DatabaseException` com `open_failed`. Se o aparelho não permitir o `chmod`, o caso é pulado com a razão no log.
  - `'fechar e reabrir com KeystoreDatabaseKeyProvider real mantém o lembrete'`.
  - `'arquivo antigo em claro migra no aparelho e some'`.
  - `'tempo de open() (média de 10) registrado no log do teste'`: só registra, não falha; o número vai para `PROGRESS.md`.
- [ ] **Passo 2:** `cd apps/patient && flutter test integration_test/encrypted_storage_test.dart -d emulator-5554`. Esperado: All tests passed. No emulador ci36, rodar arquivo a arquivo.
- [ ] **Passo 3:** commit `test(patient): cifra do banco local provada no emulador (#136)`.

### Task 8: Limite do pilar A, visível onde o usuário do pilar A chega, e documentado

**Files:** criar `lib/app/local_protection_notice.dart` (`class LocalProtectionNotice extends StatelessWidget`). Inserir no **topo da `RemindersScreen`** (abaixo do cartão de autorização, quando houver) e em `MyDataScreen` (`app.dart:1797`). A #125 ("Sobre") deve reaproveitá-lo, com nota na issue. Modificar `spec/lgpd_design.md` §0 e `PROGRESS.md`. Teste: `test/local_protection_notice_test.dart`.

Texto exato do widget (Fase 1; a C-10 acrescenta a frase da mitigação):
> **Proteção dos dados neste aparelho.** O que o SinalACS guarda neste celular fica cifrado. Isso protege se alguém copiar os arquivos do aparelho, mas não protege de quem usa o seu celular desbloqueado. Não empreste o celular desbloqueado.

- [ ] **Passo 1: testes que falham.**
  - `'RemindersScreen mostra o aviso de proteção local'`.
  - `'MyDataScreen mostra o aviso de proteção local'`.
  - `'o aviso não promete expiração nem apagar'`: o texto não contém "30 dias" nem "Apagar meus dados".
  - O `semantics_scan` e o contraste no padrão de `test/contrast_tokens_test.dart` (token de texto comum, nunca cor clínica).
  - O aviso não estoura a 200% de fonte na `RemindersScreen`.
- [ ] **Passo 2:** rodar. Esperado: FAIL.
- [ ] **Passo 3:** implementar o widget e inseri-lo.
- [ ] **Passo 4:** em `spec/lgpd_design.md` §0, substituir a frase "Os lembretes ficam em SQLite sem cifra [...]" por:
  > Os dados locais do pilar A (lembretes, consentimento local e, a partir da C-04, a trilha de eventos) ficam num único banco SQLCipher (AES-256), com chave aleatória guardada pelo Android Keystore, sem segredo do usuário (#136). O backup e a transferência entre aparelhos estão desligados; a notificação do lembrete não leva o texto do lembrete. Uma falha de leitura da chave ou de abertura do banco não apaga nada; só a chave comprovadamente ausente recomeça o banco vazio, e o app pede de novo a autorização de lembretes. **Limite do pilar A:** protege contra extração do banco (backup, root, ADB, aparelho perdido), não contra quem usa o celular desbloqueado. A mitigação prevista é a expiração em 30 dias e "Apagar meus dados" — **meta, depende da C-10 (#131), ainda não implementada**. **Pilar B (Fase 2 da #136, depende da C-05):** a chave passa a ser liberada pelo PIN (Argon2id, envelope no Keystore). Risco residual: com o aparelho **e root**, a força bruta do PIN fica offline e o bloqueio por tentativas não a impede — um PIN de 4 dígitos cai em minutos, um de 6 em horas; por isso a C-05 exige PIN de **6 dígitos ou mais**, fora de uma lista de PINs triviais, o que encarece o ataque sem impedi-lo. Residual aceito pelo dono do projeto em 2026-11-04: com o aparelho e root, nenhum segredo guardado pelo app resiste; os dados do pilar B estão no servidor, a C-12 invalida a sessão e a C-10 expira o que fica local. Evolução: exigir autenticação do sistema na chave quando o aparelho tiver bloqueio de tela. Depois de C-12, a cifra local é a única proteção de um aparelho perdido que não volta a se conectar.

  Acrescentar também uma seção #136 em `PROGRESS.md`, com o estado das Fases 1 e 2, o resultado da prova de chave raw, o tempo de `open()` e o limite da exclusão dos arquivos antigos no flash.
- [ ] **Passo 5:** `flutter test && flutter analyze`. Esperado: PASS.
- [ ] **Passo 6:** commit `docs(patient): limite da cifra local no app e na LGPD §0 (#136)`.

### Task 9: Verificação final da Fase 1, PR e registros nas issues

- [ ] `cd apps/patient && flutter analyze && flutter test`. Esperado: verde.
- [ ] `./scripts/qa/e2e.sh --emulator` (inclui o smoke do paciente). Esperado: verde.
- [ ] Inspeção manual no emulador: `adb shell run-as <applicationId> ls databases/` mostra só `sinalacs_patient_local.db`. `adb shell run-as <applicationId> cat shared_prefs/*.xml | grep -c losartana` dá 0 depois de reagendar.
- [ ] `graphify update .`
- [ ] Redigir os quatro textos de comentário em `docs/superpowers/plans/2026-11-03-issue-136-comentarios.md` e copiá-los para a descrição da PR, numa seção "Comentários a publicar após o merge". Os textos são em pt-BR e **sem nenhuma atribuição de IA** (CLAUDE.md do repositório):
  - **#128 (C-05):** PIN de 6 dígitos ou mais, a lista de PINs proibidos de D3, o residual aceito e a nota de evolução.
  - **#125 (C-02):** o "Sobre" deve reaproveitar `LocalProtectionNotice` (`apps/patient/lib/app/local_protection_notice.dart`).
  - **#131 (C-10):** chamar `PatientLocalDatabase.deleteEverything()` e acrescentar ao aviso a frase da mitigação (30 dias e "Apagar meus dados").
  - **#136:** a **proposta** de nova redação do critério "banco com dado de saúde cifrado" (divergência 1), como comentário. O corpo da issue não é editado, para preservar o critério original no histórico.
- [ ] Abrir a PR da Fase 1 contra `develop`.
- [ ] **Depois do merge em `develop`** (os comentários citam `LocalProtectionNotice` e `deleteEverything()`, que precisam existir lá) e **depois de o dono aprovar o texto final**: publicar os quatro comentários com `gh issue comment`, exatamente como aprovados.
- [ ] Marcar na #136 os critérios da Fase 1. O critério "chave liberada pelo PIN no pilar B" continua aberto.

---

# FASE 2: bloqueada pela C-05 (#128)

Só começa quando a C-05 definir o fluxo do PIN: tamanho (no mínimo 6 dígitos, D3), tentativas e onde é criado. A interface da T2 já comporta essa fase: `KeyLocked` existe e `PatientLocalDatabase` não muda.

### Task 10: `PinEnvelopeKeyProvider`

**Files:** `spec/stack.md` (`cryptography: ^2.7.0` no app do paciente), `pubspec.yaml`, criar `lib/core/storage/pin_envelope_key_provider.dart`. Testes: `test/storage/pin_envelope_key_provider_test.dart`.

**Interfaces:** `PinEnvelopeKeyProvider implements LocalDatabaseKeyProvider`.
- `obtain` devolve `KeyLocked` sem PIN em memória e `KeyUnavailable` se a leitura do envelope lançar.
- `Future<LocalKeyState> unlock(String pin)` devolve `KeyAvailable` ou lança `WrongPinException`.
- `Future<void> enroll(String pin, {required String currentRawKey})`.
- Envelope em `'sinalacs.patient.local_database_key_envelope'`, no formato JSON `{v:1, salt, nonce, ct}` em base64, com os parâmetros de D3.

- [ ] Testes:
  - `'PIN certo desembrulha a mesma chave'`.
  - `'PIN errado lança WrongPinException sem expor nada'`.
  - `'salt e nonce diferentes a cada enroll'`.
  - `'envelope não contém a chave nem o PIN'`.
  - `'Argon2id com m=19456 KiB, t=2, p=1'`.
  - `'enroll recusa PIN com menos de 6 dígitos'`.
  - `'enroll recusa PINs da lista proibida'` (`000000`, `111111`, `123456`, `987654`, `121212`). É defesa em profundidade: a validação na tela fica na C-05.
- [ ] Bancada no emulador de entrada (API 24): `unlock` abaixo de 2 s. **Se não ficar:** trocar para `cryptography_flutter` (nativo, com entrada em `spec/stack.md`), **sem reduzir os parâmetros**.
- [ ] Registrar no PRD 4.2.3 a divergência PBKDF2 → Argon2id.

### Task 11: Transição A→B sem perda

**Files:** `lib/core/storage/key_custody_transition.dart`. Teste: `test/storage/key_custody_transition_test.dart`.

**Interfaces:** `Future<void> upgradeToPin(PatientLocalDatabase db, KeystoreDatabaseKeyProvider plain, PinEnvelopeKeyProvider pin, String newPin)`. A ordem vem de D3: grava o envelope, fecha, reabre pelo envelope, confere a leitura e só então chama `plain.destroy()`.

- [ ] Testes:
  - `'dados sobrevivem à transição'`.
  - `'falha ao reabrir pelo envelope: entrada em claro preservada, envelope removido'`.
  - `'queda depois do envelope e antes do destroy: próxima abertura usa o envelope e conclui o destroy'`.
- [ ] Teste no emulador acrescentado à T7: `'depois do PIN, a chave em claro não existe mais no secure storage'`.

A tela de PIN e o bloqueio por tentativas ficam na C-05. O PIN esquecido leva à recuperação da C-12; o texto do limite é atualizado então.

---

## Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Falha transitória do Keystore apaga dados | Falha fechada (D2c); nunca há destruição automática por erro de leitura; "Apagar e recomeçar" só com confirmação (T3, T5). |
| Falha de I/O ou de permissão confundida com chave errada (`open_failed` ambíguo no 3.2.0) | Nenhum erro de abertura apaga (D2d); a ambiguidade é provada no emulador (T7); o usuário decide pelo "Apagar e recomeçar". |
| App travado com "não foi possível abrir" de forma permanente | O "Apagar e recomeçar" está sempre disponível nessa tela; os dados perdidos (lembretes, autorização) são recriáveis e a autorização é pedida de novo (D8). |
| Perda de lembretes na migração | Cópia transacional e idempotente; os arquivos antigos só são apagados depois do commit; falha na migração não bloqueia a abertura (T4). |
| Perda silenciosa do consentimento | O cartão de nova coleta e a SnackBar específica (D8, T5). |
| Chave raw tratada como passphrase pelo plugin | Prova determinística pelo salt do cabeçalho (T7); se falhar, volta à passphrase. |
| A exclusão do arquivo antigo não apaga fisicamente o flash | Os arquivos antigos guardavam texto livre de lembrete. Daqui em diante tudo nasce cifrado. Fica registrado em `PROGRESS.md`. |
| Cópias do rótulo nas `SharedPreferences` do plugin de notificação | Corpo genérico e reagendamento depois da migração (D7); conferido na T9. |
| Força bruta offline do PIN com root (Fase 2) | PIN de 6 dígitos ou mais (requisito da C-05) e residual escrito no §0; a defesa real (chave presa a autenticação no hardware) fica fora de escopo. |
| Argon2id em Dart puro lento (Fase 2) | `cryptography_flutter`, sem reduzir os parâmetros (T10). |
| `security-crypto` descontinuado | Nota em `spec/stack.md`; migração conjunta ACS e paciente fora da #136. |

## Fora de escopo

- Cifra em trânsito (RNF04) e qualquer mudança no servidor.
- iOS: as opções do Keychain são copiadas do ACS, sem prova; o piloto é Android.
- A tabela `local_events` e o evento "Ligar 192" (C-04, #127). A expiração em 30 dias e o "Apagar meus dados" (C-10, #131). A autoavaliação local (C-11, #132).
- A tela de PIN, o bloqueio por tentativas e a credencial de dispositivo (C-05, #128). A recuperação de acesso (C-12, #133).
- Chave presa a autenticação no hardware (Gatekeeper ou StrongBox); evolução registrada em D3: usá-la de forma oportunista quando houver bloqueio de tela.
- **O `open_failed` ambíguo no ACS:** o `SqlCipherVisitStore` trata o `open_failed` do 3.2.0 como chave errada e, depois da repetição, põe a fila de visitas de lado com a chave apagada. Uma falha de I/O repetida pode assim tornar ilegíveis visitas não enviadas. Abrir uma issue separada, com a evidência do teste "open_failed é ambíguo" da T7.
- A migração do `flutter_secure_storage` para fora do `EncryptedSharedPreferences` (ACS e paciente juntos).
- **A mesma lacuna de `dataExtractionRules` no app do ACS:** abrir uma issue separada.
- Pacote comum ACS/paciente para o banco cifrado: as políticas diferem.

## Decisões fechadas na revisão 2

- **Q1:** corpo genérico na notificação (D7).
- **Q2:** o aviso aparece na tela de lembretes (pilar A) e em "Meus Dados"; o "Sobre" (#125) reaproveita.
- **Q3:** chave raw (D1), condicionada à prova da T7.
- **Q5:** apagar no `KeyLost` do pilar A, só com a chave comprovadamente ausente (D2b; a revisão 3 retirou a "chave errada repetida").
- **Q4:** parâmetros do Argon2id mantidos; se estourar o tempo, usar implementação nativa, não reduzir.

## Decisões fechadas na revisão 3 (2026-11-04)

- **Recomeço automático só com a chave ausente** (D2d): o `open_failed` do 3.2.0 embrulha permissão, arquivo inacessível e falha de diretório, além da chave errada; qualquer erro de abertura com a chave presente fecha sem apagar.
- **Residual do pilar B aceito** (D3), com estas condições: PIN de 6 dígitos ou mais e lista de PINs proibidos na C-05; residual escrito no §0; nota de evolução para `setUserAuthenticationRequired` oportunista.
- **"Não autorizo" grava a recusa** (D8). É evidência LGPD como a autorização; `null` continua sendo só "nunca perguntado ou recuperado"; não há cartão insistente. A reversão é a ação "Autorizar lembretes" na tela de lembretes (T5).
- **Comentários nas issues** (T9): publicados só depois do merge da Fase 1 em `develop`, com o texto mostrado e aprovado antes, sem atribuição de IA. A nova redação da #136 vai como comentário-proposta, não como edição do corpo.

## Perguntas abertas

Nenhuma bloqueia a Fase 1.
