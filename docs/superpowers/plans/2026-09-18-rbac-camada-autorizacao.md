# Camada de Autorização (RBAC) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar RNF06/L-09 substituindo as sete checagens de papel escritas à mão por uma camada única de autorização, e garantir por teste que nenhum endpoint novo nasça público por omissão.

**Architecture:** Duas peças, sem canal novo e sem dependência nova. (1) `Authorization.require` em `application/auth/authorization.dart` — um único ponto que decide "este papel, neste território, pode?". Ele **não** lança exceção própria: recebe `onDenied` e deixa cada chamador lançar exatamente a exceção que já lançava hoje (`StateError` nos seis serviços territoriais, `TriageAuthorizationException` na triagem), então a tradução `StateError → AlertPermissionException` que os endpoints já fazem continua funcionando sem tocar em endpoint nenhum. (2) `AuthenticatedEndpoint` em `endpoints/authenticated_endpoint.dart` — a classe-base que centraliza a verificação do token (hoje duplicada em cinco endpoints) e marca, de forma legível por um teste, quais endpoints exigem credencial. Um teste de postura lê os arquivos de `lib/src/endpoints/` e falha se um endpoint novo não estender a base nem constar de uma allowlist explícita com justificativa.

**Tech Stack:** Dart/Serverpod (`backend/sinalacs_server`). Nenhum pacote novo, nenhum modelo `.spy.yaml` novo, nenhuma migração.

**Spec:** `spec/security_assessment.md` (achado **F4**, linha 175-198 — "auth seguro por convenção, não por padrão"), `spec/PRD_system.md` §2.2 linha 157 (**RNF06** "RBAC (Role-Based Access Control) … Auth própria no backend (ainda não implementado)") e §4.2.2 linha 580-596 (matriz de permissões e a admissão de que "o RBAC institucional segue não implementado"), `spec/lgpd_design.md` §5.2 linha 495 (matriz de permissões) e §LGPD-RT01 linha 621 (middleware de autenticação + validação de permissões por endpoint). Diagnóstico: `spec/validation_report.md` L-09 (linha 280).

## Global Constraints

- **Zero mudança de comportamento observável.** Toda mensagem de erro, todo tipo de exceção e todo texto em português permanecem idênticos aos de hoje. Este plano é um refactor de estrutura, não de regra: os 171 testes existentes (`cd backend/sinalacs_server && dart test`) devem continuar passando sem serem editados — **com uma única exceção declarada**, o novo teste de postura. Se algum teste existente precisar mudar, a refatoração saiu dos trilhos.
- **`Authorization.require` lança `StateError`?** Não por conta própria: quem decide é o `onDenied` de cada chamador. Isso é deliberado — `triage_session_service.dart` lança `TriageAuthorizationException` (tipada) e os outros seis lançam `StateError`. Unificar o tipo quebraria a tradução dos endpoints e os testes que a verificam.
- **Não ligar `requireLogin => true`.** O stack de autenticação do próprio Serverpod (`AuthenticationHandler`) não está conectado neste projeto — a autenticação é feita à mão, com `verifyToken`. Trocar a flag sem conectar o handler rejeitaria *todas* as chamadas. A postura de cada endpoint passa a ser verificada por teste (Task 4), que é o que o F4 pede; a flag continua `false` com o motivo documentado.
- **Papéis `admin` e `coordinator` continuam inalcançáveis de propósito.** O enum `UserRole` tem 4 valores (`patient`, `acs`, `coordinator`, `admin`), mas nenhum caminho emite `coordinator`/`admin` hoje e este plano não cria um — o backend do backoffice é escopo de outro plano, deliberadamente excluído. O teste unitário da guarda exercita esses papéis construindo `AuthenticatedUser` direto (sem emitir token), que é o suficiente para provar que a barreira os recusa.
- Comentários e mensagens em português, seguindo o repositório.
- Nunca editar `lib/src/generated/` — nada aqui toca modelo gerado, então `serverpod generate` não é necessário em nenhuma task.
- Antes de qualquer `dart test` de integração: `docker compose --profile test up -d postgres-test` (o banco de teste já está de pé neste ambiente, verificado).

---

## File Structure

