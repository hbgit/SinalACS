# QR Code do onboarding e documentos legais — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar as duas lacunas restantes do app paciente escolhidas para esta rodada: (1) RF02 de ponta a ponta — o ACS gera o convite e mostra o QR Code, o paciente lê pela câmera; (2) LGPD-RF18/RF19/RF10 — Termo de Uso e Política de Privacidade versionados no app, com resumo visual do fluxo de dados, histórico de versões e aceite explícito gravado no cadastro.

**Architecture:** O backend já tem `onboarding.generateEnrollmentToken` (ACS) e `onboarding.completeEnrollment` (paciente), mas nenhum app chama o primeiro, e o segundo só aceita o token digitado. O plano liga o ACS ao RPC existente e desenha o QR com `qr_flutter`; no paciente, `mobile_scanner` lê o QR e preenche o **mesmo** campo que já existe (o caminho manual continua). Os documentos legais são conteúdo Dart constante no app paciente (`lib/core/legal/`), versionados com o mesmo literal `2026.1` que o backend já carimba em `consent_logs.version`; o aceite vira uma quarta finalidade, `ConsentPurpose.termsOfUse`, gravada pela mesma transação do onboarding e obrigatória como `healthDataProcessing`.

**Tech Stack:** Serverpod 3.4.13 (Dart), Postgres, Flutter 3.44 (`apps/patient`, `apps/acs`), `mobile_scanner` ^7.0.0 (paciente), `qr_flutter` ^4.1.0 (ACS).

**Spec:** `spec/PRD_system.md` (RF02, linha 135) e `spec/lgpd_design.md` (LGPD-RF10 linha 157, RF18 linha 249, RF19 linha 259, retenção §5.6 linha 527). Leia os trechos antes de começar.

## Global Constraints

- Documentação, comentários, mensagens e texto de UI em **português**, no tom dos arquivos vizinhos.
- Nunca dado real de paciente em teste, log, screenshot ou config: tokens, nomes e UUIDs sintéticos (`Fulano de Tal`, `00000000-0000-4000-8000-00000000000N`).
- Nunca editar à mão `backend/sinalacs_server/lib/src/generated/`, `backend/sinalacs_client/`, `migrations/` ou `test/integration/test_tools/serverpod_test_tools.dart` — só via `serverpod generate` / `serverpod create-migration` (em `backend/sinalacs_server`, com `export PATH=$PATH:~/.pub-cache/bin`).
- **Não** rodar `dart format` em `apps/patient/lib/app/app.dart` nem em `apps/acs/lib/app/app.dart`: reflui centenas de linhas alheias. Aplicar as edições à mão, no estilo do entorno. Arquivos **novos** podem ser formatados.
- O token de convite em claro nunca vai para disco, log ou fila offline — só memória de tela (o servidor guarda só o hash, `enrollment_tokens.tokenHash`).
- Classificação de risco e territorialização não mudam: `generateEnrollmentToken` já recusa paciente de outra microárea (INV-01); o app não tenta contornar.
- Cor como texto usa o token `*OnSurface` (`AcsColors.redOnSurface`, `PatientColors.dangerOnSurface`), nunca a cor de preenchimento.
- Botões com `minimumSize: const Size(48, 52)` (WCAG 2.5.5); mensagens dinâmicas de erro dentro de `Semantics(liveRegion: true, ...)` (WCAG 4.1.3).
- `flutter analyze` tem de sair limpo (infos contam) nos dois apps; `cd backend && dart analyze` sem novos avisos além dos ~37 infos preexistentes.
- `consentPolicyVersion` (backend) e `legalDocumentsVersion` (app paciente) são o **mesmo** literal, `'2026.1'`; um teste do app guarda essa igualdade.
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Nada de push/merge sem perguntar.
- Depois de mudar código: `graphify update .` (na raiz; `graphify-out` é ignorado pelo git).
- Testes de backend exigem `docker compose --profile test up -d postgres-test` antes de `dart test`.

## Review Focus

1. **QR que não é convite** (link de site, Pix, QR de outro app) lido pela câmera → a pessoa vê "Este QR Code não é um convite do SinalACS…", e o campo do código **não** é sobrescrito. Teste na Tarefa 6 (`QR que não é convite mostra aviso e não preenche o campo`).
2. **Câmera indisponível ou permissão negada** → a leitura falha sem travar o onboarding; aparece um aviso para digitar o código, e o caminho manual continua funcionando. Teste na Tarefa 6 (`falha da câmera mostra aviso e o campo manual continua utilizável`). A página da câmera em si (canal de plataforma) só é verificável no aparelho — registrado em PROGRESS.md.
3. **ACS troca de paciente com um QR na tela** → o QR do paciente anterior some antes de gerar outro; nunca fica na tela um convite atribuído ao nome errado. Teste na Tarefa 5 (`trocar de paciente esconde o convite anterior`).
4. **Cliente que pula a tela e manda `termsAccepted: false`** → o servidor recusa com `EnrollmentException`, não grava nenhuma linha em `consent_logs` e o convite continua válido para nova tentativa. Testes na Tarefa 3 (unitário e integração).
5. **Versão do documento no app diverge da versão carimbada pelo backend** → um teste falha no CI do app paciente, em vez de o histórico de "Meus dados" mostrar um aceite de uma versão que o app nunca exibiu. Teste na Tarefa 1 (`versão dos documentos é a mesma que o backend carimba`).

---

## Mapa de arquivos

| Arquivo | Responsabilidade | Tarefa |
|---|---|---|
| `apps/patient/lib/core/legal/legal_documents.dart` (novo) | Modelo + conteúdo constante do Termo de Uso e da Política de Privacidade, versão vigente | 1 |
| `apps/patient/test/legal_documents_test.dart` (novo) | Conteúdo mínimo RF18/RF19 + guarda de versão contra o backend | 1 |
| `apps/patient/lib/app/legal_screens.dart` (novo) | `LegalDocumentsScreen` (índice) e `LegalDocumentScreen` (resumo visual + texto completo + histórico) | 2 |
| `apps/patient/lib/app/app.dart` | Link no login, item em "Mais", aceite no onboarding, botão de leitura do QR, `QrScannerScope` na raiz | 2, 3, 6 |
| `apps/patient/test/legal_screens_test.dart` (novo) | Navegação e renderização dos documentos | 2 |
| `backend/sinalacs_server/lib/src/models/enums/consent_purpose.spy.yaml` | `termsOfUse` | 3 |
| `backend/sinalacs_server/lib/src/application/onboarding/onboarding_service.dart` | Exigir aceite do termo | 3 |
| `backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart` | Parâmetro `termsAccepted` | 3 |
| `backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart` | Recusar `updateConsent(termsOfUse)` | 3 |
| `apps/patient/lib/core/network/backend_client.dart`, `lib/core/consent/consent_decisions.dart`, `test/support/fake_patient_backend.dart` | `termsAccepted` + rótulo da nova finalidade | 3 |
| `apps/acs/lib/core/network/backend_client.dart`, `test/support/fakes.dart`, `test/support/fake_rpc_server.dart` | `AcsBackend.generateInvite` | 4 |
| `apps/acs/lib/app/invite_screen.dart` (novo) | Tela "Convidar paciente" com QR | 5 |
| `apps/acs/lib/app/app.dart` | `AcsDestination.invite` + item em "Mais" | 5 |
| `apps/acs/test/invite_screen_test.dart` (novo) | Fluxo do convite | 5 |
| `apps/patient/lib/core/onboarding/enrollment_qr.dart` (novo) | Validação pura do conteúdo lido | 6 |
| `apps/patient/lib/app/qr_scanner.dart` (novo) | `QrScanner`, `QrScannerScope`, página da câmera (`mobile_scanner`) | 6 |
| `apps/patient/android/app/src/main/AndroidManifest.xml` | Permissão `CAMERA` | 6 |
| `PROGRESS.md`, `apps/CLAUDE.md`, `spec/lgpd_design.md`, `spec/PRD_system.md` | Registro do que foi feito e do que ficou de fora | 7 |

Ordem obrigatória: 1 → 2 → 3 (3 abre os documentos a partir do onboarding); 4 → 5; 6 depois de 3 (ambas editam `OnboardingScreen`). 4–5 são independentes de 1–3.

---

### Tarefa 1: Conteúdo versionado do Termo de Uso e da Política de Privacidade

