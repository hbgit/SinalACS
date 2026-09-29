# Direitos do titular no app paciente (LGPD-RF05 / LGPD-RF08) — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa por tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** dar ao paciente, no painel "Meus dados", duas coisas: revogar ou conceder de novo, por conta própria, as finalidades opcionais de consentimento; e registrar pedidos de exclusão e de correção dos próprios dados, acompanhando a situação de cada um.

**Arquitetura:** o backend ganha três RPCs em `PatientsEndpoint` (`updateConsent`, `requestDataDeletion`, `requestDataCorrection`). Elas passam por um serviço novo de aplicação, `DataSubjectRightsService`, com a store por interface, no mesmo padrão de `PatientDataOverviewService`. O consentimento continua append-only em `consent_logs` (linha nova assinada, nunca edição). Os pedidos vão para a tabela nova `data_subject_requests`, com o texto livre cifrado (AES-256-GCM, mesmo `HealthDataCipher` de `visits.notes`). `patients.myData` passa a devolver também os pedidos. No app, `MyDataScreen` ganha os interruptores de consentimento e a seção de pedidos. O espelho local de consentimento de lembretes (`ConsentPreferences`) passa a ser alinhado ao servidor cada vez que "Meus dados" carrega.

**Stack:** Serverpod 3.4.13 (Dart), Postgres 15, Flutter (Material 3), `sinalacs_client` gerado.

**Spec:** [spec/lgpd_design.md](../../../spec/lgpd_design.md) — LGPD-RF05 (linhas 102-111), LGPD-RF07 (124-133), LGPD-RF08 (136-140) e a tabela de direitos do Art. 18 (linhas 581-610). Invariantes em [CLAUDE.md](../../../CLAUDE.md) e [spec/PRD_system.md](../../../spec/PRD_system.md).

## Fora do escopo (decisão do usuário, 2026-09-28)

- **Atender os pedidos.** Nesta versão ninguém muda `status` de `open` para `completed`/`rejected`: o backoffice (`apps/admin`) ainda roda sobre `MockAdminDataSource`. O pedido fica registrado e visível ao titular. O atendimento é trabalho futuro e vai registrado no `PROGRESS.md` (Tarefa 7).
- **Revogar `healthDataProcessing` por interruptor.** Essa finalidade é a base legal de tudo, inclusive do botão de emergência, e revogá-la exige a exclusão em até 15 dias (LGPD-RF07). Cortar o tratamento no meio de um alerta violaria "alerta vermelho nunca é descartado em silêncio". Por isso o caminho é o pedido de exclusão, e a RPC recusa essa finalidade com mensagem que aponta para ele.
- Edição direta do contato de emergência, leitura de QR no onboarding (RF02) e modo claro (RF18): não foram escolhidos nesta rodada.

## Restrições globais

- Texto de UI, comentários e mensagens em **português**, no tom do código ao redor.
- `patientId` / `userId` vêm **sempre** do token (`user.id`), nunca de parâmetro (INV-05, mesmo raciocínio de `triage.evaluate`).
- `Authorization.require(user, roles: {UserRole.patient}, onDenied: ..., requireMicroArea: false)` em toda operação do titular: o escopo é o próprio titular, não o território.
- `consent_logs` é append-only: revogar grava linha nova `action: 'denied'`, e nada é atualizado nem apagado.
- Versão do termo: `consentPolicyVersion` (`'2026.1'`, em `onboarding_service.dart`). Não criar literal novo.
- Prazo de resposta a pedido do titular: **15 dias** (`spec/lgpd_design.md`, linhas 597-599).
- Texto livre do pedido de correção: no máximo **500** caracteres depois de `trim()`. Nunca vazio. Nunca vai para `audit_logs` nem para log de processo.
- Nenhum dado real de paciente em teste, seed ou log: só os UUIDs sintéticos `00000000-0000-4000-8000-00000000000N` já usados.
- Nunca editar à mão `lib/src/generated/`, `backend/sinalacs_client/lib/src/protocol/` nem `migrations/`. Rodar `serverpod generate` e `serverpod create-migration`.
- Cor de clínica usada como texto: só os tokens `*OnSurface` de `PatientColors` (ver `apps/CLAUDE.md`).
- Todo `Text` de erro ou confirmação dinâmico vai dentro de `Semantics(liveRegion: true)` (SC 4.1.3), como os que já existem em `MyDataScreen`.

## Review Focus

1. **Segundo pedido de correção com outro ainda aberto:** precisa gravar um pedido **novo**. Devolver o antigo descartaria em silêncio o texto que a pessoa acabou de escrever. Teste: Tarefa 2 (serviço) e Tarefa 6 (botão continua habilitado).
2. **Toque duplo ou pedido de exclusão repetido:** tem de resultar em exatamente **um** pedido aberto. O servidor é idempotente para exclusão, e o botão fica desabilitado com o pedido em voo. Teste: Tarefa 2 e Tarefa 6.
3. **Revogar lembretes com lembrete já agendado:** a notificação tem de parar **na hora**, não só quando a pessoa abrir "Lembretes". Teste: Tarefa 5 (`scheduler.cancelled` contém o id e o store guarda `active: false`).
4. **Texto de correção só com espaços, ou com mais de 500 caracteres:** o servidor recusa com mensagem clara, e o app nem habilita o envio para texto vazio. Teste: Tarefa 2 e Tarefa 6.
5. **Aparelho que entrou pelo login OTP (RF01) sem passar pelo onboarding:** esse aparelho não tem espelho local. Abrir "Meus dados" alinha o espelho à decisão do servidor, e uma recusa vinda do servidor cancela os lembretes ativos. Teste: Tarefa 5.

---

## Mapa de arquivos

**Backend (`backend/sinalacs_server/`)**
- Criar `lib/src/models/enums/data_subject_request_type.spy.yaml` — enum `deletion | correction`.
- Criar `lib/src/models/enums/data_subject_request_status.spy.yaml` — enum `open | completed | rejected`.
- Criar `lib/src/models/data_subject_request.spy.yaml` — tabela `data_subject_requests`.
- Criar `lib/src/models/api/patient_data_subject_request_record.spy.yaml` — DTO para o app.
- Criar `lib/src/models/exceptions/data_rights_exception.spy.yaml` — recusa de negócio tipada.
- Modificar `lib/src/models/api/patient_data_overview.spy.yaml` — campo `requests`.
- Criar `lib/src/infrastructure/database/signed_consent_log.dart` — montagem única da linha assinada de `consent_logs`.
- Modificar `lib/src/infrastructure/database/orm_onboarding_store.dart` — passa a usar a função acima.
- Modificar `lib/src/application/patients/patient_data_overview_service.dart` — `DataSubjectRequestSnapshot` e `PatientDataSnapshot.requests`.
- Criar `lib/src/application/patients/data_subject_rights_service.dart` — regras de LGPD-RF05/RF08.
- Criar `lib/src/infrastructure/database/orm_data_subject_rights_store.dart` — ORM + cifra.
- Modificar `lib/src/infrastructure/database/orm_patient_data_overview_store.dart` — carrega os pedidos.
- Modificar `lib/src/runtime/alert_runtime.dart` — `dataSubjectRightsServiceFor`.
- Modificar `lib/src/endpoints/patients_endpoint.dart` — três RPCs e o mapeamento de `requests`.
- Testes: `test/unit/signed_consent_log_test.dart`, `test/unit/data_subject_rights_service_test.dart`, `test/integration/data_subject_rights_endpoint_test.dart`.

**App (`apps/patient/`)**
- Modificar `lib/core/network/backend_client.dart` — três métodos em `PatientBackend`, `MisconfiguredBackend` e `BackendClient`, mais a cláusula `DataRightsException` em `_guard`.
- Criar `lib/core/consent/consent_decisions.dart` — decisão vigente por finalidade e rótulos.
- Modificar `lib/app/app.dart` — `deactivateAllReminders`, `MyDataScreen` (consentimentos e pedidos), `_CorrectionRequestDialog`, mensagem de recusa em `RemindersScreen`.
- Modificar `test/support/fake_patient_backend.dart`, `test/support/fake_rpc_server.dart`, `test/patient_app_mvp_test.dart`.
- Criar `test/consent_decisions_test.dart`, `test/backend_client_data_rights_test.dart`.

**Docs:** `spec/lgpd_data_audit.md`, `backend/CLAUDE.md`, `CLAUDE.md`, `PROGRESS.md`.

## Pré-requisitos do ambiente

```bash
./scripts/dev/bootstrap_env.sh                    # só se .env / config/passwords.yaml não existirem
docker compose --profile test up -d postgres-test # Postgres de teste em localhost:9090
```

---

### Tarefa 1: Schema, contrato e a linha de consentimento assinada num lugar só

**Arquivos:**
- Criar: os cinco `.spy.yaml` listados no mapa
- Modificar: `lib/src/models/api/patient_data_overview.spy.yaml`
- Criar: `lib/src/infrastructure/database/signed_consent_log.dart`
- Modificar: `lib/src/infrastructure/database/orm_onboarding_store.dart` (método `recordConsent`)
- Modificar: `lib/src/application/patients/patient_data_overview_service.dart`
- Modificar: `lib/src/endpoints/patients_endpoint.dart` (método `myData`)
- Modificar: `apps/patient/test/support/fake_patient_backend.dart`, `apps/patient/test/patient_app_mvp_test.dart` (helper `overview`)
- Modificar: `spec/lgpd_data_audit.md`
- Teste: `test/unit/signed_consent_log_test.dart`

**Interfaces:**
- Produz (gerado, servidor e cliente): `enum DataSubjectRequestType { deletion, correction }`, `enum DataSubjectRequestStatus { open, completed, rejected }`, `class DataSubjectRequest` (tabela), `class PatientDataSubjectRequestRecord { DataSubjectRequestType type; DataSubjectRequestStatus status; String? details; DateTime createdAt; DateTime dueAt; }`, `class DataRightsException { String message; }`, `PatientDataOverview.requests: List<PatientDataSubjectRequestRecord>`.
- Produz: `ConsentLog signedConsentLog(ConsentLogEntry entry, {required ConsentSignature signature, required String origin})`.
- Produz: `class DataSubjectRequestSnapshot { String id; DataSubjectRequestType type; DataSubjectRequestStatus status; String? details; DateTime createdAt; DateTime dueAt; }` e `PatientDataSnapshot.requests` (padrão `const []`).

- [ ] **Passo 1: Escrever o teste da linha assinada (falha: a função não existe)**

`backend/sinalacs_server/test/unit/signed_consent_log_test.dart`:

```dart
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/signed_consent_log.dart';
import 'package:test/test.dart';

void main() {
  final signature = ConsentSignature(secret: 'segredo-de-teste');
  final entry = ConsentLogEntry(
    userId: '00000000-0000-4000-8000-000000000001',
    purpose: ConsentPurpose.localReminders,
    action: 'denied',
    version: '2026.1',
    timestamp: DateTime.utc(2026, 9, 28, 12),
  );

  test('assina exatamente os campos que ConsentSignature.compute recebe', () {
    final row = signedConsentLog(entry, signature: signature, origin: 'painel-titular');

    expect(
      row.signature,
      signature.compute(
        userId: entry.userId,
        purpose: 'localReminders',
        action: 'denied',
        version: '2026.1',
        timestamp: entry.timestamp,
      ),
    );
    expect(row.userId.uuid, entry.userId);
    expect(row.purpose, 'localReminders');
    expect(row.action, 'denied');
    expect(row.version, '2026.1');
    expect(row.timestamp, entry.timestamp);
  });

  test('ipHash e userAgent levam o marcador de ausência com a origem do evento', () {
    final onboarding = signedConsentLog(entry, signature: signature, origin: 'onboarding');
    expect(onboarding.ipHash, 'nao-aplicavel-onboarding');
    expect(onboarding.userAgent, 'nao-aplicavel-onboarding');

    final painel = signedConsentLog(entry, signature: signature, origin: 'painel-titular');
    expect(painel.ipHash, 'nao-aplicavel-painel-titular');
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/signed_consent_log_test.dart`
Expected: FAIL na compilação (`signed_consent_log.dart` não existe).

- [ ] **Passo 3: Criar os modelos**

`lib/src/models/enums/data_subject_request_type.spy.yaml`:

```yaml
### Tipo de pedido do titular sobre os próprios dados (LGPD-RF08, Art. 18):
### exclusão/anonimização ou correção. Ver spec/lgpd_design.md linhas 583-597.
enum: DataSubjectRequestType
serialized: byName
values:
  - deletion
  - correction
```

`lib/src/models/enums/data_subject_request_status.spy.yaml`:

```yaml
### Situação de um pedido do titular. Nesta versão só `open` tem escritor:
### quem atende o pedido (backoffice) ainda não existe — ver PROGRESS.md.
enum: DataSubjectRequestStatus
serialized: byName
values:
  - open
  - completed
  - rejected
```

`lib/src/models/data_subject_request.spy.yaml`:

