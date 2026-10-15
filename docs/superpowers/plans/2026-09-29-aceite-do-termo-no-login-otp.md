# Aceite do Termo de Uso no login OTP — Plano de Implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** todo paciente que entra por CPF + OTP (RF01) e ainda não aceitou a versão vigente do Termo de Uso e da Política de Privacidade é convidado a aceitar logo após o login — o que também dá o reaceite quando `legalDocumentsVersion` mudar.

**Arquitetura:** o backend ganha `patients.acceptTermsOfUse`, que grava `ConsentPurpose.termsOfUse` = `granted` com `consentPolicyVersion`, na mesma trilha assinada de `updateConsent` (que continua recusando esse propósito). O app, depois de `verifyOtp`, lê `myData()`; se a última linha de `termsOfUse` não for `granted` na versão vigente, mostra `TermsAcceptanceScreen`. A tela **não bloqueia**: tem "Agora não" e, se `myData` falhar, o app entra direto — o alerta de emergência nunca fica atrás de um aceite.

**Stack:** Serverpod 3.4.13 (backend), Flutter 3.44 (`apps/patient`).

**Spec:** `spec/lgpd_design.md` (LGPD-RF18, ~linha 249) e `spec/PRD_system.md` (RF01). Invariante do projeto (`CLAUDE.md`): "Red alerts must never be silently dropped" — é por ele que o aceite não é um portão duro.

**Escopo decidido:** o outro item pedido, "sessão do onboarding de 1h", **já está no código** (`onboarding_endpoint.dart` emite `AuthEndpoint.patientSessionLifetime`; `onboarding_endpoint_test.dart:319` o prende). Só os textos ficaram velhos; a Tarefa 3 os corrige.

## Global Constraints

- Nunca editar à mão `backend/sinalacs_server/lib/src/generated/`, `backend/sinalacs_client/`, `migrations/` nem `test/integration/test_tools/serverpod_test_tools.dart`; regenerar com `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate`.
- Não há mudança de modelo (`.spy.yaml`), logo `serverpod create-migration` deve dizer "No changes detected" — se criar migração, algo saiu do plano.
- Sem dado real de paciente em testes, logs ou seed: só valores sintéticos.
- Texto de UI e docs em português. Commits terminam com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- `flutter analyze` limpo (infos incluídas) em `apps/patient`; `dart analyze` do backend fica no baseline de 41 infos.
- Não rodar `dart format` em `apps/patient/lib/app/app.dart`.
- Banco de teste: `docker compose --profile test up -d postgres-test`.

## Review Focus

1. **`myData()` falha logo após o login** → o app entra na tela inicial, sem travar o paciente. Teste na Tarefa 2 (`falha ao ler os consentimentos não impede a entrada`).
2. **Paciente toca "Agora não"** → chega à tela inicial e o aviso volta no próximo login; nenhuma linha é gravada. Teste na Tarefa 2.
3. **Já aceitou a versão vigente** → nenhuma tela extra, uma só chamada a `myData()`. Teste na Tarefa 2 e teste puro na Tarefa 2 (`needsTermsAcceptance`).
4. **Aceitou uma versão anterior** → o aviso aparece de novo. Teste puro na Tarefa 2.
5. **Token de ACS chamando `acceptTermsOfUse`** → recusado, nenhuma linha em `consent_logs`. Testes na Tarefa 1 (unitário e integração).
6. **Falha de rede ao aceitar** → mensagem visível, botão volta a ficar utilizável, e "Agora não" continua disponível. Teste na Tarefa 2.

---