**Files:**
- Create: `apps/patient/lib/core/legal/legal_documents.dart`
- Test: `apps/patient/test/legal_documents_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `const String legalDocumentsVersion = '2026.1';`
  - `class LegalSummaryStep { const LegalSummaryStep({required String title, required String text}); final String title; final String text; }`
  - `class LegalSection { const LegalSection({required String title, required String body}); final String title; final String body; }`
  - `class LegalVersion { const LegalVersion({required String version, required String date, required String changes}); ... }`
  - `class LegalDocument { const LegalDocument({required String id, required String title, required String version, required String effectiveDate, required List<LegalSummaryStep> summary, required List<LegalSection> sections, required List<LegalVersion> history}); ... }`
  - `const LegalDocument privacyPolicy` (id `'privacy'`) e `const LegalDocument termsOfUse` (id `'terms'`).

- [ ] **Step 1: Escrever o teste que falha**

Criar `apps/patient/test/legal_documents_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// Conteúdo mínimo que `spec/lgpd_design.md` exige de cada documento
/// (LGPD-RF18, linha 249; LGPD-RF19, linha 259). O teste procura o tópico no
/// título das seções, sem acento e em minúsculas, para não quebrar por uma
/// troca de redação que mantém o tópico.
String _norm(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

void expectTopics(LegalDocument document, List<String> topics) {
  final titles = document.sections.map((s) => _norm(s.title)).join(' | ');
  for (final topic in topics) {
    expect(titles, contains(topic), reason: '${document.title} sem seção sobre "$topic"');
  }
}

void main() {
  test('política de privacidade cobre o conteúdo mínimo do LGPD-RF19', () {
    expectTopics(privacyPolicy, [
      'quem cuida dos seus dados',
      'dados que coletamos',
      'para que usamos',
      'bases legais',
      'com quem compartilhamos',
      'por quanto tempo',
      'seus direitos',
      'como protegemos',
      'encarregado',
      'duvidas',
    ]);
  });

  test('termo de uso cobre o conteúdo mínimo do LGPD-RF18', () {
    expectTopics(termsOfUse, [
      'regras de uso',
      'responsabilidades',
      'o que nao e permitido',
      'propriedade intelectual',
      'limites de responsabilidade',
      'lei aplicavel',
      'alteracoes',
    ]);
  });

  test('os dois documentos têm resumo, versão vigente e histórico que a inclui', () {
    for (final document in [privacyPolicy, termsOfUse]) {
      expect(document.summary, isNotEmpty, reason: document.title);
      expect(document.version, legalDocumentsVersion, reason: document.title);
      expect(document.history.map((v) => v.version), contains(document.version),
          reason: '${document.title}: versão vigente fora do histórico');
      for (final section in document.sections) {
        expect(section.body.trim(), isNotEmpty, reason: '${document.title} › ${section.title}');
      }
    }
  });

  test('versão dos documentos é a mesma que o backend carimba em consent_logs', () {
    // Guarda de deriva: o aceite gravado no cadastro leva `consentPolicyVersion`
    // do backend; se o app mostrar outra versão, "Meus dados" passa a exibir um
    // aceite de um texto que a pessoa nunca viu. Monorepo: o CI do app faz
    // checkout do repositório inteiro, então o arquivo do servidor existe.
    final source = File(
      '../../backend/sinalacs_server/lib/src/application/onboarding/onboarding_service.dart',
    ).readAsStringSync();
    final match = RegExp(r"consentPolicyVersion = '([^']+)'").firstMatch(source);
    expect(match, isNotNull, reason: 'consentPolicyVersion não encontrado no backend');
    expect(legalDocumentsVersion, match!.group(1));
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/legal_documents_test.dart`
Expected: FAIL na compilação — `legal_documents.dart` não existe.

- [ ] **Step 3: Implementar o conteúdo**

Criar `apps/patient/lib/core/legal/legal_documents.dart`:

```dart
/// Termo de Uso e Política de Privacidade do app do paciente (LGPD-RF18,
/// LGPD-RF19 e LGPD-RF10 de `spec/lgpd_design.md`).
///
/// Conteúdo constante, no próprio app, de propósito: o documento precisa
/// abrir antes do cadastro (a pessoa lê antes de aceitar) e sem rede. A versão
/// é a mesma que o backend grava em `consent_logs.version`
/// (`consentPolicyVersion`), e `test/legal_documents_test.dart` falha se as
/// duas divergirem.
///
/// Trocar o texto exige versão nova: acrescente uma [LegalVersion] ao
/// histórico, mude [legalDocumentsVersion] **e** `consentPolicyVersion` no
/// backend. O texto de 2026.1 ainda precisa de revisão jurídica e dos dados
/// reais do controlador antes de produção (ver PROGRESS.md).
library;

const String legalDocumentsVersion = '2026.1';

/// Um passo do resumo visual (versão resumida do documento).
class LegalSummaryStep {
  const LegalSummaryStep({required this.title, required this.text});

  final String title;
  final String text;
}

/// Uma seção da versão completa.
class LegalSection {
  const LegalSection({required this.title, required this.body});

  final String title;
  final String body;
}

/// Uma entrada do histórico de versões (controle de versões consultável,
/// LGPD-RF18).
class LegalVersion {
  const LegalVersion({required this.version, required this.date, required this.changes});

  final String version;

  /// Data de vigência, já no formato de exibição (`dd/mm/aaaa`).
  final String date;
  final String changes;
}

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.summary,
    required this.sections,
    required this.history,
  });

  final String id;
  final String title;
  final String version;
  final String effectiveDate;
  final List<LegalSummaryStep> summary;
  final List<LegalSection> sections;
  final List<LegalVersion> history;
}

const _history2026_1 = [
  LegalVersion(
    version: '2026.1',
    date: '29/09/2026',
    changes: 'Primeira versão publicada no aplicativo.',
  ),
];

/// Política de Privacidade. O [LegalDocument.summary] é o resumo visual do
/// fluxo de dados pedido pelo LGPD-RF10: de onde o dado sai, por onde passa e
/// quem o vê, na ordem em que acontece.
const privacyPolicy = LegalDocument(
  id: 'privacy',
  title: 'Política de Privacidade',
  version: legalDocumentsVersion,
  effectiveDate: '29/09/2026',
  summary: [
    LegalSummaryStep(
      title: 'Você informa',
      text: 'Seu cadastro vem da sua UBS. No app, você responde a triagem, '
          'pode enviar um alerta de urgência e escolhe seus consentimentos.',
    ),
    LegalSummaryStep(
      title: 'O app protege',
      text: 'Tudo viaja criptografado. Suas condições de saúde, respostas de '
          'triagem e anotações de visita são guardadas cifradas no servidor.',
    ),
    LegalSummaryStep(
      title: 'A equipe da sua área vê',
      text: 'Só o agente comunitário de saúde da sua microárea e a equipe da '
          'sua UBS, para organizar as visitas pela prioridade.',
    ),
    LegalSummaryStep(
      title: 'Em emergência',
      text: 'Se o alerta for grave, o agente aciona o SAMU com o necessário '
          'para o atendimento.',
    ),
    LegalSummaryStep(
      title: 'Você decide',
      text: 'Em "Meus dados" você vê o que está guardado, copia seus dados, '
          'muda consentimentos e pede correção ou exclusão.',
    ),
  ],
  sections: [
    LegalSection(
      title: 'Quem cuida dos seus dados',
      body: 'O responsável pelos seus dados (controlador) é a Secretaria '
          'Municipal de Saúde do seu município, a quem pertence a UBS que '
          'acompanha você. O SinalACS é a ferramenta que a equipe de saúde usa '
          'para organizar as visitas.',
    ),
    LegalSection(
      title: 'Dados que coletamos',
      body: 'Cadastro: nome, data de nascimento, contato de emergência e se '
          'você tem condição crônica. O CPF é guardado só de forma embaralhada '
          '(hash), usada para conferir o seu acesso.\n'
          'Saúde: condições crônicas e respostas da triagem, guardadas '
          'cifradas, e a classificação de risco que resulta delas.\n'
          'Alerta de urgência: o horário e, se você permitir o GPS, uma área '
          'aproximada de onde você está — nunca o endereço exato.\n'
          'Consentimentos: cada escolha que você faz, com data e versão deste '
          'texto.\n'
          'Lembretes: ficam só no seu aparelho e não vão para o servidor.',
    ),
    LegalSection(
      title: 'Para que usamos',
      body: 'Para classificar o risco da sua triagem de forma igual para '
          'todos, avisar o agente de saúde quando você pede ajuda, organizar a '
          'fila de visitas da sua microárea e mostrar a você o andamento do seu '
          'pedido. Não usamos seus dados para propaganda nem os vendemos.',
    ),
    LegalSection(
      title: 'Bases legais',
      body: 'Dados de saúde são tratados com o seu consentimento específico e '
          'para a tutela da saúde (Lei 13.709/2018, art. 11). Os registros que '
          'a lei manda guardar, como os de visita, seguem a obrigação legal '
          '(art. 7º, II). Lembretes e avisos só acontecem se você consentir, e '
          'você pode mudar de ideia quando quiser.',
    ),
    LegalSection(
      title: 'Com quem compartilhamos',
      body: 'Com o agente comunitário de saúde da sua microárea e com a equipe '
          'da sua UBS. Em emergência, com o SAMU, só o necessário para o '
          'atendimento. Nenhum outro agente de saúde, de outra área, vê seus '
          'dados.',
    ),
    LegalSection(
      title: 'Por quanto tempo guardamos',
      body: 'Alertas: 2 anos. Visitas: 5 anos, como pede a legislação de '
          'saúde. Registros de acesso: 1 ano. Registros de consentimento: '
          'enquanto existir o cadastro, para provar as suas escolhas. Depois '
          'disso, os dados são apagados ou anonimizados.',
    ),
    LegalSection(
      title: 'Seus direitos',
      body: 'Você pode confirmar que tratamos seus dados, ver e copiar tudo o '
          'que está guardado, pedir correção, pedir exclusão, retirar os '
          'consentimentos que não são obrigatórios e saber com quem os dados '
          'foram compartilhados. Faça isso em "Meus dados". Os pedidos são '
          'respondidos em até 15 dias.',
    ),
    LegalSection(
      title: 'Como protegemos',
      body: 'Conexão criptografada entre o app e o servidor, dados de saúde '
          'cifrados no banco, acesso limitado à equipe da sua microárea e '
          'registro de cada acesso aos seus dados.',
    ),
    LegalSection(
      title: 'Encarregado de dados',
      body: 'O encarregado pelo tratamento de dados (DPO) é o da Secretaria '
          'Municipal de Saúde do seu município. Você pode chegar até ele pela '
          'sua UBS.',
    ),
    LegalSection(
      title: 'Dúvidas sobre seus dados',
      body: 'Fale com o seu agente comunitário de saúde ou com a sua UBS: eles '
          'encaminham a sua pergunta ao encarregado. Pedidos de correção e de '
          'exclusão podem ser feitos direto em "Meus dados".',
    ),
    LegalSection(
      title: 'Mudanças nesta política',
      body: 'Quando este texto mudar, o app mostra a nova versão com pelo '
          'menos 15 dias de antecedência e explica o que mudou. As versões '
          'anteriores ficam no histórico abaixo.',
    ),
  ],
  history: _history2026_1,
);

/// Termo de Uso, em linguagem simples (acessível para pessoas idosas e com
/// pouca leitura, LGPD-RF18).
const termsOfUse = LegalDocument(
  id: 'terms',
  title: 'Termo de Uso',
  version: legalDocumentsVersion,
  effectiveDate: '29/09/2026',
  summary: [
    LegalSummaryStep(
      title: 'Para quem é',
      text: 'Para pacientes acompanhados por um agente comunitário de saúde, '
          'com cadastro na UBS.',
    ),
    LegalSummaryStep(
      title: 'Em risco de vida, ligue 192',
      text: 'O botão de urgência avisa o seu agente de saúde. Se a vida estiver '
          'em risco, ligue também para o SAMU.',
    ),
    LegalSummaryStep(
      title: 'Use com verdade',
      text: 'Responda a triagem com sinceridade e use o alerta só quando '
          'precisar de ajuda.',
    ),
    LegalSummaryStep(
      title: 'O app ajuda, não substitui',
      text: 'A triagem organiza a prioridade das visitas. Ela não é consulta '
          'nem diagnóstico.',
    ),
  ],
  sections: [
    LegalSection(
      title: 'Regras de uso',
      body: 'O app é para você acompanhar sua saúde com a equipe da sua UBS: '
          'responder a triagem, pedir ajuda em urgência, ver o andamento do seu '
          'pedido e cuidar dos seus dados. O acesso é pessoal: entre só com o '
          'seu CPF ou com o convite que o seu agente de saúde mostrou a você.',
    ),
    LegalSection(
      title: 'Responsabilidades',
      body: 'A equipe de saúde organiza as visitas pela classificação de risco. '
          'Você se compromete a informar dados verdadeiros e a manter seu '
          'celular protegido. A classificação da triagem não é diagnóstico e '
          'não substitui uma consulta.',
    ),
    LegalSection(
      title: 'O que não é permitido',
      body: 'Enviar alertas falsos, usar o acesso de outra pessoa, tentar ver '
          'dados de outras pessoas ou atrapalhar o funcionamento do app.',
    ),
    LegalSection(
      title: 'Propriedade intelectual',
      body: 'O app, sua marca e seu código pertencem aos seus desenvolvedores e '
          'ao poder público que o adotou. O uso é gratuito e não transfere '
          'nenhum desses direitos.',
    ),
    LegalSection(
      title: 'Limites de responsabilidade',
      body: 'O app depende de internet e do seu aparelho para funcionar. Ele '
          'não garante tempo de atendimento. Em risco de vida, ligue 192 (SAMU) '
          'sem esperar resposta pelo app.',
    ),
    LegalSection(
      title: 'Lei aplicável',
      body: 'Vale a lei brasileira, incluindo a Lei Geral de Proteção de Dados '
          '(Lei 13.709/2018). Questões judiciais são tratadas no foro do seu '
          'município.',
    ),
    LegalSection(
      title: 'Alterações neste termo',
      body: 'Quando este termo mudar, o app mostra a nova versão com pelo menos '
          '15 dias de antecedência e pede o seu aceite de novo. As versões '
          'anteriores ficam no histórico abaixo.',
    ),
  ],
  history: _history2026_1,
);
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd apps/patient && flutter test test/legal_documents_test.dart`
Expected: PASS, 4/4.

- [ ] **Step 5: Analisar e commitar**

Run: `cd apps/patient && flutter analyze`
Expected: `No issues found!`

```bash
git add apps/patient/lib/core/legal/legal_documents.dart apps/patient/test/legal_documents_test.dart
git commit -m "feat(paciente): conteúdo versionado do Termo de Uso e da Política de Privacidade (LGPD-RF18/RF19)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 2: Telas dos documentos legais e pontos de entrada

**Files:**
- Create: `apps/patient/lib/app/legal_screens.dart`
- Modify: `apps/patient/lib/app/app.dart` (tela de login, ~linha 462; `_showMoreDestinations`, ~linha 2616)
- Test: `apps/patient/test/legal_screens_test.dart`

**Interfaces:**
- Consumes: `privacyPolicy`, `termsOfUse`, `LegalDocument` (Tarefa 1).
- Produces:
  - `class LegalDocumentsScreen extends StatelessWidget { const LegalDocumentsScreen({super.key}); }` — tiles com keys `legal_open_privacy` e `legal_open_terms`.
  - `class LegalDocumentScreen extends StatelessWidget { const LegalDocumentScreen({super.key, required LegalDocument document}); }` — keys `legal_version`, `legal_summary`, `legal_section_<índice>`, `legal_history`.
  - Key `login_legal_link` (tela de login) e `more_legal` (menu "Mais").

- [ ] **Step 1: Escrever os testes que falham**

Criar `apps/patient/test/legal_screens_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/app/legal_screens.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

import 'support/fake_patient_backend.dart';
import 'support/semantics_scan.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('antes de entrar, a tela de login abre a política e o termo', (tester) async {
    // Ler antes de aceitar: os documentos têm de abrir sem sessão.
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
    await tapKey(tester, 'login_legal_link');

    expect(find.byType(LegalDocumentsScreen), findsOneWidget);
    await tapKey(tester, 'legal_open_privacy');
    expect(find.text('Política de Privacidade'), findsWidgets);
    expect(find.textContaining('Versão $legalDocumentsVersion'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'legal_open_terms');
    expect(find.text('Termo de Uso'), findsWidgets);
  });

  testWidgets('documento mostra resumo, texto completo expansível e histórico de versões', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LegalDocumentScreen(document: privacyPolicy)));

    expect(find.byKey(const Key('legal_summary')), findsOneWidget);
    for (final step in privacyPolicy.summary) {
      expect(find.text(step.title), findsOneWidget);
    }
    // Versão completa recolhida por padrão: o corpo só aparece ao expandir.
    final first = privacyPolicy.sections.first;
    expect(find.text(first.body), findsNothing);
    await tapKey(tester, 'legal_section_0');
    expect(find.text(first.body), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('legal_history')));
    expect(find.textContaining('2026.1 · vigente desde 29/09/2026'), findsOneWidget);
  });

  testWidgets('documento não tem botão inerte para leitor de tela', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: LegalDocumentScreen(document: termsOfUse)));
    expectNenhumBotaoInerte(tester);
    handle.dispose();
  });
}
```

E, em `apps/patient/test/patient_app_mvp_test.dart`, acrescentar ao final de `main()` (antes da última `}`) um teste do menu "Mais", com o helper `login(tester)` que o arquivo já tem (linha ~161, o mesmo que os testes de "Meus dados" usam):

```dart
  testWidgets('menu Mais abre Privacidade e termos', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
    await login(tester);
    await tester.tap(find.text('Mais'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more_legal')));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentsScreen), findsOneWidget);
  });
```

Adicione `import 'package:sinalacs_patient/app/legal_screens.dart';` no topo.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/legal_screens_test.dart test/patient_app_mvp_test.dart`
Expected: FAIL na compilação — `legal_screens.dart` não existe.

- [ ] **Step 3: Implementar as telas**

Criar `apps/patient/lib/app/legal_screens.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:sinalacs_patient/app/patient_theme.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// Índice "Privacidade e termos": abre a partir do login (antes do cadastro,
/// para ler antes de aceitar) e do menu "Mais" — Mais → Privacidade e termos →
/// documento, três toques (painel de privacidade em até 3 cliques,
/// LGPD-RF03).
class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidade e termos')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (key, document) in const [
              ('legal_open_privacy', privacyPolicy),
              ('legal_open_terms', termsOfUse),
            ])
              Card(
                child: ListTile(
                  key: Key(key),
                  leading: Icon(
                    document.id == 'privacy' ? Icons.privacy_tip_outlined : Icons.description_outlined,
                  ),
                  title: Text(document.title),
                  subtitle: Text('Versão ${document.version} · vigente desde ${document.effectiveDate}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LegalDocumentScreen(document: document)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Um documento legal: primeiro o resumo visual (passos numerados, na ordem
/// em que o dado circula — LGPD-RF10), depois a versão completa em seções
/// expansíveis e, por fim, o histórico de versões (LGPD-RF18/RF19).
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Versão ${document.version} · vigente desde ${document.effectiveDate}',
              key: const Key('legal_version'),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text('Resumo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Column(
              key: const Key('legal_summary'),
              children: [
                for (final (index, step) in document.summary.indexed)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: PatientColors.accent,
                        foregroundColor: Colors.white,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(step.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(step.text),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Texto completo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final (index, section) in document.sections.indexed)
              ExpansionTile(
                key: Key('legal_section_$index'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                expandedAlignment: Alignment.centerLeft,
                title: Text(section.title),
                children: [Text(section.body)],
              ),
            const SizedBox(height: 16),
            const Text('Histórico de versões', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Column(
              key: const Key('legal_history'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in document.history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${entry.version} · ${entry.version == document.version ? 'vigente desde' : 'de'} ${entry.date}',
                    ),
                    subtitle: Text(entry.changes),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

Confirme que `PatientColors.accent` existe em `apps/patient/lib/app/patient_theme.dart` (texto branco sobre o *preenchimento* accent é o uso previsto por `test/contrast_tokens_test.dart`). Se o nome do token de preenchimento for outro, use o equivalente e registre a troca.

- [ ] **Step 4: Ligar os pontos de entrada em `app.dart`**

Adicionar o import junto aos outros `package:sinalacs_patient/app/...`:

```dart
import 'package:sinalacs_patient/app/legal_screens.dart';
```

Na tela de login, dentro do bloco `if (_step == _LoginStep.credenciais) ...[` (~linha 461), logo **depois** do `SizedBox` que envolve o `OutlinedButton.icon` de `start_onboarding_button`, acrescentar:

```dart
                          const SizedBox(height: 4),
                          TextButton(
                            key: const Key('login_legal_link'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LegalDocumentsScreen()),
                            ),
                            child: const Text('Política de Privacidade e Termo de Uso'),
                          ),
```

Em `_showMoreDestinations` (~linha 2616, uma linha só), acrescentar ao fim da lista `children`, depois do `ListTile` de "Meus dados", sem reformatar a linha:

```dart
, ListTile(key: const Key('more_legal'), leading: const Icon(Icons.gavel_outlined), title: const Text('Privacidade e termos'), onTap: () { Navigator.pop(sheetContext); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalDocumentsScreen())); })
```

- [ ] **Step 5: Rodar e ver passar**

Run: `cd apps/patient && flutter test test/legal_screens_test.dart test/patient_app_mvp_test.dart`
Expected: PASS (3 novos + o do menu "Mais", e os existentes do MVP).

- [ ] **Step 6: Suíte e commit**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: `No issues found!` e todos os testes passando (145 anteriores + 5 da Tarefa 1–2 = 150, ajuste se a contagem inicial diferir).

```bash
git add apps/patient/lib/app/legal_screens.dart apps/patient/lib/app/app.dart apps/patient/test/legal_screens_test.dart apps/patient/test/patient_app_mvp_test.dart
git commit -m "feat(paciente): telas de Privacidade e termos com resumo visual e histórico (LGPD-RF10/RF18/RF19)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 3: Aceite versionado do Termo de Uso no cadastro

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/enums/consent_purpose.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/application/onboarding/onboarding_service.dart:83,138-146`
- Modify: `backend/sinalacs_server/lib/src/endpoints/onboarding_endpoint.dart:38-62`
- Modify: `backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart:63-74`
- Test: `backend/sinalacs_server/test/unit/onboarding_service_test.dart`, `test/unit/data_subject_rights_service_test.dart`, `test/integration/onboarding_endpoint_test.dart`
- Modify: `apps/patient/lib/core/network/backend_client.dart` (interface ~linha 103, `MisconfiguredBackend` ~212, `BackendClient` ~456)
- Modify: `apps/patient/lib/core/consent/consent_decisions.dart:27-31`
- Modify: `apps/patient/lib/app/app.dart` (`OnboardingScreen` ~linhas 596–808; `_purposeDescription` ~1720)
- Modify: `apps/patient/test/support/fake_patient_backend.dart:249-260`
- Test: `apps/patient/test/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: `LegalDocumentScreen`, `privacyPolicy`, `termsOfUse`, `legalDocumentsVersion` (Tarefas 1–2).
- Produces:
  - `ConsentPurpose.termsOfUse` (enum gerado, cliente e servidor).
  - `onboarding.completeEnrollment(..., required bool termsAccepted)`.
  - `PatientBackend.completeEnrollment({required String token, required bool healthDataConsent, required bool remindersConsent, required bool pushConsent, required bool termsAccepted})`.
  - Keys no onboarding: `onboarding_terms_accept`, `onboarding_open_terms`, `onboarding_open_privacy`.
  - Mensagem de recusa: `'É preciso aceitar o Termo de Uso e a Política de Privacidade.'` (servidor e app, idêntica).

- [ ] **Step 1: Testes unitários do backend que falham**

Em `backend/sinalacs_server/test/unit/onboarding_service_test.dart`, grupo `completeEnrollment`:

1. No teste `'consome o token, grava 3 consent_logs e emite sessão'`: renomear para `'consome o token, grava 4 consent_logs e emite sessão'`, acrescentar `ConsentPurpose.termsOfUse: true,` ao mapa `consents`, trocar `hasLength(3)` por `hasLength(4)` e acrescentar `expect(byPurpose[ConsentPurpose.termsOfUse], 'granted');`. Atualizar o comentário "um Set de 3 ações" para "4".
2. Nos testes `'um segundo uso do mesmo token falha…'` e `'token expirado falha'`: cada mapa `const {ConsentPurpose.healthDataProcessing: true}` vira `const {ConsentPurpose.healthDataProcessing: true, ConsentPurpose.termsOfUse: true}`.
3. Acrescentar ao grupo:

```dart
    test('recusa concluir sem aceitar o Termo de Uso, e o convite continua válido', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');

      await expectLater(
        () => service.completeEnrollment(
          token: generated.token,
          consents: const {
            ConsentPurpose.healthDataProcessing: true,
            ConsentPurpose.termsOfUse: false,
          },
        ),
        throwsA(isA<EnrollmentException>().having(
          (e) => e.message,
          'message',
          'É preciso aceitar o Termo de Uso e a Política de Privacidade.',
        )),
      );
      expect(store.consentLogs, isEmpty);

      // Mesma regra do consentimento obrigatório de saúde: a recusa não
      // consome o convite, a pessoa pode aceitar e tentar de novo.
      final user = await service.completeEnrollment(
        token: generated.token,
        consents: const {
          ConsentPurpose.healthDataProcessing: true,
          ConsentPurpose.termsOfUse: true,
        },
      );
      expect(user.id, 'patient-1');
    });

    test('o aceite do termo leva a versão vigente dos documentos', () async {
      final generated = await service.generateToken(acs, patientId: 'patient-1');
      await service.completeEnrollment(
        token: generated.token,
        consents: const {
          ConsentPurpose.healthDataProcessing: true,
          ConsentPurpose.termsOfUse: true,
        },
      );
      final terms = store.consentLogs.singleWhere((e) => e.purpose == ConsentPurpose.termsOfUse);
      expect(terms.action, 'granted');
      expect(terms.version, consentPolicyVersion);
    });
```

Em `backend/sinalacs_server/test/unit/data_subject_rights_service_test.dart`, ao lado do teste que já recusa `healthDataProcessing` em `updateConsent` (procure `ConsentPurpose.healthDataProcessing` no arquivo e copie a montagem de `service`/usuário dele), acrescentar:

```dart
    test('recusa mexer no aceite do Termo de Uso pelo painel', () async {
      await expectLater(
        service.updateConsent(patient, purpose: ConsentPurpose.termsOfUse, granted: false),
        throwsA(isA<DataRightsException>()),
      );
      expect(store.consentLogs, isEmpty);
    });
```

(Use os nomes de variáveis que o teste vizinho usa para o serviço, o paciente e a store — `service`, `patient`, `store` acima são os esperados; ajuste se diferirem.)

- [ ] **Step 2: Enum + serviço + endpoint**

`backend/sinalacs_server/lib/src/models/enums/consent_purpose.spy.yaml` — acrescentar o valor e atualizar o comentário:

```yaml
### As finalidades de consentimento do onboarding (decisão §2.2 de
### docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md).
### `healthDataProcessing` e `termsOfUse` são obrigatórias para usar o app;
### as outras duas podem ser recusadas sem impedir o restante do fluxo.
### `termsOfUse` registra o aceite do Termo de Uso e da Política de
### Privacidade na versão `consentPolicyVersion` (LGPD-RF18/RF19) — não é
### consentimento revogável pelo painel, é a condição de uso do app.
enum: ConsentPurpose
serialized: byName
values:
  - healthDataProcessing
  - localReminders
  - segmentedPush
  - termsOfUse
```

`onboarding_service.dart` — atualizar o doc de `consentPolicyVersion`:

```dart
/// Versão do texto de política vigente. Mesmo padrão que
/// `spec/lgpd_design.md` define para a política de privacidade — trocar
/// exige nova versão publicada, não incrementar este literal sem mudança de
/// texto real. É também a versão do Termo de Uso e da Política de Privacidade
/// que o app paciente exibe (`legalDocumentsVersion` em
/// `apps/patient/lib/core/legal/legal_documents.dart`); o teste
/// `apps/patient/test/legal_documents_test.dart` falha se as duas divergirem.
const String consentPolicyVersion = '2026.1';
```

Em `completeEnrollment`, logo depois do `if (mandatory != true) { ... }`:

```dart
    // O aceite do Termo de Uso e da Política de Privacidade é a outra
    // condição de uso (LGPD-RF18: "aceite explícito no cadastro"). Checado
    // antes de consumir o convite, pelo mesmo motivo do consentimento de
    // saúde: a recusa não pode queimar o QR.
    if (consents[ConsentPurpose.termsOfUse] != true) {
      throw EnrollmentException(
        message: 'É preciso aceitar o Termo de Uso e a Política de Privacidade.',
      );
    }
```

Atualizar o doc do método: "grava as 3 finalidades" → "grava as 4 finalidades".

`onboarding_endpoint.dart` — acrescentar o parâmetro e o mapeamento:

```dart
  Future<EnrollmentResult> completeEnrollment(
    Session session, {
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
    required bool termsAccepted,
  }) async {
```

e, no mapa `consents:`, `ConsentPurpose.termsOfUse: termsAccepted,`. Trocar o comentário "gravar os 3 `consent_logs`" por "gravar os 4 `consent_logs`".

`data_subject_rights_service.dart` — em `updateConsent`, depois do `if` de `healthDataProcessing`:

```dart
    if (purpose == ConsentPurpose.termsOfUse) {
      throw DataRightsException(
        message: 'O aceite do Termo de Uso é feito no cadastro e não é alterado aqui. '
            'Para deixar de usar o app, solicite a exclusão dos seus dados.',
      );
    }
```

- [ ] **Step 3: Gerar código e migração**

Run:
```bash
cd backend/sinalacs_server && export PATH=$PATH:~/.pub-cache/bin && serverpod generate && serverpod create-migration
```
Expected: `generate` conclui; `create-migration` diz que não há mudança de banco (a coluna `consent_logs.purpose` é `String`). Se ele criar uma migração mesmo assim, inspecione o `migration.sql`: aceitável apenas se estiver vazio de DDL; qualquer `ALTER`/`DROP` é sinal de erro — pare e investigue.

- [ ] **Step 4: Atualizar os testes de integração**

Em `backend/sinalacs_server/test/integration/onboarding_endpoint_test.dart`, acrescentar `termsAccepted: true,` depois de cada uma das 5 linhas `pushConsent: …,`:

```bash
cd backend/sinalacs_server && sed -i -E 's/^(\s*)pushConsent: (true|false),$/&\n\1termsAccepted: true,/' test/integration/onboarding_endpoint_test.dart && grep -c "termsAccepted: true," test/integration/onboarding_endpoint_test.dart
```
Expected: `5`.

Depois, à mão:
- teste `'completeEnrollment com token válido grava 3 consent_logs…'`: renomear para "4", `hasLength(3)` → `hasLength(4)`, acrescentar `expect(byPurpose['termsOfUse'], 'granted');`;
- teste da corrida: `hasLength(3)` → `hasLength(4)` e o comentário "3 linhas, não 6" → "4 linhas, não 8";
- acrescentar, depois do teste `'recusa do consentimento obrigatório…'`, copiando o `_seed`/login dele:

```dart
    test('recusa do Termo de Uso falha, não grava nada e não consome o convite', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final generated = await endpoints.onboarding.generateEnrollmentToken(
        sessionBuilder,
        accessToken: login.accessToken,
        patientId: _patientId,
      );

      await expectLater(
        endpoints.onboarding.completeEnrollment(
          sessionBuilder,
          token: generated.token,
          healthDataConsent: true,
          remindersConsent: true,
          pushConsent: true,
          termsAccepted: false,
        ),
        throwsA(isA<EnrollmentException>()),
      );
      final rows = await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      );
      expect(rows, isEmpty);

      // O mesmo convite ainda serve: a recusa foi antes do consumo.
      final result = await endpoints.onboarding.completeEnrollment(
        sessionBuilder,
        token: generated.token,
        healthDataConsent: true,
        remindersConsent: true,
        pushConsent: true,
        termsAccepted: true,
      );
      expect(result.accessToken, isNotEmpty);
    });
```

- [ ] **Step 5: Rodar o backend**

Run:
```bash
docker compose --profile test up -d postgres-test
cd backend && dart analyze
cd sinalacs_server && dart test test/unit/onboarding_service_test.dart test/unit/data_subject_rights_service_test.dart test/integration/onboarding_endpoint_test.dart
```
Expected: analyze sem novos avisos; os três arquivos passam, incluindo os 4 testes novos.

- [ ] **Step 6: Commit do backend**

```bash
git add backend/
git commit -m "feat(backend): aceite versionado do Termo de Uso no onboarding (LGPD-RF18)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(O app paciente não compila entre este commit e o próximo — o switch de `ConsentPurpose` deixou de ser exaustivo e `completeEnrollment` ganhou um parâmetro obrigatório. É o próximo passo desta mesma tarefa.)

- [ ] **Step 7: Testes do app que falham**

Em `apps/patient/test/onboarding_flow_test.dart`:

1. Nos quatro testes que concluem o cadastro com sucesso ou chegam ao backend (`'marcar o obrigatório e concluir…'`, `'falha do backend mostra a mensagem…'`, `'…lembretes marcado grava…'`, `'…lembretes desmarcado grava…'`), acrescentar `await tapKey(tester, 'onboarding_terms_accept');` logo depois de `await tapKey(tester, 'onboarding_consent_health');`.
2. No mapa esperado de `'marcar o obrigatório e concluir…'`, acrescentar `'termsAccepted': true,`.
3. No primeiro teste (`'deve abrir com campo de token e os 3 consentimentos desmarcados'`), acrescentar:

```dart
    final termsAccept = tester.widget<CheckboxListTile>(
      find.byKey(const Key('onboarding_terms_accept')),
    );
    expect(termsAccept.value, isFalse);
```

4. Acrescentar ao final de `main()`:

```dart
  testWidgets('sem aceitar o termo, concluir mostra o motivo e não chama o backend', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'complete_enrollment_button');

    expect(find.text('É preciso aceitar o Termo de Uso e a Política de Privacidade.'), findsOneWidget);
    expect(backend.enrollmentCalls, isEmpty);
  });

  testWidgets('o onboarding abre o termo e a política antes do aceite', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
    await openOnboarding(tester);

    await tapKey(tester, 'onboarding_open_terms');
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.text('Termo de Uso'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapKey(tester, 'onboarding_open_privacy');
    expect(find.text('Política de Privacidade'), findsWidgets);
  });
```

com `import 'package:sinalacs_patient/app/legal_screens.dart';` no topo.

- [ ] **Step 8: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/onboarding_flow_test.dart`
Expected: FAIL na compilação (`termsOfUse` não tratado no `switch`, `termsAccepted` ausente) — é o estado deixado pelo Step 6.

- [ ] **Step 9: Camada de rede e rótulos do app**

`apps/patient/lib/core/network/backend_client.dart` — nas três ocorrências de `completeEnrollment` (interface, `MisconfiguredBackend`, `BackendClient`), acrescentar `required bool termsAccepted,` depois de `required bool pushConsent,`; na interface, trocar o doc "gravando os 3 consentimentos" por "gravando os 4 registros de consentimento (incluindo o aceite do Termo de Uso)"; no `BackendClient`, passar `termsAccepted: termsAccepted,` para `_client.onboarding.completeEnrollment`.

`apps/patient/test/support/fake_patient_backend.dart` — em `completeEnrollment`, acrescentar o parâmetro `required bool termsAccepted,` e a entrada `'termsAccepted': termsAccepted,` no mapa registrado.

`apps/patient/lib/core/consent/consent_decisions.dart` — no `switch` de `consentPurposeLabel`:

```dart
      ConsentPurpose.termsOfUse => 'Termo de Uso e Política de Privacidade',
```

`apps/patient/lib/app/app.dart` — em `_purposeDescription` (~linha 1720), acrescentar o braço (não é exibido como switch, mas o `switch` precisa ser exaustivo):

```dart
        ConsentPurpose.termsOfUse => 'Aceito no cadastro.',
```

- [ ] **Step 10: Aceite na tela de onboarding**

Em `OnboardingScreen` (`app.dart`):

1. Estado, junto dos outros consentimentos:

```dart
  // Aceite do Termo de Uso e da Política de Privacidade (LGPD-RF18): também
  // desmarcado por padrão e obrigatório, gravado pelo servidor com a versão
  // vigente dos documentos.
  bool _termsAccepted = false;
```

2. Em `_complete()`, logo depois do bloco que recusa `!_healthDataConsent`:

```dart
    if (!_termsAccepted) {
      setState(() {
        _error = 'É preciso aceitar o Termo de Uso e a Política de Privacidade.';
      });
      return;
    }
```

3. Na chamada `completeEnrollment(...)`, acrescentar `termsAccepted: _termsAccepted,`.

4. No `build`, depois do `CheckboxListTile` de `onboarding_consent_push` e antes do `SizedBox(height: 20)` que precede o botão:

```dart
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Termo de Uso e Privacidade', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              key: const Key('onboarding_open_terms'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const LegalDocumentScreen(document: termsOfUse)),
                              ),
                              child: const Text('Ler o Termo de Uso'),
                            ),
                            TextButton(
                              key: const Key('onboarding_open_privacy'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const LegalDocumentScreen(document: privacyPolicy)),
                              ),
                              child: const Text('Ler a Política de Privacidade'),
                            ),
                          ],
                        ),
                        CheckboxListTile(
                          key: const Key('onboarding_terms_accept'),
                          value: _termsAccepted,
                          onChanged: (value) => setState(() => _termsAccepted = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'Li e aceito o Termo de Uso e a Política de Privacidade '
                            '(versão $legalDocumentsVersion) (obrigatório)',
                          ),
                        ),
```

5. Imports em `app.dart`: `import 'package:sinalacs_patient/core/legal/legal_documents.dart';` (o de `legal_screens.dart` já entrou na Tarefa 2).

- [ ] **Step 11: Rodar e ver passar**

Run: `cd apps/patient && flutter test test/onboarding_flow_test.dart test/consent_decisions_test.dart`
Expected: PASS, incluindo os 2 testes novos.

- [ ] **Step 12: Suíte do app e commit**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: `No issues found!` e suíte verde.

Run também `cd apps/acs && flutter analyze` — o ACS consome o mesmo `sinalacs_client`; um `switch` exaustivo sobre `ConsentPurpose` ali quebraria. Expected: `No issues found!`.

```bash
git add apps/patient/
git commit -m "feat(paciente): aceite explícito do Termo de Uso e da Política no cadastro (LGPD-RF18)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 4: `generateInvite` na camada de rede do ACS

**Files:**
- Modify: `apps/acs/lib/core/network/backend_client.dart` (interface ~linha 52; `MisconfiguredBackend` ~102; `BackendClient` ~329)
- Modify: `apps/acs/test/support/fakes.dart` (`FakeAcsBackend`)
- Modify: `apps/acs/test/support/fake_rpc_server.dart` (switch de `payload`)
- Test: `apps/acs/test/backend_client_test.dart`

**Interfaces:**
- Consumes: RPC existente `onboarding.generateEnrollmentToken(accessToken, patientId) → EnrollmentTokenResult {token, expiresAt}`.
- Produces:
  - `Future<EnrollmentTokenResult> AcsBackend.generateInvite({required String patientId})`.
  - `FakeAcsBackend.inviteCalls` (`List<String>`, patientIds na ordem), `FakeAcsBackend.inviteFailure` (`BackendFailure?`); tokens sintéticos `'convite-sintetico-<n>'` (n começa em 1), `expiresAt` = `DateTime.utc(2026, 9, 29, 10, 15)`.

- [ ] **Step 1: Teste que falha**

Em `apps/acs/test/backend_client_test.dart`, acrescentar ao final de `main()`:

```dart
  test('generateInvite pede o convite do paciente com o token da sessão', () async {
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');

    final invite = await backend.generateInvite(
      patientId: '00000000-0000-4000-8000-000000000005',
    );

    expect(invite.token, 'convite-sintetico');
    expect(invite.expiresAt, DateTime.utc(2026, 9, 29, 10, 15));
    final request = server.requests.last;
    expect(request.endpoint, 'onboarding');
    expect(request.method, 'generateEnrollmentToken');
    expect(request.args['patientId'], '00000000-0000-4000-8000-000000000005');
    expect(request.args['accessToken'], isNotEmpty);
  });

  test('generateInvite recusado por território vira mensagem de paciente fora da microárea', () async {
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    server.rejectInviteWithPermission = true;

    await expectLater(
      backend.generateInvite(patientId: '00000000-0000-4000-8000-000000000009'),
      throwsA(
        isA<BackendFailure>()
            .having((f) => f.message, 'message', 'Este paciente não pertence à sua microárea.')
            .having((f) => f.isRecoverable, 'isRecoverable', isFalse),
      ),
    );
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/backend_client_test.dart`
Expected: FAIL na compilação — `generateInvite` e `rejectInviteWithPermission` não existem.

- [ ] **Step 3: Servidor de teste**

Em `apps/acs/test/support/fake_rpc_server.dart`:

1. Campo, junto de `rejectWith`:

```dart
  /// Faz `generateEnrollmentToken` recusar como o backend recusa paciente de
  /// outra microárea (`AlertPermissionException`, INV-01).
  bool rejectInviteWithPermission = false;
```

2. Em `_handle`, depois do `if` de `loginInstitutional`/`rejectWith`:

```dart
    if (method == 'generateEnrollmentToken' && rejectInviteWithPermission) {
      await _respond(request, HttpStatus.badRequest, {
        'className': 'AlertPermissionException',
        'data': {'message': 'Paciente fora da microárea do ACS.'},
      });
      return;
    }
```

3. No `switch` de `payload`, antes de `_ => null`:

```dart
      // Corpo de `onboarding.generateEnrollmentToken`. Token sintético: o real
      // tem 43 caracteres base64url, mas o cliente não valida o formato.
      'generateEnrollmentToken' => <String, Object?>{
          'token': 'convite-sintetico',
          'expiresAt': '2026-09-29T10:15:00.000Z',
        },
```

- [ ] **Step 4: Interface e implementações**

Em `apps/acs/lib/core/network/backend_client.dart`, garantir `EnrollmentTokenResult` importado de `package:sinalacs_client/sinalacs_client.dart` (acrescente ao `show`/import existente do arquivo).

Na interface `AcsBackend`, depois de `listPatients()`:

```dart
  /// Convite de onboarding de um paciente da própria microárea (RF02). O
  /// token em claro volta só nesta resposta e vira o QR Code da tela
  /// "Convidar paciente" — nunca é gravado no aparelho.
  Future<EnrollmentTokenResult> generateInvite({required String patientId});
```

Em `MisconfiguredBackend`:

```dart
  @override
  Future<EnrollmentTokenResult> generateInvite({required String patientId}) async => _recusar();
```

Em `BackendClient`, depois de `listPatients()`:

```dart
  @override
  Future<EnrollmentTokenResult> generateInvite({required String patientId}) async {
    final token = await _requireToken();
    return _guard(
      () => _client.onboarding.generateEnrollmentToken(
        accessToken: token,
        patientId: patientId,
      ),
      // O servidor recusa com `AlertPermissionException` quando o paciente
      // não é da microárea do ACS (INV-01) — "este alerta" não faria sentido.
      permissionMessage: 'Este paciente não pertence à sua microárea.',
    );
  }
```

- [ ] **Step 5: Duplo do backend**

Em `apps/acs/test/support/fakes.dart`, dentro de `FakeAcsBackend` (importe `EnrollmentTokenResult` de `package:sinalacs_client/sinalacs_client.dart` junto dos tipos já importados):

```dart
  /// patientIds pedidos em `generateInvite`, na ordem.
  final List<String> inviteCalls = <String>[];

  /// Falha da geração do convite, como paciente fora da microárea.
  BackendFailure? inviteFailure;

  @override
  Future<EnrollmentTokenResult> generateInvite({required String patientId}) async {
    inviteCalls.add(patientId);
    final failure = inviteFailure;
    if (failure != null) throw failure;
    return EnrollmentTokenResult(
      token: 'convite-sintetico-${inviteCalls.length}',
      expiresAt: DateTime.utc(2026, 9, 29, 10, 15),
    );
  }
```

- [ ] **Step 6: Rodar e ver passar**

Run: `cd apps/acs && flutter test test/backend_client_test.dart`
Expected: PASS, incluindo os 2 novos.

- [ ] **Step 7: Suíte e commit**

Run: `cd apps/acs && flutter analyze && flutter test`
Expected: `No issues found!`; 160 testes (158 + 2).

```bash
git add apps/acs/lib/core/network/backend_client.dart apps/acs/test/support/fakes.dart apps/acs/test/support/fake_rpc_server.dart apps/acs/test/backend_client_test.dart
git commit -m "feat(acs): generateInvite na camada de rede, sobre onboarding.generateEnrollmentToken (RF02)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 5: Tela "Convidar paciente" com QR Code no app do ACS

**Files:**
- Modify: `apps/acs/pubspec.yaml`, `apps/acs/pubspec.lock` (via `flutter pub add`)
- Create: `apps/acs/lib/app/invite_screen.dart`
- Modify: `apps/acs/lib/app/app.dart` (enum `AcsDestination` linha 255; switch de conteúdo ~linha 761; `_more` ~linha 769)
- Test: `apps/acs/test/invite_screen_test.dart`

**Interfaces:**
- Consumes: `AcsBackend.generateInvite`, `FakeAcsBackend.inviteCalls/inviteFailure/patients/listPatientsFailure` (Tarefa 4 e existentes); `entrar(tester)` de `test/login_flow_test.dart` (copiado abaixo, porque não é importável).
- Produces: `class InviteScreen extends StatefulWidget { const InviteScreen({super.key}); }`; `AcsDestination.invite`; keys `invite_patient_<patientId>`, `generate_invite_button`, `invite_qr`, `invite_expires_at`, `invite_token_text`, `invite_error`, `invite_retry`, `invite_no_patients`.

- [ ] **Step 1: Dependência**

Run: `cd apps/acs && flutter pub add 'qr_flutter:^4.1.0'`
Expected: `pubspec.yaml` ganha `qr_flutter: ^4.1.0`; `pubspec.lock` atualizado.

- [ ] **Step 2: Testes que falham**

Criar `apps/acs/test/invite_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';
import 'support/semantics_scan.dart';

/// Mesmo caminho de `entrar` em `login_flow_test.dart` (não importável entre
/// arquivos de teste). Credenciais sintéticas.
Future<void> entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
  await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
}