```yaml
### Pedido do titular sobre os próprios dados (LGPD-RF08): exclusão ou
### correção, com prazo de resposta de 15 dias (spec/lgpd_design.md 596-597).
###
### `details` é texto livre do titular e pode citar condição de saúde — por
### isso é cifrado na aplicação (AES-256-GCM), pelo mesmo motivo e com o
### mesmo `HealthDataCipher` de `visits.notes` (RNF03/INV-04). Num pedido de
### exclusão guarda o JSON `null` cifrado.
class: DataSubjectRequest
table: data_subject_requests
fields:
  id: UuidValue?, defaultPersist=random
  userId: UuidValue, relation(parent=users)
  requestType: DataSubjectRequestType
  detailsEncrypted: String
  detailsKeyVersion: int
  status: DataSubjectRequestStatus
  createdAt: DateTime
  ### Prazo de resposta: `createdAt` + 15 dias.
  dueAt: DateTime
indexes:
  data_subject_requests_user_id_type_idx:
    fields: userId, requestType
```

`lib/src/models/api/patient_data_subject_request_record.spy.yaml`:

```yaml
### Um pedido do próprio titular, para o painel "Meus Dados". `details` já
### decifrado — é texto que o próprio titular escreveu (direito de acesso).
class: PatientDataSubjectRequestRecord
fields:
  type: DataSubjectRequestType
  status: DataSubjectRequestStatus
  details: String?
  createdAt: DateTime
  dueAt: DateTime
```

`lib/src/models/exceptions/data_rights_exception.spy.yaml`:

```yaml
### Recusa de negócio de uma operação do titular sobre os próprios dados
### (consentimento obrigatório, texto de correção vazio ou longo demais).
### Mensagem pronta para a pessoa ler; nunca cita dado do paciente.
exception: DataRightsException
fields:
  message: String
```

Em `lib/src/models/api/patient_data_overview.spy.yaml`, acrescentar ao fim de `fields:`:

```yaml
  requests: List<PatientDataSubjectRequestRecord>
```

- [ ] **Passo 4: Gerar código e migração**

Run: `cd backend/sinalacs_server && serverpod generate && serverpod create-migration`
Expected: um diretório novo em `migrations/`, cujo `migration.sql` contém `CREATE TABLE "data_subject_requests"`, sem nenhum `DROP`. Se aparecer `DROP`, pare: algo foi alterado além do previsto.

- [ ] **Passo 5: Criar `signed_consent_log.dart`**

`lib/src/infrastructure/database/signed_consent_log.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry;
import 'package:sinalacs_server/src/generated/protocol.dart';

/// A linha de `consent_logs` de [entry], assinada por [signature].
///
/// Há dois escritores de consentimento — a conclusão do onboarding e o painel
/// "Meus Dados" (LGPD-RF05) — e os dois gravam a mesma forma de linha. Esta
/// função é o único lugar que a define, para que a assinatura e os campos não
/// divirjam entre eles.
///
/// IP e user agent não se aplicam a nenhum dos dois eventos de domínio — o
/// request HTTP em si já é auditado em `audit_logs` por outros caminhos —, então
/// os campos exigidos pelo schema levam um marcador explícito de ausência com a
/// [origin] do evento, não um valor fabricado.
ConsentLog signedConsentLog(
  ConsentLogEntry entry, {
  required ConsentSignature signature,
  required String origin,
}) {
  final marker = 'nao-aplicavel-$origin';
  return ConsentLog(
    userId: UuidValue.fromString(entry.userId),
    purpose: entry.purpose.name,
    action: entry.action,
    version: entry.version,
    timestamp: entry.timestamp,
    ipHash: marker,
    userAgent: marker,
    signature: signature.compute(
      userId: entry.userId,
      purpose: entry.purpose.name,
      action: entry.action,
      version: entry.version,
      timestamp: entry.timestamp,
    ),
  );
}
```

Em `orm_onboarding_store.dart`, trocar o corpo inteiro de `recordConsent` por:

```dart
  @override
  Future<void> recordConsent(ConsentLogEntry entry) async {
    await ConsentLog.db.insertRow(
      _session(),
      signedConsentLog(entry, signature: _signature, origin: 'onboarding'),
      transaction: _transaction,
    );
  }
```

e acrescentar o import `package:sinalacs_server/src/infrastructure/database/signed_consent_log.dart`. O valor gravado continua `'nao-aplicavel-onboarding'`, idêntico ao de antes.

- [ ] **Passo 6: Snapshot dos pedidos no serviço de "Meus Dados"**

Em `lib/src/application/patients/patient_data_overview_service.dart`, logo depois da classe `RiskEventSnapshot`:

```dart
/// Um pedido do próprio titular (LGPD-RF08: exclusão ou correção), do jeito
/// que a store enxerga — `details` já decifrado.
class DataSubjectRequestSnapshot {
  const DataSubjectRequestSnapshot({
    required this.id,
    required this.type,
    required this.status,
    required this.details,
    required this.createdAt,
    required this.dueAt,
  });

  final String id;
  final DataSubjectRequestType type;
  final DataSubjectRequestStatus status;

  /// Texto do pedido de correção; `null` num pedido de exclusão.
  final String? details;
  final DateTime createdAt;
  final DateTime dueAt;
}
```

Em `PatientDataSnapshot`, acrescentar ao construtor `this.requests = const [],` e o campo:

```dart
  /// Mais recente primeiro.
  final List<DataSubjectRequestSnapshot> requests;
```

- [ ] **Passo 7: Mapear `requests` em `patients.myData`**

Em `patients_endpoint.dart`, acrescentar o import `package:sinalacs_server/src/application/patients/patient_data_overview_service.dart` e, no `PatientDataOverview(...)` de `myData`, depois de `riskHistory: [...]`:

```dart
        requests: [for (final r in snapshot.requests) _requestRecord(r)],
```

No fim da classe:

```dart
  static PatientDataSubjectRequestRecord _requestRecord(DataSubjectRequestSnapshot r) =>
      PatientDataSubjectRequestRecord(
        type: r.type,
        status: r.status,
        details: r.details,
        createdAt: r.createdAt,
        dueAt: r.dueAt,
      );
```

- [ ] **Passo 8: Manter o app compilando com o campo novo obrigatório**

Em `apps/patient/test/support/fake_patient_backend.dart`, no valor padrão de `myDataResult`, acrescentar `requests: const [],` depois de `riskHistory: const [],`.

Em `apps/patient/test/patient_app_mvp_test.dart`, no helper `overview` do grupo `'Meus dados (LGPD)'`, trocar a assinatura e o corpo por:

```dart
    PatientDataOverview overview({
      List<PatientConsentRecord> consents = const [],
      List<PatientRiskEvent> riskHistory = const [],
      List<PatientDataSubjectRequestRecord> requests = const [],
    }) =>
        PatientDataOverview(
          name: 'Fulano de Tal',
          birthDate: DateTime.utc(1975, 3, 10),
          emergencyContact: 'Ciclana, (11) 90000-0000',
          isChronic: true,
          chronicConditions: const ['hipertensão'],
          consents: consents,
          riskHistory: riskHistory,
          requests: requests,
        );
```

Rode `grep -rn "PatientDataOverview(" apps/ backend/sinalacs_server/test` e acrescente `requests: const []` a qualquer outra construção que aparecer.

- [ ] **Passo 9: Classificar a tabela nova em `spec/lgpd_data_audit.md`**

Inserir imediatamente antes da linha que começa com `| **audit_logs** |`:

```markdown
| **data_subject_requests** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador do pedido do titular (LGPD-RF08). |
| | `userId` | `uuid` | Pseudonimizado | Chave estrangeira (`users.id`) | Titular que fez o pedido — sempre o do token, nunca parâmetro (INV-05). |
| | `requestType` | `text` | Metadado de Conformidade | `deletion` \| `correction` | — |
| | `detailsEncrypted` / `detailsKeyVersion` | `text` / `bigint` | Potencialmente Sensível (texto livre do titular) | AES-256-GCM na aplicação, mesma `HEALTH_DATA_ENCRYPTION_KEY` do §2.3 | O pedido de correção é texto livre e pode citar condição de saúde; cifrado pelo mesmo motivo de `visits.notes`. Num pedido de exclusão guarda o JSON `null` cifrado. Nunca copiado para `audit_logs`. |
| | `status` | `text` | Metadado de Conformidade | `open` \| `completed` \| `rejected` | Só `open` tem escritor nesta versão — quem atende o pedido (backoffice) ainda não existe (ver `PROGRESS.md`). |
| | `createdAt` / `dueAt` | `timestamp without time zone` | Metadado de Conformidade | `dueAt` = `createdAt` + 15 dias | Prazo de resposta do Art. 18 (spec/lgpd_design.md, linhas 596-597). |
```

Na linha de `consent_logs` que descreve `ipHash`, acrescentar ao fim da última coluna: ` Linhas gravadas pelo painel "Meus Dados" (LGPD-RF05) usam o marcador \`nao-aplicavel-painel-titular\`.`

- [ ] **Passo 10: Rodar tudo**

Run:
```bash
cd backend/sinalacs_server && dart analyze && dart test
cd ../../apps/patient && flutter analyze && flutter test
cd ../acs && flutter analyze
```
Expected: tudo verde. O teste novo passa, e `test/integration/onboarding_endpoint_test.dart` continua passando com o marcador de onboarding inalterado. O app ACS depende do mesmo `sinalacs_client` e tem de continuar compilando.

- [ ] **Passo 11: Commit**

```bash
git add backend/sinalacs_server/lib/src/models backend/sinalacs_server/lib/src/generated \
  backend/sinalacs_client backend/sinalacs_server/migrations \
  backend/sinalacs_server/lib/src/infrastructure/database/signed_consent_log.dart \
  backend/sinalacs_server/lib/src/infrastructure/database/orm_onboarding_store.dart \
  backend/sinalacs_server/lib/src/application/patients/patient_data_overview_service.dart \
  backend/sinalacs_server/lib/src/endpoints/patients_endpoint.dart \
  backend/sinalacs_server/test/unit/signed_consent_log_test.dart \
  backend/sinalacs_server/test/integration/test_tools \
  apps/patient/test spec/lgpd_data_audit.md
git commit -m "feat(lgpd): schema de pedidos do titular e linha de consentimento assinada num lugar só"
```

---

### Tarefa 2: `DataSubjectRightsService` — regras de LGPD-RF05 e RF08

**Arquivos:**
- Criar: `backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart`
- Teste: `backend/sinalacs_server/test/unit/data_subject_rights_service_test.dart`

**Interfaces:**
- Consome: `ConsentLogEntry`, `consentPolicyVersion` (`onboarding_service.dart`); `ConsentRecordSnapshot`, `DataSubjectRequestSnapshot` (`patient_data_overview_service.dart`); `AuditTrail`, `AuditEvent`; `Authorization.require`; `DataRightsException` (gerado).
- Produz:
  - `abstract interface class DataSubjectRightsStore { Future<void> recordConsent(ConsentLogEntry entry); Future<DataSubjectRequestSnapshot?> findOpenRequest(String userId, DataSubjectRequestType type); Future<DataSubjectRequestSnapshot> createRequest({required String userId, required DataSubjectRequestType type, required String? details, required DateTime createdAt, required DateTime dueAt}); }`
  - `const Duration dataSubjectRequestDeadline = Duration(days: 15);`
  - `const int correctionDetailsMaxLength = 500;`
  - `class DataSubjectRightsService({required DataSubjectRightsStore store, required AuditTrail audit, DateTime Function()? clock})` com `Future<ConsentRecordSnapshot> updateConsent(AuthenticatedUser user, {required ConsentPurpose purpose, required bool granted})`, `Future<DataSubjectRequestSnapshot> requestDeletion(AuthenticatedUser user)` e `Future<DataSubjectRequestSnapshot> requestCorrection(AuthenticatedUser user, {required String details})`.
  - Recusa de papel: `StateError`. Recusa de negócio: `DataRightsException`.

- [ ] **Passo 1: Escrever os testes (falham: o serviço não existe)**

`test/unit/data_subject_rights_service_test.dart`:

