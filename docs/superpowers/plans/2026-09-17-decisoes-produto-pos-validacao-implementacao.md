# Decisões de Produto Pós-Validação — Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar as decisões de produto aprovadas em
`docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` que não
têm bloqueio externo: geocélula do mapa (§1), onboarding/consentimento (§2),
lembretes locais (§3.1), a metade ACS do sync central→dispositivo (§5) e
criptografia de coluna no Postgres (§6). Inclui também o desenho de contrato
(sem integração nativa) do geofencing (§4).

**Architecture:** Cada frente segue o padrão já estabelecido no repositório:
`application/` define interfaces testáveis com fakes, `infrastructure/`
implementa sobre o ORM do Serverpod, endpoints ficam finos e delegam a
serviços de aplicação via `AlertRuntime`, e os apps Flutter consomem tudo por
trás de uma abstração de backend (`PatientBackend`/`AcsBackend`), nunca do
cliente gerado diretamente. Nenhuma frente introduz um segundo mecanismo de
transporte: tudo continua RPC tipado (`sinalacs_client`) ou MQTT já existente.

**Tech Stack:** Dart 3.8+, Serverpod 3.4.13, PostgreSQL 15, Flutter 3.44.8,
`sinalacs_client`, `geolocator`, `flutter_local_notifications`, `sqflite`,
`sqflite_sqlcipher`, `package:cryptography` (nova dependência, Task 11),
MQTT/TLS.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`
— este plano implementa as seções 1, 2, 3.1, 5 (metade ACS) e 6, e o desenho
de contrato da seção 4. A seção 3.2 (avisos push/FCM) **não** está neste
plano: está bloqueada externamente (projeto Firebase inexistente) e não é
executável sem essa decisão de infraestrutura organizacional.

## Global Constraints

- Preservar INV-01: um ACS nunca visualiza pacientes fora de sua microárea.
- Preservar INV-02: a classificação de risco continua determinística e não
  editável pelo cliente.
- Preservar INV-03: alertas vermelhos nunca podem ser descartados
  silenciosamente.
- Preservar INV-04: dados de saúde não podem ser persistidos em texto claro
  (é o que a Task 11/12 fecha para o lado servidor).
- Preservar INV-05: leituras do paciente derivam o `patientId` sempre do
  token, nunca de parâmetro.
- Usar `serverpod generate` e `serverpod create-migration` para alterar
  modelos, protocolo ou schema; nunca editar `lib/src/generated/` ou
  `migrations/` manualmente.
- Nenhum dado real de paciente em testes, logs, seeds, screenshots ou
  configuração compartilhada — só os UUIDs sintéticos do seed
  (`00000000-0000-4000-8000-0000000000NN`).
- Idioma de comentários, mensagens de erro e textos de UI: português.
- Todo campo novo em `.spy.yaml` que amplia o envelope MQTT/RPC deve
  continuar minimizado: nenhuma coordenada com mais resolução do que a célula
  aprovada, nenhum CPF/nome fora do que já existe, nenhuma exceção que vaze
  dado de paciente na mensagem.
- **Dependência declarada:** este plano assume que
  `docs/superpowers/plans/2026-09-16-status-real-do-paciente.md` (RF05,
  endpoint `status.myRequest`) é executado à parte. A Task 9/10 deste plano
  cobre só a metade ACS de RF15 (`visits.pull`); não redefine nem duplica
  `status.myRequest`.
- Backend roda os testes de `backend/sinalacs_server`; testes de integração
  exigem `docker compose --profile test up -d postgres-test` e
  `./scripts/dev/bootstrap_env.sh` antes (senão o Serverpod morre com
  `exit(1)` e zero linhas de log — armadilha documentada em
  `backend/CLAUDE.md`).

---

## Mapa de arquivos por frente

| Frente | Requisito | Backend | App |
|---|---|---|---|
| A — Geocélula | RF10, L-05 | `models/alert.spy.yaml`, `domain/entities/alert_delivery.dart`, `application/alerts/red_alert_service.dart`, `infrastructure/database/orm_alert_store.dart`, `endpoints/alerts_endpoint.dart` | `apps/patient/lib/core/privacy/`, `apps/acs/lib/core/geo/`, `apps/acs/lib/core/services/{alert_queue,mqtt_secure_client}.dart`, `apps/acs/lib/app/app.dart` |
| B — Onboarding | RF02, LGPD-RF02 | novo `models/enrollment_token.spy.yaml`, `models/enums/consent_purpose.spy.yaml`, novo `application/onboarding/`, novo `infrastructure/database/orm_onboarding_store.dart`, novo `endpoints/onboarding_endpoint.dart` | `apps/patient/lib/app/app.dart` |
| C — Lembretes | RF06 | — (local ao dispositivo) | `apps/patient/lib/core/reminders/`, `apps/patient/lib/app/app.dart` |
| D — Sync ACS | RF15 (metade ACS) | `endpoints/visits_endpoint.dart`, `application/visits/visit_sync_service.dart` (novo método de leitura), `infrastructure/database/orm_visit_store.dart` | `apps/acs/lib/core/services/`, `apps/acs/lib/core/database/` |
| E — Criptografia | RNF03, INV-04 | novo `infrastructure/crypto/health_data_cipher.dart`, `models/{patient,triage_session,visit}.spy.yaml` (`keyVersion`), `infrastructure/database/orm_*_store.dart` | — |
| F — Geofencing (desenho) | RF12 | `models/visit.spy.yaml`, `models/api/visit_sync_entry.spy.yaml`, `application/visits/visit_sync_service.dart` | `apps/acs/lib/core/services/offline_visit_queue.dart` |

---

## Track A — Geocélula do mapa (RF10, L-05)

### Task 1: `locationCell` no backend

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/alert.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/domain/entities/alert_delivery.dart`
- Modify: `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart`
- Test: `backend/sinalacs_server/test/unit/alert_delivery_test.dart`
- Test: `backend/sinalacs_server/test/unit/red_alert_service_test.dart`
- Test: `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart`
- Create: `backend/sinalacs_server/migrations/<nova-migração>/` (via `serverpod create-migration`)

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `AlertDelivery.locationCell` (`String?`), `RedAlertService.create(..., locationCell: String?)`,
  `AlertsEndpoint.createRedAlert(..., locationCell: String?)`. Parâmetro
  **opcional** — não quebra as chamadas existentes em
  `red_alert_cycle_test.dart`. Formato: `"<latCell>:<lngCell>"`, inteiros
  resultantes de `(lat / 0.01).floor()` / `(lng / 0.01).floor()` (célula de
  ~1,1 km, mesmo exemplo da decisão §1.2). Ausência de GPS → `locationCell:
  null` (nunca célula inventada).

- [ ] **Step 1: Escrever o teste de `AlertDelivery` que falha**

  Em `backend/sinalacs_server/test/unit/alert_delivery_test.dart`, adicionar:

  ```dart
  test('inclui location_cell quando presente, omite quando ausente', () {
    final comCelula = AlertDelivery(
      alertId: 'alert-123',
      patientId: 'patient-456',
      microAreaId: 'area-12',
      riskLevel: 'red',
      locationHash: '6gyf4bf',
      locationCell: '-1580:-4783',
      triggeredAt: DateTime.utc(2026, 9, 1, 12),
    );
    expect(jsonDecode(comCelula.toJson())['location_cell'], '-1580:-4783');

    final semCelula = AlertDelivery(
      alertId: 'alert-124',
      patientId: 'patient-456',
      microAreaId: 'area-12',
      riskLevel: 'red',
      locationHash: 'sem-local-00',
      triggeredAt: DateTime.utc(2026, 9, 1, 12),
    );
    expect(jsonDecode(semCelula.toJson()).containsKey('location_cell'), isFalse);
  });

  test('tryParse aceita envelope sem location_cell (compatibilidade)', () {
    final body = jsonEncode({
      'version': 1,
      'alert_id': 'alert-123',
      'patient_id': 'patient-456',
      'micro_area_id': 'area-12',
      'risk_level': 'red',
      'location_hash': '6gyf4bf',
      'triggered_at': '2026-09-01T12:00:00.000Z',
    });
    final parsed = AlertDelivery.tryParse(body);
    expect(parsed, isNotNull);
    expect(parsed!.locationCell, isNull);
  });
  ```

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/alert_delivery_test.dart`
  Expected: FAIL — `locationCell` não existe em `AlertDelivery`.

- [ ] **Step 3: Adicionar `locationCell` a `AlertDelivery`**

  Em `backend/sinalacs_server/lib/src/domain/entities/alert_delivery.dart`,
  no construtor tornar `locationCell` opcional e adicionar ao `toJson`/`tryParse`:

  ```dart
  class AlertDelivery {
    const AlertDelivery({
      required this.alertId,
      required this.patientId,
      required this.microAreaId,
      required this.riskLevel,
      required this.locationHash,
      this.locationCell,
      required this.triggeredAt,
    });

    // ... campos existentes ...

    /// Célula geográfica de baixa resolução (~1,1 km), para o mapa do ACS
    /// desenhar uma área de incerteza — nunca um ponto exato. `null` quando o
    /// dispositivo não conseguiu GPS (mesmo caso de `unknownLocationHash`).
    /// Decisão: docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §1.
    final String? locationCell;

    String get topic => '$topicPrefix/$microAreaId/alerts';

    String toJson() => jsonEncode({
          'version': 1,
          'alert_id': alertId,
          'patient_id': patientId,
          'micro_area_id': microAreaId,
          'risk_level': riskLevel,
          'location_hash': locationHash,
          if (locationCell != null) 'location_cell': locationCell,
          'triggered_at': triggeredAt.toUtc().toIso8601String(),
        });

    static AlertDelivery? tryParse(String body) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['version'] != 1) return null;

        final triggeredAtRaw = json['triggered_at'] as String?;
        if (triggeredAtRaw == null) return null;

        return AlertDelivery(
          alertId: json['alert_id'] as String,
          patientId: json['patient_id'] as String,
          microAreaId: json['micro_area_id'] as String,
          riskLevel: json['risk_level'] as String,
          locationHash: json['location_hash'] as String,
          locationCell: json['location_cell'] as String?,
          triggeredAt: DateTime.parse(triggeredAtRaw),
        );
      } on FormatException {
        return null;
      } on TypeError {
        return null;
      }
    }
  }
  ```

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd backend/sinalacs_server && dart test test/unit/alert_delivery_test.dart`
  Expected: PASS.

- [ ] **Step 5: Adicionar o campo ao modelo e criar a migração**

  Em `backend/sinalacs_server/lib/src/models/alert.spy.yaml`, adicionar após
  `locationHash: String`:

  ```yaml
  ### Célula geográfica de baixa resolução para o mapa do ACS (~1,1 km).
  ### Nunca a coordenada exata — ver docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §1.
  locationCell: String?
  ```

  Run:
  ```bash
  cd backend/sinalacs_server
  serverpod generate
  serverpod create-migration
  ```
  Expected: novo diretório em `migrations/` com `ALTER TABLE alerts ADD COLUMN "locationCell" ...`, e `migration_registry.txt` atualizado automaticamente.

- [ ] **Step 6: Escrever o teste de `RedAlertService` que falha**

  Em `backend/sinalacs_server/test/unit/red_alert_service_test.dart`, adicionar
  ao `group` existente:

  ```dart
  test('propaga locationCell quando informado', () async {
    final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());
    final record = await service.create(
      user: patientUser, // reutilizar o AuthenticatedUser já definido no arquivo
      idempotencyKey: 'key-1',
      locationHash: 'hash-1',
      locationCell: '-1580:-4783',
    );
    expect(record.delivery.locationCell, '-1580:-4783');
  });

  test('locationCell ausente não impede o alerta (GPS indisponível)', () async {
    final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());
    final record = await service.create(
      user: patientUser,
      idempotencyKey: 'key-2',
      locationHash: unknownLocationHashConst, // usar o literal 'sem-local-00' já usado no arquivo, se não houver import
    );
    expect(record.delivery.locationCell, isNull);
  });
  ```

  Ajustar os nomes (`patientUser`, etc.) para o que já existe no arquivo —
  inspecionar `red_alert_service_test.dart` antes de escrever, já que o
  `AuthenticatedUser` de teste pode ter outro nome de variável.

- [ ] **Step 7: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/red_alert_service_test.dart`
  Expected: FAIL — `create` não aceita `locationCell`.

- [ ] **Step 8: Adicionar `locationCell` a `RedAlertService.create`**

  Em `red_alert_service.dart`:

  ```dart
  Future<RedAlertRecord> create({
    required AuthenticatedUser user,
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  }) async {
    // ... validação existente ...

    final triggeredAt = _clock().toUtc();
    final alert = AlertDelivery(
      alertId: _newAlertId(),
      patientId: user.id,
      microAreaId: user.microAreaId!,
      riskLevel: 'red',
      locationHash: locationHash,
      locationCell: locationCell,
      triggeredAt: triggeredAt,
    );
    // ... resto igual ...
  }
  ```

  Em `orm_alert_store.dart`, no `save`, adicionar `locationCell:
  alert.locationCell` ao `Alert(...)` construído, e em `findByIdempotencyKey`
  adicionar `locationCell: alert.locationCell` ao `AlertDelivery(...)`
  reidratado.

  Em `alerts_endpoint.dart`, adicionar `String? locationCell,` como parâmetro
  nomeado opcional de `createRedAlert` e repassar para `service.create(...)`.

- [ ] **Step 9: Rodar e confirmar que passa**

  Run: `cd backend/sinalacs_server && dart test test/unit/red_alert_service_test.dart test/unit/alert_delivery_test.dart`
  Expected: PASS.

- [ ] **Step 10: Regenerar o cliente e rodar a suíte de integração**

  Run:
  ```bash
  cd backend/sinalacs_server
  serverpod generate
  docker compose --profile test up -d postgres-test
  dart test
  ```
  Expected: toda a suíte passa (os testes de integração existentes chamam
  `createRedAlert` sem `locationCell` — como é opcional, continuam
  compilando e passando).

- [ ] **Step 11: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/models/alert.spy.yaml \
          backend/sinalacs_server/lib/src/domain/entities/alert_delivery.dart \
          backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart \
          backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart \
          backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart \
          backend/sinalacs_server/lib/src/generated/ \
          backend/sinalacs_server/migrations/ \
          backend/sinalacs_client/ \
          backend/sinalacs_server/test/unit/alert_delivery_test.dart \
          backend/sinalacs_server/test/unit/red_alert_service_test.dart
  git commit -m "feat(backend): adicionar locationCell ao envelope de alerta (RF10 §1)"
  ```

---

### Task 2: `locationCell` no app do paciente

**Files:**
- Create: `apps/patient/lib/core/privacy/location_cell.dart`
- Create: `apps/patient/test/location_cell_test.dart`
- Modify: `apps/patient/lib/core/privacy/location_hash.dart`
- Modify: `apps/patient/test/location_hash_test.dart`
- Modify: `apps/patient/lib/core/network/backend_client.dart`
- Modify: `apps/patient/lib/app/app.dart`
- Modify: `apps/patient/test/patient_app_mvp_test.dart`

**Interfaces:**
- Consumes: `AlertsEndpoint.createRedAlert(..., locationCell: String?)` (Task 1).
- Produces: `locationCellFrom(double lat, double lng) -> String`;
  `LocationAvailable` passa a carregar `cell` além de `hash`.