Future<void> abrirConvite(WidgetTester tester) async {
  await tester.tap(find.text('Mais'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Convidar paciente'));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FakeAcsBackend backendComPacientes() => FakeAcsBackend()
  ..patients = [
    MicroAreaPatient(
      patientId: syntheticPatientId(5),
      name: 'Fulano de Tal',
      isChronic: false,
      chronicConditions: const [],
    ),
    MicroAreaPatient(
      patientId: syntheticPatientId(6),
      name: 'Ciclana da Silva',
      isChronic: true,
      chronicConditions: const ['diabetes'],
    ),
  ];

void main() {
  testWidgets('escolher o paciente e gerar mostra o QR com validade', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes();
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)));
    await entrar(tester);
    await abrirConvite(tester);

    final gerar = tester.widget<FilledButton>(find.byKey(const Key('generate_invite_button')));
    expect(gerar.onPressed, isNull, reason: 'sem paciente escolhido não há convite');

    await tapKey(tester, 'invite_patient_${syntheticPatientId(6)}');
    await tapKey(tester, 'generate_invite_button');

    expect(backend.inviteCalls, [syntheticPatientId(6)]);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('invite_expires_at')), findsOneWidget);
    expect(find.textContaining('Válido até'), findsOneWidget);
    expect(find.text('convite-sintetico-1'), findsOneWidget);
  });

  testWidgets('gerar de novo substitui o convite exibido', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes();
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)));
    await entrar(tester);
    await abrirConvite(tester);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');
    await tapKey(tester, 'generate_invite_button');

    expect(backend.inviteCalls, hasLength(2));
    expect(find.text('convite-sintetico-2'), findsOneWidget);
    expect(find.text('convite-sintetico-1'), findsNothing);
  });

  testWidgets('trocar de paciente esconde o convite anterior', (tester) async {
    // Um QR na tela atribuído ao nome errado ativaria o cadastro de outra
    // pessoa no aparelho de quem ler.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes();
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)));
    await entrar(tester);
    await abrirConvite(tester);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');
    expect(find.byType(QrImageView), findsOneWidget);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(6)}');
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('convite-sintetico-1'), findsNothing);
  });

  testWidgets('recusa do servidor mostra o motivo e nenhum QR', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes()
      ..inviteFailure = const BackendFailure('Este paciente não pertence à sua microárea.', isRecoverable: false);
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)));
    await entrar(tester);
    await abrirConvite(tester);

    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');

    expect(find.byKey(const Key('invite_error')), findsOneWidget);
    expect(find.text('Este paciente não pertence à sua microárea.'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('falha ao carregar pacientes permite tentar de novo', (tester) async {
    final backend = backendComPacientes()
      ..listPatientsFailure = const BackendFailure('Sem conexão com o servidor.');
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)));
    await entrar(tester);
    await abrirConvite(tester);

    expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
    backend.listPatientsFailure = null;
    await tapKey(tester, 'invite_retry');
    expect(find.text('Fulano de Tal'), findsOneWidget);
  });

  testWidgets('microárea sem paciente explica e não oferece geração', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: FakeAcsBackend(), feedBuilder: (queue) => FakeAlertFeed(queue)));
    await entrar(tester);
    await abrirConvite(tester);

    expect(find.byKey(const Key('invite_no_patients')), findsOneWidget);
    expect(find.byKey(const Key('generate_invite_button')), findsNothing);
  });

  testWidgets('tela de convite não tem botão inerte para leitor de tela', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(SinalAcsApp(backend: backendComPacientes(), feedBuilder: (queue) => FakeAlertFeed(queue)));
    await entrar(tester);
    await abrirConvite(tester);
    expectNenhumBotaoInerte(tester);
    handle.dispose();
  });
}
```

`syntheticPatientId`, `seedMicroAreaId` e `FakeAlertFeed` estão em `test/support/fakes.dart`; `expectNenhumBotaoInerte` em `test/support/semantics_scan.dart` (verificados em 2026-09-29).

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/invite_screen_test.dart`
Expected: FAIL — não há item "Convidar paciente" no menu (`find.text('Convidar paciente')` não encontra nada).