```dart
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/application/patients/data_subject_rights_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _patientId = '00000000-0000-4000-8000-000000000001';
const _microAreaId = '00000000-0000-4000-8000-000000000003';

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

const _acs = AuthenticatedUser(
  id: '00000000-0000-4000-8000-000000000002',
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

final _now = DateTime.utc(2026, 9, 28, 12);

class FakeDataSubjectRightsStore implements DataSubjectRightsStore {
  final consents = <ConsentLogEntry>[];
  final requests = <({String userId, DataSubjectRequestSnapshot snapshot})>[];
  var _nextId = 1;

  @override
  Future<void> recordConsent(ConsentLogEntry entry) async => consents.add(entry);

  @override
  Future<DataSubjectRequestSnapshot?> findOpenRequest(
    String userId,
    DataSubjectRequestType type,
  ) async {
    for (final r in requests.reversed) {
      if (r.userId == userId &&
          r.snapshot.type == type &&
          r.snapshot.status == DataSubjectRequestStatus.open) {
        return r.snapshot;
      }
    }
    return null;
  }

  @override
  Future<DataSubjectRequestSnapshot> createRequest({
    required String userId,
    required DataSubjectRequestType type,
    required String? details,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    final snapshot = DataSubjectRequestSnapshot(
      id: 'pedido-${_nextId++}',
      type: type,
      status: DataSubjectRequestStatus.open,
      details: details,
      createdAt: createdAt,
      dueAt: dueAt,
    );
    requests.add((userId: userId, snapshot: snapshot));
    return snapshot;
  }
}

class FakeAuditTrail extends AuditTrail {
  FakeAuditTrail({this.failOnRecord = false});

  final bool failOnRecord;
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async {
    if (failOnRecord) throw StateError('trilha de auditoria fora do ar');
    events.add(event);
  }
}

void main() {
  late FakeDataSubjectRightsStore store;
  late FakeAuditTrail audit;
  late DataSubjectRightsService service;

  setUp(() {
    store = FakeDataSubjectRightsStore();
    audit = FakeAuditTrail();
    service = DataSubjectRightsService(store: store, audit: audit, clock: () => _now);
  });

  group('updateConsent (LGPD-RF05)', () {
    test('revogar grava uma linha nova "denied", com a versão vigente e o relógio do servidor', () async {
      final record = await service.updateConsent(
        _patient,
        purpose: ConsentPurpose.localReminders,
        granted: false,
      );

      final entry = store.consents.single;
      expect(entry.userId, _patientId);
      expect(entry.purpose, ConsentPurpose.localReminders);
      expect(entry.action, 'denied');
      expect(entry.version, consentPolicyVersion);
      expect(entry.timestamp, _now);

      expect(record.purpose, 'localReminders');
      expect(record.action, 'denied');
      expect(record.timestamp, _now);
    });

    test('conceder de novo grava "granted"', () async {
      await service.updateConsent(_patient, purpose: ConsentPurpose.segmentedPush, granted: true);

      expect(store.consents.single.action, 'granted');
    });

    test('recusa mexer no consentimento obrigatório, em qualquer direção, sem gravar nada', () async {
      for (final granted in [false, true]) {
        await expectLater(
          service.updateConsent(
            _patient,
            purpose: ConsentPurpose.healthDataProcessing,
            granted: granted,
          ),
          throwsA(isA<DataRightsException>()),
        );
      }
      expect(store.consents, isEmpty);
      expect(audit.events, isEmpty);
    });

    test('um ACS não altera consentimento de ninguém', () async {
      await expectLater(
        service.updateConsent(_acs, purpose: ConsentPurpose.localReminders, granted: false),
        throwsA(isA<StateError>()),
      );
      expect(store.consents, isEmpty);
    });

    test('grava uma linha de escrita em audit_logs', () async {
      await service.updateConsent(_patient, purpose: ConsentPurpose.localReminders, granted: false);

      final event = audit.events.single;
      expect(event.userId, _patientId);
      expect(event.actionType, 'write');
      expect(event.resourceType, 'consent_log');
      expect(event.result, 'granted');
    });

    test('não exige microárea: o escopo é o próprio titular', () async {
      const semArea = AuthenticatedUser(
        id: _patientId,
        role: UserRole.patient,
        microAreaId: null,
        deviceId: 'patient-device-001',
      );

      await service.updateConsent(semArea, purpose: ConsentPurpose.localReminders, granted: true);
      expect(store.consents, hasLength(1));
    });
  });

  group('requestDeletion (LGPD-RF08)', () {
    test('abre um pedido em análise com prazo de 15 dias', () async {
      final request = await service.requestDeletion(_patient);

      expect(request.type, DataSubjectRequestType.deletion);
      expect(request.status, DataSubjectRequestStatus.open);
      expect(request.details, isNull);
      expect(request.createdAt, _now);
      expect(request.dueAt, _now.add(const Duration(days: 15)));
      expect(store.requests.single.userId, _patientId);
    });

    test('pedir de novo com um pedido aberto devolve o mesmo, sem duplicar', () async {
      final first = await service.requestDeletion(_patient);
      final second = await service.requestDeletion(_patient);

      expect(second.id, first.id);
      expect(store.requests, hasLength(1));
      expect(audit.events, hasLength(1));
    });

    test('o pedido novo vai para audit_logs com o id do pedido', () async {
      final request = await service.requestDeletion(_patient);

      final event = audit.events.single;
      expect(event.actionType, 'write');
      expect(event.resourceType, 'data_subject_request');
      expect(event.resourceId, request.id);
      expect(event.result, 'granted');
    });

    test('um ACS não pede exclusão em nome de ninguém', () async {
      await expectLater(service.requestDeletion(_acs), throwsA(isA<StateError>()));
      expect(store.requests, isEmpty);
    });

    test('uma trilha de auditoria fora do ar não impede o pedido', () async {
      service = DataSubjectRightsService(
        store: store,
        audit: FakeAuditTrail(failOnRecord: true),
        clock: () => _now,
      );

      final request = await service.requestDeletion(_patient);
      expect(request.status, DataSubjectRequestStatus.open);
    });
  });

  group('requestCorrection (LGPD-RF08)', () {
    test('grava o texto sem os espaços das pontas', () async {
      final request = await service.requestCorrection(
        _patient,
        details: '  Meu contato de emergência mudou.  ',
      );

      expect(request.type, DataSubjectRequestType.correction);
      expect(request.details, 'Meu contato de emergência mudou.');
      expect(request.dueAt, _now.add(const Duration(days: 15)));
    });

    test('um segundo pedido com outro aberto é pedido NOVO — o texto novo não se perde', () async {
      await service.requestCorrection(_patient, details: 'Contato errado.');
      final second = await service.requestCorrection(_patient, details: 'Nome com grafia errada.');

      expect(store.requests, hasLength(2));
      expect(second.details, 'Nome com grafia errada.');
    });

    test('texto vazio ou só espaços é recusado', () async {
      for (final details in ['', '   ', '\n\t']) {
        await expectLater(
          service.requestCorrection(_patient, details: details),
          throwsA(isA<DataRightsException>()),
        );
      }
      expect(store.requests, isEmpty);
    });

    test('aceita 500 caracteres e recusa 501', () async {
      await service.requestCorrection(_patient, details: 'a' * 500);
      await expectLater(
        service.requestCorrection(_patient, details: 'a' * 501),
        throwsA(isA<DataRightsException>()),
      );
      expect(store.requests, hasLength(1));
    });

    test('o texto do pedido nunca vai para audit_logs', () async {
      await service.requestCorrection(_patient, details: 'Tenho hipertensão, não diabetes.');

      final event = audit.events.single;
      expect(event.resourceType, 'data_subject_request');
      expect(event.resourceId, isNot(contains('hipertensão')));
      expect(event.result, 'granted');
    });

    test('um ACS não pede correção em nome de ninguém', () async {
      await expectLater(
        service.requestCorrection(_acs, details: 'Qualquer coisa.'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/data_subject_rights_service_test.dart`
Expected: FAIL na compilação (`data_subject_rights_service.dart` não existe).

- [ ] **Passo 3: Implementar o serviço**

`lib/src/application/patients/data_subject_rights_service.dart`:

```dart
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry, consentPolicyVersion;
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart'
    show ConsentRecordSnapshot, DataSubjectRequestSnapshot;
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência das operações do titular sobre os próprios dados. Interface
/// aqui, implementação ORM em `infrastructure/`, mesmo padrão de
/// `PatientDataOverviewStore`.
abstract interface class DataSubjectRightsStore {
  /// Grava uma linha nova, assinada, em `consent_logs` — nunca edita uma
  /// anterior (append-only, LGPD-RF04).
  Future<void> recordConsent(ConsentLogEntry entry);

  /// O pedido em aberto mais recente daquele tipo, ou `null`.
  Future<DataSubjectRequestSnapshot?> findOpenRequest(
    String userId,
    DataSubjectRequestType type,
  );

  Future<DataSubjectRequestSnapshot> createRequest({
    required String userId,
    required DataSubjectRequestType type,
    required String? details,
    required DateTime createdAt,
    required DateTime dueAt,
  });
}

/// Prazo de resposta a um pedido do titular (spec/lgpd_design.md, 596-597).
const Duration dataSubjectRequestDeadline = Duration(days: 15);

/// Teto do texto de um pedido de correção, contado depois do `trim()`. O app
/// usa o mesmo número no `maxLength` do campo.
const int correctionDetailsMaxLength = 500;

/// Direitos do titular exercidos pelo próprio app (LGPD-RF05 e LGPD-RF08):
/// conceder/revogar finalidades opcionais e pedir exclusão ou correção.
///
/// `userId` vem SEMPRE de `user.id` — nunca de parâmetro —, pelo mesmo motivo
/// de INV-05 em `triage.evaluate`. `requireMicroArea: false`, mesmo motivo de
/// `PatientDataOverviewService.myData`: o escopo é o titular, não o território.
class DataSubjectRightsService {
  DataSubjectRightsService({
    required DataSubjectRightsStore store,
    required AuditTrail audit,
    DateTime Function()? clock,
  })  : _store = store,
        _audit = audit,
        _clock = clock ?? DateTime.now;

  final DataSubjectRightsStore _store;
  final AuditTrail _audit;
  final DateTime Function() _clock;

  /// Concede ou revoga uma finalidade opcional. `healthDataProcessing` é
  /// recusado nas duas direções: é a base legal do app inteiro — inclusive do
  /// alerta de emergência — e retirá-lo exige a exclusão dos dados em até 15
  /// dias (LGPD-RF07), que é o que [requestDeletion] registra.
  Future<ConsentRecordSnapshot> updateConsent(
    AuthenticatedUser user, {
    required ConsentPurpose purpose,
    required bool granted,
  }) async {
    _requirePatient(user);
    if (purpose == ConsentPurpose.healthDataProcessing) {
      throw DataRightsException(
        message: 'O consentimento para dados de saúde é obrigatório para usar o app. '
            'Para retirá-lo, solicite a exclusão dos seus dados.',
      );
    }

    final now = _clock().toUtc();
    final action = granted ? 'granted' : 'denied';
    await _store.recordConsent(ConsentLogEntry(
      userId: user.id,
      purpose: purpose,
      action: action,
      version: consentPolicyVersion,
      timestamp: now,
    ));
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'consent_log',
      result: 'granted',
    ));

    return ConsentRecordSnapshot(
      purpose: purpose.name,
      action: action,
      version: consentPolicyVersion,
      timestamp: now,
    );
  }

  /// Pede a exclusão/anonimização dos próprios dados. Idempotente enquanto
  /// houver um pedido de exclusão em aberto: pedir de novo devolve o mesmo, em
  /// vez de empilhar pedidos iguais para a equipe.
  Future<DataSubjectRequestSnapshot> requestDeletion(AuthenticatedUser user) async {
    _requirePatient(user);
    final open = await _store.findOpenRequest(user.id, DataSubjectRequestType.deletion);
    if (open != null) return open;
    return _create(user, DataSubjectRequestType.deletion, null);
  }

  /// Pede a correção de um dado. Ao contrário da exclusão, NÃO é idempotente:
  /// cada pedido carrega um texto próprio, e devolver um pedido anterior
  /// descartaria em silêncio o texto que a pessoa acabou de escrever.
  Future<DataSubjectRequestSnapshot> requestCorrection(
    AuthenticatedUser user, {
    required String details,
  }) async {
    _requirePatient(user);
    final trimmed = details.trim();
    if (trimmed.isEmpty) {
      throw DataRightsException(message: 'Descreva o que precisa ser corrigido.');
    }
    if (trimmed.length > correctionDetailsMaxLength) {
      throw DataRightsException(
        message: 'A descrição pode ter no máximo $correctionDetailsMaxLength caracteres.',
      );
    }
    return _create(user, DataSubjectRequestType.correction, trimmed);
  }

  Future<DataSubjectRequestSnapshot> _create(
    AuthenticatedUser user,
    DataSubjectRequestType type,
    String? details,
  ) async {
    final now = _clock().toUtc();
    final request = await _store.createRequest(
      userId: user.id,
      type: type,
      details: details,
      createdAt: now,
      dueAt: now.add(dataSubjectRequestDeadline),
    );
    // Só o id do pedido: o texto da correção pode citar condição de saúde e
    // não entra na trilha (ver `AuditEvent.result`).
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'data_subject_request',
      resourceId: request.id,
      result: 'granted',
    ));
    return request;
  }

  void _requirePatient(AuthenticatedUser user) => Authorization.require(
        user,
        roles: {UserRole.patient},
        onDenied: () =>
            StateError('Somente o próprio paciente pode exercer direitos sobre os seus dados.'),
        requireMicroArea: false,
      );
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit/data_subject_rights_service_test.dart && dart analyze`
Expected: PASS, todos os testes; analyze sem issues.