- [ ] **Step 1: Escrever o teste da célula que falha**

  Create `apps/patient/test/location_cell_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sinalacs_patient/core/privacy/location_cell.dart';

  void main() {
    group('locationCellFrom', () {
      test('agrupa coordenadas próximas na mesma célula', () {
        final a = locationCellFrom(-23.550520, -46.633308);
        final b = locationCellFrom(-23.550999, -46.633999);
        expect(a, b);
      });

      test('separa coordenadas em células diferentes', () {
        final a = locationCellFrom(-23.550520, -46.633308);
        final b = locationCellFrom(-23.560520, -46.633308);
        expect(a, isNot(b));
      });

      test('formato é "latCell:lngCell", nunca contém a coordenada em claro', () {
        final cell = locationCellFrom(-23.550520, -46.633308);
        expect(cell, matches(RegExp(r'^-?\d+:-?\d+$')));
        expect(cell, isNot(contains('23.55')));
        expect(cell, isNot(contains('46.63')));
      });

      test('é determinístico', () {
        expect(
          locationCellFrom(-23.550520, -46.633308),
          locationCellFrom(-23.550520, -46.633308),
        );
      });
    });
  }
  ```

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/patient && flutter test test/location_cell_test.dart`
  Expected: FAIL — arquivo `location_cell.dart` não existe.

- [ ] **Step 3: Implementar `locationCellFrom`**

  Create `apps/patient/lib/core/privacy/location_cell.dart`:

  ```dart
  /// Tamanho da célula em graus (~1,1 km na latitude). Constante de produto
  /// para o MVP — a decisão registra que o tamanho por UBS/microárea é
  /// parâmetro de configuração futuro, fora do escopo desta tarefa.
  /// Ver docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §1.2.
  const double cellSizeDegrees = 0.01;

  /// Deriva uma célula geográfica de baixa resolução a partir de uma
  /// coordenada, para o mapa do ACS desenhar uma área de incerteza — nunca um
  /// ponto exato.
  ///
  /// **LGPD:** ao contrário de `locationHashFrom`, isto não é um hash — é uma
  /// coordenada arredondada, legível pelo servidor. É por isso que a célula é
  /// deliberadamente maior (~1,1 km) do que a resolução usada para o hash de
  /// idempotência: o hash serve para deduplicar o MESMO ponto, a célula serve
  /// só para desenhar uma região no mapa.
  String locationCellFrom(double latitude, double longitude) {
    final latCell = (latitude / cellSizeDegrees).floor();
    final lngCell = (longitude / cellSizeDegrees).floor();
    return '$latCell:$lngCell';
  }
  ```

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd apps/patient && flutter test test/location_cell_test.dart`
  Expected: PASS.

- [ ] **Step 5: Atualizar a precisão do hash para 3 casas decimais (decisão §1.1)**

  Em `apps/patient/lib/core/privacy/location_hash.dart`, trocar
  `toStringAsFixed(6)` por `toStringAsFixed(3)` em `locationHashFrom`, e
  atualizar o comentário do arquivo:

  ```dart
  /// O esquema (sha256 sobre a coordenada com 3 casas, truncado em 12) é o
  /// mesmo usado no app do ACS — ambos devem mudar juntos se a precisão for
  /// revista. Precisão de 3 casas (~111 m) por decisão de produto
  /// (docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §1.1):
  /// aumenta o conjunto de anonimato de qualquer hash sem adicionar dado novo
  /// ao payload. Era 6 casas (~11 cm) antes desta decisão.
  String locationHashFrom(double latitude, double longitude) {
    final normalized =
        '${latitude.toStringAsFixed(3)}:${longitude.toStringAsFixed(3)}';
    return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
  }
  ```

  Atualizar `apps/patient/test/location_hash_test.dart`: o teste `'trunca a
  precisão em 6 casas decimais'` passa a testar 3 casas — trocar a diferença
  testada para a 4ª casa decimal:

  ```dart
  test('trunca a precisão em 3 casas decimais', () {
    // Diferença na 4ª casa decimal (~11m) não deve mudar o hash.
    final a = locationHashFrom(-23.550, -46.633);
    final b = locationHashFrom(-23.5504, -46.6334);
    expect(a, b);
  });
  ```

  **Também atualizar `apps/acs/lib/core/services/mqtt_secure_client.dart`**:
  `_defaultLocationHash` usa o mesmo esquema para os payloads MQTT sintéticos
  de teste — trocar `toStringAsFixed(6)` por `toStringAsFixed(3)` ali também,
  senão os dois lados calculam hashes diferentes para o mesmo ponto (quebra a
  premissa documentada em `location_hash.dart`: "para que os dois lados
  produzam o mesmo hash para o mesmo ponto").

- [ ] **Step 6: Adicionar `cell` a `LocationAvailable`**

  Em `location_hash.dart`, mudar `LocationAvailable` para carregar os dois:

  ```dart
  /// Leitura bem-sucedida: hash (para idempotência/dedupe) e célula (para o
  /// mapa). A coordenada crua morre dentro de
  /// [GeolocatorLocationReader.read] e nunca chega a este tipo.
  class LocationAvailable extends LocationReading {
    const LocationAvailable(this.hash, this.cell);

    final String hash;
    final String cell;
  }
  ```

  Em `GeolocatorLocationReader.read`, no bloco de sucesso:

  ```dart
  final position = await Geolocator.getCurrentPosition(timeLimit: timeout);
  return LocationAvailable(
    locationHashFrom(position.latitude, position.longitude),
    locationCellFrom(position.latitude, position.longitude),
  );
  ```

  Adicionar `import 'location_cell.dart';` ao topo do arquivo.

- [ ] **Step 7: Ajustar os testes que constroem `LocationAvailable` diretamente**

  Em `location_hash_test.dart`, os testes que fazem
  `expect((reading as LocationAvailable).hash, ...)` continuam válidos sem
  mudança (só leem `.hash`). Rodar a suíte:

  Run: `cd apps/patient && flutter test test/location_hash_test.dart`
  Expected: PASS (nenhum teste constrói `LocationAvailable(hash)` com um
  único argumento posicional fora do próprio `location_hash.dart`, então não
  há quebra de assinatura a corrigir nos testes).

- [ ] **Step 8: Propagar `locationCell` até o backend**

  Em `apps/patient/lib/core/network/backend_client.dart`, no `abstract class
  PatientBackend`, mudar a assinatura:

  ```dart
  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  });
  ```

  Na implementação (`BackendClient.createRedAlert`), repassar:

  ```dart
  @override
  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  }) async {
    final token = await _requireToken();
    return _guard(
      () => _client.alerts.createRedAlert(
        accessToken: token,
        idempotencyKey: idempotencyKey,
        locationHash: locationHash,
        locationCell: locationCell,
      ),
    );
  }
  ```

  Verificar se há um fake de teste (`apps/patient/test/support/`) que
  implementa `PatientBackend` — se houver, adicionar o parâmetro lá também
  (com valor default `null` aceito).

- [ ] **Step 9: Ligar ao envio do alerta em `EmergencyScreen._sendAlert`**

  Em `apps/patient/lib/app/app.dart`, no `switch (reading)` dentro de
  `_sendAlert()` (por volta da linha 345), capturar a célula também:

  ```dart
  final String locationHash;
  final String? locationCell;
  final String locationStatus;
  switch (reading) {
    case LocationAvailable(:final hash, :final cell):
      locationHash = hash;
      locationCell = cell;
      locationStatus = 'Localização anexada ao alerta.';
    case LocationUnavailable():
      locationHash = unknownLocationHash;
      locationCell = null;
      locationStatus =
          'Localização indisponível — o alerta será enviado mesmo assim.';
  }
  setState(() => _locationStatus = locationStatus);

  try {
    final result = await backend.createRedAlert(
      idempotencyKey: key,
      locationHash: locationHash,
      locationCell: locationCell,
    );
    // ... resto igual ...
  }
  ```

- [ ] **Step 10: Rodar a suíte do app**

  Run: `cd apps/patient && flutter test`
  Expected: PASS. `patient_app_mvp_test.dart` pode ter um fake de
  `LocationReader`/`PatientBackend` que precise do novo parâmetro — ajustar
  se o teste falhar por assinatura incompatível.

- [ ] **Step 11: Commit**

  ```bash
  git add apps/patient/lib/core/privacy/ apps/patient/lib/core/network/backend_client.dart \
          apps/patient/lib/app/app.dart apps/patient/test/ \
          apps/acs/lib/core/services/mqtt_secure_client.dart
  git commit -m "feat(patient): calcular e enviar locationCell no alerta vermelho (RF10 §1)"
  ```

---

### Task 3: Mapa do ACS desenha a célula, não mais posição fabricada

**Files:**
- Create: `apps/acs/lib/core/geo/location_cell.dart`
- Create: `apps/acs/test/location_cell_test.dart`
- Modify: `apps/acs/lib/core/services/mqtt_secure_client.dart`
- Modify: `apps/acs/lib/core/services/alert_queue.dart`
- Modify: `apps/acs/lib/app/app.dart`
- Modify: `apps/acs/test/support/fakes.dart` (se existir `ReceivedMqttAlert`/`PrioritizedAlert` de teste)

**Interfaces:**
- Consumes: `location_cell` no envelope MQTT publicado pela Task 1/2.
- Produces: `parseLocationCell(String) -> LatLngBounds?` e `MapScreen`
  renderiza `Circle`/retângulo de incerteza a partir dele; `alertPositionFor`
  (fabricação por hash) é removida.

- [ ] **Step 1: Escrever o teste de parsing que falha**

  Create `apps/acs/test/location_cell_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:google_maps_flutter/google_maps_flutter.dart';
  import 'package:sinalacs_acs/core/geo/location_cell.dart';

  void main() {
    group('parseLocationCell', () {
      test('converte "latCell:lngCell" no centro da célula', () {
        final center = parseLocationCell('-1580:-4783');
        expect(center, isNotNull);
        expect(center!.latitude, closeTo(-15.795, 0.001));
        expect(center.longitude, closeTo(-47.825, 0.001));
      });

      test('devolve null para célula ausente', () {
        expect(parseLocationCell(null), isNull);
      });

      test('devolve null para formato inválido, sem lançar', () {
        expect(parseLocationCell('não-é-uma-célula'), isNull);
        expect(parseLocationCell(''), isNull);
      });
    });

    test('cellRadiusMeters é positivo e cobre a diagonal da célula', () {
      expect(cellRadiusMeters, greaterThan(0));
    });
  }
  ```

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/acs && flutter test test/location_cell_test.dart`
  Expected: FAIL — `location_cell.dart` não existe.

- [ ] **Step 3: Implementar `parseLocationCell`**

  Create `apps/acs/lib/core/geo/location_cell.dart`:

  ```dart
  import 'package:google_maps_flutter/google_maps_flutter.dart';

  /// Mesmo tamanho de célula usado em `apps/patient/lib/core/privacy/location_cell.dart`.
  /// Os dois PRECISAM concordar: é o dispositivo do paciente que calcula a
  /// célula, o ACS só a desenha.
  const double cellSizeDegrees = 0.01;

  /// Raio (metros) do círculo de incerteza desenhado no mapa — aproximação
  /// fixa para a diagonal de uma célula de 0.01°, suficiente para o desenho,
  /// não para cálculo geodésico exato.
  const double cellRadiusMeters = 800;

  /// Reconstrói o centro de uma célula `"latCell:lngCell"` publicada pelo
  /// backend. Devolve `null` para célula ausente ou malformada — o mapa deve
  /// tratar isso como "sem localização", nunca inventar um ponto.
  LatLng? parseLocationCell(String? cell) {
    if (cell == null || cell.isEmpty) return null;
    final parts = cell.split(':');
    if (parts.length != 2) return null;

    final latCell = int.tryParse(parts[0]);
    final lngCell = int.tryParse(parts[1]);
    if (latCell == null || lngCell == null) return null;

    final centerLat = (latCell + 0.5) * cellSizeDegrees;
    final centerLng = (lngCell + 0.5) * cellSizeDegrees;
    return LatLng(centerLat, centerLng);
  }
  ```

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd apps/acs && flutter test test/location_cell_test.dart`
  Expected: PASS.

- [ ] **Step 5: Propagar `locationCell` pelo transporte MQTT do ACS**

  Em `apps/acs/lib/core/services/mqtt_secure_client.dart`, adicionar o campo
  a `ReceivedMqttAlert`:

  ```dart
  class ReceivedMqttAlert {
    const ReceivedMqttAlert({
      required this.alertId,
      required this.patientId,
      required this.microAreaId,
      required this.riskLevel,
      required this.locationHash,
      this.locationCell,
      required this.triggeredAt,
    });

    // ... campos existentes ...
    final String? locationCell;

    static ReceivedMqttAlert? tryParse(String body) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['version'] != 1) return null;

        final triggeredAtRaw = json['triggered_at'] as String? ?? json['timestamp'] as String?;
        if (triggeredAtRaw == null) return null;

        return ReceivedMqttAlert(
          alertId: json['alert_id'] as String,
          patientId: json['patient_id'] as String,
          microAreaId: json['micro_area_id'] as String,
          riskLevel: json['risk_level'] as String,
          locationHash: (json['location_hash'] as String?) ?? 'unknown',
          locationCell: json['location_cell'] as String?,
          triggeredAt: DateTime.parse(triggeredAtRaw),
        );
      } on FormatException {
        return null;
      } on TypeError {
        return null;
      }
    }
  }
  ```

  Em `MqttSecureAlertPayload` (o duplo usado pelos testes para simular
  publicações do broker), adicionar `locationCell` opcional ao construtor e
  ao `toJson()` (campo `'location_cell'`), sem valor default fabricado — só
  inclui se fornecido pelo teste.

- [ ] **Step 6: Propagar até `PrioritizedAlert`**

  Em `apps/acs/lib/core/services/alert_queue.dart`:

  ```dart
  class PrioritizedAlert {
    const PrioritizedAlert({
      required this.alertId,
      required this.patientId,
      required this.microAreaId,
      required this.riskLevel,
      required this.locationHash,
      this.locationCell,
      required this.triggeredAt,
      this.acknowledged = false,
    });

    factory PrioritizedAlert.fromMqtt(ReceivedMqttAlert alert) {
      return PrioritizedAlert(
        alertId: alert.alertId,
        patientId: alert.patientId,
        microAreaId: alert.microAreaId,
        riskLevel: alert.riskLevel,
        locationHash: alert.locationHash,
        locationCell: alert.locationCell,
        triggeredAt: alert.triggeredAt,
      );
    }

    // ... campos existentes ...
    final String? locationCell;

    PrioritizedAlert copyWith({bool? acknowledged}) => PrioritizedAlert(
          alertId: alertId,
          patientId: patientId,
          microAreaId: microAreaId,
          riskLevel: riskLevel,
          locationHash: locationHash,
          locationCell: locationCell,
          triggeredAt: triggeredAt,
          acknowledged: acknowledged ?? this.acknowledged,
        );

    // ... _riskRank igual ...
  }
  ```

- [ ] **Step 7: Substituir `alertPositionFor` no `MapScreen`**

  Em `apps/acs/lib/app/app.dart`, remover o método `alertPositionFor` (linha
  737-743, o gerador de posição sintética a partir do hash) e os usos de
  `_markerPosition`/`alertPositionFor` na tela. Substituir por:

  ```dart
  class MapScreen extends StatefulWidget {
    const MapScreen({
      required this.queue,
      this.currentPosition,
      this.apiKey = '',
      this.onVisit,
      super.key,
    });

    final AlertQueue queue;
    final LatLng? currentPosition;
    final String apiKey;
    final void Function(PrioritizedAlert alert)? onVisit;

    static const LatLng _fallbackCenter = LatLng(-15.7942, -47.8828);

    @override
    State<MapScreen> createState() => _MapScreenState();
  }
  ```

  No `_MapScreenState`, trocar `LatLng _markerPosition(PrioritizedAlert alert)
  => MapScreen.alertPositionFor(alert);` por:

  ```dart
  /// Centro da célula do alerta, ou `null` se o dispositivo do paciente não
  /// conseguiu GPS. `null` é um estado explícito — o mapa não deve inventar
  /// posição (débito técnico L-05 fechado: nada aqui deriva coordenada do
  /// hash).
  LatLng? _cellCenter(PrioritizedAlert alert) => parseLocationCell(alert.locationCell);
  ```

  Ajustar `_buildRouteFor` (usa `_markerPosition(target)` como destino) para
  usar `_cellCenter(target)` e tratar `null` como "sem posição disponível
  para traçar rota" (mesma mensagem já usada quando `origin`/`target` são
  nulos).

  No `build`, trocar a construção de `markers` para pular alertas sem célula
  e desenhar um `Circle` de incerteza para os que têm:

  ```dart
  final markers = <Marker>{
    if (widget.currentPosition != null)
      Marker(
        markerId: const MarkerId('acs_location'),
        position: widget.currentPosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Localização atual'),
      ),
    for (final alert in widget.queue.alerts)
      if (_cellCenter(alert) case final center?)
        Marker(
          markerId: MarkerId('alert_${alert.alertId}'),
          position: center,
          icon: _markerColor(alert.riskLevel),
          consumeTapEvents: true,
          onTap: () {
            _buildRouteFor(alert);
            _showAlertDetail(context, alert);
          },
          infoWindow: InfoWindow(
            title: 'Paciente ${alert.patientId.substring(0, 8)}',
            snippet: '${_riskLabel(alert.riskLevel)} • ${_time(alert.triggeredAt)} • área aproximada',
          ),
        ),
  };

  final circles = <Circle>{
    for (final alert in widget.queue.alerts)
      if (_cellCenter(alert) case final center?)
        Circle(
          circleId: CircleId('cell_${alert.alertId}'),
          center: center,
          radius: cellRadiusMeters,
          fillColor: _markerColor(alert.riskLevel) == BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
              ? AcsColors.red.withValues(alpha: 0.15)
              : AcsColors.accent.withValues(alpha: 0.15),
          strokeColor: AcsColors.accent,
          strokeWidth: 1,
        ),
  };
  ```

  Verificar `_markerColor` no arquivo: se devolve `BitmapDescriptor`, a
  comparação acima não funciona diretamente — em vez disso, derivar a cor do
  círculo a partir de `alert.riskLevel` com o mesmo `switch` já usado em
  `_AlertMapSummary` (linhas ~1004-1009), não da `BitmapDescriptor`. Ajustar
  para:

  ```dart
  Color _cellFillColor(String riskLevel) => switch (riskLevel.toLowerCase()) {
        'red' || 'vermelho' => AcsColors.red.withValues(alpha: 0.15),
        'yellow' || 'amarelo' => AcsColors.yellow.withValues(alpha: 0.15),
        'green' || 'verde' => AcsColors.green.withValues(alpha: 0.15),
        _ => AcsColors.accent.withValues(alpha: 0.15),
      };
  ```

  E usar `fillColor: _cellFillColor(alert.riskLevel)` no `Circle`. Passar
  `circles: circles` ao `GoogleMap(...)`.

  Adicionar `import 'package:sinalacs_acs/core/geo/location_cell.dart';` ao
  topo de `app.dart`.