- [ ] **Step 4: Implementar a tela**

Criar `apps/acs/lib/app/invite_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_scope.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show EnrollmentTokenResult, MicroAreaPatient;

/// Convite de onboarding (RF02): o ACS escolhe um paciente da própria
/// microárea e mostra o QR Code que o app do paciente lê.
///
/// O token em claro existe só na memória desta tela — nunca vai para disco,
/// log ou fila offline; o servidor guarda só o hash (`enrollment_tokens`).
/// Sai da tela, some o token. A lista mostra nome e condições crônicas, a
/// mesma minimização do seletor da visita de rotina (spec/lgpd_design.md:364).
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  List<MicroAreaPatient>? _patients;
  MicroAreaPatient? _selected;
  EnrollmentTokenResult? _invite;
  String? _error;
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    // `BackendScope.of` depende de herança: não pode rodar dentro do
    // `initState` em si.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await BackendScope.of(context).listPatients();
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _loading = false;
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  void _select(MicroAreaPatient patient) {
    setState(() {
      // O convite exibido pertence ao paciente anterior: nunca deixá-lo na
      // tela sob o nome de outra pessoa.
      if (_selected?.patientId != patient.patientId) _invite = null;
      _selected = patient;
      _error = null;
    });
  }

  Future<void> _generate() async {
    final patient = _selected;
    if (patient == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final invite = await BackendScope.of(context).generateInvite(patientId: patient.patientId);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _generating = false;
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _invite = null;
        _error = failure.message;
        _generating = false;
      });
    }
  }

  String _hhmm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final patients = _patients;
    final invite = _invite;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Convidar paciente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Escolha o paciente e mostre o QR Code para ele ler no app SinalACS '
          'Paciente. O convite vale por 15 minutos e só pode ser usado uma vez.',
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (patients == null)
          OutlinedButton.icon(
            key: const Key('invite_retry'),
            onPressed: _load,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          )
        else if (patients.isEmpty)
          const Text(
            'Nenhum paciente cadastrado na sua microárea.',
            key: Key('invite_no_patients'),
          )
        else ...[
          for (final patient in patients)
            ListTile(
              key: Key('invite_patient_${patient.patientId}'),
              selected: _selected?.patientId == patient.patientId,
              title: Text(patient.name),
              subtitle: patient.chronicConditions.isEmpty ? null : Text(patient.chronicConditions.join(', ')),
              trailing: _selected?.patientId == patient.patientId
                  ? const Icon(Icons.check_circle, color: AcsColors.accentOnSurface)
                  : null,
              onTap: () => _select(patient),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('generate_invite_button'),
            onPressed: _selected == null || _generating ? null : _generate,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            icon: const Icon(Icons.qr_code_2),
            label: Text(invite == null ? 'Gerar convite' : 'Gerar novo convite'),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const Key('invite_error'),
                style: const TextStyle(color: AcsColors.redOnSurface, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        if (invite != null && _selected != null) ...[
          const SizedBox(height: 24),
          Center(
            child: Container(
              key: const Key('invite_qr'),
              // Fundo branco com margem: leitores de QR precisam da "zona
              // silenciosa" clara em volta, e o tema do app é escuro.
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: invite.token,
                size: 240,
                backgroundColor: Colors.white,
                semanticsLabel: 'QR Code do convite de ${_selected!.name}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Convite de ${_selected!.name} · Válido até ${_hhmm(invite.expiresAt.toLocal())} · uso único',
            key: const Key('invite_expires_at'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Se a câmera do paciente não funcionar, ele pode digitar este código:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          SelectableText(
            invite.token,
            key: const Key('invite_token_text'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ],
    );
  }
}
```