- [ ] **Passo 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart \
  backend/sinalacs_server/test/unit/data_subject_rights_service_test.dart
git commit -m "feat(lgpd): serviço de direitos do titular — revogação por finalidade e pedidos de exclusão/correção"
```

---

### Tarefa 3: Store ORM, runtime e as três RPCs, provados contra Postgres real

**Arquivos:**
- Criar: `backend/sinalacs_server/lib/src/infrastructure/database/orm_data_subject_rights_store.dart`
- Modificar: `lib/src/infrastructure/database/orm_patient_data_overview_store.dart`
- Modificar: `lib/src/runtime/alert_runtime.dart`
- Modificar: `lib/src/endpoints/patients_endpoint.dart`
- Teste: `backend/sinalacs_server/test/integration/data_subject_rights_endpoint_test.dart`

**Interfaces:**
- Consome: `DataSubjectRightsStore`, `DataSubjectRightsService` (Tarefa 2); `signedConsentLog` (Tarefa 1); `HealthDataCipher` com `encryptJson`/`decryptJson` (`infrastructure/crypto/encrypted_json.dart`).
- Produz:
  - `Future<DataSubjectRequestSnapshot> dataSubjectRequestSnapshotOf(DataSubjectRequest row, HealthDataCipher cipher)` (top-level, usada pelas duas stores).
  - `AlertRuntime.dataSubjectRightsServiceFor(Session session)`.
  - RPCs: `patients.updateConsent({accessToken, ConsentPurpose purpose, bool granted}) → PatientConsentRecord`, `patients.requestDataDeletion({accessToken}) → PatientDataSubjectRequestRecord`, `patients.requestDataCorrection({accessToken, String details}) → PatientDataSubjectRequestRecord`.

- [ ] **Passo 1: Escrever os testes de integração (falham: as RPCs não existem)**

`test/integration/data_subject_rights_endpoint_test.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, os direitos do titular exercidos pelo app
/// (LGPD-RF05/RF08): a linha assinada em `consent_logs`, o pedido cifrado em
/// `data_subject_requests` e o reflexo de ambos em `patients.myData`.
/// `data_subject_rights_service_test.dart` prova as regras com fakes.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _chainSecret = 'test-audit-chain-secret';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: _chainSecret,
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      smsGateway: 'log',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    );

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient',
      name: 'Paciente de desenvolvimento',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980, 1, 1),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  ]);
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: const [],
    ),
  );
}

void main() {
  withServerpod('Dados os direitos do titular exercidos pelo app', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    Future<String> patientToken() async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient')).accessToken;

    test('updateConsent grava linha assinada em consent_logs e myData passa a mostrá-la', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final record = await endpoints.patients.updateConsent(
        sessionBuilder,
        accessToken: token,
        purpose: ConsentPurpose.localReminders,
        granted: false,
      );
      expect(record.action, 'denied');

      final row = (await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      ))
          .single;
      expect(row.purpose, 'localReminders');
      expect(row.action, 'denied');
      expect(row.ipHash, 'nao-aplicavel-painel-titular');
      expect(
        row.signature,
        ConsentSignature(secret: _chainSecret).compute(
          userId: _patientId,
          purpose: row.purpose,
          action: row.action,
          version: row.version,
          timestamp: row.timestamp,
        ),
      );

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.consents.last.purpose, 'localReminders');
      expect(overview.consents.last.action, 'denied');
    });

    test('updateConsent recusa a finalidade obrigatória sem gravar nada', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await expectLater(
        endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: token,
          purpose: ConsentPurpose.healthDataProcessing,
          granted: false,
        ),
        throwsA(isA<DataRightsException>()),
      );
      expect(await ConsentLog.db.count(session), 0);
    });

    test('requestDataDeletion repetido deixa um pedido só, com prazo de 15 dias, visível em myData', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final first = await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);
      final second = await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);

      expect(second.createdAt, first.createdAt);
      expect(first.dueAt.difference(first.createdAt), const Duration(days: 15));
      expect(first.status, DataSubjectRequestStatus.open);
      expect(await DataSubjectRequest.db.count(session), 1);

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.requests.single.type, DataSubjectRequestType.deletion);
      expect(overview.requests.single.status, DataSubjectRequestStatus.open);
    });

    test('requestDataCorrection guarda o texto cifrado e myData devolve o texto decifrado', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.requestDataCorrection(
        sessionBuilder,
        accessToken: token,
        details: 'Meu contato de emergência mudou.',
      );

      final row = (await DataSubjectRequest.db.find(session)).single;
      expect(row.detailsEncrypted, isNot(contains('contato')));
      expect(row.detailsEncrypted, isNotEmpty);

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.requests.single.type, DataSubjectRequestType.correction);
      expect(overview.requests.single.details, 'Meu contato de emergência mudou.');
    });

    test('um ACS não chama nenhuma das três', () async {
      await _seed(sessionBuilder.build());
      final token =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: token,
          purpose: ConsentPurpose.localReminders,
          granted: false,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.requestDataCorrection(sessionBuilder, accessToken: token, details: 'x'),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('cada escrita deixa linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.updateConsent(
        sessionBuilder,
        accessToken: token,
        purpose: ConsentPurpose.segmentedPush,
        granted: true,
      );
      await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);

      final consentRows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('consent_log'),
      );
      final requestRows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('data_subject_request'),
      );
      expect(consentRows, hasLength(1));
      expect(requestRows, hasLength(1));
      expect(requestRows.single.userId, UuidValue.fromString(_patientId));
    });
  });
}
```

Antes de rodar, abra `test/integration/patient_data_overview_endpoint_test.dart` e confirme que `developmentLogin(role: 'patient')` emite o id `...0001` (o teste existente depende disso). Confirme também o nome da coluna de recurso em `AuditLog` (`resourceType`, como no teste existente).

- [ ] **Passo 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/integration/data_subject_rights_endpoint_test.dart`
Expected: FAIL na compilação (`endpoints.patients.updateConsent` não existe).

- [ ] **Passo 3: Store ORM**

`lib/src/infrastructure/database/orm_data_subject_rights_store.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry;
import 'package:sinalacs_server/src/application/patients/data_subject_rights_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart'
    show DataSubjectRequestSnapshot;
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:sinalacs_server/src/infrastructure/database/signed_consent_log.dart';

/// Um pedido lido do banco, com `details` decifrado. Compartilhado com
/// `OrmPatientDataOverviewStore`, que lista os mesmos pedidos em "Meus Dados".
Future<DataSubjectRequestSnapshot> dataSubjectRequestSnapshotOf(
  DataSubjectRequest row,
  HealthDataCipher cipher,
) async =>
    DataSubjectRequestSnapshot(
      id: row.id!.uuid,
      type: row.requestType,
      status: row.status,
      details: await cipher.decryptJson(row.detailsEncrypted, row.detailsKeyVersion) as String?,
      createdAt: row.createdAt,
      dueAt: row.dueAt,
    );

/// Implementação de [DataSubjectRightsStore] sobre o ORM do Serverpod.
///
/// [chainSecret] é o mesmo `AUDIT_CHAIN_SECRET` que assina `consent_logs` no
/// onboarding (`OrmOnboardingStore`) — a linha sai de [signedConsentLog], a
/// mesma função, para as duas origens não divergirem.
class OrmDataSubjectRightsStore implements DataSubjectRightsStore {
  OrmDataSubjectRightsStore({
    required Session Function() session,
    required String chainSecret,
    required HealthDataCipher cipher,
  })  : _session = session,
        _signature = ConsentSignature(secret: chainSecret),
        _cipher = cipher;

  final Session Function() _session;
  final ConsentSignature _signature;
  final HealthDataCipher _cipher;

  @override
  Future<void> recordConsent(ConsentLogEntry entry) async {
    await ConsentLog.db.insertRow(
      _session(),
      signedConsentLog(entry, signature: _signature, origin: 'painel-titular'),
    );
  }

  @override
  Future<DataSubjectRequestSnapshot?> findOpenRequest(
    String userId,
    DataSubjectRequestType type,
  ) async {
    final row = await DataSubjectRequest.db.findFirstRow(
      _session(),
      where: (t) =>
          t.userId.equals(UuidValue.fromString(userId)) &
          t.requestType.equals(type) &
          t.status.equals(DataSubjectRequestStatus.open),
      orderBy: (t) => t.createdAt,
      orderDescending: true,
    );
    return row == null ? null : dataSubjectRequestSnapshotOf(row, _cipher);
  }

  @override
  Future<DataSubjectRequestSnapshot> createRequest({
    required String userId,
    required DataSubjectRequestType type,
    required String? details,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    // Cifra sempre, inclusive o `null` da exclusão: a coluna vazia fica
    // reservada para linha escrita fora do caminho Dart (ver `decryptJson`).
    final encrypted = await _cipher.encryptJson(details);
    final row = await DataSubjectRequest.db.insertRow(
      _session(),
      DataSubjectRequest(
        userId: UuidValue.fromString(userId),
        requestType: type,
        detailsEncrypted: encrypted.ciphertextBase64,
        detailsKeyVersion: encrypted.keyVersion,
        status: DataSubjectRequestStatus.open,
        createdAt: createdAt,
        dueAt: dueAt,
      ),
    );
    return dataSubjectRequestSnapshotOf(row, _cipher);
  }
}
```

- [ ] **Passo 4: `myData` carrega os pedidos**

Em `orm_patient_data_overview_store.dart`, acrescentar o import `package:sinalacs_server/src/infrastructure/database/orm_data_subject_rights_store.dart` e, depois da consulta `alertRows`:

```dart
    final requestRows = await DataSubjectRequest.db.find(
      session,
      where: (t) => t.userId.equals(id),
      orderBy: (t) => t.createdAt,
      orderDescending: true,
    );
    final requests = [
      for (final row in requestRows) await dataSubjectRequestSnapshotOf(row, _cipher),
    ];
```

No `return PatientDataSnapshot(...)`, acrescentar `requests: requests,` depois de `riskHistory: riskHistory,`. Atualizar o comentário da classe: "Agrega cinco consultas independentes — `patients`, `users`, `consent_logs`, o histórico de risco de `triage_sessions`/`alerts` e `data_subject_requests`…", e acrescentar que também decifra `detailsEncrypted`, texto que o próprio titular escreveu.

- [ ] **Passo 5: Runtime**

Em `lib/src/runtime/alert_runtime.dart`, logo depois de `patientDataOverviewServiceFor`:

```dart
  /// Constrói o serviço de direitos do titular (LGPD-RF05/RF08) para uma
  /// requisição.
  DataSubjectRightsService dataSubjectRightsServiceFor(Session session) =>
      DataSubjectRightsService(
        store: OrmDataSubjectRightsStore(
          session: () => session,
          chainSecret: config.auditChainSecret,
          cipher: healthDataCipher,
        ),
        audit: auditTrailFor(session),
      );
```

Acrescentar os imports de `data_subject_rights_service.dart` e `orm_data_subject_rights_store.dart`, no mesmo estilo dos imports vizinhos.

- [ ] **Passo 6: As três RPCs**

Em `patients_endpoint.dart`, depois de `myData`:

```dart
  /// Concede ou revoga, pelo próprio titular, uma finalidade opcional de
  /// consentimento (LGPD-RF05): uma linha nova em `consent_logs`, nunca a
  /// edição da anterior. `healthDataProcessing` volta como
  /// [DataRightsException] — retirá-lo passa pelo pedido de exclusão.
  Future<PatientConsentRecord> updateConsent(
    Session session, {
    required String accessToken,
    required ConsentPurpose purpose,
    required bool granted,
  }) async {
    final user = authenticate(accessToken);

    try {
      final record = await AlertRuntime.instance
          .dataSubjectRightsServiceFor(session)
          .updateConsent(user, purpose: purpose, granted: granted);
      return PatientConsentRecord(
        purpose: record.purpose,
        action: record.action,
        version: record.version,
        timestamp: record.timestamp,
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Pedido de exclusão/anonimização dos próprios dados (LGPD-RF08).
  /// Idempotente enquanto houver um pedido de exclusão em aberto.
  Future<PatientDataSubjectRequestRecord> requestDataDeletion(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      return _requestRecord(
        await AlertRuntime.instance.dataSubjectRightsServiceFor(session).requestDeletion(user),
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Pedido de correção de um dado (LGPD-RF08). [details] é texto livre do
  /// titular, gravado cifrado; vazio ou acima de 500 caracteres volta como
  /// [DataRightsException].
  Future<PatientDataSubjectRequestRecord> requestDataCorrection(
    Session session, {
    required String accessToken,
    required String details,
  }) async {
    final user = authenticate(accessToken);

    try {
      return _requestRecord(
        await AlertRuntime.instance
            .dataSubjectRightsServiceFor(session)
            .requestCorrection(user, details: details),
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
```