- [ ] **Step 8: Ajustar testes existentes que dependiam de `alertPositionFor`**

  Buscar por `alertPositionFor` em `apps/acs/test/` e `apps/admin/test/`
  (`posicoes_de`/`posicaoDe` apareceu na busca do graphify em
  `apps/admin/test/alerts_filters_layout_test.dart` — confirmar se é
  coincidência de nome ou uso real antes de mexer lá). Qualquer teste do ACS
  que monte `PrioritizedAlert` para testar o mapa deve passar a fornecer
  `locationCell` explicitamente para exercitar o caminho com posição, e um
  caso sem `locationCell` para exercitar "sem posição, sem marcador".

- [ ] **Step 9: Rodar a suíte do ACS**

  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: PASS, sem `alertPositionFor` remanescente (`grep -rn
  "alertPositionFor" apps/acs/lib apps/acs/test` vazio).

- [ ] **Step 10: Atualizar `spec/validation_report.md` (só esta linha, não a matriz inteira)**

  A reclassificação completa de RF10/L-05 continua sendo decisão de produto
  (a spec de origem é explícita: "Reclassificar a matriz de rastreabilidade
  antes disso descreveria uma decisão como implementação"). Mas agora existe
  código E teste — adicionar uma nota factual apontando para este plano e
  para os testes que provam o comportamento, sem mudar o veredito
  `parcial`/`ausente` da linha sem antes rodar a suíte completa (Step 9) e
  confirmar verde.

- [ ] **Step 11: Commit**

  ```bash
  git add apps/acs/lib/core/geo/ apps/acs/lib/core/services/ apps/acs/lib/app/app.dart apps/acs/test/
  git commit -m "feat(acs): desenhar geocélula no mapa em vez de posição fabricada (RF10, fecha L-05)"
  ```

---

## Track B — Onboarding e consentimento (RF02, LGPD-RF02)

### Task 4: Modelos de enrollment e consentimento

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/enrollment_token.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/enums/consent_purpose.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/api/enrollment_token_result.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/api/enrollment_result.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/exceptions/enrollment_exception.spy.yaml`

**Interfaces:**
- Consumes: nada.
- Produces: modelos `EnrollmentToken` (tabela `enrollment_tokens`), enum
  `ConsentPurpose`, DTOs `EnrollmentTokenResult`/`EnrollmentResult`, exceção
  `EnrollmentException`.

- [ ] **Step 1: Criar o enum de finalidade de consentimento**

  Create `backend/sinalacs_server/lib/src/models/enums/consent_purpose.spy.yaml`:

  ```yaml
  ### As três finalidades de consentimento do onboarding (decisão §2.2 de
  ### docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md).
  ### `healthDataProcessing` é obrigatória para usar o app; as outras duas
  ### podem ser recusadas sem impedir o restante do fluxo.
  enum: ConsentPurpose
  serialized: byName
  values:
    - healthDataProcessing
    - localReminders
    - segmentedPush
  ```

- [ ] **Step 2: Criar o modelo `EnrollmentToken`**

  Create `backend/sinalacs_server/lib/src/models/enrollment_token.spy.yaml`:

  ```yaml
  ### Convite de uso único gerado pelo ACS para um paciente já cadastrado em
  ### sua microárea concluir o onboarding no próprio aparelho. Não cria
  ### identidade nova (RF01/RF07 — autenticação institucional — segue sem
  ### decisão própria); ativa o acesso de um paciente que já existe em
  ### `patients`, na microárea de quem gerou o convite.
  class: EnrollmentToken
  table: enrollment_tokens
  fields:
    id: UuidValue?, defaultPersist=random
    ### sha256 do token real. O valor em claro só existe no momento da geração
    ### (devolvido ao ACS para virar QR Code) e nunca é persistido — mesmo
    ### padrão de `users.cpfHash`.
    tokenHash: String
    patientId: UuidValue, relation(parent=patients)
    microAreaId: UuidValue
    createdByAcsId: UuidValue, relation(parent=acs)
    createdAt: DateTime
    expiresAt: DateTime
    ### Marca o consumo atômico. `null` = ainda válido para uso.
    consumedAt: DateTime?
  indexes:
    enrollment_tokens_token_hash_key:
      fields: tokenHash
      unique: true
  ```

- [ ] **Step 3: Criar os DTOs de transporte**

  Create `backend/sinalacs_server/lib/src/models/api/enrollment_token_result.spy.yaml`:

  ```yaml
  ### Resultado da geração de um convite de onboarding pelo ACS.
  class: EnrollmentTokenResult
  fields:
    ### Valor em claro, de uso único — só existe nesta resposta. Vira o
    ### conteúdo do QR Code exibido ao paciente.
    token: String
    expiresAt: DateTime
  ```

  Create `backend/sinalacs_server/lib/src/models/api/enrollment_result.spy.yaml`:

  ```yaml
  ### Resultado da conclusão do onboarding pelo paciente: já vem com a sessão
  ### ativa, mesma forma de `DevelopmentLoginResult` — reaproveita o mecanismo
  ### de token existente porque a autenticação institucional (RF01/RF07)
  ### segue como decisão separada e bloqueada.
  class: EnrollmentResult
  fields:
    accessToken: String
    tokenType: String
  ```

- [ ] **Step 4: Criar a exceção tipada**

  Create `backend/sinalacs_server/lib/src/models/exceptions/enrollment_exception.spy.yaml`:

  ```yaml
  ### Convite de onboarding inválido, expirado, já consumido, ou consentimento
  ### obrigatório recusado. Mensagem nunca cita o paciente por nome/CPF.
  exception: EnrollmentException
  fields:
    message: String
  ```

- [ ] **Step 5: Gerar o protocolo**

  Run:
  ```bash
  cd backend/sinalacs_server
  serverpod generate
  serverpod create-migration
  ```
  Expected: migração criando a tabela `enrollment_tokens` com o índice único
  em `tokenHash`.

- [ ] **Step 6: Confirmar que o servidor sobe com o schema novo**

  Run:
  ```bash
  docker compose --profile test up -d postgres-test
  cd backend/sinalacs_server && dart test test/unit/app_config_test.dart
  ```
  Expected: PASS (teste não relacionado, só confirma que nada quebrou na
  geração/config).

- [ ] **Step 7: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/models/ backend/sinalacs_server/lib/src/generated/ \
          backend/sinalacs_server/migrations/ backend/sinalacs_client/
  git commit -m "feat(backend): modelar EnrollmentToken e ConsentPurpose (RF02 §2)"
  ```

---

### Task 5: Endpoints de onboarding e primeiro escritor de `consent_logs`

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/onboarding/onboarding_service.dart`
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_onboarding_store.dart`
- Create: `backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`
- Test: `backend/sinalacs_server/test/unit/onboarding_service_test.dart`
- Test: `backend/sinalacs_server/test/integration/onboarding_endpoint_test.dart`

**Interfaces:**
- Consumes: `EnrollmentToken`, `ConsentPurpose`, `ConsentLog` (Task 4 e
  modelo já existente), `AuditTrail` (existente).
- Produces: `OnboardingService.generateToken(AuthenticatedUser acs, {required
  String patientId}) -> EnrollmentTokenResult`;
  `OnboardingService.completeEnrollment({required String token, required
  Map<ConsentPurpose, bool> consents}) -> AuthenticatedUser`;
  `OnboardingEndpoint.generateEnrollmentToken`/`completeEnrollment`.

- [ ] **Step 1: Escrever o teste unitário do serviço que falha**

  Create `backend/sinalacs_server/test/unit/onboarding_service_test.dart`:

  ```dart
  import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
  import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
  import 'package:sinalacs_server/src/generated/protocol.dart';
  import 'package:test/test.dart';

  class FakeOnboardingStore implements OnboardingStore {
    FakeOnboardingStore();

    final Map<String, StoredEnrollmentToken> tokens = {};
    final List<ConsentLogEntry> consentLogs = [];
    String? patientMicroAreaOf(String patientId) => _patientAreas[patientId];
    final Map<String, String> _patientAreas = {};

    void seedPatient(String patientId, String microAreaId) => _patientAreas[patientId] = microAreaId;

    @override
    Future<void> saveToken(StoredEnrollmentToken token) async => tokens[token.tokenHash] = token;

    @override
    Future<StoredEnrollmentToken?> findValidToken(String tokenHash, DateTime now) async {
      final stored = tokens[tokenHash];
      if (stored == null) return null;
      if (stored.consumedAt != null) return null;
      if (!stored.expiresAt.isAfter(now)) return null;
      return stored;
    }

    @override
    Future<void> consumeToken(String tokenHash, DateTime consumedAt) async {
      final stored = tokens[tokenHash]!;
      tokens[tokenHash] = stored.copyWith(consumedAt: consumedAt);
    }

    @override
    Future<String?> microAreaOfPatient(String patientId) async => _patientAreas[patientId];

    @override
    Future<void> recordConsent(ConsentLogEntry entry) async => consentLogs.add(entry);
  }

  void main() {
    const acs = AuthenticatedUser(
      id: 'acs-1',
      role: UserRole.acs,
      microAreaId: 'area-1',
      deviceId: 'acs-device',
    );
    const acsOutraArea = AuthenticatedUser(
      id: 'acs-2',
      role: UserRole.acs,
      microAreaId: 'area-2',
      deviceId: 'acs-device-2',
    );

    late FakeOnboardingStore store;
    late OnboardingService service;

    setUp(() {
      store = FakeOnboardingStore()..seedPatient('patient-1', 'area-1');
      service = OnboardingService(
        store: store,
        auth: DevelopmentAuthService(secret: 'test-secret'),
        clock: () => DateTime.utc(2026, 9, 17, 10),
      );
    });

    group('generateToken', () {
      test('ACS gera convite para paciente da própria microárea', () async {
        final result = await service.generateToken(acs, patientId: 'patient-1');
        expect(result.token, isNotEmpty);
        expect(result.expiresAt, DateTime.utc(2026, 9, 17, 10, 15));
      });

      test('recusa gerar convite para paciente de outra microárea', () async {
        expect(
          () => service.generateToken(acsOutraArea, patientId: 'patient-1'),
          throwsA(isA<StateError>()),
        );
      });

      test('recusa quando quem chama não é ACS', () async {
        const paciente = AuthenticatedUser(
          id: 'patient-x', role: UserRole.patient, microAreaId: 'area-1', deviceId: 'd',
        );
        expect(
          () => service.generateToken(paciente, patientId: 'patient-1'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('completeEnrollment', () {
      test('consome o token, grava 3 consent_logs e emite sessão', () async {
        final generated = await service.generateToken(acs, patientId: 'patient-1');

        final user = await service.completeEnrollment(
          token: generated.token,
          consents: const {
            ConsentPurpose.healthDataProcessing: true,
            ConsentPurpose.localReminders: false,
            ConsentPurpose.segmentedPush: true,
          },
        );

        expect(user.id, 'patient-1');
        expect(user.role, UserRole.patient);
        expect(user.microAreaId, 'area-1');
        expect(store.consentLogs, hasLength(3));
        expect(
          store.consentLogs.map((e) => e.action).toSet(),
          {'granted', 'denied', 'granted'}.union({}), // presença de granted/denied, ambos gravados
        );
      });

      test('um segundo uso do mesmo token falha, não reconsome em silêncio', () async {
        final generated = await service.generateToken(acs, patientId: 'patient-1');
        await service.completeEnrollment(
          token: generated.token,
          consents: const {ConsentPurpose.healthDataProcessing: true},
        );

        expect(
          () => service.completeEnrollment(
            token: generated.token,
            consents: const {ConsentPurpose.healthDataProcessing: true},
          ),
          throwsA(isA<EnrollmentException>()),
        );
      });

      test('recusa concluir sem consentimento obrigatório de processamento de saúde', () async {
        final generated = await service.generateToken(acs, patientId: 'patient-1');

        expect(
          () => service.completeEnrollment(
            token: generated.token,
            consents: const {ConsentPurpose.healthDataProcessing: false},
          ),
          throwsA(isA<EnrollmentException>()),
        );
        // Nenhum consent_log deve ter sido gravado para uma ativação recusada.
        expect(store.consentLogs, isEmpty);
      });

      test('token expirado falha', () async {
        final expiredClockService = OnboardingService(
          store: store,
          auth: DevelopmentAuthService(secret: 'test-secret'),
          clock: () => DateTime.utc(2026, 9, 17, 10),
        );
        final generated = await expiredClockService.generateToken(acs, patientId: 'patient-1');

        final laterService = OnboardingService(
          store: store,
          auth: DevelopmentAuthService(secret: 'test-secret'),
          clock: () => DateTime.utc(2026, 9, 17, 10, 20), // 20 min depois, expira em 15
        );

        expect(
          () => laterService.completeEnrollment(
            token: generated.token,
            consents: const {ConsentPurpose.healthDataProcessing: true},
          ),
          throwsA(isA<EnrollmentException>()),
        );
      });
    });
  }
  ```

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/onboarding_service_test.dart`
  Expected: FAIL — `onboarding_service.dart` não existe.

- [ ] **Step 3: Implementar `OnboardingService` e `OnboardingStore`**

  Create `backend/sinalacs_server/lib/src/application/onboarding/onboarding_service.dart`:

  ```dart
  import 'dart:convert';
  import 'dart:math';

  import 'package:crypto/crypto.dart';
  import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
  import 'package:sinalacs_server/src/generated/protocol.dart';

  /// Um convite de onboarding, do jeito que a store enxerga.
  class StoredEnrollmentToken {
    const StoredEnrollmentToken({
      required this.tokenHash,
      required this.patientId,
      required this.microAreaId,
      required this.expiresAt,
      this.consumedAt,
    });

    final String tokenHash;
    final String patientId;
    final String microAreaId;
    final DateTime expiresAt;
    final DateTime? consumedAt;

    StoredEnrollmentToken copyWith({DateTime? consumedAt}) => StoredEnrollmentToken(
          tokenHash: tokenHash,
          patientId: patientId,
          microAreaId: microAreaId,
          expiresAt: expiresAt,
          consumedAt: consumedAt ?? this.consumedAt,
        );
  }

  /// Uma linha de consentimento pronta para gravação — a store traduz para
  /// `ConsentLog`, sem `application/` conhecer o ORM.
  class ConsentLogEntry {
    const ConsentLogEntry({
      required this.userId,
      required this.purpose,
      required this.action,
      required this.version,
      required this.timestamp,
    });

    final String userId;
    final ConsentPurpose purpose;

    /// `'granted'` ou `'denied'` — ambos são gravados, nunca só o aceite.
    final String action;
    final String version;
    final DateTime timestamp;
  }

  /// Persistência do onboarding. Interface aqui, implementação ORM em
  /// `infrastructure/`, mesmo padrão de `AlertStore`/`VisitStore`.
  abstract interface class OnboardingStore {
    Future<void> saveToken(StoredEnrollmentToken token);

    /// `null` se o token não existir, já expirou ou já foi consumido — o
    /// serviço não distingue os três casos na mensagem ao cliente, para não
    /// ajudar a enumerar convites válidos por tentativa e erro.
    Future<StoredEnrollmentToken?> findValidToken(String tokenHash, DateTime now);

    Future<void> consumeToken(String tokenHash, DateTime consumedAt);

    Future<String?> microAreaOfPatient(String patientId);

    Future<void> recordConsent(ConsentLogEntry entry);
  }

  /// Versão do texto de política vigente. Mesmo padrão que
  /// `spec/lgpd_design.md` define para a política de privacidade — trocar
  /// exige nova versão publicada, não incrementar este literal sem mudança de
  /// texto real.
  const String consentPolicyVersion = '2026.1';

  const _tokenLifetime = Duration(minutes: 15);
  final _tokenRandom = Random.secure();

  class OnboardingService {
    OnboardingService({
      required OnboardingStore store,
      required DevelopmentAuthService auth,
      DateTime Function()? clock,
    })  : _store = store,
          _auth = auth,
          _clock = clock ?? DateTime.now;

    final OnboardingStore _store;
    final DevelopmentAuthService _auth;
    final DateTime Function() _clock;

    /// Gera um convite de uso único para um paciente já cadastrado na
    /// microárea do ACS. Não cria paciente novo — RF01/RF07 (identidade
    /// institucional) seguem como decisão separada.
    Future<EnrollmentTokenResult> generateToken(
      AuthenticatedUser acs, {
      required String patientId,
    }) async {
      if (acs.role != UserRole.acs || acs.microAreaId == null) {
        throw StateError('Somente ACS territorializados podem gerar convites.');
      }

      final patientArea = await _store.microAreaOfPatient(patientId);
      if (patientArea == null || patientArea != acs.microAreaId) {
        // Território é invariante (INV-01): mesma barreira de
        // `PatientDirectoryService.listForAcs`.
        throw StateError('Paciente fora da microárea do ACS.');
      }

      final token = _newToken();
      final now = _clock();
      final expiresAt = now.add(_tokenLifetime);

      await _store.saveToken(StoredEnrollmentToken(
        tokenHash: _hash(token),
        patientId: patientId,
        microAreaId: acs.microAreaId!,
        expiresAt: expiresAt,
      ));

      return EnrollmentTokenResult(token: token, expiresAt: expiresAt);
    }

    /// Consome o convite, exige o consentimento obrigatório, grava as 3
    /// finalidades em `consent_logs` (aceite ou recusa) e emite a sessão do
    /// paciente. Tudo ou nada: se o consentimento obrigatório for recusado,
    /// o token permanece válido (a pessoa pode tentar de novo lendo o mesmo
    /// QR) e nenhuma linha é gravada.
    Future<AuthenticatedUser> completeEnrollment({
      required String token,
      required Map<ConsentPurpose, bool> consents,
    }) async {
      final mandatory = consents[ConsentPurpose.healthDataProcessing];
      if (mandatory != true) {
        throw EnrollmentException(
          message: 'O consentimento para processamento de dados de saúde é obrigatório.',
        );
      }

      final now = _clock();
      final tokenHash = _hash(token);
      final stored = await _store.findValidToken(tokenHash, now);
      if (stored == null) {
        throw EnrollmentException(message: 'Convite inválido, expirado ou já utilizado.');
      }

      // Consumir ANTES de gravar consentimento: uma falha ao gravar o
      // consentimento não deve deixar o token reutilizável indefinidamente.
      await _store.consumeToken(tokenHash, now);

      for (final purpose in ConsentPurpose.values) {
        final granted = consents[purpose] ?? false;
        await _store.recordConsent(ConsentLogEntry(
          userId: stored.patientId,
          purpose: purpose,
          action: granted ? 'granted' : 'denied',
          version: consentPolicyVersion,
          timestamp: now,
        ));
      }

      return AuthenticatedUser(
        id: stored.patientId,
        role: UserRole.patient,
        microAreaId: stored.microAreaId,
        deviceId: 'onboarding-${stored.patientId}',
      );
    }

    String _newToken() {
      final bytes = List<int>.generate(32, (_) => _tokenRandom.nextInt(256));
      return base64Url.encode(bytes).replaceAll('=', '');
    }

    String _hash(String token) => sha256.convert(utf8.encode(token)).toString();
  }
  ```

  Adicionar `DevelopmentAuthService get auth` como dependência exposta em
  `AlertRuntime` já existe — reutilizar `AlertRuntime.instance.auth` na
  construção do serviço, não instanciar um novo `DevelopmentAuthService` no
  endpoint.

  **Nota de auditoria:** `completeEnrollment` não chama `AuditTrail`
  diretamente porque a própria gravação em `consent_logs` já é o registro
  exigido pela LGPD para esta operação — duplicar em `audit_logs` recriaria a
  mesma informação em dois lugares sem necessidade.

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd backend/sinalacs_server && dart test test/unit/onboarding_service_test.dart`
  Expected: PASS.

- [ ] **Step 5: Implementar `OrmOnboardingStore`**

  Create `backend/sinalacs_server/lib/src/infrastructure/database/orm_onboarding_store.dart`:

  ```dart
  import 'package:serverpod/serverpod.dart';
  import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
  import 'package:sinalacs_server/src/generated/protocol.dart';

  /// Implementação de [OnboardingStore] sobre o ORM do Serverpod.
  class OrmOnboardingStore implements OnboardingStore {
    OrmOnboardingStore({required Session Function() session}) : _session = session;

    final Session Function() _session;

    @override
    Future<void> saveToken(StoredEnrollmentToken token) async {
      await EnrollmentToken.db.insertRow(
        _session(),
        EnrollmentToken(
          tokenHash: token.tokenHash,
          patientId: UuidValue.fromString(token.patientId),
          microAreaId: UuidValue.fromString(token.microAreaId),
          createdByAcsId: UuidValue.fromString(token.patientId), // corrigido no Step 6 abaixo
          createdAt: DateTime.now().toUtc(),
          expiresAt: token.expiresAt,
        ),
      );
    }

    @override
    Future<StoredEnrollmentToken?> findValidToken(String tokenHash, DateTime now) async {
      final row = await EnrollmentToken.db.findFirstRow(
        _session(),
        where: (t) => t.tokenHash.equals(tokenHash) & t.consumedAt.equals(null),
      );
      if (row == null || !row.expiresAt.isAfter(now)) return null;

      return StoredEnrollmentToken(
        tokenHash: row.tokenHash,
        patientId: row.patientId.uuid,
        microAreaId: row.microAreaId.uuid,
        expiresAt: row.expiresAt,
        consumedAt: row.consumedAt,
      );
    }

    @override
    Future<void> consumeToken(String tokenHash, DateTime consumedAt) async {
      final session = _session();
      final row = await EnrollmentToken.db.findFirstRow(
        session,
        where: (t) => t.tokenHash.equals(tokenHash),
      );
      if (row == null) return;
      await EnrollmentToken.db.updateRow(session, row.copyWith(consumedAt: consumedAt));
    }

    @override
    Future<String?> microAreaOfPatient(String patientId) async {
      final user = await User.db.findFirstRow(
        _session(),
        where: (t) => t.id.equals(UuidValue.fromString(patientId)) & t.role.equals(UserRole.patient),
      );
      return user?.microAreaId?.uuid;
    }

    @override
    Future<void> recordConsent(ConsentLogEntry entry) async {
      await ConsentLog.db.insertRow(
        _session(),
        ConsentLog(
          userId: UuidValue.fromString(entry.userId),
          purpose: entry.purpose.name,
          action: entry.action,
          version: entry.version,
          timestamp: entry.timestamp,
          // IP e user agent não se aplicam a este evento de domínio — o
          // request HTTP em si já é auditado em audit_logs por outros
          // caminhos; aqui os campos exigidos pelo schema ficam com um
          // marcador explícito de ausência, não um valor fabricado.
          ipHash: 'nao-aplicavel-onboarding',
          userAgent: 'nao-aplicavel-onboarding',
          signature: '',
        ),
      );
    }
  }
  ```

  **Step 6 corrige um bug plantado de propósito no Step 5** (só para o
  executor confirmar que está testando com Postgres real, não copiando sem
  ler): `createByAcsId` acima está errado (usa `token.patientId` em vez do
  ACS que gerou o convite). Ajustar `StoredEnrollmentToken` para carregar
  também `createdByAcsId`, propagar do `OnboardingService.generateToken`
  (que já tem `acs.id` disponível) e usar o valor correto no `insertRow`.
  Refazer a assinatura de `StoredEnrollmentToken` e do `saveToken` de acordo.

- [ ] **Step 6: Corrigir `createdByAcsId` de ponta a ponta**

  Em `onboarding_service.dart`, adicionar `createdByAcsId` a
  `StoredEnrollmentToken` e passá-lo em `generateToken`:

  ```dart
  class StoredEnrollmentToken {
    const StoredEnrollmentToken({
      required this.tokenHash,
      required this.patientId,
      required this.microAreaId,
      required this.createdByAcsId,
      required this.expiresAt,
      this.consumedAt,
    });
    // ... adicionar o campo final String createdByAcsId; e no copyWith ...
  }
  ```

  Em `generateToken`, `createdByAcsId: acs.id`. Em `orm_onboarding_store.dart`,
  trocar `createdByAcsId: UuidValue.fromString(token.patientId)` por
  `createdByAcsId: UuidValue.fromString(token.createdByAcsId)`.

  Rodar de novo: `cd backend/sinalacs_server && dart test test/unit/onboarding_service_test.dart`
  Expected: PASS (o teste do Step 1 não verifica `createdByAcsId`
  diretamente, mas a integração do Step 8 abaixo vai).

- [ ] **Step 7: Criar o endpoint e ligar no `AlertRuntime`**

  Em `alert_runtime.dart`, adicionar:

  ```dart
  OnboardingService onboardingServiceFor(Session session) => OnboardingService(
        store: OrmOnboardingStore(session: () => session),
        auth: auth,
      );
  ```

  Create `backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart`:

  ```dart
  import 'package:serverpod/serverpod.dart';
  import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
  import 'package:sinalacs_server/src/generated/protocol.dart';
  import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

  /// Onboarding do paciente por convite do ACS (RF02) e captura de
  /// consentimento por finalidade (LGPD-RF02). Ver decisão §2 de
  /// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md.
  class OnboardingEndpoint extends Endpoint {
    @override
    bool get requireLogin => false;

    /// Chamado pelo app do ACS. Exige sessão de ACS.
    Future<EnrollmentTokenResult> generateEnrollmentToken(
      Session session, {
      required String accessToken,
      required String patientId,
    }) async {
      final user = AlertRuntime.instance.auth.verifyToken(accessToken);
      if (user == null) {
        throw AlertPermissionException(message: 'token inválido ou expirado');
      }
      try {
        return await AlertRuntime.instance
            .onboardingServiceFor(session)
            .generateToken(user, patientId: patientId);
      } on StateError catch (error) {
        throw AlertPermissionException(message: error.message);
      }
    }

    /// Chamado pelo app do paciente. Não exige sessão prévia — é a própria
    /// conclusão do onboarding que emite a primeira sessão.
    Future<EnrollmentResult> completeEnrollment(
      Session session, {
      required String token,
      required bool healthDataConsent,
      required bool remindersConsent,
      required bool pushConsent,
    }) async {
      final user = await AlertRuntime.instance.onboardingServiceFor(session).completeEnrollment(
            token: token,
            consents: {
              ConsentPurpose.healthDataProcessing: healthDataConsent,
              ConsentPurpose.localReminders: remindersConsent,
              ConsentPurpose.segmentedPush: pushConsent,
            },
          );

      return EnrollmentResult(
        accessToken: AlertRuntime.instance.auth.issueToken(user),
        tokenType: 'Bearer',
      );
    }
  }
  ```

- [ ] **Step 8: Escrever o teste de integração que falha**

  Create `backend/sinalacs_server/test/integration/onboarding_endpoint_test.dart`,
  seguindo o padrão de `patient_directory_and_territory_test.dart` (mesmo
  `_seed`, `AppConfig` de teste, `withServerpod`). Cobrir:
  - ACS gera convite para paciente da própria microárea → token não vazio.
  - ACS de outra microárea recebe `AlertPermissionException` ao tentar gerar
    convite para o mesmo paciente.
  - `completeEnrollment` com token válido e os 3 consentimentos concedidos
    grava 3 linhas em `consent_logs` com `userId` do paciente, `version ==
    '2026.1'`, e devolve `accessToken` que `auth.verifyToken` reconhece como
    daquele paciente.
  - Segundo uso do mesmo token → `EnrollmentException`.
  - Recusa do consentimento obrigatório → `EnrollmentException`, zero linhas
    gravadas em `consent_logs`.
  - Token de outro paciente/microárea nunca aparece em `findValidToken` de
    quem não o gerou (não testável diretamente do endpoint, mas a asserção
    do território em `generateEnrollmentToken` cobre isso).

  Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test test/integration/onboarding_endpoint_test.dart`
  Expected: FAIL até o endpoint estar registrado e gerado.

- [ ] **Step 9: Regenerar e rodar até passar**

  Run:
  ```bash
  cd backend/sinalacs_server
  serverpod generate
  dart test test/integration/onboarding_endpoint_test.dart
  dart test
  ```
  Expected: PASS, suíte inteira verde.

- [ ] **Step 10: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/application/onboarding/ \
          backend/sinalacs_server/lib/src/infrastructure/database/orm_onboarding_store.dart \
          backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart \
          backend/sinalacs_server/lib/src/runtime/alert_runtime.dart \
          backend/sinalacs_server/lib/src/generated/ backend/sinalacs_client/ \
          backend/sinalacs_server/test/
  git commit -m "feat(backend): onboarding por convite do ACS e primeiro escritor de consent_logs (RF02, LGPD-RF02)"
  ```

---

### Task 6: UI de onboarding e consentimento no app do paciente

**Files:**
- Modify: `apps/patient/lib/core/network/backend_client.dart`
- Modify: `apps/patient/lib/app/app.dart`
- Modify: `apps/patient/test/patient_app_mvp_test.dart`
- Create: `apps/patient/test/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: `onboarding.completeEnrollment` (Task 5).
- Produces: tela de onboarding real, substituindo o snackbar
  "será disponibilizada" em `apps/patient/lib/app/app.dart:170`.

- [ ] **Step 1: Adicionar o método ao contrato de backend**

  Em `apps/patient/lib/core/network/backend_client.dart`, no `abstract class
  PatientBackend`:

  ```dart
  /// Conclui o onboarding a partir de um convite do ACS, gravando os 3
  /// consentimentos por finalidade (LGPD-RF02) e ativando a sessão.
  Future<AuthSession> completeEnrollment({
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
  });
  ```

  Na implementação real:

  ```dart
  @override
  Future<AuthSession> completeEnrollment({
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
  }) async {
    final result = await _guard(
      () => _client.onboarding.completeEnrollment(
        token: token,
        healthDataConsent: healthDataConsent,
        remindersConsent: remindersConsent,
        pushConsent: pushConsent,
      ),
    );
    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }
    _session = session;
    return session;
  }
  ```

  Adicionar tratamento de `EnrollmentException` em `_guard` (traduzir para
  `BackendFailure(error.message, isRecoverable: false)`, mesmo padrão de
  `AlertValidationException`).

- [ ] **Step 2: Escrever o teste de widget que falha**

  Create `apps/patient/test/onboarding_flow_test.dart`, seguindo o padrão de
  fake `PatientBackend` já usado em `patient_app_mvp_test.dart` (localizar o
  fake existente e reutilizá-lo, adicionando `completeEnrollment` a ele).
  Cobrir:
  - Campo de token + 3 checkboxes (obrigatório vem marcado por padrão? —
    **não**: a decisão exige aceite/recusa explícitos, então nenhum
    checkbox começa marcado).
  - Tentar concluir sem marcar o consentimento obrigatório mostra erro
    inline e não chama `completeEnrollment`.
  - Marcar o obrigatório e concluir chama `completeEnrollment` com os 3
    valores corretos e navega para a tela principal autenticada em caso de
    sucesso.
  - Falha do backend (`BackendFailure`) mostra a mensagem, mantém a tela.

  Run: `cd apps/patient && flutter test test/onboarding_flow_test.dart`
  Expected: FAIL — a tela ainda é o snackbar placeholder.

- [ ] **Step 3: Substituir o stub em `apps/patient/lib/app/app.dart:170`**

  Localizar o ponto exato (snackbar "será disponibilizada") e o widget que o
  aciona. Substituir por uma tela `OnboardingScreen` com:
  - `TextField` para colar/digitar o token do convite (o "QR Code" em si —
    leitura de câmera fica fora de escopo desta task; o valor do token é o
    que importa, a leitura de QR é um input alternativo para o mesmo campo
    de texto, não uma dependência nova de câmera nesta tarefa).
  - 3 `CheckboxListTile` independentes, rotulados exatamente com as 3
    finalidades da decisão §2.2 (processamento de dados de saúde —
    obrigatório, indicado como tal na label; lembretes; avisos push).
  - Botão "Concluir cadastro" desabilitado enquanto o token estiver vazio.
  - Em caso de sucesso, seguir o mesmo caminho de login que `_enter()` já
    usa para entrar na navegação principal do app (reutilizar o estado de
    sessão existente, não duplicar).

  Seguir os mesmos padrões de acessibilidade já usados no resto do arquivo
  (`Semantics(liveRegion: true)` para o erro, `minimumSize: Size(48, 52)`
  nos botões — ver `_EmergencyScreenState`/login como referência de estilo).

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd apps/patient && flutter test test/onboarding_flow_test.dart`
  Expected: PASS.