Nota: a mensagem de erro no carregamento da lista (`patients == null`) é o mesmo `_error` exibido abaixo do botão "Tentar de novo".

- [ ] **Step 5: Ligar no shell do ACS**

Em `apps/acs/lib/app/app.dart`:
- import: `import 'package:sinalacs_acs/app/invite_screen.dart';` (junto de `acs_theme.dart`);
- linha 255: `enum AcsDestination { area, queue, map, visit, escalation, geofencing, notices, invite }`;
- no `switch` de conteúdo, depois de `AcsDestination.notices => const NoticesScreen(),`: `AcsDestination.invite => const InviteScreen(),`;
- em `_more`, depois do item de "Avisos à comunidade": `_moreItem(sheet, Icons.qr_code_2, 'Convidar paciente', AcsDestination.invite),`.

- [ ] **Step 6: Rodar e ver passar**

Run: `cd apps/acs && flutter test test/invite_screen_test.dart`
Expected: PASS, 7/7.

- [ ] **Step 7: Suíte e commit**

Run: `cd apps/acs && flutter analyze && flutter test`
Expected: `No issues found!`; 167 testes.

```bash
git add apps/acs/pubspec.yaml apps/acs/pubspec.lock apps/acs/lib/app/invite_screen.dart apps/acs/lib/app/app.dart apps/acs/test/invite_screen_test.dart
git commit -m "feat(acs): tela Convidar paciente com QR Code do convite de onboarding (RF02)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 6: Leitura do QR Code pela câmera no app paciente

**Files:**
- Modify: `apps/patient/pubspec.yaml`, `apps/patient/pubspec.lock` (via `flutter pub add`)
- Create: `apps/patient/lib/core/onboarding/enrollment_qr.dart`
- Create: `apps/patient/lib/app/qr_scanner.dart`
- Modify: `apps/patient/lib/app/app.dart` (`SinalAcsApp` linhas 31–111; `OnboardingScreen`)
- Modify: `apps/patient/android/app/src/main/AndroidManifest.xml`
- Test: `apps/patient/test/enrollment_qr_test.dart` (novo), `apps/patient/test/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: `OnboardingScreen` com o aceite da Tarefa 3.
- Produces:
  - `String? parseEnrollmentQr(String raw)` — devolve o token (sem espaços nas pontas) só se casar `^[A-Za-z0-9_-]{43}$` (32 bytes em base64url sem padding, formato de `OnboardingService._newToken`).
  - `typedef QrScanner = Future<String?> Function(BuildContext context);` — `null` = pessoa cancelou.
  - `Future<String?> scanQrWithCamera(BuildContext context)`.
  - `class QrScannerScope extends InheritedWidget { const QrScannerScope({required QrScanner scanner, required Widget child}); static QrScanner of(BuildContext); }`.
  - `SinalAcsApp({..., QrScanner? qrScanner})`.
  - Keys: `scan_qr_button`; erros aparecem em `onboarding_error` (key existente).