### Tarefa 1: `patients.acceptTermsOfUse` no backend

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/patients_endpoint.dart`
- Regenerar: `backend/sinalacs_server/lib/src/generated/`, `backend/sinalacs_client/`, `test/integration/test_tools/serverpod_test_tools.dart`
- Test: `backend/sinalacs_server/test/unit/data_subject_rights_service_test.dart`, `backend/sinalacs_server/test/integration/data_subject_rights_endpoint_test.dart`

**Interfaces:**
- Consumes: `DataSubjectRightsStore.recordConsent`, `consentPolicyVersion`, `_requirePatient` (já existentes).
- Produces: `Future<ConsentRecordSnapshot> DataSubjectRightsService.acceptTermsOfUse(AuthenticatedUser user)`; RPC `Future<PatientConsentRecord> patients.acceptTermsOfUse(Session, {required String accessToken})`, no cliente `client.patients.acceptTermsOfUse(accessToken: ...)`.

- [ ] **Step 1: Testes que falham**

Em `test/unit/data_subject_rights_service_test.dart`, dentro de `main()`, depois do grupo `updateConsent (LGPD-RF05)`:

```dart
  group('acceptTermsOfUse (LGPD-RF18)', () {
    test('grava "granted" para termsOfUse com a versão vigente e audita', () async {
      final record = await service.acceptTermsOfUse(_patient);

      final entry = store.consents.single;
      expect(entry.userId, _patientId);
      expect(entry.purpose, ConsentPurpose.termsOfUse);
      expect(entry.action, 'granted');
      expect(entry.version, consentPolicyVersion);
      expect(entry.timestamp, _now);
      expect(record.purpose, 'termsOfUse');
      expect(record.action, 'granted');
      expect(audit.events.single.resourceType, 'consent_log');
    });

    test('só paciente aceita: ACS é recusado sem gravar nada', () async {
      await expectLater(service.acceptTermsOfUse(_acs), throwsA(isA<StateError>()));
      expect(store.consents, isEmpty);
      expect(audit.events, isEmpty);
    });
  });
```

Em `test/integration/data_subject_rights_endpoint_test.dart`, depois do teste `updateConsent recusa a finalidade obrigatória sem gravar nada`:

```dart
    test('acceptTermsOfUse grava termsOfUse assinado e myData passa a mostrá-lo', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final record = await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);
      expect(record.purpose, 'termsOfUse');
      expect(record.action, 'granted');

      final row = (await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      ))
          .single;
      expect(row.purpose, 'termsOfUse');
      expect(row.version, consentPolicyVersion);
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
      expect(overview.consents.last.purpose, 'termsOfUse');
    });

    test('acceptTermsOfUse recusa token de ACS sem gravar nada', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final acsToken =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: acsToken),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(await ConsentLog.db.count(session), 0);
    });
```

Se `consentPolicyVersion` ainda não estiver importado no teste de integração, acrescente `import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart' show consentPolicyVersion;`.