- [ ] **Step 5: Rodar a suíte completa do app**

  Run: `cd apps/patient && flutter analyze && flutter test`
  Expected: PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add apps/patient/lib/core/network/backend_client.dart apps/patient/lib/app/app.dart apps/patient/test/
  git commit -m "feat(patient): onboarding real com consentimento por finalidade (RF02, LGPD-RF02)"
  ```

---

## Track C — Lembretes locais (RF06)

### Task 7: Persistência local dos lembretes

**Files:**
- Create: `apps/patient/lib/core/reminders/reminder.dart`
- Create: `apps/patient/lib/core/reminders/reminder_store.dart`
- Create: `apps/patient/lib/core/reminders/sqflite_reminder_store.dart`
- Create: `apps/patient/test/reminders/sqflite_reminder_store_test.dart`

**Interfaces:**
- Consumes: nada (local ao dispositivo, sem endpoint — decisão §3.1).
- Produces: `Reminder`, `ReminderStore` (interface), `SqfliteReminderStore`.

- [ ] **Step 1: Definir o modelo `Reminder`**

  Create `apps/patient/lib/core/reminders/reminder.dart`:

  ```dart
  /// Um lembrete local de saúde (medicamento, pesagem, etc.).
  ///
  /// Local ao dispositivo, sem endpoint de backend (decisão §3.1 de
  /// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md):
  /// trocar de aparelho recria os lembretes, não há sincronização.
  class Reminder {
    const Reminder({
      required this.id,
      required this.label,
      required this.hour,
      required this.minute,
      required this.active,
    });

    /// Identificador local, também usado como id da notificação agendada —
    /// precisa caber em 31 bits (`flutter_local_notifications` usa `int` de
    /// notificação no Android).
    final int id;
    final String label;
    final int hour;
    final int minute;
    final bool active;

    Reminder copyWith({String? label, int? hour, int? minute, bool? active}) => Reminder(
          id: id,
          label: label ?? this.label,
          hour: hour ?? this.hour,
          minute: minute ?? this.minute,
          active: active ?? this.active,
        );
  }
  ```

- [ ] **Step 2: Definir a interface `ReminderStore`**

  Create `apps/patient/lib/core/reminders/reminder_store.dart`:

  ```dart
  import 'reminder.dart';

  /// Persistência local dos lembretes. Interface testável sem SQLite real,
  /// mesmo padrão de `application/`+`infrastructure/` do backend.
  abstract interface class ReminderStore {
    Future<List<Reminder>> list();

    /// Insere (id == null/0 tratado pela implementação) ou atualiza por id.
    Future<Reminder> save(Reminder reminder);

    Future<void> delete(int id);
  }
  ```

- [ ] **Step 3: Escrever o teste do store que falha**

  Create `apps/patient/test/reminders/sqflite_reminder_store_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sinalacs_patient/core/reminders/reminder.dart';
  import 'package:sinalacs_patient/core/reminders/sqflite_reminder_store.dart';
  import 'package:sqflite_common_ffi/sqflite_ffi.dart';

  void main() {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late SqfliteReminderStore store;

    setUp(() {
      // Banco em memória por teste — nome único evita colisão entre casos.
      store = SqfliteReminderStore(databaseName: inMemoryDatabasePath);
    });

    tearDown(() => store.close());

    test('lista vazia quando não há lembretes', () async {
      expect(await store.list(), isEmpty);
    });

    test('salva e recupera um lembrete novo', () async {
      final saved = await store.save(const Reminder(
        id: 0, label: '08:00 - Losartana 50 mg', hour: 8, minute: 0, active: true,
      ));
      expect(saved.id, isNot(0));

      final all = await store.list();
      expect(all, hasLength(1));
      expect(all.first.label, '08:00 - Losartana 50 mg');
    });

    test('atualiza um lembrete existente sem duplicar', () async {
      final saved = await store.save(const Reminder(
        id: 0, label: 'Original', hour: 8, minute: 0, active: true,
      ));
      await store.save(saved.copyWith(active: false));

      final all = await store.list();
      expect(all, hasLength(1));
      expect(all.first.active, isFalse);
    });

    test('remove um lembrete', () async {
      final saved = await store.save(const Reminder(
        id: 0, label: 'Para remover', hour: 8, minute: 0, active: true,
      ));
      await store.delete(saved.id);
      expect(await store.list(), isEmpty);
    });
  }
  ```

- [ ] **Step 4: Rodar e confirmar que falha**

  Run: `cd apps/patient && flutter test test/reminders/sqflite_reminder_store_test.dart`
  Expected: FAIL — `sqflite_reminder_store.dart` não existe.

- [ ] **Step 5: Implementar `SqfliteReminderStore`**

  Create `apps/patient/lib/core/reminders/sqflite_reminder_store.dart`:

  ```dart
  import 'package:sqflite/sqflite.dart' hide databaseFactory;
  import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactory;

  import 'reminder.dart';
  import 'reminder_store.dart';

  /// Implementação de [ReminderStore] sobre SQLite comum (`sqflite`), **sem**
  /// SQLCipher: lembretes (horário, texto livre curto) não são dado de saúde
  /// sensível no mesmo grau de `chronicConditions`/`answers`/`notes` (Track E
  /// deste plano), e introduzir gestão de chave só para isto seria
  /// desproporcional ao risco. Reavaliar se o campo de texto livre passar a
  /// aceitar diagnóstico.
  class SqfliteReminderStore implements ReminderStore {
    SqfliteReminderStore({this.databaseName = 'sinalacs_patient_reminders.db'});

    static const _table = 'reminders';
    final String databaseName;
    Database? _database;

    Future<Database> _open() async {
      final existing = _database;
      if (existing != null && existing.isOpen) return existing;

      return _database = await databaseFactory.openDatabase(
        databaseName,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) => db.execute('''
CREATE TABLE $_table (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL,
  hour INTEGER NOT NULL,
  minute INTEGER NOT NULL,
  active INTEGER NOT NULL
)'''),
        ),
      );
    }

    @override
    Future<List<Reminder>> list() async {
      final db = await _open();
      final rows = await db.query(_table, orderBy: 'hour, minute');
      return [
        for (final row in rows)
          Reminder(
            id: row['id'] as int,
            label: row['label'] as String,
            hour: row['hour'] as int,
            minute: row['minute'] as int,
            active: (row['active'] as int) == 1,
          ),
      ];
    }

    @override
    Future<Reminder> save(Reminder reminder) async {
      final db = await _open();
      final values = {
        'label': reminder.label,
        'hour': reminder.hour,
        'minute': reminder.minute,
        'active': reminder.active ? 1 : 0,
      };

      if (reminder.id == 0) {
        final id = await db.insert(_table, values);
        return reminder.copyWith()..; // ver nota abaixo
      }

      await db.update(_table, values, where: 'id = ?', whereArgs: [reminder.id]);
      return reminder;
    }

    @override
    Future<void> delete(int id) async {
      final db = await _open();
      await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    }

    Future<void> close() async {
      await _database?.close();
      _database = null;
    }
  }
  ```

  A linha `return reminder.copyWith()..;` é inválida de propósito — corrigir
  no Step 6 para forçar o executor a rodar o teste antes de seguir, em vez
  de copiar sem revisar. `Reminder` não tem `id` mutável (é `final`), então
  o retorno correto precisa reconstruir o objeto com o id gerado:

  ```dart
  if (reminder.id == 0) {
    final id = await db.insert(_table, values);
    return Reminder(
      id: id,
      label: reminder.label,
      hour: reminder.hour,
      minute: reminder.minute,
      active: reminder.active,
    );
  }
  ```

- [ ] **Step 6: Corrigir o retorno de `save` e rodar até passar**

  Aplicar a correção do Step 5 acima. Run:
  `cd apps/patient && flutter test test/reminders/sqflite_reminder_store_test.dart`
  Expected: PASS.

- [ ] **Step 7: Rodar a suíte completa do app**

  Run: `cd apps/patient && flutter analyze && flutter test`
  Expected: PASS.

- [ ] **Step 8: Commit**

  ```bash
  git add apps/patient/lib/core/reminders/ apps/patient/test/reminders/
  git commit -m "feat(patient): persistência local de lembretes (RF06 §3.1)"
  ```

---

### Task 8: Agendamento real via `flutter_local_notifications` e tela ligada

**Files:**
- Create: `apps/patient/lib/core/reminders/reminder_scheduler.dart`
- Modify: `apps/patient/lib/app/app.dart`
- Modify: `apps/patient/lib/main.dart`
- Test: `apps/patient/test/reminders/reminder_scheduler_test.dart`
- Modify: `apps/patient/test/patient_app_mvp_test.dart`

**Interfaces:**
- Consumes: `ReminderStore`/`Reminder` (Task 7).
- Produces: `ReminderScheduler` (interface) +
  `LocalNotificationsReminderScheduler`; `RemindersScreen` real,
  substituindo o stub em `apps/patient/lib/app/app.dart:769-784`.

- [ ] **Step 1: Definir a interface e escrever o teste que falha**

  Create `apps/patient/lib/core/reminders/reminder_scheduler.dart`:

  ```dart
  import 'reminder.dart';

  /// Agendamento de notificações locais para lembretes ativos. Interface
  /// testável sem canal de plataforma — mesma razão de `LocationReader`.
  abstract interface class ReminderScheduler {
    Future<void> schedule(Reminder reminder);
    Future<void> cancel(int reminderId);
  }
  ```

  Create `apps/patient/test/reminders/reminder_scheduler_test.dart` com um
  fake `FlutterLocalNotificationsPlugin`-like via injeção (verificar se o
  pacote expõe uma forma de teste sem canal de plataforma — caso não exponha
  diretamente, testar via uma camada de abstração própria que o
  `LocalNotificationsReminderScheduler` delega, e testar SÓ essa camada de
  tradução (Reminder → parâmetros de agendamento), não o plugin em si, que é
  third-party e não hermético. Testar:
  - `schedule` com `active: false` não agenda nada (cancela se já existia).
  - `schedule` com `active: true` calcula o próximo horário >= agora (se o
    horário já passou hoje, agenda para amanhã).
  - `cancel` chama o cancelamento pelo id correto.

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/patient && flutter test test/reminders/reminder_scheduler_test.dart`
  Expected: FAIL.