- [ ] **Step 1: Dependência e permissão**

Run: `cd apps/patient && flutter pub add 'mobile_scanner:^7.0.0'`
Expected: `pubspec.yaml` ganha `mobile_scanner: ^7.0.0`; `pubspec.lock` atualizado.

Em `apps/patient/android/app/src/main/AndroidManifest.xml`, depois da permissão `RECEIVE_BOOT_COMPLETED`:

```xml
    <!-- Usada por `scanQrWithCamera` (lib/app/qr_scanner.dart) para ler o QR
         Code do convite do ACS no onboarding (RF02). A imagem não sai do
         aparelho: só o texto do QR preenche o campo do convite. Câmera não é
         obrigatória para instalar — sem ela, a pessoa digita o código. -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
```

- [ ] **Step 2: Testes que falham**

Criar `apps/patient/test/enrollment_qr_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/onboarding/enrollment_qr.dart';

/// Token sintético no formato real: 43 caracteres base64url.
const conviteSintetico = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCde';

void main() {
  test('aceita um convite no formato do servidor', () {
    expect(conviteSintetico.length, 43);
    expect(parseEnrollmentQr(conviteSintetico), conviteSintetico);
  });

  test('tira espaços e quebras de linha nas pontas', () {
    expect(parseEnrollmentQr('  $conviteSintetico\n'), conviteSintetico);
  });

  test('recusa QR que não é convite', () {
    expect(parseEnrollmentQr('https://exemplo.invalid/pagina'), isNull);
    expect(parseEnrollmentQr('00020126580014br.gov.bcb.pix'), isNull);
    expect(parseEnrollmentQr(''), isNull);
    expect(parseEnrollmentQr(conviteSintetico.substring(1)), isNull, reason: '42 caracteres');
    expect(parseEnrollmentQr('${conviteSintetico}A'), isNull, reason: '44 caracteres');
    expect(parseEnrollmentQr(conviteSintetico.replaceFirst('A', '+')), isNull,
        reason: 'base64 padrão, não url-safe');
  });
}
```