Atualizar o comentário de classe de `PatientsEndpoint`: além do diretório da microárea, ela agora serve o próprio paciente ("Perfil clínico", "Meus Dados" e os direitos do titular).

- [ ] **Passo 7: Regenerar o cliente e rodar**

Run:
```bash
cd backend/sinalacs_server && serverpod generate
dart analyze && dart test
```
Expected: `generate` acrescenta os três métodos a `backend/sinalacs_client` e a `test/integration/test_tools/serverpod_test_tools.dart`, sem migração nova (nenhum `.spy.yaml` mudou). Suíte inteira verde, incluindo `endpoint_auth_posture_test.dart`: `PatientsEndpoint` já estende `AuthenticatedEndpoint`.

- [ ] **Passo 8: Commit**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_client \
  backend/sinalacs_server/test/integration
git commit -m "feat(lgpd): RPCs de consentimento e pedidos do titular, com store ORM cifrada"
```

---

### Tarefa 4: Contrato no app — `PatientBackend`, `_guard` e a decisão vigente de consentimento

**Arquivos:**
- Modificar: `apps/patient/lib/core/network/backend_client.dart`
- Criar: `apps/patient/lib/core/consent/consent_decisions.dart`
- Modificar: `apps/patient/test/support/fake_patient_backend.dart`
- Modificar: `apps/patient/test/support/fake_rpc_server.dart`
- Teste: `apps/patient/test/consent_decisions_test.dart`, `apps/patient/test/backend_client_data_rights_test.dart`

**Interfaces:**
- Consome: RPCs da Tarefa 3 pelo cliente gerado (`_client.patients.updateConsent/requestDataDeletion/requestDataCorrection`).
- Produz:
  - Em `PatientBackend`: `Future<PatientConsentRecord> updateConsent({required ConsentPurpose purpose, required bool granted});`, `Future<PatientDataSubjectRequestRecord> requestDataDeletion();` e `Future<PatientDataSubjectRequestRecord> requestDataCorrection(String details);`.
  - `Map<ConsentPurpose, bool> currentConsentDecisions(List<PatientConsentRecord> history)`, `String consentPurposeLabel(ConsentPurpose purpose)` e `String consentRecordLabel(String purpose)`.
  - Em `FakePatientBackend`: `updateConsentCalls` (`List<({ConsentPurpose purpose, bool granted})>`), `updateConsentFailure`, `requestDataDeletionCount`, `correctionRequests` (`List<String>`), `dataRequestFailure` e `dataRequestGate` (`Completer<void>?`). Os três métodos acrescentam o registro a `myDataResult`, para que o recarregamento mostre o estado novo.
  - Em `FakeRpcServer`: `String? rejectDataRightsWith`.

- [ ] **Passo 1: Testes da decisão vigente (falham: o arquivo não existe)**

`apps/patient/test/consent_decisions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/consent/consent_decisions.dart';

PatientConsentRecord _record(String purpose, String action, DateTime at) =>
    PatientConsentRecord(purpose: purpose, action: action, version: '2026.1', timestamp: at);