- **Create** `backend/sinalacs_server/lib/src/application/auth/authorization.dart` — `Authorization.require`, a única regra de papel/território do backend.
- **Create** `backend/sinalacs_server/lib/src/endpoints/authenticated_endpoint.dart` — `authenticateToken()` (função) + `AuthenticatedEndpoint` (classe-base).
- **Create** `backend/sinalacs_server/test/unit/authorization_test.dart` — testes herméticos da guarda.
- **Create** `backend/sinalacs_server/test/unit/endpoint_auth_posture_test.dart` — o guard de F4.
- **Modify** os 4 endpoints que só têm métodos autenticados: `alerts_endpoint.dart`, `visits_endpoint.dart`, `triage_endpoint.dart`, `patients_endpoint.dart` — passam a estender `AuthenticatedEndpoint` e perdem o `_authenticate` próprio.
- **Modify** os 6 serviços com checagem ad-hoc: `application/alerts/red_alert_service.dart` (3 sítios), `application/visits/visit_sync_service.dart` (2), `application/patients/patient_directory_service.dart` (1), `application/onboarding/onboarding_service.dart` (1), `application/triage/triage_session_service.dart` (1).
- **Modify** `endpoints/onboarding_endpoint.dart` — postura mista (um método público, um autenticado): continua `Endpoint` puro, mas passa a usar `authenticateToken` e entra na allowlist do teste de postura.
- **Modify** `spec/security_assessment.md`, `spec/validation_report.md` (L-09), `backend/CLAUDE.md` — sincronizar o que deixou de ser verdade.

---

## Task 1: A guarda `Authorization.require`

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/authorization.dart`
- Test: `backend/sinalacs_server/test/unit/authorization_test.dart`

**Interfaces:**
- Consumes: `AuthenticatedUser` de `application/auth/development_auth_service.dart` (campos `id`, `role` (`UserRole`), `microAreaId` (`String?`), `deviceId`).
- Produces: `Authorization.require(user, {required Set<UserRole> roles, required Object Function() onDenied, bool requireMicroArea = true}) → void`. É esta assinatura exata que as Tasks 2 e 3 usam.

- [ ] **Step 1: Escrever o teste que falha**

Cria `backend/sinalacs_server/test/unit/authorization_test.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
// `TriageAuthorizationException` é uma classe Dart escrita à mão (não gerada),
// declarada em `application/triage/triage_session_service.dart:15` — é o único
// ponto do backend que recusa com exceção tipada em vez de `StateError`.
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

AuthenticatedUser _user(UserRole role, {String? microAreaId = 'micro-area-1'}) =>
    AuthenticatedUser(
      id: '00000000-0000-4000-8000-000000000002',
      role: role,
      microAreaId: microAreaId,
      deviceId: 'test-device',
    );