Em `apps/patient/test/onboarding_flow_test.dart`, acrescentar o import `import 'package:sinalacs_patient/app/qr_scanner.dart';`, a constante

```dart
/// Token sintético no formato real (43 caracteres base64url).
const _conviteSintetico = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCde';
```

e, ao final de `main()`:

```dart
  testWidgets('ler o QR do convite preenche o campo e libera concluir', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      qrScanner: (_) async => _conviteSintetico,
    ));
    await openOnboarding(tester);

    await tapKey(tester, 'scan_qr_button');
    final field = tester.widget<TextField>(find.byKey(const Key('onboarding_token_field')));
    expect(field.controller!.text, _conviteSintetico);

    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'complete_enrollment_button');
    expect(backend.enrollmentCalls.single['token'], _conviteSintetico);
  });

  testWidgets('cancelar a leitura não muda o que já foi digitado', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      qrScanner: (_) async => null,
    ));
    await openOnboarding(tester);
    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');

    await tapKey(tester, 'scan_qr_button');

    final field = tester.widget<TextField>(find.byKey(const Key('onboarding_token_field')));
    expect(field.controller!.text, 'convite-123');
    expect(find.byKey(const Key('onboarding_error')), findsNothing);
  });

  testWidgets('QR que não é convite mostra aviso e não preenche o campo', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      qrScanner: (_) async => 'https://exemplo.invalid/pagina',
    ));
    await openOnboarding(tester);
    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');

    await tapKey(tester, 'scan_qr_button');

    expect(find.textContaining('não é um convite do SinalACS'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('onboarding_token_field')));
    expect(field.controller!.text, 'convite-123');
  });

  testWidgets('falha da câmera mostra aviso e o campo manual continua utilizável', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      qrScanner: (_) async => throw StateError('câmera indisponível'),
    ));
    await openOnboarding(tester);

    await tapKey(tester, 'scan_qr_button');
    expect(find.textContaining('Não foi possível usar a câmera'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'complete_enrollment_button');
    expect(backend.enrollmentCalls, hasLength(1));
  });
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/enrollment_qr_test.dart test/onboarding_flow_test.dart`
Expected: FAIL na compilação — `enrollment_qr.dart`, `qr_scanner.dart` e o parâmetro `qrScanner` não existem.

- [ ] **Step 4: Validação pura**

Criar `apps/patient/lib/core/onboarding/enrollment_qr.dart`:

```dart
/// Formato do convite que `OnboardingService._newToken` gera no servidor:
/// 32 bytes aleatórios em base64url, sem `=` de padding — 43 caracteres.
final _enrollmentToken = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// O token contido num QR Code lido pela câmera, ou `null` se o QR não for um
/// convite do SinalACS (link, Pix, QR de outro app).
///
/// Só a leitura da câmera passa por aqui: o campo digitado à mão continua
/// indo ao servidor como está, e é o servidor quem diz se o convite vale.
/// Aqui o objetivo é outro — não sobrescrever o campo com o conteúdo de um QR
/// qualquer que a câmera tenha pegado.
String? parseEnrollmentQr(String raw) {
  final value = raw.trim();
  return _enrollmentToken.hasMatch(value) ? value : null;
}
```

- [ ] **Step 5: Leitor e escopo**