- [ ] **Step 2: Ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/data_subject_rights_service_test.dart`
Expected: FAIL na compilação — `acceptTermsOfUse` não existe em `DataSubjectRightsService`.

- [ ] **Step 3: Serviço**

Em `data_subject_rights_service.dart`, extrair a gravação de `updateConsent` para um método privado e reusá-la. Substituir, em `updateConsent`, o trecho de `final now = ...` até o `return ConsentRecordSnapshot(...)` por `return _record(user, purpose: purpose, action: granted ? 'granted' : 'denied');` e acrescentar:

```dart
  /// Aceite explícito do Termo de Uso e da Política de Privacidade por quem
  /// entrou por CPF + OTP sem passar pelo onboarding (LGPD-RF18) — ou que
  /// aceitou uma versão anterior. É a única via de escrita de `termsOfUse`
  /// fora do cadastro: [updateConsent] continua recusando esse propósito, para
  /// que o termo não vire uma chave liga/desliga no painel.
  Future<ConsentRecordSnapshot> acceptTermsOfUse(AuthenticatedUser user) async {
    _requirePatient(user);
    return _record(user, purpose: ConsentPurpose.termsOfUse, action: 'granted');
  }

  Future<ConsentRecordSnapshot> _record(
    AuthenticatedUser user, {
    required ConsentPurpose purpose,
    required String action,
  }) async {
    final now = _clock().toUtc();
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
```

Em `updateConsent`, `_requirePatient(user)` e as duas recusas continuam antes do `return _record(...)`.

- [ ] **Step 4: Endpoint**

Em `patients_endpoint.dart`, logo depois de `updateConsent`:

```dart
  /// Aceite do Termo de Uso e da Política de Privacidade vigentes (LGPD-RF18)
  /// por quem entrou por OTP sem passar pelo onboarding, ou aceitou uma versão
  /// anterior. Só paciente; grava uma linha nova e assinada em `consent_logs`.
  Future<PatientConsentRecord> acceptTermsOfUse(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      final record = await AlertRuntime.instance
          .dataSubjectRightsServiceFor(session)
          .acceptTermsOfUse(user);
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
```

- [ ] **Step 5: Regenerar**

Run: `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate && serverpod create-migration`
Expected: geração sem erro; `create-migration` diz "No changes detected" e não cria pasta em `migrations/`.

- [ ] **Step 6: Ver passar e suíte**

Run: `cd backend/sinalacs_server && docker compose --profile test up -d postgres-test && dart test`
Expected: PASS, todos verdes (329 + 4 novos = 333).

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server backend/sinalacs_client
git commit -m "feat(backend): patients.acceptTermsOfUse para o aceite do termo fora do onboarding (LGPD-RF18)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 2: aceite depois do login OTP, no app paciente

**Files:**
- Create: `apps/patient/lib/core/legal/terms_acceptance.dart`
- Modify: `apps/patient/lib/core/network/backend_client.dart` (interface, `MisconfiguredBackend`, `BackendClient`)
- Modify: `apps/patient/lib/app/legal_screens.dart` (`TermsAcceptanceScreen`)
- Modify: `apps/patient/lib/app/app.dart` (`_entrar`)
- Test: `apps/patient/test/terms_acceptance_test.dart` (novo), `apps/patient/test/support/fake_patient_backend.dart`, `apps/patient/test/terms_gate_flow_test.dart` (novo)

**Interfaces:**
- Consumes: `PatientConsentRecord({purpose: String, action: String, version: String, timestamp: DateTime})`; `legalDocumentsVersion`; `LegalDocumentsScreen`; `BackendScope.of(context).myData()`.
- Produces:
  - `bool needsTermsAcceptance(List<PatientConsentRecord> consents)` — `true` se a linha mais recente (por `timestamp`) com `purpose == 'termsOfUse'` não existir, não for `granted` ou não tiver `version == legalDocumentsVersion`.
  - `Future<PatientConsentRecord> PatientBackend.acceptTermsOfUse()`.
  - `TermsAcceptanceScreen({required VoidCallback onContinue})`, keys `terms_gate_read_button`, `terms_gate_checkbox`, `terms_gate_accept_button`, `terms_gate_later_button`, `terms_gate_error`.
  - No fake: `acceptTermsCalls` (int), `acceptTermsFailure` (`BackendFailure?`).

- [ ] **Step 1: Testes que falham**

Criar `apps/patient/test/terms_acceptance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show PatientConsentRecord;
import 'package:sinalacs_patient/core/legal/legal_documents.dart';
import 'package:sinalacs_patient/core/legal/terms_acceptance.dart';

PatientConsentRecord linha(String action, String version, int minuto, {String purpose = 'termsOfUse'}) =>
    PatientConsentRecord(
      purpose: purpose,
      action: action,
      version: version,
      timestamp: DateTime.utc(2026, 9, 29, 12, minuto),
    );

void main() {
  test('sem nenhuma linha de termsOfUse, precisa aceitar', () {
    expect(needsTermsAcceptance(const []), isTrue);
    expect(
      needsTermsAcceptance([linha('granted', '2026.1', 0, purpose: 'localReminders')]),
      isTrue,
    );
  });

  test('aceite da versão vigente dispensa o aviso', () {
    expect(needsTermsAcceptance([linha('granted', legalDocumentsVersion, 0)]), isFalse);
  });

  test('aceite de versão anterior pede de novo', () {
    expect(needsTermsAcceptance([linha('granted', '2025.9', 0)]), isTrue);
  });

  test('vale a linha mais recente, seja qual for a ordem da lista', () {
    final velha = linha('granted', '2025.9', 0);
    final nova = linha('granted', legalDocumentsVersion, 5);
    expect(needsTermsAcceptance([nova, velha]), isFalse);
    expect(needsTermsAcceptance([velha, nova]), isFalse);
  });

  test('linha mais recente que não é "granted" pede de novo', () {
    expect(
      needsTermsAcceptance([
        linha('granted', legalDocumentsVersion, 0),
        linha('denied', legalDocumentsVersion, 5),
      ]),
      isTrue,
    );
  });
}
```

Criar `apps/patient/test/terms_gate_flow_test.dart`. Antes de escrever, **abrir `test/patient_app_mvp_test.dart` e copiar o helper `login(tester)`** (o mesmo que o teste "menu Mais abre Privacidade e termos" usa) para dentro deste arquivo, pois helpers de teste não são importáveis entre arquivos:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show PatientConsentRecord;
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';

// (colar aqui o helper `login(tester)` de patient_app_mvp_test.dart)

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Paciente que ainda não aceitou nada: é o de quem entrou por OTP sem onboarding.
FakePatientBackend semAceite() {
  final backend = FakePatientBackend();
  backend.myDataResult = backend.myDataResult.copyWith(consents: const []);
  return backend;
}

void main() {
  testWidgets('sem aceite registrado, o login leva à tela de aceite', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_gate_accept_button')), findsOneWidget);
    expect(find.text('Registrar alerta de urgência'), findsNothing);
  });

  testWidgets('aceitar exige marcar a caixa, grava uma vez e segue para a tela inicial', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    final antes = tester.widget<FilledButton>(find.byKey(const Key('terms_gate_accept_button')));
    expect(antes.onPressed, isNull);

    await tapKey(tester, 'terms_gate_checkbox');
    await tapKey(tester, 'terms_gate_accept_button');

    expect(backend.acceptTermsCalls, 1);
    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
  });

  testWidgets('"Agora não" entra sem gravar nada', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    await tapKey(tester, 'terms_gate_later_button');

    expect(backend.acceptTermsCalls, 0);
    expect(find.byKey(const Key('terms_gate_later_button')), findsNothing);
  });

  testWidgets('já aceitou a versão vigente: nenhuma tela extra, uma leitura', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
    expect(backend.myDataCallCount, 1);
  });

  testWidgets('falha ao ler os consentimentos não impede a entrada', (tester) async {
    // Emergência: o alerta de urgência não pode ficar atrás de um aceite.
    final backend = semAceite()..myDataFailure = const BackendFailure('sem rede');
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('falha ao aceitar mostra o erro, mantém "Agora não" e permite tentar de novo', (tester) async {
    final backend = semAceite()..acceptTermsFailure = const BackendFailure('Sem conexão.');
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    await tapKey(tester, 'terms_gate_checkbox');
    await tapKey(tester, 'terms_gate_accept_button');

    expect(find.byKey(const Key('terms_gate_error')), findsOneWidget);
    expect(find.byKey(const Key('terms_gate_later_button')), findsOneWidget);

    backend.acceptTermsFailure = null;
    await tapKey(tester, 'terms_gate_accept_button');
    expect(backend.acceptTermsCalls, 2);
    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
  });

  testWidgets('"Ler o Termo e a Política" abre os documentos', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: semAceite()));
    await login(tester);

    await tapKey(tester, 'terms_gate_read_button');

    expect(find.textContaining('Versão $legalDocumentsVersion'), findsWidgets);
  });
}
```

Ajustar `find.byType(NavigationBar)` para o widget que a tela inicial realmente usa, se `PatientHomeShell` não usar `NavigationBar` (conferir em `app.dart` antes de rodar). Se o construtor de `BackendFailure` tiver outra forma que `const BackendFailure('...')`, seguir o de `onboarding_flow_test.dart`. Se `myDataResult.copyWith` não aceitar `consents`, usar `myDataResult = PatientDataOverview(...)` copiando os campos do fake.

Em `test/support/fake_patient_backend.dart`: no `myDataResult` padrão trocar `consents: const []` por uma linha de aceite vigente, para que os testes de login existentes não passem a ver a tela nova:

```dart
    consents: [
      PatientConsentRecord(
        purpose: 'termsOfUse',
        action: 'granted',
        version: '2026.1',
        timestamp: DateTime.utc(2026, 9, 1),
      ),
    ],
```

e, junto de `updateConsentCalls`:

```dart
  /// Chamadas a [acceptTermsOfUse].
  int acceptTermsCalls = 0;
  BackendFailure? acceptTermsFailure;

  /// Como no servidor: uma linha `termsOfUse` `granted` a mais no histórico.
  @override
  Future<PatientConsentRecord> acceptTermsOfUse() async {
    acceptTermsCalls++;
    final failure = acceptTermsFailure;
    if (failure != null) throw failure;
    final record = PatientConsentRecord(
      purpose: 'termsOfUse',
      action: 'granted',
      version: '2026.1',
      timestamp: DateTime.now().toUtc(),
    );
    myDataResult = myDataResult.copyWith(consents: [...myDataResult.consents, record]);
    return record;
  }
```

- [ ] **Step 2: Ver falhar**

Run: `cd apps/patient && flutter test test/terms_acceptance_test.dart test/terms_gate_flow_test.dart`
Expected: FAIL na compilação — `terms_acceptance.dart`, `acceptTermsOfUse` e `TermsAcceptanceScreen` não existem.

- [ ] **Step 3: Regra pura**

Criar `apps/patient/lib/core/legal/terms_acceptance.dart`:

```dart
import 'package:sinalacs_client/sinalacs_client.dart' show PatientConsentRecord;
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// `true` quando o paciente ainda precisa aceitar o Termo de Uso e a Política
/// de Privacidade vigentes (LGPD-RF18).
///
/// Vale a linha **mais recente** de `termsOfUse`, pela data, e não a última da
/// lista: o histórico é append-only, mas a ordem em que o servidor o devolve
/// não é contrato. Só conta um `granted` na versão que o app exibe hoje
/// ([legalDocumentsVersion]) — é isso que faz o aviso voltar quando a versão
/// mudar.
bool needsTermsAcceptance(List<PatientConsentRecord> consents) {
  PatientConsentRecord? latest;
  for (final record in consents) {
    if (record.purpose != 'termsOfUse') continue;
    if (latest == null || record.timestamp.isAfter(latest.timestamp)) latest = record;
  }
  return latest == null ||
      latest.action != 'granted' ||
      latest.version != legalDocumentsVersion;
}
```

- [ ] **Step 4: Camada de rede**

Em `backend_client.dart`: na interface `PatientBackend`, depois de `updateConsent`:

```dart
  /// Aceita o Termo de Uso e a Política de Privacidade vigentes (LGPD-RF18),
  /// para quem entrou por OTP sem passar pelo onboarding. O servidor grava uma
  /// linha `termsOfUse` `granted` em `consent_logs`.
  Future<PatientConsentRecord> acceptTermsOfUse();
```

Em `MisconfiguredBackend`, depois de `updateConsent`: `@override Future<PatientConsentRecord> acceptTermsOfUse() async => _recusar();`.

Em `BackendClient`, depois de `updateConsent`:

```dart
  @override
  Future<PatientConsentRecord> acceptTermsOfUse() async {
    final token = await _requireToken();
    return _guard(() => _client.patients.acceptTermsOfUse(accessToken: token));
  }
```

- [ ] **Step 5: Tela**

Em `legal_screens.dart`, acrescentar (ajustando imports se `LegalDocumentsScreen` estiver no mesmo arquivo, o que é o caso):

```dart
/// Convite para aceitar o Termo de Uso e a Política de Privacidade vigentes,
/// mostrado depois do login por OTP a quem ainda não aceitou a versão atual
/// (LGPD-RF18).
///
/// **Não é um portão.** "Agora não" segue para a tela inicial e o aviso volta
/// no próximo login: um paciente em emergência precisa chegar ao alerta de
/// urgência sem ler nada antes (invariante "red alerts never dropped").
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({required this.onContinue, super.key});

  /// Chamado depois do aceite gravado, ou ao escolher "Agora não".
  final VoidCallback onContinue;

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _checked = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendScope.of(context).acceptTermsOfUse();
      if (!mounted) return;
      widget.onContinue();
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termo de Uso e Privacidade')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Atualizamos o Termo de Uso e a Política de Privacidade '
              '(versão $legalDocumentsVersion). Leia e aceite para continuar '
              'usando o app com tudo em dia.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('terms_gate_read_button'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalDocumentsScreen()),
              ),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Ler o Termo e a Política'),
            ),
            CheckboxListTile(
              key: const Key('terms_gate_checkbox'),
              value: _checked,
              onChanged: _busy ? null : (value) => setState(() => _checked = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Li e aceito o Termo de Uso e a Política de Privacidade.'),
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('terms_gate_error'),
                  style: const TextStyle(color: PatientColors.dangerOnSurface),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('terms_gate_accept_button'),
              onPressed: _checked && !_busy ? _accept : null,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              child: const Text('Aceitar e continuar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('terms_gate_later_button'),
              onPressed: _busy ? null : widget.onContinue,
              style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
              child: const Text('Agora não'),
            ),
          ],
        ),
      ),
    );
  }
}
```

Conferir os imports já presentes em `legal_screens.dart` (`BackendScope`, `BackendFailure`, `PatientColors`) e acrescentar os que faltarem. Se `dangerOnSurface` não for o token de texto de erro que as telas vizinhas usam, seguir o token que `_PatientLoginScreenState` usa para `_error`.

- [ ] **Step 6: Ligar ao login**

Em `app.dart`, em `_PatientLoginScreenState._entrar`, trocar o `Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PatientHomeShell(...)))` que vem logo depois de `verifyOtp` por:

```dart
      final needsTerms = await _needsTerms();
      if (!mounted) return;
      final home = MaterialPageRoute<void>(
        builder: (_) => const PatientHomeShell(initialDestination: PatientDestination.triage),
      );
      Navigator.of(context).pushReplacement(
        needsTerms
            ? MaterialPageRoute<void>(
                builder: (routeContext) => TermsAcceptanceScreen(
                  onContinue: () => Navigator.of(routeContext).pushReplacement(home),
                ),
              )
            : home,
      );
```

e acrescentar ao `State`:

```dart
  /// Quem entrou por OTP sem onboarding, ou com aceite de versão anterior,
  /// recebe o convite ao aceite (LGPD-RF18). Falhou a leitura → entra direto:
  /// o alerta de emergência não espera por um aceite.
  Future<bool> _needsTerms() async {
    try {
      final overview = await BackendScope.of(context).myData();
      return needsTermsAcceptance(overview.consents);
    } on BackendFailure {
      return false;
    }
  }
```

Imports: `package:sinalacs_patient/core/legal/terms_acceptance.dart`. Manter o `Semantics`/`_busy` existentes de `_entrar`: o botão continua ocupado durante `myData()`.

- [ ] **Step 7: Ver passar**

Run: `cd apps/patient && flutter test test/terms_acceptance_test.dart test/terms_gate_flow_test.dart`
Expected: PASS (5 + 7).

- [ ] **Step 8: Suíte completa e commit**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: `No issues found!`, tudo verde. Se testes antigos de "Meus Dados" contarem linhas de consentimento e quebrarem por causa da linha `termsOfUse` que o fake agora traz, ajuste a contagem esperada e registre no ledger — o histórico real do servidor também a mostra.

```bash
git add apps/patient
git commit -m "feat(paciente): convite ao aceite do Termo de Uso depois do login por OTP (LGPD-RF18)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 3: Textos velhos da sessão do onboarding e registro

**Files:**
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart` (comentário ~linhas 154–160)
- Modify: `backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart` (comentário ~linhas 63–67)
- Modify: `apps/CLAUDE.md` (parágrafo do login do paciente), `PROGRESS.md`, `spec/lgpd_design.md`

**Interfaces:** Consumes: tudo acima. Produces: nada de código.

- [ ] **Step 1: Comentários**

Em `auth_endpoint.dart`, trocar a frase "não é o TTL de toda sessão de paciente: há dois caminhos de emissão, e o de onboarding (`onboarding_endpoint.dart`) ainda emite o padrão de 15 minutos, lacuna do RF02 registrada no plano." por "os dois caminhos de emissão do paciente — este e `onboarding.completeEnrollment` — usam `patientSessionLifetime`; `onboarding_endpoint_test.dart` prende o segundo."

Em `onboarding_endpoint.dart`, trocar o comentário "não há renovação silenciosa — 15 minutos padrão bastaria pouco. Ver PROGRESS.md 'Um defeito do RF02 que esta entrega mediu'." por "não há renovação silenciosa, então a sessão usa `patientSessionLifetime` (1 hora), como o login por OTP. O TTL de 15 minutos era um defeito do RF02, corrigido — ver PROGRESS.md."

- [ ] **Step 2: apps/CLAUDE.md**

No parágrafo "The patient login is passwordless now (RF01)…", remover a frase "One known gap: the onboarding path (`onboarding.completeEnrollment`, RF02) still issues the 15-minute default and has nothing to renew from — registered with an owner in [PROGRESS.md](../../../PROGRESS.md). One stale comment comes with it: the doc of `isExpired` … not the role." e acrescentar no lugar: "Both patient session paths — the OTP login and `onboarding.completeEnrollment` — issue the same 1-hour token (`AuthEndpoint.patientSessionLifetime`). After the OTP login the app reads `myData()` and, when the latest `termsOfUse` consent row is not `granted` in `legalDocumentsVersion`, shows `TermsAcceptanceScreen` (`legal_screens.dart`); it is a prompt, not a gate — \"Agora não\" and a failed `myData()` both go straight to the home, so the emergency alert never waits for an acceptance. `patients.acceptTermsOfUse` is the only writer of `termsOfUse` outside onboarding; `updateConsent` still refuses it."

- [ ] **Step 3: PROGRESS.md e spec**

Em `PROGRESS.md`, junto da linha ~991 (`onboarding_endpoint.dart:62 faz issueToken(user) — o default de 15 minutos`), acrescentar uma linha: "> **Resolvido:** `completeEnrollment` já emite `patientSessionLifetime`; o teste `onboarding_endpoint_test.dart` prende o valor. Esta seção descreve o defeito como foi medido." E, ao final do arquivo, uma seção `## Aceite do termo no login OTP (2026-09-29)` com: o que existe (`patients.acceptTermsOfUse`, `TermsAcceptanceScreen`, regra `needsTermsAcceptance`), o que ficou de fora de propósito (o aceite não é portão duro por causa do alerta de emergência; aviso com 15 dias de antecedência e revisão jurídica do texto seguem pendentes; toda chamada a `acceptTermsOfUse` grava uma linha nova, sem checar se já havia aceite da versão vigente — o app só chama quando `needsTermsAcceptance`), e as contagens reais de teste depois da entrega (rode as suítes e copie os números).

Em `spec/lgpd_design.md`, na nota "Estado (2026-09-29)" logo após LGPD-RF18, acrescentar: "Pacientes que entram por OTP sem onboarding são convidados a aceitar no primeiro login (`patients.acceptTermsOfUse`); o convite não é obrigatório para acessar o alerta de emergência."

- [ ] **Step 4: Verificações e commit**

Run:
```bash
./scripts/qa/ci_invariants.sh
graphify update .
```
Expected: invariantes OK; grafo atualizado.

```bash
git add backend/sinalacs_server/lib/src/endpoints apps/CLAUDE.md PROGRESS.md spec/lgpd_design.md
git commit -m "docs: sessão do onboarding já é de 1h; registra o aceite do termo no login OTP

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