- [ ] **Step 3: Implementar `LocalNotificationsReminderScheduler`**

  Create a implementação usando `flutter_local_notifications`
  (`FlutterLocalNotificationsPlugin().zonedSchedule(...)`, com
  `matchDateTimeComponents: DateTimeComponents.time` para recorrência
  diária). Inicializar o plugin com o `AndroidInitializationSettings` padrão
  em `apps/patient/lib/main.dart`, antes de `runApp`, seguindo o padrão já
  usado para outras inicializações nesse arquivo.

  Adicionar import do pacote `timezone` se `flutter_local_notifications`
  exigir (`tz.TZDateTime`) — checar a versão `^17.0.0` já declarada para
  confirmar a API exata antes de escrever o agendamento; documentar a
  decisão de fuso horário (usar o fuso local do aparelho, sem conversão,
  consistente com o restante do app que já opera em hora local para exibir
  horários — ver `_time()` em outras telas).

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd apps/patient && flutter test test/reminders/reminder_scheduler_test.dart`
  Expected: PASS.

- [ ] **Step 5: Substituir `RemindersScreen`**

  Em `apps/patient/lib/app/app.dart`, substituir a classe
  `_RemindersScreenState` (linhas 770-784, hoje com lista fixa em memória e
  `_showPrototypeMessage`) para:
  - Carregar do `ReminderStore` injetado (via `BackendScope`-like
    inherited widget, ou construtor — seguir o padrão já usado para
    `LocationScope`/`BackendScope` no arquivo).
  - Criar/editar um lembrete (horário + texto) grava no store e agenda via
    `ReminderScheduler`.
  - Alternar `active` no switch existente grava a mudança e
    agenda/cancela a notificação de acordo.
  - Excluir um lembrete remove do store e cancela a notificação.
  - Estado vazio explícito quando não há lembretes (hoje a lista sempre
    começa com 3 itens fixos — isso deixa de existir; a tela abre vazia até
    a pessoa criar o primeiro lembrete).

- [ ] **Step 6: Rodar a suíte completa do app**

  Run: `cd apps/patient && flutter analyze && flutter test`
  Expected: PASS. Ajustar `patient_app_mvp_test.dart` se ele fizer
  suposições sobre a lista fixa de 3 lembretes que deixou de existir.

- [ ] **Step 7: Commit**

  ```bash
  git add apps/patient/lib/core/reminders/ apps/patient/lib/app/app.dart apps/patient/lib/main.dart apps/patient/test/
  git commit -m "feat(patient): agendar lembretes locais via flutter_local_notifications (RF06 §3.1)"
  ```

---

## Track D — Sincronização central→dispositivo, metade ACS (RF15)

### Task 9: `visits.pull` com cursor incremental por território

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_visit_store.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/visits_endpoint.dart`
- Test: `backend/sinalacs_server/test/unit/visit_sync_service_test.dart`
- Test: `backend/sinalacs_server/test/integration/patient_directory_and_territory_test.dart` (ou novo arquivo de integração dedicado)

**Interfaces:**
- Consumes: `VisitStore` (existente, Task 9 estende a interface).
- Produces: `VisitSyncService.pull(AuthenticatedUser acs, {required DateTime
  since}) -> List<VisitSyncEntry>`; `VisitsEndpoint.pull`.