void main() {
  group('Authorization.require', () {
    test('aceita o papel permitido e devolve o controle ao chamador', () {
      expect(
        () => Authorization.require(
          _user(UserRole.acs),
          roles: {UserRole.acs},
          onDenied: () => StateError('não deveria ser lançada'),
        ),
        returnsNormally,
      );
    });

    test('recusa outro papel lançando o que o chamador passou', () {
      expect(
        () => Authorization.require(
          _user(UserRole.patient),
          roles: {UserRole.acs},
          onDenied: () => StateError('Somente ACS podem fazer isto.'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Somente ACS podem fazer isto.',
          ),
        ),
      );
    });

    // O tipo da exceção é decisão do chamador, não da guarda: a triagem lança
    // TriageAuthorizationException e os serviços territoriais lançam StateError.
    // Unificar aqui quebraria a tradução dos endpoints.
    test('preserva o tipo da exceção do chamador', () {
      expect(
        () => Authorization.require(
          _user(UserRole.acs),
          roles: {UserRole.patient},
          onDenied: () => const TriageAuthorizationException('x'),
        ),
        throwsA(isA<TriageAuthorizationException>()),
      );
    });

    test('recusa papel permitido sem território quando exigido', () {
      expect(
        () => Authorization.require(
          _user(UserRole.acs, microAreaId: null),
          roles: {UserRole.acs},
          onDenied: () => StateError('sem território'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    // statusFor (RF05) é escopado ao próprio paciente e não depende de
    // território: exigir microárea ali recusaria todo paciente que o seed cria
    // com microárea — e passaria despercebido, porque o teste de hoje usa um
    // paciente que tem uma.
    test('não exige território quando requireMicroArea é false', () {
      expect(
        () => Authorization.require(
          _user(UserRole.patient, microAreaId: null),
          roles: {UserRole.patient},
          onDenied: () => StateError('não deveria ser lançada'),
          requireMicroArea: false,
        ),
        returnsNormally,
      );
    });

    test('recusa papéis ainda não emitidos pelo backend', () {
      for (final role in [UserRole.admin, UserRole.coordinator]) {
        expect(
          () => Authorization.require(
            _user(role),
            roles: {UserRole.acs, UserRole.patient},
            onDenied: () => StateError('papel não autorizado'),
          ),
          throwsA(isA<StateError>()),
          reason: '$role não pode passar numa regra de ACS/paciente',
        );
      }
    });
  });
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/authorization_test.dart`
Expected: FAIL — erro de compilação, `authorization.dart` não existe ("Error when reading ... no such file" / "Target of URI doesn't exist").

- [ ] **Step 3: Escrever a implementação mínima**

Cria `backend/sinalacs_server/lib/src/application/auth/authorization.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// A única decisão de "este papel, neste território, pode?" do backend
/// (RNF06, achado F4 de spec/security_assessment.md).
///
/// Antes desta classe a mesma pergunta era respondida sete vezes, à mão, uma
/// por serviço — seis com `StateError` e uma com `TriageAuthorizationException`.
/// Nada obrigava um serviço novo a ter a sua: um caso de uso nascia público por
/// omissão e só uma revisão humana pegava.
///
/// Esta guarda **não escolhe o tipo da exceção**. Ela recebe `onDenied` e lança
/// o que o chamador construir, porque o tipo faz parte do contrato de cada
/// serviço: os endpoints traduzem `StateError` para `AlertPermissionException`
/// (ver `VisitsEndpoint.sync`) e `TriageAuthorizationException` é tipada e
/// serializada ao cliente. Uma guarda que lançasse um tipo próprio quebraria as
/// duas traduções de uma vez.
abstract final class Authorization {
  /// Exige que [user] tenha um dos [roles] e, quando [requireMicroArea], que o
  /// token carregue um território.
  ///
  /// `requireMicroArea` é `true` por omissão porque a territorialização é
  /// invariante (INV-01): quem lê ou escreve dado de paciente o faz *dentro* de
  /// uma microárea, e um token sem território não tem barreira nenhuma para
  /// aplicar. O caso `false` existe para leitura escopada ao próprio titular
  /// (`alerts.statusFor`, RF05), que não passa por território — ali quem
  /// restringe é o `user.id` vindo do token, não a microárea.
  static void require(
    AuthenticatedUser user, {
    required Set<UserRole> roles,
    required Object Function() onDenied,
    bool requireMicroArea = true,
  }) {
    if (!roles.contains(user.role)) throw onDenied();
    if (requireMicroArea && user.microAreaId == null) throw onDenied();
  }
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/unit/authorization_test.dart`
Expected: PASS — 6 testes.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/authorization.dart \
        backend/sinalacs_server/test/unit/authorization_test.dart
git commit -m "feat(backend): Authorization.require — guarda única de papel e território (RNF06)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 2: Migrar as sete checagens ad-hoc para a guarda

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart:115`, `:172`, `:185`
- Modify: `backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart:156`, `:200`
- Modify: `backend/sinalacs_server/lib/src/application/patients/patient_directory_service.dart:49`
- Modify: `backend/sinalacs_server/lib/src/application/onboarding/onboarding_service.dart:104`
- Modify: `backend/sinalacs_server/lib/src/application/triage/triage_session_service.dart:105`

**Interfaces:**
- Consumes: `Authorization.require` da Task 1.
- Produces: nada novo — os serviços mantêm as assinaturas e as exceções que já tinham.

Cada substituição é mecânica e **preserva a mensagem literal**. As mensagens estão copiadas abaixo, verbatim, porque é isso que os testes de hoje asseveram.

- [ ] **Step 1: Confirmar que a suíte está verde antes de mexer**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — `+171: All tests passed!` (contagem medida neste repositório em 2026-09-18; se estiver diferente, anote o número antes de continuar para comparar depois).

- [ ] **Step 2: Migrar `red_alert_service.dart` (três sítios)**

Adicione o import no topo do arquivo:

```dart
import 'package:sinalacs_server/src/application/auth/authorization.dart';
```

Substitua o bloco em `createRedAlert` (linhas 115-117):

```dart
    if (user.role != UserRole.patient || user.microAreaId == null) {
      throw StateError('Somente pacientes territorializados podem criar alertas.');
    }
```

por:

```dart
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () =>
          StateError('Somente pacientes territorializados podem criar alertas.'),
    );
```

Substitua o bloco em `acknowledge` (linhas 172-174):

```dart
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem confirmar alertas.');
    }
```

por:

```dart
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem confirmar alertas.'),
    );
```

Substitua o bloco em `statusFor` (linhas 185-187):

```dart
    if (user.role != UserRole.patient) {
      throw StateError('Somente pacientes podem consultar o status do próprio alerta.');
    }
```

por — note o `requireMicroArea: false`, que é a preservação exata do comportamento de hoje (a checagem original testava só o papel):

```dart
    // `requireMicroArea: false` preserva a regra de hoje: `statusFor` é
    // escopado ao próprio titular pelo `user.id` do token (INV-05), então um
    // paciente sem microárea continua podendo ver o próprio status.
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () =>
          StateError('Somente pacientes podem consultar o status do próprio alerta.'),
      requireMicroArea: false,
    );
```

- [ ] **Step 3: Migrar `visit_sync_service.dart` (dois sítios, mensagem idêntica)**

Adicione o import `authorization.dart`. Em `pull` (linhas 156-158) e em `sync` (linhas 200-202), substitua:

```dart
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem sincronizar visitas.');
    }
```

por (nos **dois** lugares):

```dart
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem sincronizar visitas.'),
    );
```

- [ ] **Step 4: Migrar `patient_directory_service.dart`**

Adicione o import `authorization.dart`. Substitua as linhas 49-51:

```dart
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem listar pacientes.');
    }
```

por:

```dart
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem listar pacientes.'),
    );
```

- [ ] **Step 5: Migrar `onboarding_service.dart`**

Adicione o import `authorization.dart`. Substitua as linhas 104-106 — atenção ao nome do parâmetro: aqui a variável é `acs`, não `user`:

```dart
    if (acs.role != UserRole.acs || acs.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem gerar convites.');
    }
```

por:

```dart
    Authorization.require(
      acs,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem gerar convites.'),
    );
```

- [ ] **Step 6: Migrar `triage_session_service.dart` — o sítio de exceção tipada**

Adicione o import `authorization.dart`. Substitua as linhas 105-109:

```dart
    if (user.role != UserRole.patient) {
      throw const TriageAuthorizationException(
        'Somente o paciente pode registrar a própria triagem.',
      );
    }
```

por:

```dart
    // O tipo aqui é `TriageAuthorizationException` (declarada em .spy.yaml e
    // serializada ao cliente), não `StateError` — a guarda só decide, o
    // chamador escolhe o que lançar.
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () => const TriageAuthorizationException(
        'Somente o paciente pode registrar a própria triagem.',
      ),
      requireMicroArea: false,
    );
```

- [ ] **Step 7: Rodar a suíte inteira e confirmar que nada mudou**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — a **mesma** contagem do Step 1. Se algum teste existente falhar, a mensagem ou o tipo da exceção divergiu: compare com a mensagem literal colada nos steps acima.

- [ ] **Step 8: Confirmar que nenhuma checagem ad-hoc sobrou**

Run: `cd backend/sinalacs_server && grep -rn "role != UserRole" lib/src/application/ lib/src/endpoints/`
Expected: **nenhuma saída** (o comando não imprime nada e retorna 1; isso é o resultado esperado).

- [ ] **Step 9: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/
git commit -m "refactor(backend): unificar as 7 checagens de papel em Authorization.require (RNF06)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 3: `AuthenticatedEndpoint` e a verificação de token num só lugar

**Files:**
- Create: `backend/sinalacs_server/lib/src/endpoints/authenticated_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/visits_endpoint.dart:15-17`, `:59-65`
- Modify: `backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/patients_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart`

**Interfaces:**
- Consumes: `Authorization` da Task 1; `AlertRuntime.instance.auth.verifyToken`.
- Produces: `authenticateToken(String accessToken) → AuthenticatedUser` (função de topo) e `abstract class AuthenticatedEndpoint extends Endpoint` com `protected AuthenticatedUser authenticate(String accessToken)`. É o que a Task 4 procura no texto-fonte de cada endpoint.

Hoje a mesma função existe cinco vezes, byte a byte igual, em `alerts_endpoint.dart:120-126`, `visits_endpoint.dart:59-65`, `triage_endpoint.dart`, `patients_endpoint.dart` e `onboarding_endpoint.dart:18-21` — com duas mensagens diferentes para o mesmo caso ("token inválido ou expirado" e variações). A duplicação é o motivo de um endpoint novo poder esquecer de autenticar.

- [ ] **Step 1: Criar a classe-base**

Cria `backend/sinalacs_server/lib/src/endpoints/authenticated_endpoint.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Verifica o token de acesso e devolve o usuário, ou recusa.
///
/// Era o corpo idêntico de cinco métodos privados `_authenticate`, um por
/// endpoint. Fica numa função só para que exista **um** lugar onde a
/// verificação pode ser lida — e para que um endpoint novo tenha de onde
/// herdá-la em vez de reescrevê-la.
AuthenticatedUser authenticateToken(String accessToken) {
  final user = AlertRuntime.instance.auth.verifyToken(accessToken);
  if (user == null) {
    throw AlertPermissionException(message: 'token inválido ou expirado');
  }
  return user;
}

/// Endpoint cujos métodos exigem credencial.
///
/// A existência desta classe é o que permite ao teste de postura
/// (`test/unit/endpoint_auth_posture_test.dart`) distinguir, no texto-fonte,
/// um endpoint autenticado de um público. `requireLogin` continua `false`: o
/// stack de autenticação do próprio Serverpod (`AuthenticationHandler`) não
/// está conectado neste projeto — a autenticação é feita à mão, com
/// `verifyToken`, e ligar a flag sem conectar o handler rejeitaria *todas* as
/// chamadas. O que muda aqui é a postura ficar declarada e verificável, que é
/// o que o achado F4 de spec/security_assessment.md pede.
abstract class AuthenticatedEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  /// Delega para [authenticateToken]; existe como método para que os endpoints
  /// chamem `authenticate(...)` como sempre chamaram.
  @protected
  AuthenticatedUser authenticate(String accessToken) =>
      authenticateToken(accessToken);
}
```

- [ ] **Step 2: Migrar `visits_endpoint.dart`**

No topo, adicione o import e troque a superclasse:

```dart
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
```

```dart
class VisitsEndpoint extends AuthenticatedEndpoint {
```

Remova o `@override bool get requireLogin => false;` (linhas 16-17) — a base já o define.

Remova o método `_authenticate` (linhas 59-65) inteiro e troque as duas chamadas `_authenticate(accessToken)` (linhas 24 e 49) por `authenticate(accessToken)`. **Não** declare nada no lugar: o `authenticate` vem herdado da base. Se sobrar um import de `development_auth_service.dart` sem uso depois da remoção, apague-o — o analisador do Step 6 aponta.

- [ ] **Step 3: Migrar `alerts_endpoint.dart`**

Mesma troca: `class AlertsEndpoint extends AuthenticatedEndpoint`, remover o `requireLogin` local e o `_authenticate`, e trocar as chamadas internas para `authenticate(accessToken)`.

- [ ] **Step 4: Migrar `triage_endpoint.dart` e `patients_endpoint.dart`**

Idem: superclasse, remoção do `requireLogin` local e do `_authenticate`, chamadas para `authenticate(accessToken)`.

- [ ] **Step 5: Migrar `onboarding_endpoint.dart` — postura mista, sem herdar a base**

Este endpoint **não** pode estender `AuthenticatedEndpoint`: `generateEnrollmentToken` exige token de ACS, mas `completeEnrollment` é público **por desenho** (quem conclui o onboarding ainda não tem sessão — o convite de uso único *é* a credencial, ver `onboarding_service.dart:135-175`). Ele continua `extends Endpoint` com `requireLogin => false`, e passa a usar a função compartilhada em vez do `_authenticate` local:

```dart
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
```

Troque o corpo do `_authenticate` local por uma chamada à função:

```dart
  AuthenticatedUser _authenticate(String accessToken) =>
      authenticateToken(accessToken);
```

Ou, preferencialmente, remova o wrapper e chame `authenticateToken(accessToken)` direto no método — deixe o arquivo com uma linha a menos. Adicione um comentário no topo da classe explicando a postura mista, porque é exatamente isto que o teste da Task 4 vai permitir:

```dart
/// Postura de autenticação **mista**, e é por isso que este endpoint não
/// estende `AuthenticatedEndpoint`: `generateEnrollmentToken` exige token de
/// ACS, mas `completeEnrollment` é público por desenho — quem o chama ainda
/// não tem sessão, e o convite de uso único é a credencial. Ver a allowlist
/// em `test/unit/endpoint_auth_posture_test.dart`.
```

- [ ] **Step 6: Analisar e rodar a suíte**

Run: `cd backend && dart analyze`
Expected: nenhum problema. Se aparecer aviso de import não usado, remova o import indicado.

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — mesma contagem da Task 2.

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server/lib/src/endpoints/
git commit -m "refactor(backend): AuthenticatedEndpoint centraliza a verificação de token (F4)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 4: O guard de postura de autenticação (achado F4)

**Files:**
- Test: `backend/sinalacs_server/test/unit/endpoint_auth_posture_test.dart`

**Interfaces:**
- Consumes: a string `extends AuthenticatedEndpoint` que a Task 3 introduziu nos quatro endpoints autenticados.
- Produces: nada de runtime — é um guard de regressão.

O teste lê o texto-fonte de `lib/src/endpoints/`. Não importa as classes: importá-las puxaria o runtime do Serverpod e o teste deixaria de ser hermético. `dart test` roda com o diretório de trabalho na raiz do pacote (`backend/sinalacs_server`), então o caminho relativo resolve.

- [ ] **Step 1: Escrever o teste**

Cria `backend/sinalacs_server/test/unit/endpoint_auth_posture_test.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';

/// Endpoints que NÃO estendem `AuthenticatedEndpoint`, cada um com o motivo.
///
/// A allowlist é o ponto do teste: adicionar um endpoint novo faz esta suíte
/// falhar até que alguém decida, por escrito, qual é a postura dele. Antes
/// disso a decisão era implícita — um endpoint nascia público porque ninguém
/// tinha escrito a checagem ainda (achado F4 de spec/security_assessment.md).
const _publicByDesign = <String, String>{
  'HealthEndpoint': 'liveness: precisa responder antes de haver credencial',
  'AuthEndpoint': 'é o próprio emissor de token',
  'OnboardingEndpoint':
      'postura mista: completeEnrollment é público por desenho (o convite de '
      'uso único é a credencial), generateEnrollmentToken exige token de ACS',
};

void main() {
  test('todo endpoint é autenticado por padrão ou explicitamente isento', () {
    final directory = Directory('lib/src/endpoints');
    expect(
      directory.existsSync(),
      isTrue,
      reason: 'o teste roda com cwd em backend/sinalacs_server',
    );

    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_endpoint.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'nenhum endpoint encontrado — o caminho mudou?');

    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      final match = RegExp(r'class (\w+) extends').firstMatch(source);
      final name = match?.group(1);
      if (name == null) {
        offenders.add('${file.path}: não foi possível ler o nome da classe');
        continue;
      }

      final isGuarded = source.contains('extends AuthenticatedEndpoint');
      final isAllowlisted = _publicByDesign.containsKey(name);
      if (!isGuarded && !isAllowlisted) {
        offenders.add(
          '$name (${file.path}) não estende AuthenticatedEndpoint e não está '
          'na allowlist de postura pública',
        );
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('a allowlist não guarda endpoint que já virou autenticado', () {
    // Entrada obsoleta na allowlist é pior que entrada ausente: ela documenta
    // uma postura pública que não existe mais e esconde a hora de removê-la.
    for (final name in _publicByDesign.keys) {
      final path = 'lib/src/endpoints/${_fileNameFor(name)}';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$name não existe mais em $path');
      expect(
        file.readAsStringSync().contains('extends AuthenticatedEndpoint'),
        isFalse,
        reason: '$name já é autenticado — remova-o da allowlist',
      );
    }
  });
}

/// `HealthEndpoint` → `health_endpoint.dart`.
String _fileNameFor(String className) {
  final snake = className
      .replaceAll('Endpoint', '')
      .replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match.group(0)!}')
      .toLowerCase()
      .replaceAll(RegExp('^_'), '');
  return '${snake}_endpoint.dart';
}
```

- [ ] **Step 2: Rodar e confirmar que passa com os quatro endpoints migrados**

Run: `cd backend/sinalacs_server && dart test test/unit/endpoint_auth_posture_test.dart`
Expected: PASS — 2 testes.

- [ ] **Step 3: Provar que o guard realmente pega um endpoint público novo**

Esta é a verificação que importa: um guard que nunca falha não prova nada. Crie um arquivo temporário:

```bash
cat > backend/sinalacs_server/lib/src/endpoints/temp_probe_endpoint.dart <<'EOF'
import 'package:serverpod/serverpod.dart';

class TempProbeEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;
}
EOF
```

Run: `cd backend/sinalacs_server && dart test test/unit/endpoint_auth_posture_test.dart`
Expected: **FAIL**, com `TempProbeEndpoint (lib/src/endpoints/temp_probe_endpoint.dart) não estende AuthenticatedEndpoint`.

Apague o arquivo de prova e confirme que volta a passar:

```bash
rm backend/sinalacs_server/lib/src/endpoints/temp_probe_endpoint.dart
cd backend/sinalacs_server && dart test test/unit/endpoint_auth_posture_test.dart
```

Expected: PASS.

- [ ] **Step 4: Rodar a suíte inteira**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — contagem da Task 2 + 2 (os dois testes novos da Task 1 e os dois desta).

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/test/unit/endpoint_auth_posture_test.dart
git commit -m "test(backend): guard de postura de autenticação por endpoint (F4/RNF06)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 5: Sincronizar a documentação com o que deixou de ser verdade

**Files:**
- Modify: `spec/security_assessment.md` (achado F4, linhas 175-198)
- Modify: `spec/validation_report.md` (L-09, linhas 280-283; e a linha 99 de RNF06 na matriz de RNF)
- Modify: `backend/CLAUDE.md` (a seção que descreve a autenticação dos endpoints)

**Interfaces:**
- Consumes: tudo das Tasks 1-4.
- Produces: nada de código.

O repositório já tem o hábito de manter esses documentos honestos — `spec/lgpd_design.md` carrega um bloco "Estado atual (verificado 2026-09-18)" desde a última rodada. Aqui é o mesmo movimento.

- [ ] **Step 1: Atualizar o achado F4**

Em `spec/security_assessment.md`, no achado **F4**, acrescente ao final da seção (sem apagar o diagnóstico original, que registra o estado em que foi medido) um parágrafo de estado atual:

```markdown
**Estado atual (2026-09-18):** a extração recomendada foi implementada —
`Authorization.require` (`backend/sinalacs_server/lib/src/application/auth/authorization.dart`)
é a única regra de papel/território, os quatro endpoints com postura
integralmente autenticada estendem `AuthenticatedEndpoint`
(`.../endpoints/authenticated_endpoint.dart`) e
`test/unit/endpoint_auth_posture_test.dart` falha se um endpoint novo não
estender a base nem constar da allowlist explícita. `requireLogin` continua
`false` em todos eles **de propósito**: o `AuthenticationHandler` do Serverpod
não está conectado, e ligar a flag sem conectá-lo rejeitaria todas as chamadas.
```

- [ ] **Step 2: Atualizar L-09 no relatório de validação**

Em `spec/validation_report.md`, substitua o texto atual de L-09 (linhas 280-283) por:

```markdown
- **L-09 · RNF06 (RBAC) — camada de autorização implementada, papéis
  institucionais ainda ausentes.** `Authorization.require` centraliza a decisão
  de papel/território e substituiu as 7 checagens ad-hoc; os 4 endpoints
  integralmente autenticados estendem `AuthenticatedEndpoint` e um teste de
  postura impede um endpoint novo de nascer público. O que **não** mudou: os
  papéis `coordinator` e `admin` continuam sem caminho de emissão e sem
  endpoint que os exercite — isso é o backend do backoffice (L-01), fora do
  escopo desta rodada. Ver
  `docs/superpowers/plans/2026-09-18-rbac-camada-autorizacao.md`.
```

Na tabela de RNF (linha 99), troque o veredito de RNF06 de `ausente` para `parcial`, mantendo a coluna de evidência coerente:

```markdown
| RNF06 | RBAC | **parcial** | `Authorization.require` é a única regra de papel/território e um teste de postura cobre os 7 endpoints, mas `requireLogin` segue `false` (o `AuthenticationHandler` do Serverpod não está conectado) e os papéis `coordinator`/`admin` não têm caminho de emissão. |
```

Atualize também a linha de contagem logo abaixo da tabela de RFs, se ela citar RNF06.

- [ ] **Step 3: Atualizar `backend/CLAUDE.md`**

No parágrafo "**Serverpod is RPC, not REST**" (linha 68), onde os endpoints são descritos, acrescente a informação de postura. O texto atual lista cada endpoint; acrescente ao final do parágrafo:

```markdown
Toda autorização passa por uma regra única,
`Authorization.require` (`lib/src/application/auth/authorization.dart`): o
chamador decide o que lançar (`StateError` nos serviços territoriais,
`TriageAuthorizationException` na triagem), e é isso que preserva a tradução
`StateError → AlertPermissionException` feita nos endpoints. Os endpoints com
postura integralmente autenticada estendem `AuthenticatedEndpoint`
(`lib/src/endpoints/authenticated_endpoint.dart`), que centraliza a
verificação do token; `test/unit/endpoint_auth_posture_test.dart` lê o
texto-fonte de `lib/src/endpoints/` e falha se um endpoint novo não estender a
base nem constar da allowlist justificada. `requireLogin` continua `false` em
todos: o `AuthenticationHandler` do Serverpod não está conectado.
```

- [ ] **Step 4: Rodar `graphify update` e commitar**

O `CLAUDE.md` da raiz pede manter o grafo em dia depois de mexer no código:

```bash
graphify update .
git add spec/security_assessment.md spec/validation_report.md backend/CLAUDE.md graphify-out/
git commit -m "docs: registrar a camada de autorização (RNF06/L-09) como parcial

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Verificação final

- [ ] **Suíte backend inteira verde:** `cd backend/sinalacs_server && dart test` → `All tests passed!`, com a contagem da Task 2 mais 4.
- [ ] **Analisador limpo:** `cd backend && dart analyze` → nenhum problema.
- [ ] **Nenhuma checagem ad-hoc sobrou:** `grep -rn "role != UserRole" backend/sinalacs_server/lib/src/` → sem saída.
- [ ] **Nenhum `_authenticate` privado duplicado sobrou:** `grep -rn "AuthenticatedUser _authenticate" backend/sinalacs_server/lib/src/` → sem saída.
- [ ] **O guard de postura falha quando deve:** o Step 3 da Task 4 foi executado (arquivo de prova criado → suíte vermelha → arquivo removido → suíte verde). Sem essa prova, o guard não está verificado.

## Fora de escopo (registrado, não implementado)

- **Emitir `coordinator`/`admin`.** Sem caminho de emissão e sem endpoint que os exercite — é o backend do backoffice (L-01), excluído desta rodada por decisão de escopo.
- **Conectar o `AuthenticationHandler` do Serverpod e virar `requireLogin => true`.** Troca o contrato de token de todos os endpoints e dos dois apps; o ganho sobre o teste de postura (que já impede endpoint público acidental) não paga o risco agora.
- **MFA/TOTP para o ACS.** Exigido por `spec/lgpd_design.md` (LGPD-RF11, LGPD-RT06) e recomendado pelo achado F5, mas adiado por decisão de escopo registrada em 2026-09-18 — ver o plano de RF07 para a lacuna documentada.