void main() {
  test('histórico vazio não tem decisão nenhuma — "nunca decidiu" não vira recusa', () {
    expect(currentConsentDecisions(const []), isEmpty);
  });

  test('vale o registro mais recente, qualquer que seja a ordem da lista', () {
    final decisions = currentConsentDecisions([
      _record('localReminders', 'denied', DateTime.utc(2026, 2, 1)),
      _record('localReminders', 'granted', DateTime.utc(2026, 1, 1)),
    ]);

    expect(decisions, {ConsentPurpose.localReminders: false});
  });

  test('empate de horário: vale o último da lista', () {
    final at = DateTime.utc(2026, 1, 1);
    final decisions = currentConsentDecisions([
      _record('segmentedPush', 'granted', at),
      _record('segmentedPush', 'denied', at),
    ]);

    expect(decisions[ConsentPurpose.segmentedPush], isFalse);
  });

  test('as três finalidades do onboarding saem independentes', () {
    final at = DateTime.utc(2026, 1, 1);
    final decisions = currentConsentDecisions([
      _record('healthDataProcessing', 'granted', at),
      _record('localReminders', 'granted', at),
      _record('segmentedPush', 'denied', at),
    ]);

    expect(decisions, {
      ConsentPurpose.healthDataProcessing: true,
      ConsentPurpose.localReminders: true,
      ConsentPurpose.segmentedPush: false,
    });
  });

  test('finalidade que o app não conhece é ignorada', () {
    final decisions = currentConsentDecisions([
      _record('finalidadeFutura', 'granted', DateTime.utc(2026, 1, 1)),
    ]);

    expect(decisions, isEmpty);
  });

  test('rótulo de registro cai no nome cru só para finalidade desconhecida', () {
    expect(consentRecordLabel('localReminders'), 'Lembretes neste aparelho');
    expect(consentRecordLabel('finalidadeFutura'), 'finalidadeFutura');
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/consent_decisions_test.dart`
Expected: FAIL na compilação (import inexistente).

- [ ] **Passo 3: Implementar `consent_decisions.dart`**

```dart
import 'package:sinalacs_client/sinalacs_client.dart';

/// Decisão vigente de cada finalidade, a partir do histórico de
/// `consent_logs` que `patients.myData` devolve.
///
/// O histórico é append-only (LGPD-RF04): revogar grava uma linha nova, nunca
/// apaga a anterior, então vale o registro mais recente de cada finalidade.
/// Empate de horário resolve pela ordem da lista, que o servidor entrega da
/// mais antiga para a mais nova. Finalidade que o app não conhece é ignorada, e
/// finalidade sem registro fica fora do mapa — quem lê distingue "nunca
/// decidiu" de "recusou", mesmo cuidado de `ConsentPreferences`.
Map<ConsentPurpose, bool> currentConsentDecisions(List<PatientConsentRecord> history) {
  final known = ConsentPurpose.values.asNameMap();
  final latest = <ConsentPurpose, PatientConsentRecord>{};
  for (final record in history) {
    final purpose = known[record.purpose];
    if (purpose == null) continue;
    final previous = latest[purpose];
    if (previous == null || !record.timestamp.isBefore(previous.timestamp)) {
      latest[purpose] = record;
    }
  }
  return {for (final entry in latest.entries) entry.key: entry.value.action == 'granted'};
}

/// Nome de cada finalidade para a pessoa ler.
String consentPurposeLabel(ConsentPurpose purpose) => switch (purpose) {
      ConsentPurpose.healthDataProcessing => 'Tratamento de dados de saúde',
      ConsentPurpose.localReminders => 'Lembretes neste aparelho',
      ConsentPurpose.segmentedPush => 'Avisos da equipe de saúde',
    };

/// Rótulo de um registro do histórico, que carrega a finalidade como texto.
/// Uma finalidade desconhecida aparece crua, em vez de sumir do histórico.
String consentRecordLabel(String purpose) {
  final known = ConsentPurpose.values.asNameMap()[purpose];
  return known == null ? purpose : consentPurposeLabel(known);
}
```

Run: `flutter test test/consent_decisions_test.dart` → PASS.

- [ ] **Passo 4: Teste do `_guard` pelo cliente real (falha: métodos inexistentes)**

Em `test/support/fake_rpc_server.dart`, acrescentar o campo depois de `rejectVerifyWith`:

```dart
  /// Definida, faz `updateConsent`/`requestDataDeletion`/`requestDataCorrection`
  /// recusarem com esta mensagem, no formato de `DataRightsException`.
  String? rejectDataRightsWith;
```

e, em `_handle`, logo depois do bloco `if (recusa != null) { ... }`:

```dart
    final recusaDeDireitos = switch (method) {
      'updateConsent' || 'requestDataDeletion' || 'requestDataCorrection' =>
        rejectDataRightsWith,
      _ => null,
    };
    if (recusaDeDireitos != null) {
      await _respond(request, HttpStatus.badRequest, {
        'className': 'DataRightsException',
        'data': {'__className__': 'DataRightsException', 'message': recusaDeDireitos},
      });
      return;
    }
```

`apps/patient/test/backend_client_data_rights_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_rpc_server.dart';

/// A tradução `DataRightsException → BackendFailure(mensagem do servidor, não
/// recuperável)` pelo [BackendClient] real. A suíte de widgets usa o
/// `FakePatientBackend`, que não tem `_guard`, e apagar a cláusula de lá não
/// deixaria nada vermelho sem este arquivo.
void main() {
  late FakeRpcServer server;
  late BackendClient backend;

  setUp(() async {
    server = await FakeRpcServer.start();
    backend = BackendClient(host: server.host);
    await backend.verifyOtp(cpf: '123.456.789-09', code: '123456');
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  Matcher recusaDoServidor(String mensagem) => throwsA(
        isA<BackendFailure>()
            .having((falha) => falha.message, 'mensagem', mensagem)
            .having((falha) => falha.isRecoverable, 'isRecoverable', isFalse),
      );

  test('a recusa de updateConsent chega com a mensagem do servidor', () async {
    server.rejectDataRightsWith = 'O consentimento para dados de saúde é obrigatório.';

    await expectLater(
      backend.updateConsent(purpose: ConsentPurpose.healthDataProcessing, granted: false),
      recusaDoServidor('O consentimento para dados de saúde é obrigatório.'),
    );

    final pedido = server.requests.last;
    expect(pedido.endpoint, 'patients');
    expect(pedido.method, 'updateConsent');
    expect(pedido.args['purpose'], 'healthDataProcessing');
    expect(pedido.args['granted'], false);
  });

  test('a recusa de requestDataCorrection chega com a mensagem do servidor', () async {
    server.rejectDataRightsWith = 'Descreva o que precisa ser corrigido.';

    await expectLater(
      backend.requestDataCorrection('   '),
      recusaDoServidor('Descreva o que precisa ser corrigido.'),
    );
    expect(server.requests.last.args['details'], '   ');
  });

  test('a recusa de requestDataDeletion chega com a mensagem do servidor', () async {
    server.rejectDataRightsWith = 'Recusado.';

    await expectLater(backend.requestDataDeletion(), recusaDoServidor('Recusado.'));
    expect(server.requests.last.method, 'requestDataDeletion');
  });
}
```

Se `verifyOtp` do fake exigir um `requestOtp` antes, confira em `backend_client_otp_test.dart` como aquele arquivo obtém a sessão e repita o mesmo passo no `setUp`.

- [ ] **Passo 5: Implementar os métodos no app**

Em `backend_client.dart`, na interface `PatientBackend`, depois de `myData()`:

```dart
  /// Concede ou revoga uma finalidade opcional de consentimento (LGPD-RF05).
  /// O servidor grava uma linha nova em `consent_logs`; `healthDataProcessing`
  /// é recusado com [BackendFailure] não recuperável.
  Future<PatientConsentRecord> updateConsent({
    required ConsentPurpose purpose,
    required bool granted,
  });

  /// Pede a exclusão dos próprios dados (LGPD-RF08). Pedir de novo com um
  /// pedido aberto devolve o mesmo.
  Future<PatientDataSubjectRequestRecord> requestDataDeletion();

  /// Pede a correção de um dado (LGPD-RF08). O servidor faz o `trim` e recusa
  /// texto vazio ou acima de 500 caracteres.
  Future<PatientDataSubjectRequestRecord> requestDataCorrection(String details);
```

Em `MisconfiguredBackend`, depois de `myData`:

```dart
  @override
  Future<PatientConsentRecord> updateConsent({
    required ConsentPurpose purpose,
    required bool granted,
  }) async =>
      _recusar();

  @override
  Future<PatientDataSubjectRequestRecord> requestDataDeletion() async => _recusar();

  @override
  Future<PatientDataSubjectRequestRecord> requestDataCorrection(String details) async =>
      _recusar();
```

Em `BackendClient`, depois de `myData`:

```dart
  @override
  Future<PatientConsentRecord> updateConsent({
    required ConsentPurpose purpose,
    required bool granted,
  }) async {
    final token = await _requireToken();
    return _guard(
      () => _client.patients.updateConsent(accessToken: token, purpose: purpose, granted: granted),
    );
  }

  @override
  Future<PatientDataSubjectRequestRecord> requestDataDeletion() async {
    final token = await _requireToken();
    return _guard(() => _client.patients.requestDataDeletion(accessToken: token));
  }

  @override
  Future<PatientDataSubjectRequestRecord> requestDataCorrection(String details) async {
    final token = await _requireToken();
    return _guard(
      () => _client.patients.requestDataCorrection(accessToken: token, details: details),
    );
  }
```

Em `_guard`, logo depois da cláusula `on OtpRequestException`:

```dart
    } on DataRightsException catch (error) {
      // Recusa de negócio de um direito do titular (consentimento obrigatório,
      // texto de correção inválido). A mensagem é do servidor, pronta para a
      // pessoa ler; tentar de novo sem mudar nada dá a mesma recusa.
      throw BackendFailure(error.message, isRecoverable: false);
```

- [ ] **Passo 6: Implementar no `FakePatientBackend`**

Acrescentar `import 'dart:async';` no topo. Depois de `int myDataCallCount = 0;`:

```dart
  /// Chamadas a [updateConsent], na ordem.
  final List<({ConsentPurpose purpose, bool granted})> updateConsentCalls =
      <({ConsentPurpose purpose, bool granted})>[];
  BackendFailure? updateConsentFailure;

  int requestDataDeletionCount = 0;
  final List<String> correctionRequests = <String>[];
  BackendFailure? dataRequestFailure;

  /// Definido, segura [requestDataDeletion] até ser completado — é como o teste
  /// observa a tela com o pedido ainda em voo.
  Completer<void>? dataRequestGate;
```

Depois do método `myData()`:

```dart
  /// Como no servidor: uma linha nova no histórico, que o próximo [myData]
  /// devolve.
  @override
  Future<PatientConsentRecord> updateConsent({
    required ConsentPurpose purpose,
    required bool granted,
  }) async {
    updateConsentCalls.add((purpose: purpose, granted: granted));
    final failure = updateConsentFailure;
    if (failure != null) throw failure;
    final record = PatientConsentRecord(
      purpose: purpose.name,
      action: granted ? 'granted' : 'denied',
      version: '2026.1',
      timestamp: DateTime.now().toUtc(),
    );
    myDataResult = myDataResult.copyWith(consents: [...myDataResult.consents, record]);
    return record;
  }

  /// Idempotente enquanto houver exclusão aberta, como o servidor.
  @override
  Future<PatientDataSubjectRequestRecord> requestDataDeletion() async {
    requestDataDeletionCount++;
    await dataRequestGate?.future;
    final failure = dataRequestFailure;
    if (failure != null) throw failure;
    for (final request in myDataResult.requests) {
      if (request.type == DataSubjectRequestType.deletion &&
          request.status == DataSubjectRequestStatus.open) {
        return request;
      }
    }
    return _appendRequest(DataSubjectRequestType.deletion, null);
  }

  @override
  Future<PatientDataSubjectRequestRecord> requestDataCorrection(String details) async {
    correctionRequests.add(details);
    final failure = dataRequestFailure;
    if (failure != null) throw failure;
    return _appendRequest(DataSubjectRequestType.correction, details);
  }

  PatientDataSubjectRequestRecord _appendRequest(DataSubjectRequestType type, String? details) {
    final now = DateTime.now().toUtc();
    final record = PatientDataSubjectRequestRecord(
      type: type,
      status: DataSubjectRequestStatus.open,
      details: details,
      createdAt: now,
      dueAt: now.add(const Duration(days: 15)),
    );
    myDataResult = myDataResult.copyWith(requests: [...myDataResult.requests, record]);
    return record;
  }
```

- [ ] **Passo 7: Rodar e ver passar**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: tudo verde, incluindo os dois arquivos novos.

- [ ] **Passo 8: Commit**

```bash
git add apps/patient/lib/core apps/patient/test
git commit -m "feat(paciente): contrato de direitos do titular no cliente e decisão vigente de consentimento"
```

---

### Tarefa 5: "Meus dados" — interruptores de consentimento e espelho local alinhado ao servidor

**Arquivos:**
- Modificar: `apps/patient/lib/app/app.dart` (`MyDataScreen`, `_RemindersScreenState._load`, `_consentDeniedMessage`, função nova `deactivateAllReminders`)
- Teste: `apps/patient/test/patient_app_mvp_test.dart` (grupo `'Meus dados (LGPD)'`)

**Interfaces:**
- Consome: `PatientBackend.updateConsent` e `FakePatientBackend.updateConsentCalls/updateConsentFailure` (Tarefa 4); `currentConsentDecisions`, `consentPurposeLabel` e `consentRecordLabel` (Tarefa 4); `RemindersScope`.
- Produz: `Future<bool> deactivateAllReminders(RemindersScope scope)` (top-level em `app.dart`). Em `_MyDataScreenState`: `bool _busy`, `String _formatDate(DateTime)` e `Future<void> _load()` (alinha o espelho local). A chave `Key('my_data_confirmation')` substitui `Key('my_data_export_confirmation')`. Chaves novas: `consent_switch_localReminders`, `consent_switch_segmentedPush`, `consent_health_data_notice`, `consent_revoke_confirm`, `consent_revoke_cancel`.

- [ ] **Passo 1: Escrever os testes (falham)**

Em `test/patient_app_mvp_test.dart`, primeiro renomeie a chave nos testes existentes:

```bash
cd apps/patient && sed -i "s/my_data_export_confirmation/my_data_confirmation/g" test/patient_app_mvp_test.dart
```

No teste `'mostra consentimentos e histórico de risco devolvidos pelo servidor'` (o que usa `find.text('healthDataProcessing')`), trocar essa asserção por `expect(find.text('Tratamento de dados de saúde'), findsOneWidget);`. O histórico passa a usar o rótulo; o aviso da finalidade obrigatória é um texto mais longo e não casa com `find.text` exato.

Dentro do grupo `'Meus dados (LGPD)'`, depois do helper `overview`, acrescentar os helpers e os testes:

```dart
    PatientConsentRecord consent(ConsentPurpose purpose, String action, DateTime at) =>
        PatientConsentRecord(purpose: purpose.name, action: action, version: '2026.1', timestamp: at);

    List<PatientConsentRecord> onboardingConsents() {
      final at = DateTime.utc(2026, 1, 1);
      return [
        consent(ConsentPurpose.healthDataProcessing, 'granted', at),
        consent(ConsentPurpose.localReminders, 'granted', at),
        consent(ConsentPurpose.segmentedPush, 'denied', at),
      ];
    }

    /// "Meus dados" com os duplos de lembretes: a tela agora lê e alinha o
    /// espelho local, e sem eles o `SinalAcsApp` montaria o SQLite real.
    Future<void> pumpMyData(
      WidgetTester tester,
      FakePatientBackend backend, {
      ReminderStore? store,
      ReminderScheduler? scheduler,
      ConsentPreferences? consentPreferences,
    }) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        reminderStore: store ?? _InMemoryReminderStore(),
        reminderScheduler: scheduler ?? _RecordingReminderScheduler(),
        consentPreferences: consentPreferences ?? _FixedConsentPreferences(),
      ));
      await login(tester);
      await openMyData(tester);
    }

    Future<void> tapSwitch(WidgetTester tester, ConsentPurpose purpose) async {
      final finder = find.byKey(Key('consent_switch_${purpose.name}'));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    bool switchValue(WidgetTester tester, ConsentPurpose purpose) =>
        tester.widget<SwitchListTile>(find.byKey(Key('consent_switch_${purpose.name}'))).value;

    testWidgets('os interruptores mostram a decisão mais recente de cada finalidade', (tester) async {
      final backend = FakePatientBackend()
        ..myDataResult = overview(consents: [
          ...onboardingConsents(),
          consent(ConsentPurpose.localReminders, 'denied', DateTime.utc(2026, 2, 1)),
        ]);
      await pumpMyData(tester, backend, consentPreferences: _FixedConsentPreferences(granted: false));

      expect(switchValue(tester, ConsentPurpose.localReminders), isFalse);
      expect(switchValue(tester, ConsentPurpose.segmentedPush), isFalse);
      expect(find.byKey(const Key('consent_switch_healthDataProcessing')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('consent_health_data_notice'))).data,
        contains('solicite a exclusão'),
      );
    });

    testWidgets('revogar pede confirmação; cancelar não chama o servidor', (tester) async {
      final backend = FakePatientBackend()..myDataResult = overview(consents: onboardingConsents());
      await pumpMyData(tester, backend);

      await tapSwitch(tester, ConsentPurpose.localReminders);
      expect(find.text('Revogar consentimento?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('consent_revoke_cancel')));
      await tester.pumpAndSettle();

      expect(backend.updateConsentCalls, isEmpty);
      expect(switchValue(tester, ConsentPurpose.localReminders), isTrue);
    });

    testWidgets(
        'confirmar a revogação de lembretes registra no servidor, atualiza o espelho e '
        'cancela na hora o lembrete já agendado', (tester) async {
      final store = _InMemoryReminderStore();
      final seeded = await store.save(
        const Reminder(id: 0, label: 'Losartana 50 mg', hour: 8, minute: 0, active: true),
      );
      final scheduler = _RecordingReminderScheduler();
      final prefs = _FixedConsentPreferences(granted: true);
      final backend = FakePatientBackend()..myDataResult = overview(consents: onboardingConsents());
      await pumpMyData(tester, backend, store: store, scheduler: scheduler, consentPreferences: prefs);

      await tapSwitch(tester, ConsentPurpose.localReminders);
      await tester.tap(find.byKey(const Key('consent_revoke_confirm')));
      await tester.pumpAndSettle();

      expect(backend.updateConsentCalls.single, (purpose: ConsentPurpose.localReminders, granted: false));
      expect(prefs.granted, isFalse);
      expect(scheduler.cancelled, [seeded.id]);
      expect((await store.list()).single.active, isFalse);
      expect(switchValue(tester, ConsentPurpose.localReminders), isFalse);
      expect(
        tester.widget<Text>(find.byKey(const Key('my_data_confirmation'))).data,
        contains('revogado'),
      );
    });

    testWidgets('conceder não pede confirmação e não mexe nos lembretes', (tester) async {
      final scheduler = _RecordingReminderScheduler();
      final backend = FakePatientBackend()..myDataResult = overview(consents: onboardingConsents());
      await pumpMyData(tester, backend, scheduler: scheduler);

      await tapSwitch(tester, ConsentPurpose.segmentedPush);

      expect(find.text('Revogar consentimento?'), findsNothing);
      expect(backend.updateConsentCalls.single, (purpose: ConsentPurpose.segmentedPush, granted: true));
      expect(scheduler.cancelled, isEmpty);
      expect(switchValue(tester, ConsentPurpose.segmentedPush), isTrue);
    });

    testWidgets('falha do servidor mostra o erro e o interruptor fica como estava', (tester) async {
      final handle = tester.ensureSemantics();
      final backend = FakePatientBackend()
        ..myDataResult = overview(consents: onboardingConsents())
        ..updateConsentFailure = const BackendFailure('Sem conexão com o servidor.');
      await pumpMyData(tester, backend);

      await tapSwitch(tester, ConsentPurpose.segmentedPush);

      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('my_data_error'))).flagsCollection.isLiveRegion, isTrue);
      expect(switchValue(tester, ConsentPurpose.segmentedPush), isFalse);
      handle.dispose();
    });

    testWidgets('aparelho sem espelho local (login OTP) recebe a concessão do servidor ao abrir', (tester) async {
      final prefs = _FixedConsentPreferences(granted: null);
      final backend = FakePatientBackend()..myDataResult = overview(consents: onboardingConsents());
      await pumpMyData(tester, backend, consentPreferences: prefs);

      expect(prefs.granted, isTrue);
    });

    testWidgets('recusa vinda do servidor cancela lembretes ativos de um aparelho sem espelho', (tester) async {
      final store = _InMemoryReminderStore();
      final seeded = await store.save(
        const Reminder(id: 0, label: 'Metformina 850 mg', hour: 7, minute: 0, active: true),
      );
      final scheduler = _RecordingReminderScheduler();
      final prefs = _FixedConsentPreferences(granted: null);
      final backend = FakePatientBackend()
        ..myDataResult = overview(consents: [
          ...onboardingConsents(),
          consent(ConsentPurpose.localReminders, 'denied', DateTime.utc(2026, 2, 1)),
        ]);
      await pumpMyData(tester, backend, store: store, scheduler: scheduler, consentPreferences: prefs);

      expect(prefs.granted, isFalse);
      expect(scheduler.cancelled, [seeded.id]);
    });

    testWidgets('os interruptores não criam nó de botão inerte', (tester) async {
      final handle = tester.ensureSemantics();
      final backend = FakePatientBackend()..myDataResult = overview(consents: onboardingConsents());
      await pumpMyData(tester, backend);
      await tester.ensureVisible(find.byKey(const Key('consent_switch_segmentedPush')));
      await tester.pumpAndSettle();

      expectNenhumBotaoInerte(tester);
      handle.dispose();
    });
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart --plain-name "Meus dados"`
Expected: FAIL — `consent_switch_*`, `my_data_confirmation` e `Tratamento de dados de saúde` não existem.

- [ ] **Passo 3: `deactivateAllReminders` e a refatoração de `RemindersScreen`**

Em `app.dart`, logo antes de `class RemindersScreen extends StatefulWidget`:

```dart
/// Cancela no sistema operacional e desativa no store todo lembrete ativo.
///
/// É o que acontece quando o consentimento de lembretes não está (ou deixou de
/// estar) concedido: `RemindersScreen` chama ao abrir, e "Meus dados" chama ao
/// saber de uma revogação — sem isso, um lembrete agendado antes continuaria
/// disparando até a pessoa abrir "Lembretes" (LGPD-RF05). Devolve se algum
/// lembrete foi alterado.
Future<bool> deactivateAllReminders(RemindersScope scope) async {
  final stillActive = (await scope.store.list()).where((r) => r.active).toList();
  for (final r in stillActive) {
    await scope.scheduler.cancel(r.id);
    await scope.store.save(r.copyWith(active: false));
  }
  return stillActive.isNotEmpty;
}
```

Em `_RemindersScreenState._load`, trocar o bloco dentro de `if (consentGranted != true) { ... }` (mantendo o comentário) por:

```dart
      if (consentGranted != true) {
        // Recusa (ou estado desconhecido, tratado como recusa por padrão de
        // segurança): nenhum lembrete pode continuar agendado no sistema
        // operacional depois disso — sem isso, um lembrete criado antes da
        // recusa continuaria disparando mesmo depois dela (LGPD-RF05).
        if (await deactivateAllReminders(scope)) {
          reminders = await scope.store.list();
        }
      }
```

Em `_consentDeniedMessage`, trocar o texto do ramo `granted == false` por:

```dart
      return 'Você recusou ou revogou o consentimento para lembretes locais — '
          'reative em "Meus dados" para agendar notificações.';
```

- [ ] **Passo 4: Estado, carga e alteração de consentimento em `MyDataScreen`**

Acrescentar o import `package:sinalacs_patient/core/consent/consent_decisions.dart` ao topo de `app.dart`.

Em `_MyDataScreenState`, acrescentar o campo `bool _busy = false;` e trocar `_load` por:

```dart
  Future<void> _load() async {
    final backend = BackendScope.of(context);
    final reminders = RemindersScope.of(context);
    try {
      final data = await backend.myData();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
      await _alignLocalRemindersMirror(reminders, data);
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }

  /// O servidor é a fonte da decisão de lembretes (`consent_logs`); o store
  /// local é só o espelho que `RemindersScreen` consulta (ver
  /// `ConsentPreferences`). Alinhar aqui cobre a revogação feita nesta tela e
  /// também o aparelho que entrou pelo login OTP (RF01) sem passar pelo
  /// onboarding, que nunca teve espelho. Sem decisão de lembretes no servidor,
  /// não mexe em nada.
  Future<void> _alignLocalRemindersMirror(RemindersScope scope, PatientDataOverview data) async {
    final granted = currentConsentDecisions(data.consents)[ConsentPurpose.localReminders];
    if (granted == null) return;
    try {
      if (await scope.consentPreferences.localRemindersGranted() != granted) {
        await scope.consentPreferences.saveLocalRemindersConsent(granted);
      }
      if (!granted) await deactivateAllReminders(scope);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Sua escolha foi registrada, mas os lembretes deste aparelho não puderam ser atualizados.');
    }
  }

  Future<bool> _confirmRevocation(ConsentPurpose purpose) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revogar consentimento?'),
        content: Text(
          '${consentPurposeLabel(purpose)}: seus dados deixam de ser usados para esta '
          'finalidade a partir de agora. Você pode conceder de novo quando quiser.'
          '${purpose == ConsentPurpose.localReminders ? ' Os lembretes agendados neste aparelho serão desativados.' : ''}',
        ),
        actions: [
          TextButton(
            key: const Key('consent_revoke_cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('consent_revoke_confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// LGPD-RF05: revogar pede confirmação explícita; conceder, não. O
  /// interruptor segue a decisão devolvida pelo servidor no recarregamento,
  /// então uma falha o deixa exatamente como estava.
  Future<void> _changeConsent(ConsentPurpose purpose, bool granted) async {
    if (_busy) return;
    if (!granted && !await _confirmRevocation(purpose)) return;
    if (!mounted) return;
    final backend = BackendScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _confirmation = null;
    });
    try {
      final record = await backend.updateConsent(purpose: purpose, granted: granted);
      if (!mounted) return;
      setState(() => _confirmation = '${consentPurposeLabel(purpose)}: consentimento '
          '${granted ? 'concedido' : 'revogado'} em ${_formatDate(record.timestamp.toLocal())}.');
      await _load();
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// dd/mm/aaaa. Não converte fuso: quem passa um instante (consentimento,
  /// pedido) chama `.toLocal()` antes; a data de nascimento é meia-noite UTC e
  /// passa como está, senão cairia no dia anterior no Brasil.
  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _purposeDescription(ConsentPurpose purpose) => switch (purpose) {
        ConsentPurpose.localReminders =>
          'Notificações de remédios e cuidados que você agenda em "Lembretes".',
        ConsentPurpose.segmentedPush =>
          'Avisos da UBS para a sua microárea. Ainda não são enviados nesta versão.',
        ConsentPurpose.healthDataProcessing => 'Obrigatório para usar o app.',
      };
```

Em `_export`, trocar a chave e o texto de confirmação não muda. Só a chave do `Text` muda, no `build` (passo 5).

- [ ] **Passo 5: `build` de `MyDataScreen`**

1. No `Text` de confirmação, trocar `key: const Key('my_data_export_confirmation')` por `key: const Key('my_data_confirmation')`.
2. No cartão, trocar a linha da data de nascimento por `Text('Data de nascimento: ${_formatDate(data.birthDate)}'),`.
3. Logo depois de `else if (data != null) ...[`, declarar a decisão vigente, transformando o spread em bloco de expressão. Como Dart não permite `final` dentro de lista, calcule no início do `build`, junto de `final data = _data;`:

```dart
    final decisions = data == null
        ? const <ConsentPurpose, bool>{}
        : currentConsentDecisions(data.consents);
```

4. Trocar o trecho que vai de `const Text('Consentimentos', ...)` até o fim do `.map` dos consentimentos por:

```dart
          const Text('Suas escolhas de consentimento', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            decisions[ConsentPurpose.healthDataProcessing] == true
                ? '${consentPurposeLabel(ConsentPurpose.healthDataProcessing)}: concedido — '
                    'obrigatório para usar o app. Para retirá-lo, solicite a exclusão dos seus dados abaixo.'
                : '${consentPurposeLabel(ConsentPurpose.healthDataProcessing)}: sem registro de consentimento.',
            key: const Key('consent_health_data_notice'),
          ),
          for (final purpose in const [ConsentPurpose.localReminders, ConsentPurpose.segmentedPush])
            SwitchListTile(
              key: Key('consent_switch_${purpose.name}'),
              contentPadding: EdgeInsets.zero,
              title: Text(consentPurposeLabel(purpose)),
              subtitle: Text(_purposeDescription(purpose)),
              value: decisions[purpose] ?? false,
              onChanged: _busy ? null : (value) => _changeConsent(purpose, value),
            ),
          const SizedBox(height: 16),
          const Text('Histórico de consentimentos', style: TextStyle(fontWeight: FontWeight.bold)),
          if (data.consents.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Nenhum consentimento registrado.', style: TextStyle(color: Colors.white54)),
            )
          else
            ...data.consents.map(
              (consent) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(consentRecordLabel(consent.purpose)),
                subtitle: Text('${consent.action == 'granted' ? 'Concedido' : 'Recusado'} · '
                    'v${consent.version} · ${_formatDate(consent.timestamp.toLocal())}'),
              ),
            ),
```

- [ ] **Passo 6: Rodar e ver passar**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: tudo verde. Os testes de "Meus dados" que já existiam não injetam duplos de lembrete. Eles continuam verdes porque o histórico deles não traz `localReminders`, e `_alignLocalRemindersMirror` sai antes de tocar no SQLite. Se algum ficar pendurado, é esse o motivo: passe a usar `pumpMyData`.

- [ ] **Passo 7: Commit**

```bash
git add apps/patient/lib/app/app.dart apps/patient/test/patient_app_mvp_test.dart
git commit -m "feat(paciente): revogar e conceder consentimento em Meus dados (LGPD-RF05)"
```

---

### Tarefa 6: "Meus dados" — pedidos de exclusão e de correção

**Arquivos:**
- Modificar: `apps/patient/lib/app/app.dart` (`MyDataScreen`; classe nova `_CorrectionRequestDialog`)
- Teste: `apps/patient/test/patient_app_mvp_test.dart` (grupo `'Meus dados (LGPD)'`)

**Interfaces:**
- Consome: `PatientBackend.requestDataDeletion/requestDataCorrection`; `FakePatientBackend.requestDataDeletionCount/correctionRequests/dataRequestFailure/dataRequestGate` (Tarefa 4); `_busy`, `_formatDate`, `_load` e `pumpMyData` (Tarefa 5).
- Produz: chaves `request_deletion_button`, `request_correction_button`, `deletion_request_confirm`, `deletion_request_cancel`, `correction_details_field`, `correction_request_submit`, `correction_request_cancel`; chave `pedidos` no JSON exportado.

- [ ] **Passo 1: Escrever os testes (falham)**

No grupo `'Meus dados (LGPD)'`, depois dos testes da Tarefa 5:

```dart
    Future<void> tapByKey(WidgetTester tester, String key) async {
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    OutlinedButton outlined(WidgetTester tester, String key) =>
        tester.widget<OutlinedButton>(find.byKey(Key(key)));

    PatientDataSubjectRequestRecord openRequest(DataSubjectRequestType type, {String? details}) =>
        PatientDataSubjectRequestRecord(
          type: type,
          status: DataSubjectRequestStatus.open,
          details: details,
          // Meio-dia UTC: `toLocal()` mantém o dia em qualquer fuso entre
          // UTC-11 e UTC+11 — meia-noite viraria 15/09 no Brasil.
          createdAt: DateTime.utc(2026, 9, 1, 12),
          dueAt: DateTime.utc(2026, 9, 16, 12),
        );

    testWidgets('sem pedidos, mostra o estado vazio e os dois botões habilitados', (tester) async {
      final backend = FakePatientBackend()..myDataResult = overview();
      await pumpMyData(tester, backend);

      expect(find.text('Nenhum pedido feito.'), findsOneWidget);
      expect(outlined(tester, 'request_deletion_button').onPressed, isNotNull);
      expect(outlined(tester, 'request_correction_button').onPressed, isNotNull);
    });

    testWidgets('pedir exclusão explica prazo e retenção, registra e mostra o pedido em análise', (tester) async {
      final backend = FakePatientBackend()..myDataResult = overview();
      await pumpMyData(tester, backend);

      await tapByKey(tester, 'request_deletion_button');
      expect(find.textContaining('15 dias'), findsOneWidget);
      expect(find.textContaining('emergência'), findsOneWidget);
      await tester.tap(find.byKey(const Key('deletion_request_confirm')));
      await tester.pumpAndSettle();

      expect(backend.requestDataDeletionCount, 1);
      expect(find.textContaining('Exclusão dos dados · Em análise'), findsOneWidget);
      expect(outlined(tester, 'request_deletion_button').onPressed, isNull);
      expect(find.text('Exclusão já solicitada — em análise'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('my_data_confirmation'))).data,
        startsWith('Pedido de exclusão registrado'),
      );
    });

    testWidgets('cancelar o diálogo de exclusão não chama o servidor', (tester) async {
      final backend = FakePatientBackend()..myDataResult = overview();
      await pumpMyData(tester, backend);

      await tapByKey(tester, 'request_deletion_button');
      await tester.tap(find.byKey(const Key('deletion_request_cancel')));
      await tester.pumpAndSettle();

      expect(backend.requestDataDeletionCount, 0);
    });

    testWidgets('com o pedido em voo os botões ficam desabilitados — um pedido só', (tester) async {
      final gate = Completer<void>();
      final backend = FakePatientBackend()
        ..myDataResult = overview()
        ..dataRequestGate = gate;
      await pumpMyData(tester, backend);

      await tapByKey(tester, 'request_deletion_button');
      await tester.tap(find.byKey(const Key('deletion_request_confirm')));
      await tester.pumpAndSettle();

      expect(outlined(tester, 'request_deletion_button').onPressed, isNull);
      expect(outlined(tester, 'request_correction_button').onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(backend.requestDataDeletionCount, 1);
    });

    testWidgets('pedido aberto vindo do servidor já desabilita o botão de exclusão', (tester) async {
      final backend = FakePatientBackend()
        ..myDataResult = overview(requests: [openRequest(DataSubjectRequestType.deletion)]);
      await pumpMyData(tester, backend);

      expect(outlined(tester, 'request_deletion_button').onPressed, isNull);
      expect(find.textContaining('resposta até 16/09/2026'), findsOneWidget);
    });

    testWidgets('correção: só envia com texto de verdade, e sem os espaços das pontas', (tester) async {
      final backend = FakePatientBackend()..myDataResult = overview();
      await pumpMyData(tester, backend);

      await tapByKey(tester, 'request_correction_button');
      FilledButton submit() =>
          tester.widget<FilledButton>(find.byKey(const Key('correction_request_submit')));
      expect(submit().onPressed, isNull);

      await tester.enterText(find.byKey(const Key('correction_details_field')), '   ');
      await tester.pump();
      expect(submit().onPressed, isNull);

      await tester.enterText(find.byKey(const Key('correction_details_field')), '  Meu contato mudou.  ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('correction_request_submit')));
      await tester.pumpAndSettle();

      expect(backend.correctionRequests, ['Meu contato mudou.']);
      expect(find.textContaining('Correção de dados · Em análise'), findsOneWidget);
      expect(find.textContaining('"Meu contato mudou."'), findsOneWidget);
    });

    testWidgets('com uma correção aberta, pedir outra continua possível', (tester) async {
      final backend = FakePatientBackend()
        ..myDataResult = overview(
          requests: [openRequest(DataSubjectRequestType.correction, details: 'Contato errado.')],
        );
      await pumpMyData(tester, backend);

      expect(outlined(tester, 'request_correction_button').onPressed, isNotNull);
    });

    testWidgets('falha ao pedir exclusão mostra o erro e reabilita o botão', (tester) async {
      final backend = FakePatientBackend()
        ..myDataResult = overview()
        ..dataRequestFailure = const BackendFailure('Sem conexão com o servidor.');
      await pumpMyData(tester, backend);

      await tapByKey(tester, 'request_deletion_button');
      await tester.tap(find.byKey(const Key('deletion_request_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
      expect(outlined(tester, 'request_deletion_button').onPressed, isNotNull);
    });

    testWidgets('os botões de pedido não criam nó de botão inerte', (tester) async {
      final handle = tester.ensureSemantics();
      final backend = FakePatientBackend()..myDataResult = overview();
      await pumpMyData(tester, backend);
      await tester.ensureVisible(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      expectNenhumBotaoInerte(tester);
      handle.dispose();
    });
```

No teste existente `'"Copiar meus dados" grava um JSON válido...'`, acrescentar `requests: [openRequest(DataSubjectRequestType.deletion)],` ao `overview(...)`. Depois da asserção de `consentimentos`, acrescentar:

```dart
      expect((decoded['pedidos'] as List).single, {
        'tipo': 'deletion',
        'situacao': 'open',
        'data': DateTime.utc(2026, 9, 1, 12).toIso8601String(),
        'prazo': DateTime.utc(2026, 9, 16, 12).toIso8601String(),
      });
```

Acrescentar `import 'dart:async';` no topo do arquivo de teste se ainda não houver (por causa do `Completer`).

- [ ] **Passo 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart --plain-name "Meus dados"`
Expected: FAIL — `request_deletion_button` não existe.

- [ ] **Passo 3: Diálogo de correção**

Em `app.dart`, logo depois da classe `_MyDataScreenState`:

```dart
/// Pede o texto de uma correção (LGPD-RF08). Devolve o texto já sem espaços
/// nas pontas, ou `null` se a pessoa cancelar. O limite de 500 é o mesmo que o
/// servidor impõe (`correctionDetailsMaxLength`); o servidor revalida, porque
/// o app não é a única origem possível da chamada.
class _CorrectionRequestDialog extends StatefulWidget {
  const _CorrectionRequestDialog();

  @override
  State<_CorrectionRequestDialog> createState() => _CorrectionRequestDialogState();
}

class _CorrectionRequestDialogState extends State<_CorrectionRequestDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = _controller.text.trim();
    return AlertDialog(
      title: const Text('Solicitar correção'),
      content: TextField(
        key: const Key('correction_details_field'),
        controller: _controller,
        maxLength: 500,
        maxLines: 4,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'O que precisa ser corrigido?',
          helperText: 'Condições crônicas você mesmo atualiza em "Perfil clínico".',
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('correction_request_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('correction_request_submit'),
          onPressed: details.isEmpty ? null : () => Navigator.pop(context, details),
          child: const Text('Enviar pedido'),
        ),
      ],
    );
  }
}
```

- [ ] **Passo 4: Ações de pedido em `_MyDataScreenState`**

```dart
  /// Envia um pedido e recarrega. Mesmo formato de [_changeConsent]: `_busy`
  /// desabilita os controles enquanto a chamada está em voo, e é isso que
  /// impede o segundo toque de virar segundo pedido.
  Future<void> _submitRequest(
    Future<PatientDataSubjectRequestRecord> Function(PatientBackend backend) call,
    String done,
  ) async {
    final backend = BackendScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _confirmation = null;
    });
    try {
      final record = await call(backend);
      if (!mounted) return;
      setState(() => _confirmation = '$done. Resposta até ${_formatDate(record.dueAt.toLocal())}.');
      await _load();
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Solicitar exclusão dos seus dados?'),
        content: const Text(
          'A equipe da UBS analisa o pedido em até 15 dias e a resposta aparece aqui. '
          'Registros de saúde (alertas, triagens e visitas) podem ser mantidos pelo prazo '
          'legal de 5 anos e anonimizados depois, em vez de apagados. Enquanto o pedido '
          'estiver em análise, o app continua funcionando — inclusive o botão de emergência.',
        ),
        actions: [
          TextButton(
            key: const Key('deletion_request_cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('deletion_request_confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Solicitar exclusão'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submitRequest((backend) => backend.requestDataDeletion(), 'Pedido de exclusão registrado');
  }

  Future<void> _requestCorrection() async {
    if (_busy) return;
    final details = await showDialog<String>(
      context: context,
      builder: (_) => const _CorrectionRequestDialog(),
    );
    if (details == null || !mounted) return;
    await _submitRequest(
      (backend) => backend.requestDataCorrection(details),
      'Pedido de correção registrado',
    );
  }

  String _requestTypeLabel(DataSubjectRequestType type) => switch (type) {
        DataSubjectRequestType.deletion => 'Exclusão dos dados',
        DataSubjectRequestType.correction => 'Correção de dados',
      };

  String _requestStatusLabel(DataSubjectRequestStatus status) => switch (status) {
        DataSubjectRequestStatus.open => 'Em análise',
        DataSubjectRequestStatus.completed => 'Atendido',
        DataSubjectRequestStatus.rejected => 'Recusado',
      };
```

Em `_toJson`, depois de `'historicoDeClassificacaoDeRisco': [...]`:

```dart
        'pedidos': [
          for (final request in data.requests)
            {
              'tipo': request.type.name,
              'situacao': request.status.name,
              if (request.details != null) 'detalhes': request.details,
              'data': request.createdAt.toIso8601String(),
              'prazo': request.dueAt.toIso8601String(),
            },
        ],
```

- [ ] **Passo 5: Seção de pedidos no `build`**

Acrescentar ao lado de `decisions`, no início do `build`:

```dart
    final openDeletion = data?.requests.any((r) =>
            r.type == DataSubjectRequestType.deletion &&
            r.status == DataSubjectRequestStatus.open) ??
        false;
```

Entre o fim do histórico de risco e o `const SizedBox(height: 16)` que precede o `FilledButton.icon` de exportação, inserir:

```dart
          const SizedBox(height: 16),
          const Text('Pedidos sobre seus dados', style: TextStyle(fontWeight: FontWeight.bold)),
          if (data.requests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Nenhum pedido feito.', style: TextStyle(color: Colors.white54)),
            )
          else
            ...data.requests.map(
              (request) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${_requestTypeLabel(request.type)} · ${_requestStatusLabel(request.status)}'),
                subtitle: Text([
                  'Pedido em ${_formatDate(request.createdAt.toLocal())} · '
                      'resposta até ${_formatDate(request.dueAt.toLocal())}',
                  if (request.details != null) '"${request.details}"',
                ].join('\n')),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('request_deletion_button'),
            onPressed: _busy || openDeletion ? null : _requestDeletion,
            icon: const Icon(Icons.delete_outline),
            label: Text(openDeletion ? 'Exclusão já solicitada — em análise' : 'Solicitar exclusão dos dados'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('request_correction_button'),
            onPressed: _busy ? null : _requestCorrection,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Solicitar correção'),
          ),
```

Atualizar o texto introdutório da tela para: `'Confirmação de que seus dados pessoais estão sendo tratados pelo SinalACS, o que está cadastrado, suas escolhas de consentimento, pedidos de correção ou exclusão, e uma cópia para guardar.'`

- [ ] **Passo 6: Rodar e ver passar**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: tudo verde.

- [ ] **Passo 7: Commit**

```bash
git add apps/patient/lib/app/app.dart apps/patient/test/patient_app_mvp_test.dart
git commit -m "feat(paciente): pedidos de exclusão e correção em Meus dados (LGPD-RF08)"
```

---

### Tarefa 7: Documentação e verificação final

**Arquivos:**
- Modificar: `PROGRESS.md`, `CLAUDE.md`, `backend/CLAUDE.md`

- [ ] **Passo 1: Contagens de schema**

Medir o número de tabelas de domínio no `definition.sql` da migração nova:

```bash
cd backend/sinalacs_server && grep -c '^CREATE TABLE "' migrations/$(ls migrations | grep -v registry | sort | tail -1)/definition.sql
```

Em `backend/CLAUDE.md` (seção `models/`), trocar `16 tables, 6 enums (...)` pelo número medido de tabelas de domínio (esperado: 17). Acrescentar `DataSubjectRequestType` e `DataSubjectRequestStatus` à lista de enums, que passam a ser 8. Em `CLAUDE.md` (raiz), trocar `16 domain tables` pelo mesmo número. Na lista de RPCs do `Project overview` de `CLAUDE.md`, trocar `patients` (`listMicroArea`, `myData`, chronic conditions) por `patients` (`listMicroArea`, `myData`, chronic conditions, `updateConsent`, `requestDataDeletion`, `requestDataCorrection`).

- [ ] **Passo 2: `PROGRESS.md`**

Acrescentar uma seção no fim:

```markdown
## Direitos do titular no app paciente — LGPD-RF05 e LGPD-RF08 (2026-09-28)

"Meus dados" deixou de ser só leitura. O paciente agora:

- **concede ou revoga** por conta própria as duas finalidades opcionais
  (`localReminders`, `segmentedPush`) — `patients.updateConsent` grava uma
  linha nova assinada em `consent_logs` (append-only; a assinatura sai de
  `signedConsentLog`, a mesma função do onboarding). Revogar pede confirmação
  explícita. Revogar lembretes cancela na hora os lembretes agendados no
  aparelho, e o espelho local (`ConsentPreferences`) passa a ser alinhado ao
  servidor sempre que "Meus dados" carrega — o que também resolve o aparelho que
  entrou pelo login OTP sem passar pelo onboarding;
- **pede exclusão** (`patients.requestDataDeletion`, idempotente enquanto houver
  uma aberta) ou **correção** (`patients.requestDataCorrection`, texto livre de
  até 500 caracteres, cifrado com AES-256-GCM em `data_subject_requests`), e vê
  a situação e o prazo (15 dias) de cada pedido.

O que **não** foi feito, de propósito:

- **Ninguém atende os pedidos.** `status` só é escrito como `open`: o backoffice
  (`apps/admin`) ainda roda sobre `MockAdminDataSource`. O prazo de 15 dias é
  exibido mas não é cumprido por sistema nenhum. **Dono:** quem der backend ao
  admin.
- **`healthDataProcessing` não tem interruptor.** É a base legal do app inteiro,
  inclusive do alerta de emergência; `updateConsent` recusa essa finalidade com
  `DataRightsException` e aponta para o pedido de exclusão. Parar o tratamento
  depois da exclusão atendida (LGPD-RF07, "em até 15 dias") depende do mesmo
  atendimento acima.
- **Corrida de dois pedidos de exclusão simultâneos.** A idempotência é
  "procura aberto, senão cria", sem índice único parcial (o Serverpod não
  declara `WHERE` em índice). Dois pedidos concorrentes podem gerar duas linhas
  abertas; no app, o botão desabilitado com o pedido em voo cobre o toque duplo.
- **`segmentedPush` é registrado mas não tem efeito**: não há projeto Firebase
  (RF14). A descrição na tela diz isso.
```

- [ ] **Passo 3: Verificação completa**

Run:
```bash
cd backend/sinalacs_server && dart analyze && dart test
cd ../../apps/patient && flutter analyze && flutter test
cd ../acs && flutter analyze && flutter test
cd ../.. && ./scripts/qa/ci_invariants.sh
```
Expected: tudo verde. Registrar as contagens de testes impressas (backend, paciente) para a mensagem final.

- [ ] **Passo 4: Grafo e commit**

```bash
graphify update .
git add PROGRESS.md CLAUDE.md backend/CLAUDE.md graphify-out
git commit -m "docs(lgpd): registra os direitos do titular no app paciente e o que ficou de fora"
```

- [ ] **Passo 5 (opcional, se a stack local estiver de pé): verificação ponta a ponta**

Use a skill `validacao-e2e`. Com `docker compose up --build`, abra o app paciente no emulador, entre com um paciente do seed, revogue "Lembretes neste aparelho" e peça uma correção. Confira no Postgres: `SELECT purpose, action, "ipHash" FROM consent_logs ORDER BY timestamp DESC LIMIT 1;` e `SELECT "requestType", status, left("detailsEncrypted", 12) FROM data_subject_requests;`. O texto da correção **não** pode aparecer em claro.