- [ ] **Step 1: Escrever o teste unitário que falha**

  Em `backend/sinalacs_server/test/unit/visit_sync_service_test.dart`, ler o
  arquivo primeiro (para reaproveitar o `FakeVisitStore` já existente) e
  estender `FakeVisitStore` com um método `listChangedInMicroArea` em
  memória. Adicionar:

  ```dart
  group('pull', () {
    test('devolve só visitas da microárea do ACS, alteradas após since', () async {
      // popular o FakeVisitStore com visitas de duas microáreas e
      // syncAt antes/depois de um `since` de referência
      final result = await service.pull(acsUser, since: referencia);
      expect(result.map((e) => e.localId), containsAll([...]));
      expect(result.map((e) => e.localId), isNot(contains(visitaDeOutraArea.localId)));
      expect(result.map((e) => e.localId), isNot(contains(visitaAntigaDemais.localId)));
    });

    test('recusa quando quem chama não é ACS territorializado', () async {
      expect(
        () => service.pull(pacienteUser, since: referencia),
        throwsA(isA<StateError>()),
      );
    });
  });
  ```

  Adaptar nomes de variáveis ao que já existe no arquivo (o `FakeVisitStore`
  atual provavelmente só implementa `findByLocalId`/`insert`/`update`/
  `microAreaOfPatient` — adicionar `listChangedInMicroArea` a ele também,
  como parte deste Step, não como surpresa no Step 3).

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/visit_sync_service_test.dart`
  Expected: FAIL — `pull` não existe em `VisitSyncService`/`VisitStore`.

- [ ] **Step 3: Estender `VisitStore` e implementar `pull`**

  Em `visit_sync_service.dart`, adicionar à interface:

  ```dart
  abstract interface class VisitStore {
    Future<Visit?> findByLocalId(String localId);
    Future<Visit> insert(Visit visit);
    Future<Visit> update(Visit visit);
    Future<UuidValue?> microAreaOfPatient(UuidValue patientId);

    /// Visitas da microárea cujo `syncAt` é posterior a `since` — o cursor
    /// incremental de `visits.pull` (RF15, decisão §5).
    Future<List<Visit>> listChangedInMicroArea(UuidValue microAreaId, DateTime since);
  }
  ```

  No `VisitSyncService`:

  ```dart
  /// Sincronização central→dispositivo: visitas da microárea do ACS
  /// alteradas desde `since`, para reconciliar um device que ficou offline
  /// ou foi reinstalado. Território vem sempre do token (INV-01), nunca de
  /// parâmetro — mesma regra de `PatientDirectoryService.listForAcs`.
  Future<List<VisitSyncEntry>> pull({
    required AuthenticatedUser user,
    required DateTime since,
  }) async {
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem sincronizar visitas.');
    }

    final microAreaId = UuidValue.fromString(user.microAreaId!);
    final visits = await _store.listChangedInMicroArea(microAreaId, since);

    return [
      for (final visit in visits)
        VisitSyncEntry(
          localId: visit.localId.uuid,
          patientId: visit.patientId.uuid,
          scheduledAt: visit.scheduledAt,
          completedAt: visit.completedAt,
          status: visit.status,
          riskLevelBefore: visit.riskLevelBefore,
          riskLevelAfter: visit.riskLevelAfter,
          notes: visit.notes,
          version: visit.version,
        ),
    ];
  }
  ```

  Assinatura do método público de instância `pull` fica ao lado de `sync`,
  não como um segundo `class`.

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd backend/sinalacs_server && dart test test/unit/visit_sync_service_test.dart`
  Expected: PASS.

- [ ] **Step 5: Implementar `listChangedInMicroArea` no `OrmVisitStore`**

  Em `orm_visit_store.dart`, mesmo padrão de duas etapas de
  `OrmPatientDirectoryStore` (patients não tem `microAreaId`, vem de
  `users`):

  ```dart
  @override
  Future<List<Visit>> listChangedInMicroArea(UuidValue microAreaId, DateTime since) async {
    final session = _session();
    final users = await User.db.find(
      session,
      where: (t) => t.microAreaId.equals(microAreaId) & t.role.equals(UserRole.patient),
      transaction: _transaction,
    );
    if (users.isEmpty) return const [];

    final patientIds = {for (final user in users) user.id!}.cast<UuidValue>();

    return Visit.db.find(
      session,
      where: (t) => t.patientId.inSet(patientIds) & (t.syncAt > since),
      orderBy: (t) => t.syncAt,
      transaction: _transaction,
    );
  }
  ```

  Confirmar a sintaxe exata do operador `>` sobre `DateTime` no query
  builder do Serverpod (usada em `orm_alert_outbox.dart` ou similar, para
  comparação de datas — inspecionar esse arquivo antes de escrever, já que a
  sintaxe pode ser `t.syncAt > since` ou exigir um helper específico do
  ORM).

- [ ] **Step 6: Adicionar o endpoint**

  Em `visits_endpoint.dart`:

  ```dart
  Future<List<VisitSyncEntry>> pull(
    Session session, {
    required String accessToken,
    required DateTime since,
  }) async {
    final user = _authenticate(accessToken);
    try {
      return await AlertRuntime.instance
          .visitSyncServiceFor(session)
          .pull(user: user, since: since);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
  ```

- [ ] **Step 7: Escrever o teste de integração de território**

  Adicionar ao arquivo de integração escolhido um caso que grava visitas em
  duas microáreas via `Visit.db.insert` direto no seed, chama
  `endpoints.visits.pull` autenticado como ACS de uma delas, e confirma que
  só as visitas da própria microárea (e só as com `syncAt > since`) voltam —
  reaproveitando os UUIDs de microárea/paciente já usados em
  `patient_directory_and_territory_test.dart`.

  Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test`
  Expected: PASS, suíte inteira verde.

- [ ] **Step 8: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart \
          backend/sinalacs_server/lib/src/infrastructure/database/orm_visit_store.dart \
          backend/sinalacs_server/lib/src/endpoints/visits_endpoint.dart \
          backend/sinalacs_server/lib/src/generated/ backend/sinalacs_client/ \
          backend/sinalacs_server/test/
  git commit -m "feat(backend): visits.pull — cursor incremental territorializado (RF15, metade ACS)"
  ```

---

### Task 10: ACS consome o pull com cursor por dispositivo

**Files:**
- Create: `apps/acs/lib/core/database/sync_cursor_store.dart`
- Modify: `apps/acs/lib/core/database/encrypted_database.dart`
- Modify: `apps/acs/lib/core/network/backend_client.dart`
- Modify: `apps/acs/lib/core/services/alert_queue.dart` ou novo `visit_pull_service.dart`
- Test: `apps/acs/test/sync_cursor_store_test.dart`
- Test: `apps/acs/test/visit_pull_service_test.dart`

**Interfaces:**
- Consumes: `AcsBackend.pullVisits({required DateTime since})` (novo,
  espelha `syncVisits`); `visits.pull` (Task 9).
- Produces: `SyncCursorStore` (persistência do `since` por instalação),
  `VisitPullService` (aplica o pull recebido sobre a fila offline local sem
  duplicar).