Criar `apps/patient/lib/app/qr_scanner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Lê um QR Code e devolve o texto dele, ou `null` se a pessoa voltar sem ler.
/// Pode lançar quando a câmera não está disponível.
typedef QrScanner = Future<String?> Function(BuildContext context);

/// Disponibiliza o [QrScanner] para a árvore de widgets.
///
/// Mesmo padrão de `BackendScope`/`LocationScope`: a tela de onboarding não
/// abre a câmera diretamente, o que permite trocar o leitor por um duplo em
/// teste hermético — a câmera real é canal de plataforma e não existe no
/// `flutter test`.
class QrScannerScope extends InheritedWidget {
  const QrScannerScope({required this.scanner, required super.child, super.key});

  final QrScanner scanner;

  static QrScanner of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<QrScannerScope>();
    assert(scope != null, 'Nenhum QrScannerScope acima deste widget.');
    return scope!.scanner;
  }

  @override
  bool updateShouldNotify(QrScannerScope oldWidget) => scanner != oldWidget.scanner;
}

/// Leitor real: abre a câmera numa tela própria e devolve o primeiro QR lido.
/// A imagem não é guardada nem enviada — só o texto do QR volta.
Future<String?> scanQrWithCamera(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _CameraScanPage()),
    );

class _CameraScanPage extends StatefulWidget {
  const _CameraScanPage();

  @override
  State<_CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<_CameraScanPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  // A câmera entrega vários quadros por segundo: sem esta trava, o mesmo QR
  // tentaria fechar a tela várias vezes.
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler QR Code do convite')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Não foi possível usar a câmera. Volte e digite o código do convite.',
                  key: Key('camera_error'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aponte a câmera para o QR Code mostrado pelo agente de saúde.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Se a versão resolvida do `mobile_scanner` tiver `errorBuilder` com três parâmetros (`(context, error, child)`, séries 5.x/6.x), ajuste a assinatura e registre a versão resolvida no ledger; o comportamento é o mesmo.

- [ ] **Step 6: Ligar no app**

Em `apps/patient/lib/app/app.dart`:

1. Imports: `import 'package:sinalacs_patient/app/qr_scanner.dart';` e `import 'package:sinalacs_patient/core/onboarding/enrollment_qr.dart';`.
2. `SinalAcsApp`: parâmetro `this.qrScanner,` no construtor e o campo

```dart
  /// Injetável para teste. Em execução normal é [scanQrWithCamera], que abre
  /// a câmera do aparelho.
  final QrScanner? qrScanner;
```

3. `_SinalAcsAppState`: `late final QrScanner _qrScanner = widget.qrScanner ?? scanQrWithCamera;` e, no `build`, envolver o `MaterialApp` em `QrScannerScope(scanner: _qrScanner, child: MaterialApp(...))` (é o filho de `RemindersScope`).
4. Trocar o doc de `OnboardingScreen` ("a leitura por câmera é apenas um jeito alternativo… (fora de escopo aqui)") por:

```dart
/// O campo de texto recebe o token do convite. A leitura do QR Code pela
/// câmera ("Ler QR Code com a câmera") preenche o mesmo campo — digitar
/// continua possível para quem não tem câmera ou negou a permissão.
```

5. Em `_OnboardingScreenState`, o método:

```dart
  Future<void> _scan() async {
    final scanner = QrScannerScope.of(context);
    final String? raw;
    try {
      raw = await scanner(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível usar a câmera. Digite o código do convite.');
      return;
    }
    if (!mounted || raw == null) return;
    final token = parseEnrollmentQr(raw);
    setState(() {
      if (token == null) {
        _error = 'Este QR Code não é um convite do SinalACS. Peça ao agente de '
            'saúde para mostrar o convite de novo.';
      } else {
        _tokenController.text = token;
        _error = null;
      }
    });
  }
```

6. No `build`, trocar o texto de instrução por:

```dart
                        const Text(
                          'Leia o QR Code do convite mostrado pelo agente '
                          'comunitário de saúde, ou digite o código.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('scan_qr_button'),
                            onPressed: _busy ? null : _scan,
                            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                            icon: const Icon(Icons.qr_code_scanner_outlined),
                            label: const Text('Ler QR Code com a câmera'),
                          ),
                        ),
```

(o `SizedBox(height: 20)` seguinte, antes do `TextField`, permanece).

- [ ] **Step 7: Rodar e ver passar**

Run: `cd apps/patient && flutter test test/enrollment_qr_test.dart test/onboarding_flow_test.dart`
Expected: PASS (3 + 4 novos, e os existentes).

- [ ] **Step 8: Suíte, build e commit**

Run: `cd apps/patient && flutter analyze && flutter test && flutter build apk --debug`
Expected: `No issues found!`, suíte verde, APK gerado (prova que o plugin nativo integra com `minSdk = 24`). Se o build do APK falhar por falta de SDK Android na máquina, registre no ledger e siga — o CI (`android-e2e`) cobre.

```bash
git add apps/patient/pubspec.yaml apps/patient/pubspec.lock apps/patient/lib/core/onboarding/enrollment_qr.dart apps/patient/lib/app/qr_scanner.dart apps/patient/lib/app/app.dart apps/patient/android/app/src/main/AndroidManifest.xml apps/patient/test/enrollment_qr_test.dart apps/patient/test/onboarding_flow_test.dart
git commit -m "feat(paciente): leitura do QR Code do convite pela câmera no onboarding (RF02)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 7: Registro em PROGRESS.md e nos documentos de referência

**Files:**
- Modify: `PROGRESS.md` (nova seção ao final)
- Modify: `apps/CLAUDE.md`
- Modify: `spec/lgpd_design.md` (notas de estado junto a LGPD-RF10/RF18/RF19)
- Modify: `spec/PRD_system.md:135`

**Interfaces:**
- Consumes: tudo acima. Produces: nada de código.

- [ ] **Step 1: PROGRESS.md**

Acrescentar ao final (conte os testes reais com a saída das suítes antes de escrever os números):

```markdown
## QR Code do onboarding e documentos legais (2026-09-29)

Plano: `docs/superpowers/plans/2026-09-29-qr-onboarding-e-documentos-legais.md`, branch `fix/patient`.

**RF02 de ponta a ponta.** O ACS ganhou "Mais › Convidar paciente": escolhe um paciente da própria microárea, gera o convite (`onboarding.generateEnrollmentToken`, que existia sem nenhum chamador) e mostra o QR Code (`qr_flutter`), com validade de 15 minutos e o código em texto para digitação. O paciente lê com "Ler QR Code com a câmera" (`mobile_scanner`, permissão `CAMERA`, câmera opcional na instalação), que preenche o mesmo campo do código; QR que não tem o formato do convite (43 caracteres base64url) é recusado sem sobrescrever o campo. O PRD citava `qr_code_scanner`, pacote descontinuado — trocado por `mobile_scanner`.

**LGPD-RF18/RF19/RF10.** Termo de Uso e Política de Privacidade versão 2026.1 no app paciente (`lib/core/legal/legal_documents.dart`): resumo visual em passos (fluxo do dado), texto completo em seções, histórico de versões. Abrem antes do cadastro (link no login e no onboarding) e depois em "Mais › Privacidade e termos". O aceite é explícito, desmarcado por padrão e obrigatório; vira `ConsentPurpose.termsOfUse` em `consent_logs`, na mesma transação dos outros consentimentos, com `version = consentPolicyVersion`. `updateConsent` recusa alterá-lo. Um teste do app falha se a versão exibida divergir da carimbada pelo backend.

**Ficou de fora, de propósito:**
- O texto 2026.1 precisa de revisão jurídica e dos dados reais do controlador e do encarregado (hoje genéricos: "Secretaria Municipal de Saúde do seu município").
- Aviso de mudança com 15 dias de antecedência e novo aceite quando a versão mudar: só existe uma versão; não há mecanismo de reaceite no login.
- Pacientes que entram por CPF + OTP (RF01) sem ter passado pelo onboarding nunca aceitaram o termo — o seed inclusive. Falta um aceite no primeiro login.
- Canal de dúvidas é "fale com o ACS ou a UBS", sem canal digital próprio.
- A página da câmera (`_CameraScanPage`) só roda no aparelho; os testes cobrem o fluxo com um leitor duplo. Validar no emulador com um QR gerado pelo app do ACS.
- Contagens de teste depois desta entrega: backend N, paciente N, ACS N.
```

- [ ] **Step 2: apps/CLAUDE.md**

Na seção "Flutter apps (`apps/acs/`, `apps/patient/`)", depois do parágrafo do login passwordless do paciente, acrescentar:

```markdown
The onboarding QR (RF02) now exists on both sides: the ACS's "Mais › Convidar paciente" (`apps/acs/lib/app/invite_screen.dart`) calls `onboarding.generateEnrollmentToken` through `AcsBackend.generateInvite` and draws the token with `qr_flutter` — the plaintext token lives only in that screen's `State`, never on disk, and switching patient hides the previous QR. The patient's onboarding reads it with `mobile_scanner` through `QrScannerScope` (`apps/patient/lib/app/qr_scanner.dart`), injectable like `BackendScope` so widget tests never touch the camera; `parseEnrollmentQr` only accepts the server's 43-char base64url format. Terms of Use and Privacy Policy are constant Dart content in `apps/patient/lib/core/legal/legal_documents.dart`; `legalDocumentsVersion` must equal the backend's `consentPolicyVersion`, and `test/legal_documents_test.dart` reads the server file to enforce it. Acceptance is `ConsentPurpose.termsOfUse`, mandatory in `completeEnrollment` like `healthDataProcessing`.
```

- [ ] **Step 3: specs**

Em `spec/PRD_system.md:135`, trocar `` Câmera, `qr_code_scanner` `` por `` Câmera, `mobile_scanner` (paciente) e `qr_flutter` (ACS) ``.

Em `spec/lgpd_design.md`, logo depois da tabela de cada um dos requisitos LGPD-RF10 (~linha 157), RF18 (~249) e RF19 (~259), acrescentar uma linha de estado:

```markdown
> **Estado (2026-09-29):** implementado no app paciente — ver PROGRESS.md "QR Code do onboarding e documentos legais". Pendentes: revisão jurídica do texto, aviso com 15 dias de antecedência e reaceite a cada nova versão.
```

(Na RF10, troque "reaceite a cada nova versão" por "canal digital de dúvidas".)

- [ ] **Step 4: Verificações finais e commit**

Run:
```bash
./scripts/qa/ci_invariants.sh
graphify update .
```
Expected: invariantes OK; grafo atualizado.

```bash
git add PROGRESS.md apps/CLAUDE.md spec/lgpd_design.md spec/PRD_system.md
git commit -m "docs: registra o QR do onboarding e os documentos legais do app paciente

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