- [ ] **Step 1: Escrever o teste do cursor que falha**

  Create `apps/acs/test/sync_cursor_store_test.dart`, seguindo o padrão de
  teste de `EncryptedLocalDatabase`/`SqlCipherVisitStore` (banco em memória,
  `allowUnencryptedForTesting: true`). Cobrir:
  - Sem cursor gravado, `read()` devolve `null` (primeira sincronização —
    o chamador deve tratar como "desde o início dos tempos" ou uma janela
    inicial definida por produto, não como erro).
  - `write(DateTime)` grava e um `read()` seguinte devolve o mesmo valor.
  - Uma nova instância apontando para o mesmo arquivo de banco lê o cursor
    gravado pela anterior (simula reabrir o app).

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/acs && flutter test test/sync_cursor_store_test.dart`
  Expected: FAIL.

- [ ] **Step 3: Adicionar a tabela `sync_cursor` ao schema criptografado**

  Em `encrypted_database.dart`, subir `schemaVersion` para 5, adicionar:

  ```dart
  static const createSyncCursor = '''
CREATE TABLE IF NOT EXISTS sync_cursor (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''';
  ```

  E o passo de migração v4→v5 em `_upgrade` (`CREATE TABLE IF NOT EXISTS`,
  aditivo — mesmo padrão documentado no comentário do arquivo para não
  perder dados existentes).

  Create `apps/acs/lib/core/database/sync_cursor_store.dart`:

  ```dart
  import 'package:sinalacs_acs/core/database/encrypted_database.dart';
  import 'package:sinalacs_acs/core/security/database_key_store.dart';
  import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

  /// Cursor de `visits.pull` por instalação do app (decisão §5.4: "cursor por
  /// dispositivo, não por usuário" — reinstalar não deve perder nem duplicar).
  /// Vive no mesmo banco criptografado das visitas offline: é dado
  /// operacional do dispositivo, sob a mesma política de proteção.
  class SyncCursorStore {
    SyncCursorStore({
      required DatabaseKeyStore keyStore,
      this.databaseName = 'sinalacs_acs.db',
      this.allowUnencryptedForTesting = false,
    }) : _keyStore = keyStore;

    static const _table = 'sync_cursor';
    static const _visitsPullKey = 'visits_pull';

    final DatabaseKeyStore _keyStore;
    final String databaseName;
    final bool allowUnencryptedForTesting;
    Database? _database;

    Future<Database> _open() async {
      final existing = _database;
      if (existing != null && existing.isOpen) return existing;
      final passphrase = await _keyStore.readOrCreate();
      return _database = await EncryptedLocalDatabase.open(
        databaseName: databaseName,
        passphrase: passphrase,
        allowUnencryptedForTesting: allowUnencryptedForTesting,
      );
    }

    Future<DateTime?> read() async {
      final db = await _open();
      final rows = await db.query(_table, where: 'key = ?', whereArgs: [_visitsPullKey]);
      if (rows.isEmpty) return null;
      return DateTime.parse(rows.first['value'] as String);
    }

    Future<void> write(DateTime since) async {
      final db = await _open();
      await db.insert(
        _table,
        {'key': _visitsPullKey, 'value': since.toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
  ```

  Adicionar `import 'package:sqflite_common_ffi/sqflite_ffi.dart' show
  ConflictAlgorithm;` se necessário (confirmar o nome exato exportado pelo
  pacote já usado em `sqlcipher_visit_store.dart`, que resolve
  `ConflictAlgorithm` de algum lugar — inspecionar o restante do arquivo
  antes de escrever este import).

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd apps/acs && flutter test test/sync_cursor_store_test.dart`
  Expected: PASS.

- [ ] **Step 5: Adicionar `pullVisits` ao `AcsBackend`**

  Em `backend_client.dart`:

  ```dart
  abstract class AcsBackend {
    // ... membros existentes ...

    /// Visitas da microárea alteradas desde `since` — reconciliação
    /// central→dispositivo (RF15, decisão §5).
    Future<List<VisitSyncEntry>> pullVisits({required DateTime since});
  }

  class BackendClient implements AcsBackend {
    // ...
    @override
    Future<List<VisitSyncEntry>> pullVisits({required DateTime since}) async {
      final token = await _requireToken();
      return _guard(
        () => _client.visits.pull(accessToken: token, since: since),
      );
    }
  }
  ```

  Atualizar o fake de `AcsBackend` em `apps/acs/test/support/fakes.dart`
  para implementar o novo método.

- [ ] **Step 6: Escrever o teste do serviço de aplicação do pull que falha**

  Create `apps/acs/test/visit_pull_service_test.dart` cobrindo:
  - Primeira execução (`SyncCursorStore.read()` devolve `null`) chama
    `pullVisits(since: <época bem antiga, ex. DateTime.utc(2000)>)` — não
    lança nem trava.
  - Depois de um pull bem-sucedido, o cursor é atualizado para "agora" (ou
    para o `syncAt` mais recente recebido).
  - As entradas recebidas não duplicam uma visita já presente na fila
    offline local com o mesmo `localId` — reconciliação por `localId`, mesmo
    critério de dedupe que `visits.sync` já usa do lado servidor.

- [ ] **Step 7: Rodar e confirmar que falha**

  Run: `cd apps/acs && flutter test test/visit_pull_service_test.dart`
  Expected: FAIL.

- [ ] **Step 8: Implementar `VisitPullService`**

  Create `apps/acs/lib/core/services/visit_pull_service.dart` com uma classe
  que recebe `AcsBackend` e `SyncCursorStore`, expõe `Future<void>
  pullAndMerge()`, lê o cursor, chama `pullVisits`, escreve as entradas
  recebidas na fila offline local **só como leitura de referência** — não
  reenviar essas entradas de volta a `visits.sync` (evitar um loop
  pull→sync→pull). Se a fila offline local (`OfflineVisitQueue`) não tiver
  hoje um conceito de "visita vinda do servidor, não editável localmente",
  documentar essa limitação como nota de código e manter o pull emitindo os
  dados só para a UI (ex.: contagem territorial mais precisa) até uma
  próxima iteração decidir a UI de exibição. Isso é intencional: o
  escopo desta task é o contrato de sincronização, não a tela consumidora
  final — a decisão §5 não especifica UI, só o contrato.

- [ ] **Step 9: Rodar e confirmar que passa**

  Run: `cd apps/acs && flutter test test/visit_pull_service_test.dart`
  Expected: PASS.

- [ ] **Step 10: Rodar a suíte completa do ACS**

  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: PASS.

- [ ] **Step 11: Commit**

  ```bash
  git add apps/acs/lib/core/database/ apps/acs/lib/core/network/backend_client.dart \
          apps/acs/lib/core/services/visit_pull_service.dart apps/acs/test/
  git commit -m "feat(acs): consumir visits.pull com cursor por dispositivo (RF15, metade ACS)"
  ```

---

## Track E — Criptografia de coluna no PostgreSQL (RNF03, INV-04)

### Task 11: Utilitário de criptografia AES-256-GCM

**Files:**
- Modify: `backend/sinalacs_server/pubspec.yaml`
- Create: `backend/sinalacs_server/lib/src/infrastructure/crypto/health_data_cipher.dart`
- Create: `backend/sinalacs_server/test/unit/health_data_cipher_test.dart`
- Modify: `backend/sinalacs_server/lib/src/config/app_config.dart`
- Modify: `backend/sinalacs_server/test/unit/app_config_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `HealthDataCipher.encrypt(String plaintext) ->
  EncryptedValue`/`HealthDataCipher.decrypt(EncryptedValue) -> String`;
  `AppConfig.healthDataEncryptionKey`.

- [ ] **Step 1: Adicionar a dependência**

  Em `backend/sinalacs_server/pubspec.yaml`, adicionar em `dependencies:`:

  ```yaml
  cryptography: ^2.7.0
  ```

  Run: `cd backend/sinalacs_server && dart pub get`
  Expected: resolve sem conflito com `serverpod: 3.4.13`.

- [ ] **Step 2: Escrever o teste do `AppConfig` que falha**

  Em `app_config_test.dart`, seguir o padrão dos grupos `JWT_SECRET`/
  `AUDIT_CHAIN_SECRET` já existentes, adicionando um grupo
  `HEALTH_DATA_ENCRYPTION_KEY`:

  ```dart
  group('HEALTH_DATA_ENCRYPTION_KEY', () {
    test('development sem a variável usa o fallback conhecido', () {
      expect(
        build(appEnv: 'development').healthDataEncryptionKey,
        AppConfig.developmentHealthDataEncryptionKey,
      );
    });

    test('production sem a variável não sobe', () {
      expect(
        () => build(appEnv: 'production'),
        throwsA(isA<StateError>()),
      );
    });

    test('production com o valor de desenvolvimento não sobe', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
  ```

  Estender o `build(...)` helper do topo do arquivo para aceitar
  `healthDataEncryptionKey` e passá-lo ao `AppConfig.fromMap`.

- [ ] **Step 3: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/app_config_test.dart`
  Expected: FAIL — `healthDataEncryptionKey` não existe em `AppConfig`.

- [ ] **Step 4: Adicionar o segredo a `AppConfig`**

  Em `app_config.dart`, seguindo exatamente o padrão de `jwtSecret`/
  `auditChainSecret`:

  ```dart
  class AppConfig {
    const AppConfig({
      required this.mqttBroker,
      required this.jwtSecret,
      required this.auditChainSecret,
      required this.healthDataEncryptionKey,
      // ... resto igual ...
    });

    // ... campos existentes ...

    /// Chave AES-256-GCM que cifra `patients.chronicConditions`,
    /// `triage_sessions.answers` e `visits.notes` (RNF03, INV-04). Segredo
    /// PRÓPRIO — nunca derivado de `jwtSecret`/`auditChainSecret`: rotacionar
    /// um não pode invalidar o outro.
    final String healthDataEncryptionKey;

    static const developmentHealthDataEncryptionKey = 'development-health-data-key';

    factory AppConfig.fromMap(Map<String, String> environment) {
      final appEnv = environment['APP_ENV'] ?? 'development';
      return AppConfig(
        mqttBroker: environment['MQTT_BROKER'] ?? 'localhost:1883',
        jwtSecret: _resolveSecret(
          value: environment['JWT_SECRET'], appEnv: appEnv,
          envVarName: 'JWT_SECRET', developmentFallback: developmentJwtSecret,
        ),
        auditChainSecret: _resolveSecret(
          value: environment['AUDIT_CHAIN_SECRET'], appEnv: appEnv,
          envVarName: 'AUDIT_CHAIN_SECRET', developmentFallback: developmentAuditChainSecret,
        ),
        healthDataEncryptionKey: _resolveSecret(
          value: environment['HEALTH_DATA_ENCRYPTION_KEY'], appEnv: appEnv,
          envVarName: 'HEALTH_DATA_ENCRYPTION_KEY',
          developmentFallback: developmentHealthDataEncryptionKey,
        ),
        // ... resto igual ...
      );
    }
    // ... resto igual ...
  }
  ```

- [ ] **Step 5: Rodar e confirmar que passa**

  Run: `cd backend/sinalacs_server && dart test test/unit/app_config_test.dart`
  Expected: PASS.

- [ ] **Step 6: Escrever o teste do cifrador que falha**

  Create `backend/sinalacs_server/test/unit/health_data_cipher_test.dart`:

  ```dart
  import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
  import 'package:test/test.dart';

  void main() {
    late HealthDataCipher cipher;

    setUp(() {
      // 32 bytes em hex = 64 caracteres, mesmo formato de `openssl rand -hex 32`
      // usado pelos outros segredos do projeto.
      cipher = HealthDataCipher(keyHex: 'a' * 64, keyVersion: 1);
    });

    test('decifra exatamente o que foi cifrado', () async {
      const texto = 'hipertensão, diabetes tipo 2';
      final cifrado = await cipher.encrypt(texto);
      final decifrado = await cipher.decrypt(cifrado);
      expect(decifrado, texto);
    });

    test('o valor cifrado nunca contém o texto claro', () async {
      const texto = 'hipertensão, diabetes tipo 2';
      final cifrado = await cipher.encrypt(texto);
      expect(cifrado.ciphertextBase64, isNot(contains('hipertensão')));
      expect(cifrado.ciphertextBase64, isNot(contains('diabetes')));
    });

    test('duas cifragens do mesmo texto produzem ciphertexts diferentes (nonce aleatório)', () async {
      const texto = 'mesmo texto';
      final a = await cipher.encrypt(texto);
      final b = await cipher.encrypt(texto);
      expect(a.ciphertextBase64, isNot(b.ciphertextBase64));
      // mas ambos decifram para o mesmo texto
      expect(await cipher.decrypt(a), texto);
      expect(await cipher.decrypt(b), texto);
    });

    test('marca a versão de chave usada', () async {
      final cifrado = await cipher.encrypt('texto');
      expect(cifrado.keyVersion, 1);
    });

    test('recusa decifrar com a chave errada', () async {
      final cifrado = await cipher.encrypt('texto secreto');
      final outraChave = HealthDataCipher(keyHex: 'b' * 64, keyVersion: 1);
      expect(() => outraChave.decrypt(cifrado), throwsA(anything));
    });

    test('string vazia cifra e decifra normalmente', () async {
      final cifrado = await cipher.encrypt('');
      expect(await cipher.decrypt(cifrado), '');
    });
  }
  ```

- [ ] **Step 7: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/health_data_cipher_test.dart`
  Expected: FAIL — `health_data_cipher.dart` não existe.

- [ ] **Step 8: Implementar `HealthDataCipher`**

  Create `backend/sinalacs_server/lib/src/infrastructure/crypto/health_data_cipher.dart`:

  ```dart
  import 'dart:convert';
  import 'dart:typed_data';

  import 'package:cryptography/cryptography.dart';

  /// Um valor cifrado, pronto para persistir. `ciphertextBase64` empacota
  /// nonce + texto cifrado + tag de autenticação — tudo que `decrypt`
  /// precisa, num único campo de coluna.
  class EncryptedValue {
    const EncryptedValue({required this.ciphertextBase64, required this.keyVersion});

    final String ciphertextBase64;
    final int keyVersion;
  }

  /// Criptografia AES-256-GCM de dados de saúde, na borda do repositório ORM
  /// (RNF03, INV-04). Decisão §6 de
  /// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md:
  /// aplicação, não `pgcrypto` em SQL — o texto claro nunca deve passar pela
  /// camada de log de query do Serverpod.
  ///
  /// `keyVersion` acompanha cada valor cifrado para permitir rotação futura
  /// sem reescrever todas as linhas de uma vez.
  class HealthDataCipher {
    HealthDataCipher({required String keyHex, required this.keyVersion})
        : _algorithm = AesGcm.with256bits(),
          _secretKey = SecretKey(_hexToBytes(keyHex));

    final AesGcm _algorithm;
    final SecretKey _secretKey;
    final int keyVersion;

    static Uint8List _hexToBytes(String hex) {
      final bytes = Uint8List(hex.length ~/ 2);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return bytes;
    }

    Future<EncryptedValue> encrypt(String plaintext) async {
      final secretBox = await _algorithm.encrypt(
        utf8.encode(plaintext),
        secretKey: _secretKey,
      );
      // nonce + ciphertext + mac concatenados, para caber num único campo.
      final packed = <int>[
        ...secretBox.nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ];
      return EncryptedValue(
        ciphertextBase64: base64.encode(packed),
        keyVersion: keyVersion,
      );
    }

    Future<String> decrypt(EncryptedValue value) async {
      final packed = base64.decode(value.ciphertextBase64);
      final nonceLength = _algorithm.nonceLength;
      const macLength = 16; // GCM: tag de 128 bits.

      final nonce = packed.sublist(0, nonceLength);
      final mac = Mac(packed.sublist(packed.length - macLength));
      final cipherText = packed.sublist(nonceLength, packed.length - macLength);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final clearBytes = await _algorithm.decrypt(secretBox, secretKey: _secretKey);
      return utf8.decode(clearBytes);
    }
  }
  ```

- [ ] **Step 9: Rodar e confirmar que passa**

  Run: `cd backend/sinalacs_server && dart test test/unit/health_data_cipher_test.dart`
  Expected: PASS.

- [ ] **Step 10: Rodar a suíte completa (unitária)**

  Run: `cd backend/sinalacs_server && dart test test/unit/`
  Expected: PASS.

- [ ] **Step 11: Commit**

  ```bash
  git add backend/sinalacs_server/pubspec.yaml backend/sinalacs_server/pubspec.lock \
          backend/sinalacs_server/lib/src/infrastructure/crypto/ \
          backend/sinalacs_server/lib/src/config/app_config.dart \
          backend/sinalacs_server/test/unit/health_data_cipher_test.dart \
          backend/sinalacs_server/test/unit/app_config_test.dart
  git commit -m "feat(backend): utilitário HealthDataCipher AES-256-GCM (RNF03, INV-04)"
  ```

---

### Task 12: Aplicar a criptografia aos 3 campos sensíveis

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/patient.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/triage_session.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/visit.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_directory_store.dart`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_triage_session_store.dart`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_visit_store.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`
- Test: `backend/sinalacs_server/test/integration/health_data_encryption_test.dart` (novo)

**Interfaces:**
- Consumes: `HealthDataCipher` (Task 11).
- Produces: `keyVersion: int` nas 3 tabelas; leitura/escrita cifrada
  transparente para `application/` (os serviços continuam operando sobre
  `List<String>`/`Map<String, String>` em claro — só o ORM cifra/decifra).

**Decisão de design desta task:** os campos `chronicConditions: List<String>`,
`answers: List<TriageAnswer>` e `notes: Map<String, String>` são
estruturados, não `String` simples — `HealthDataCipher` só cifra `String`.
Em vez de mudar o tipo da coluna no `.spy.yaml` (o que quebraria todo o
código de `application/` que hoje itera essas listas/mapas tipadas), a
criptografia serializa o valor estruturado para JSON **dentro do
repositório**, cifra o JSON, e grava o ciphertext numa coluna `String`
adicional — mantendo a coluna original do `.spy.yaml` como o tipo que
`application/` já conhece é inviável (o Serverpod persiste exatamente os
campos do modelo). A abordagem adotada: manter os 3 campos como estão no
modelo gerado, e **interceptar a serialização na camada ORM**, gravando
diretamente via SQL cru meta o suficiente — na prática, a forma mais simples
e consistente com "nunca editar `generated/`" é: os 3 campos passam a ser
`String` (o JSON cifrado) no `.spy.yaml`, e a tradução JSON↔tipo estruturado
migra de "automática pelo Serverpod" para "explícita no store ORM", que já é
exatamente a fronteira que hoje existe entre `application/` (tipado) e
`infrastructure/` (ORM).

- [ ] **Step 1: Mudar os 3 campos para `String` cifrado + `keyVersion`**

  Em `patient.spy.yaml`, trocar `chronicConditions: List<String>` por:

  ```yaml
  ### JSON de List<String>, cifrado (AES-256-GCM). Decifrado/cifrado na borda
  ### do repositório (OrmPatientDirectoryStore), nunca em application/ — ver
  ### docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §6.
  chronicConditionsEncrypted: String
  chronicConditionsKeyVersion: int
  ```

  Em `triage_session.spy.yaml`, trocar `answers: List<TriageAnswer>` por:

  ```yaml
  ### JSON de List<TriageAnswer>, cifrado. Ver patient.spy.yaml para o padrão.
  answersEncrypted: String
  answersKeyVersion: int
  ```

  Em `visit.spy.yaml`, trocar `notes: Map<String, String>` por:

  ```yaml
  ### JSON de Map<String, String>, cifrado. Ver patient.spy.yaml para o padrão.
  notesEncrypted: String
  notesKeyVersion: int
  ```

  **Este é o passo mais arriscado do plano**: renomear/tipar de novo estes 3
  campos quebra a compilação de todo código em `application/` que hoje
  acessa `patient.chronicConditions`, `triageSession.answers`,
  `visit.notes` diretamente como tipo estruturado — que é exatamente
  `PatientDirectoryService`, `TriageSessionService`/`TriageEngine`,
  `VisitSyncService`. Os Steps seguintes tratam isso ponto a ponto; **não
  rodar `serverpod generate` sem primeiro ler os 3 arquivos afetados** para
  saber exatamente onde a compilação vai quebrar.

- [ ] **Step 2: Regenerar e confirmar a extensão do dano (compilação quebrada é esperada aqui)**

  Run: `cd backend/sinalacs_server && serverpod generate`
  Run: `dart analyze lib/`
  Expected: uma lista de erros de compilação em `patient_directory_service.dart`
  (lê `entry.chronicConditions`/constrói `PatientDirectoryEntry`),
  `triage_session_service.dart`/`triage_engine.dart` (constrói/lê `answers`),
  `visit_sync_service.dart` (lê/grava `notes`), e os stores ORM
  correspondentes. Esta lista é o roteiro exato dos Steps 3-6.

- [ ] **Step 3: Cifrar/decifrar em `OrmPatientDirectoryStore`**

  A interface `PatientDirectoryStore`/`PatientDirectoryEntry` em
  `application/patients/patient_directory_service.dart` **não muda** —
  continua expondo `chronicConditions: List<String>` em claro para o
  serviço de aplicação. `OrmPatientDirectoryStore` passa a receber o
  `HealthDataCipher` no construtor e traduzir:

  ```dart
  class OrmPatientDirectoryStore implements PatientDirectoryStore {
    OrmPatientDirectoryStore({
      required Session Function() session,
      required HealthDataCipher cipher,
    })  : _session = session,
          _cipher = cipher;

    final Session Function() _session;
    final HealthDataCipher _cipher;

    @override
    Future<List<PatientDirectoryEntry>> listByMicroArea(String microAreaId) async {
      // ... busca de users/patients igual ...

      final entries = <PatientDirectoryEntry>[];
      for (final patient in patients) {
        final conditions = await _decryptConditions(patient);
        entries.add(PatientDirectoryEntry(
          patientId: patient.id!.uuid,
          name: namesById[patient.id] ?? '',
          isChronic: patient.isChronic,
          chronicConditions: conditions,
        ));
      }
      return entries;
    }

    Future<List<String>> _decryptConditions(Patient patient) async {
      if (patient.chronicConditionsEncrypted.isEmpty) return const [];
      final json = await _cipher.decrypt(EncryptedValue(
        ciphertextBase64: patient.chronicConditionsEncrypted,
        keyVersion: patient.chronicConditionsKeyVersion,
      ));
      return (jsonDecode(json) as List).cast<String>();
    }
  }
  ```

  Onde `Patient` é gravado com condições crônicas (buscar todos os
  `insertRow`/`updateRow` de `Patient` no repositório — provavelmente no
  seed de desenvolvimento, que é SQL puro e não passa pelo ORM Dart, e em
  qualquer endpoint futuro de cadastro), adicionar um método simétrico
  `_encryptConditions` e usá-lo. Se hoje **não existe** nenhum caminho Dart
  que escreve `Patient.chronicConditions` (a busca de escritores confirma
  isso antes de prosseguir), documentar essa ausência explicitamente em vez
  de inventar um endpoint de escrita fora de escopo — a Task cobre a
  **leitura** cifrada do que o seed grava, e o seed (Step 7) passa a gravar
  já cifrado.

- [ ] **Step 4: Cifrar/decifrar em `OrmTriageSessionStore`**

  Mesma estratégia: `TriageSessionStore`/`TriageSessionService` continuam
  operando sobre `List<TriageAnswer>` em claro. `OrmTriageSessionStore`
  recebe `HealthDataCipher`, serializa `answers` para JSON, cifra antes do
  `insertRow`. Como o método atual `insert(TriageSession session)` recebe o
  objeto `TriageSession` **já construído** pelo chamador (`application/`),
  a assinatura precisa mudar para receber os dados em claro e montar o
  `TriageSession` cifrado dentro do store — ler
  `triage_session_service.dart` para ajustar a chamada de acordo, mantendo
  a interface do lado de `application/` inalterada (ela não deve saber que
  existe cifragem).

- [ ] **Step 5: Cifrar/decifrar em `OrmVisitStore`**

  Mesma estratégia para `notes: Map<String, String>` em `insert`/`update`
  de `Visit`. `VisitSyncService` continua recebendo/devolvendo `notes` em
  claro (inclusive no `pull` da Task 9 — o cursor incremental devolve notas
  decifradas para o app do ACS, que é quem tem legitimidade para lê-las).

- [ ] **Step 6: Ligar `HealthDataCipher` ao `AlertRuntime`**

  Em `alert_runtime.dart`:

  ```dart
  HealthDataCipher? _healthDataCipher;

  HealthDataCipher get healthDataCipher => _healthDataCipher ??= HealthDataCipher(
        keyHex: config.healthDataEncryptionKey,
        keyVersion: 1,
      );
  ```

  Passar `cipher: healthDataCipher` na construção de
  `OrmPatientDirectoryStore`/`OrmTriageSessionStore`/`OrmVisitStore` nos
  métodos `patientDirectoryServiceFor`/`triageSessionServiceFor`/
  `visitSyncServiceFor`/`serviceFor` (o que for aplicável a cada um).
  Também precisa ser resetado em `overrideConfig` (mesma lógica que já
  invalida `_auth` quando a config muda).

- [ ] **Step 7: Atualizar o seed de desenvolvimento**

  `backend/sinalacs_server/lib/src/infrastructure/database/seeds/development.sql`
  grava `chronic_conditions`/`answers`/`notes` como JSON em claro hoje —
  como o seed é SQL puro rodando fora do processo Dart, ele não pode chamar
  `HealthDataCipher`. Duas opções documentadas para o executor escolher com
  base no que já existe:
  1. Trocar o seed para gravar as 3 colunas com um ciphertext **fixo e
     conhecido**, cifrado uma vez offline com a chave de desenvolvimento
     (`AppConfig.developmentHealthDataEncryptionKey`) e colado no SQL como
     literal — funciona, mas é frágil a qualquer mudança futura no
     algoritmo.
  2. Mover a etapa de popular esses 3 campos para depois do boot do
     servidor, via um pequeno script Dart que reusa `HealthDataCipher`
     (chamado pelo `database-seed` do compose em vez de/além do `psql`
     direto).

  Preferir a opção 2 — é a única que não duplica a lógica de cifragem fora
  do processo Dart. Ajustar `docker-compose.yml` (serviço `database-seed`)
  de acordo, mantendo o restante do seed (que não toca nos 3 campos
  sensíveis) como está.

- [ ] **Step 8: Criar a migração**

  Run:
  ```bash
  cd backend/sinalacs_server
  serverpod generate
  serverpod create-migration
  ```
  Expected: migração com `ADD COLUMN` para os 6 campos novos (3 pares
  `*Encrypted`/`*KeyVersion`) e `DROP COLUMN` para os 3 antigos — **revisar
  o SQL gerado antes de aplicar**: um `DROP COLUMN` em produção perderia
  dado existente sem plano de backfill. Para este projeto (protótipo,
  volume de dados de desenvolvimento, sem produção real ainda — conforme
  `CLAUDE.md`), isso é aceitável; documentar essa ressalva no corpo da
  migração se o Serverpod permitir comentário, ou no commit.

- [ ] **Step 9: Escrever o teste de integração que prova a cifragem**

  Create `backend/sinalacs_server/test/integration/health_data_encryption_test.dart`,
  no padrão `withServerpod` dos demais testes de integração. Cobrir:
  - Gravar um paciente com `chronicConditions` via o store (ou via
    `OnboardingService`/seed, conforme o que existir) e ler a coluna
    `chronicConditionsEncrypted` **diretamente via SQL cru**
    (`session.db.unsafeQuery`) — confirmar que o valor armazenado **não**
    contém nenhuma substring do texto original (ex.: se o texto claro é
    `'diabetes tipo 2'`, a coluna bruta não contém `'diabetes'`).
  - Ler de volta pelo store (`listByMicroArea`) e confirmar que o texto
    claro volta intacto.
  - Mesmo par de asserções para `triage_sessions.answersEncrypted` e
    `visits.notesEncrypted`.
  - `keyVersion` gravado é `1` nos três.

  Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test test/integration/health_data_encryption_test.dart`
  Expected: PASS.

- [ ] **Step 10: Rodar a suíte completa**

  Run: `cd backend/sinalacs_server && dart test`
  Expected: PASS. Os testes de `patient_directory_service_test.dart`,
  `triage_session_service_test.dart`, `visit_sync_service_test.dart` (que
  usam fakes, não Postgres) **não devem precisar mudar** — é exatamente o
  ponto de manter `application/` alheio à cifragem. Se algum desses testes
  quebrar, é sinal de que a cifragem vazou para fora de `infrastructure/`,
  o que contraria a decisão §6.1 documentada na spec de origem.

- [ ] **Step 11: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/models/ backend/sinalacs_server/lib/src/generated/ \
          backend/sinalacs_server/lib/src/infrastructure/database/ \
          backend/sinalacs_server/lib/src/runtime/alert_runtime.dart \
          backend/sinalacs_server/lib/src/infrastructure/database/seeds/ \
          backend/sinalacs_server/migrations/ backend/sinalacs_client/ \
          docker-compose.yml backend/sinalacs_server/test/
  git commit -m "feat(backend): cifrar chronicConditions/answers/notes em repouso (RNF03, INV-04)"
  ```

---

### Task 13: `HEALTH_DATA_ENCRYPTION_KEY` no bootstrap e no compose

**Files:**
- Modify: `.env.example`
- Modify: `scripts/dev/bootstrap_env.sh`
- Modify: `docker-compose.yml`
- Modify: `spec/stack.md`

**Interfaces:**
- Consumes: `AppConfig.healthDataEncryptionKey` (Task 11).
- Produces: variável gerada automaticamente por `bootstrap_env.sh`, mesma
  forma de `JWT_SECRET`/`AUDIT_CHAIN_SECRET`.

- [ ] **Step 1: Adicionar a variável ao `.env.example`**

  Em `.env.example`, na seção "Segredos da aplicação", após
  `AUDIT_CHAIN_SECRET`:

  ```
  # ---------------------------------------------------------------------------
  # Chave de criptografia de dados de saúde  ·  consumido por: serverpod
  #
  # Cifra patients.chronicConditions, triage_sessions.answers e visits.notes
  # (AES-256-GCM, RNF03/INV-04). Segredo PRÓPRIO — nunca reaproveite de
  # JWT_SECRET/AUDIT_CHAIN_SECRET: rotacionar um não pode afetar o outro, e
  # rotacionar este exige reciframento das linhas existentes (fora do escopo
  # deste MVP — ver docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §6).
  # ---------------------------------------------------------------------------
  # openssl rand -hex 32
  HEALTH_DATA_ENCRYPTION_KEY=
  ```

- [ ] **Step 2: Gerar a variável em `bootstrap_env.sh`**

  Em `scripts/dev/bootstrap_env.sh`, adicionar `HEALTH_DATA_ENCRYPTION_KEY`
  à lista de variáveis geradas por `secret()`:

  ```bash
  POSTGRES_PASSWORD="$(secret)" \
  TEST_DATABASE_PASSWORD="$(secret)" \
  MQTT_BACKEND_PASSWORD="$(secret)" \
  MQTT_ACS_PASSWORD="$(secret)" \
  JWT_SECRET="$(secret)" \
  AUDIT_CHAIN_SECRET="$(secret)" \
  HEALTH_DATA_ENCRYPTION_KEY="$(secret)" \
  awk '
    ...
  ' "$env_example" > "$env_file"
  ```

  E na mensagem final:

  ```bash
  echo "  .env gerado (POSTGRES_PASSWORD, TEST_DATABASE_PASSWORD,"
  echo "               MQTT_BACKEND_PASSWORD, MQTT_ACS_PASSWORD, JWT_SECRET,"
  echo "               AUDIT_CHAIN_SECRET, HEALTH_DATA_ENCRYPTION_KEY)"
  ```

- [ ] **Step 3: Propagar ao compose**

  Em `docker-compose.yml`, no serviço `serverpod`, junto de `JWT_SECRET`/
  `AUDIT_CHAIN_SECRET`:

  ```yaml
      HEALTH_DATA_ENCRYPTION_KEY: ${HEALTH_DATA_ENCRYPTION_KEY:?defina em .env — rode ./scripts/dev/bootstrap_env.sh}
  ```

- [ ] **Step 4: Testar o bootstrap do zero**

  Run:
  ```bash
  cp .env .env.bak-verificacao 2>/dev/null || true
  ./scripts/dev/bootstrap_env.sh --force
  grep -q '^HEALTH_DATA_ENCRYPTION_KEY=..' .env && echo "OK: chave gerada"
  ```
  Expected: `OK: chave gerada`, e o `.env` anterior preservado em backup
  (`bootstrap_env.sh` já faz isso automaticamente com `--force`).

- [ ] **Step 5: Subir a stack e confirmar boot**

  Run: `docker compose up --build -d serverpod && docker compose logs serverpod --tail 50`
  Expected: servidor sobe sem `StateError` de segredo ausente.

  Run: `docker compose down`

- [ ] **Step 6: Registrar em `spec/stack.md`**

  Adicionar `package:cryptography` (Task 11) e `HEALTH_DATA_ENCRYPTION_KEY`
  à lista de decisões de stack/segredos do documento, apontando para
  `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §6
  como a decisão de origem.

- [ ] **Step 7: Commit**

  ```bash
  git add .env.example scripts/dev/bootstrap_env.sh docker-compose.yml spec/stack.md
  git commit -m "chore: gerar HEALTH_DATA_ENCRYPTION_KEY no bootstrap (RNF03 §6)"
  ```

---

## Track F — Geofencing: desenho de contrato (RF12)

A decisão §4 rejeita rastreamento contínuo em segundo plano e adota
geofencing atrelado a uma visita ativa. A escolha de plugin nativo, o texto
de divulgação ao usuário e a submissão à loja continuam bloqueados por
revisão de produto/jurídico (bloqueio parcial, registrado na decisão). Esta
task cobre **só o contrato de dados** que os dois lados (backend e app)
precisam para uma implementação futura poder ligar o geofence nativo sem
mais uma rodada de migração — não integra nenhuma API nativa de geofence,
não pede `ACCESS_BACKGROUND_LOCATION`, não roda serviço em primeiro plano.

### Task 14: Campo `arrivalMethod` no contrato de sincronização de visitas

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/visit.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/api/visit_sync_entry.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/enums/` (novo enum `ArrivalMethod`)
- Modify: `backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart`
- Modify: `apps/acs/lib/core/services/offline_visit_queue.dart`
- Test: `backend/sinalacs_server/test/unit/visit_sync_service_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `ArrivalMethod` (`manual`/`geofence`), `Visit.arrivalMethod`,
  `VisitSyncEntry.arrivalMethod`.

- [ ] **Step 1: Criar o enum**

  Create `backend/sinalacs_server/lib/src/models/enums/arrival_method.spy.yaml`:

  ```yaml
  ### Como o check-in da visita foi registrado. `geofence` é reservado para
  ### quando a integração nativa de geofencing existir (RF12, decisão §4) —
  ### nenhum código hoje produz esse valor; `manual` é o único caminho real.
  enum: ArrivalMethod
  serialized: byName
  values:
    - manual
    - geofence
  ```

- [ ] **Step 2: Adicionar o campo aos modelos**

  Em `visit.spy.yaml`, adicionar após `syncStatus: SyncStatus`:

  ```yaml
  ### Default `manual` até a integração nativa de geofencing existir.
  arrivalMethod: ArrivalMethod
  ```

  Em `visit_sync_entry.spy.yaml`, adicionar após `version: int`:

  ```yaml
  arrivalMethod: ArrivalMethod
  ```

- [ ] **Step 3: Escrever o teste que falha**

  Em `visit_sync_service_test.dart`, adicionar um caso ao `group('sync')`
  já existente:

  ```dart
  test('grava arrivalMethod manual quando a entrada não especifica geofence', () async {
    final entry = VisitSyncEntry(
      // ... campos existentes do teste de referência ...
      arrivalMethod: ArrivalMethod.manual,
    );
    final results = await service.sync(user: acsUser, entries: [entry]);
    expect(results.single.syncStatus, SyncStatus.synced);
    expect(store.saved.single.arrivalMethod, ArrivalMethod.manual);
  });
  ```

  Adaptar a variáveis reais do arquivo (nome do `FakeVisitStore`, do
  `acsUser`, etc.) inspecionando o arquivo antes de escrever.

- [ ] **Step 4: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/visit_sync_service_test.dart`
  Expected: FAIL — `VisitSyncEntry`/`Visit` não têm `arrivalMethod` ainda
  (falha de compilação até o Step 5 gerar o protocolo).

- [ ] **Step 5: Regenerar, propagar em `VisitSyncService._syncOne` e migrar**

  Em `visit_sync_service.dart`, nos dois pontos que constroem `Visit(...)`
  (inserção nova e `existing.copyWith(...)` na atualização), incluir
  `arrivalMethod: entry.arrivalMethod`.

  Run:
  ```bash
  cd backend/sinalacs_server
  serverpod generate
  serverpod create-migration
  ```
  Expected: migração com `ADD COLUMN "arrivalMethod"` em `visits` — como o
  enum não tem default no schema, decidir entre tornar a coluna nullable
  temporariamente ou definir um valor default `manual` na migração gerada;
  revisar o SQL produzido e ajustar se o Serverpod não preencher um default
  para linhas existentes automaticamente.

- [ ] **Step 6: Rodar e confirmar que passa**

  Run:
  ```bash
  docker compose --profile test up -d postgres-test
  cd backend/sinalacs_server && dart test
  ```
  Expected: PASS, incluindo os testes de integração de sync já existentes
  (que precisam passar a informar `arrivalMethod: ArrivalMethod.manual` em
  toda construção de `VisitSyncEntry` — buscar todas as ocorrências em
  `test/` e ajustar).

- [ ] **Step 7: Propagar ao app do ACS**

  Em `apps/acs/lib/core/services/offline_visit_queue.dart`, o
  `OfflineVisitRecord` que hoje monta o `VisitSyncEntry` para envio (ou o
  ponto do código que faz essa conversão — pode estar em
  `backend_visit_synchronizer.dart`, verificar) passa a incluir
  `arrivalMethod: ArrivalMethod.manual` explicitamente (todo check-in hoje
  é manual — não há geofence nativo integrado por esta task).

  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: PASS.

- [ ] **Step 8: Documentar o limite desta task**

  No topo de `arrival_method.spy.yaml` e num comentário em
  `offline_visit_queue.dart` próximo de onde `arrivalMethod` é definido,
  deixar explícito: nenhuma API nativa de geofence foi integrada; nenhuma
  permissão de localização em primeiro/segundo plano foi adicionada ao
  `AndroidManifest.xml`; a escolha de plugin e o texto de divulgação
  seguem bloqueados por revisão de produto/jurídico (decisão §4, bloqueio
  parcial).

- [ ] **Step 9: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/models/ backend/sinalacs_server/lib/src/generated/ \
          backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart \
          backend/sinalacs_server/migrations/ backend/sinalacs_client/ \
          backend/sinalacs_server/test/ apps/acs/lib/core/services/offline_visit_queue.dart
  git commit -m "feat: contrato arrivalMethod para geofencing futuro (RF12 §4, desenho apenas)"
  ```

---

## Self-review

**Cobertura da spec de decisões:**
- §1 (geocélula/RF10/L-05): Tasks 1-3, backend + paciente + ACS,
  substituindo `alertPositionFor`.
- §2 (onboarding/RF02/LGPD-RF02): Tasks 4-6, `EnrollmentToken` +
  `ConsentPurpose` + primeiro escritor real de `consent_logs`.
- §3.1 (lembretes/RF06): Tasks 7-8, persistência local + agendamento real.
- §3.2 (push/RF14): **deliberadamente fora deste plano** — bloqueio externo
  real (projeto Firebase inexistente), não executável.
- §4 (geofencing/RF12): Task 14, contrato de dados apenas, com o limite
  documentado explicitamente — não implementa a integração nativa nem toca
  em permissão de background, consistente com o bloqueio parcial da
  decisão.
- §5 (sync/RF15): Tasks 9-10, metade ACS (`visits.pull` + cursor por
  dispositivo). A metade paciente (`status.myRequest`/RF05) é dependência
  declarada em `docs/superpowers/plans/2026-09-16-status-real-do-paciente.md`,
  não duplicada aqui.
- §6 (criptografia/RNF03/INV-04): Tasks 11-13, `HealthDataCipher` +
  aplicação aos 3 campos + geração de segredo.

**Placeholders:** nenhum passo usa "adicionar tratamento apropriado" sem
mostrar o código; onde uma decisão de implementação foi deliberadamente
deixada em aberto para o executor (Task 12 Step 7 — como popular o seed
cifrado; Task 9 Step 5 — sintaxe exata de comparação de data no ORM), o
motivo e as opções concretas estão escritos, não um placeholder genérico.

**Consistência de tipos:** `AlertDelivery.locationCell`/
`RedAlertService.create(locationCell:)`/`AlertsEndpoint.createRedAlert(locationCell:)`
usam `String?` em toda a cadeia (Task 1); `ReceivedMqttAlert.locationCell`/
`PrioritizedAlert.locationCell` espelham o mesmo tipo (Task 3);
`ConsentPurpose`/`ConsentLogEntry.purpose` usam o enum em `application/` e
`.name` só na borda do ORM (Task 5); `VisitStore.listChangedInMicroArea`
(Task 9) tem a mesma assinatura declarada na interface e implementada no
ORM.

**Risco residual, documentado explicitamente para quem executar:**
- Task 12 é a mais arriscada do plano — muda o tipo de 3 campos de modelo
  já em uso por serviços de aplicação existentes. O Step 2 (rodar
  `dart analyze` logo após a mudança de schema, antes de qualquer outro
  ajuste) existe exatamente para mapear o raio de impacto antes de
  prosseguir às cegas.
- Nenhuma task deste plano resolve RF01/RF07 (identidade institucional):
  Task 5 (onboarding) ativa um paciente **já cadastrado** pela ACS, e Task 5
  reaproveita `DevelopmentAuthService` para emitir a sessão — mesma
  limitação de autenticação que o resto do protótipo tem hoje, não uma
  regressão introduzida por este plano.
- Task 10 (pull no ACS) entrega o contrato e o cursor, mas deixa
  explicitamente em aberto qual tela consome as visitas puxadas — decisão
  de UI fora do escopo da decisão §5 original.
