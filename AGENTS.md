# AGENTS.md

## Visão geral do projeto

O SinalACS é uma plataforma para priorização de atendimentos na Atenção Primária à Saúde, transformando sinais clínicos estruturados em uma fila de trabalho para o ACS (Agente Comunitário de Saúde), ordenada por risco e preparada para operar em conectividade instável.

O repositório já contém um protótipo funcional com:
- backend em Dart/Serverpod;
- apps Flutter para paciente e ACS;
- PostgreSQL como persistência central;
- broker MQTT para entrega de alertas em tempo real;
- fluxo de sincronização offline para visitas do ACS.

Os dois fluxos centrais continuam sendo:
- paciente: autenticação simples, alerta de urgência, triagem estruturada e acompanhamento de status;
- ACS: priorização dinâmica, territorialização por microárea, registro offline e acompanhamento do território.

## Leitura obrigatória antes de implementar

Antes de mexer em produto, arquitetura ou comportamento, consulte primeiro:
- [README.md](README.md) — visão geral do produto e estado atual;
- [spec/PRD_system.md](spec/PRD_system.md) — requisitos, JTBD, invariantes e métricas;
- [spec/stack.md](spec/stack.md) — decisões de stack e infraestrutura;
- [spec/ui_design.md](spec/ui_design.md) — linguagem visual e UX;
- [spec/lgpd_design.md](spec/lgpd_design.md) — privacidade e LGPD;
- [spec/lgpd_data_audit.md](spec/lgpd_data_audit.md) — classificação de sensibilidade LGPD, campo a campo, de todas as tabelas persistidas;
- [spec/ux_accessibility_assessment.md](spec/ux_accessibility_assessment.md) — auditoria WCAG 2.2 AA (contraste, alvo de toque, semântica) dos apps ACS, paciente e admin;
- [spec/ux_ui_test_plan.md](spec/ux_ui_test_plan.md) — plano de testes de UX/UI derivado de `spec/ui_design.md`;
- [CLAUDE.md](CLAUDE.md) — guia técnico e comandos para IA; é a referência mais atualizada do repositório;
- [PROGRESS.md](PROGRESS.md) — status dos milestones e histórico de migração;
- [backend/](backend) — workspace Dart com `sinalacs_server` e `sinalacs_client`;
- [apps/acs](apps/acs) e [apps/patient](apps/patient) — aplicativos Flutter reais;
- [spec/ui_acs](spec/ui_acs) e [spec/ui_paciente](spec/ui_paciente) — protótipos visuais e fluxos do produto.

Quando houver conflito entre convenções gerais e documentação do projeto, a documentação do projeto vence.

## Invariantes de negócio e segurança

Não violar estes pontos sob qualquer hipótese:
- a microárea do ACS restringe o acesso apenas ao território correspondente;
- a classificação de risco é determinística e não pode ser alterada por intervenção manual no fluxo de triagem;
- alertas vermelhos nunca podem ser descartados silenciosamente;
- dados de saúde devem seguir os padrões de privacidade e LGPD;
- o cliente ACS deve operar mesmo com rede instável;
- a sincronização local/central é uma área crítica de risco arquitetural.

## Arquitetura atual do repositório

### Backend
- O backend está em um workspace Dart em [backend/](backend), com os pacotes `sinalacs_server` e `sinalacs_client`.
- A stack atual é Serverpod, não um servidor hand-rolled em `dart:io`.
- O servidor usa PostgreSQL e MQTT; a autenticação de desenvolvimento é opcional e não substitui autenticação institucional real.
- A camada de domínio fica em `backend/sinalacs_server/lib/src/application/` e a infraestrutura em `.../infrastructure/`.
- Os modelos e endpoints são definidos com Serverpod; não se deve editar manualmente arquivos gerados em `lib/src/generated/` ou migrações sem regenerar via `serverpod generate` e `serverpod create-migration`.
- O fluxo principal inclui: `auth.developmentLogin`, `triage.evaluate`, `alerts.createRedAlert`, `alerts.acknowledge` e `visits.sync`.
- MQTT conecta em background após boot, com reconexão exponencial e sem bloquear a API.

### Apps Flutter
- A app do paciente e a app do ACS vivem em [apps/patient](apps/patient) e [apps/acs](apps/acs).
- Ambos usam o cliente gerado `sinalacs_client` por dependência local e não devem depender diretamente de detalhes de implementação do servidor em widgets.
- O app ACS é o mais crítico em termos de offline-first e sincronização: guarda visitas locais, tenta sincronizar em fila e trata conflitos sem perder registros.
- O tema visual é dark mode, com foco em legibilidade e uso de cor restrito a sinal clínico (vermelho, amarelo, verde).
- O app do paciente não deve reintroduzir regras de risco no cliente; a classificação deve vir do backend via `triage.evaluate`.
- [apps/admin](apps/admin) (`sinalacs_admin`) é o backoffice administrativo — deixou de ser um esqueleto de pubspec e hoje é um app navegável real, com 4 telas somente leitura (Indicadores, Microáreas, Alertas, Auditoria) atrás de `AdminHomeShell`. Ainda não consome `sinalacs_client`: usa a interface `AdminDataSource`, hoje implementada só por `MockAdminDataSource`, seguindo o mesmo padrão de DI de `PatientBackend`/`AcsBackend`. O login é local e não chama `auth.developmentLogin` (o backend só aceita `role: 'patient'`/`role: 'acs'` hoje). Toda tela que exibe dado sensível registra o próprio acesso via `recordAccess()` antes de renderizar, por exigência de auditoria do PRD §4.2.2. É o único dos três apps com suporte a Flutter Web, e desde a adição da plataforma Android também roda em celular e tablet (`flutter run -d emulator-5554`). O layout segue desktop-first: os pontos de quebra ficam em `lib/app/admin_layout.dart` e o layout compacto é complemento, nunca substituição — os dez testes de widget originais continuam passando sem edição, o que é o que prova isso.

### Infraestrutura local
- O ambiente de desenvolvimento usa Docker Compose com PostgreSQL, Mosquitto, backend e Traefik.
- Há geração local de segredos via [scripts/dev/bootstrap_env.sh](scripts/dev/bootstrap_env.sh); o projeto não possui `.env` versionado.
- O servidor e o broker exigem valores configurados por ambiente; não reaproveitar credenciais do ambiente local em produção.

## Regras de desenvolvimento

### 1) Preserve o contexto do produto
- A solução é orientada por risco clínico e não por roteiros geográficos fixos.
- O foco do MVP é priorização e resposta rápida a urgências.
- O idioma principal da documentação, comentários e textos de UI é o português.

### 2) Respeite a arquitetura escolhida
- Prefira soluções simples e previsíveis alinhadas ao stack já decidido: Flutter + Dart + PostgreSQL + MQTT.
- Não introduzir frameworks ou serviços novos sem justificativa no PRD, stack ou arquitetura do projeto.
- Ao alterar sincronização ou fila offline, preservar retry, deduplicação, conflito e persistência local.

### 3) Preserve invariantes de negócio e segurança
- Microárea deve restringir dados ao território do ACS.
- Red alert não pode ser perdido em silêncio.
- Triagem precisa ser determinística e consistente com o modelo do Protocolo de Manchester.
- Nenhum dado sensível de paciente deve entrar em logs, screenshots, testes, seeds ou configurações compartilhadas.

### 4) Ao criar ou alterar código
- Manter a lógica de domínio separada da infraestrutura.
- Preferir interfaces e casos de uso testáveis, como no padrão de `application/` + `infrastructure/`.
- Evitar acoplamento de widgets e UI com o cliente gerado do backend.
- Quando houver mudança em modelos ou endpoints, gerar a migração correspondente em vez de editar arquivos gerados manualmente.

### 5) Quando o trabalho for de UI
- Manter dark mode, alta legibilidade e baixo ruído visual.
- Usar cores apenas para sinal clínico; não decorar interfaces com vermelho/amarelo/verde sem relação com risco.
- Manter foco em mobile-first e acessibilidade.
- Ao reaproveitar uma cor clínica de preenchimento (`red`/`accent`/`danger`) como cor de texto/ícone, usar a variante `*OnSurface` (`acs_theme.dart`/`patient_theme.dart`/`admin_theme.dart`) e medir contraste contra a superfície real (`Card`/`surfaceRaised`), não contra o fundo do Scaffold — ver `spec/ux_accessibility_assessment.md` e os testes em `test/contrast_tokens_test.dart` de cada app.

### 6) Quando o trabalho for de backend ou dados
- Considerar uso de SQLite/SQLCipher e filas locais para operação offline.
- Planejar retry, reconciliação de conflitos e rastreabilidade de eventos.
- Manter a lógica de sincronização e persistência consistentes com o fluxo de visitas do ACS.

## Comandos e validações importantes

Antes do primeiro ambiente local:
```bash
./scripts/dev/bootstrap_env.sh
```

Subir a stack local:
```bash
docker compose up --build
```

Rodar testes do backend:
```bash
cd backend
dart pub get
cd sinalacs_server
dart test
```

Rodar análise do Flutter nos apps:
```bash
cd apps/patient && flutter pub get && flutter analyze && flutter test
cd apps/acs && flutter pub get && flutter analyze && flutter test
cd apps/admin && flutter pub get && flutter analyze && flutter test
cd apps/admin && flutter run -d emulator-5554          # no emulador Android
cd apps/admin && flutter test integration_test -d emulator-5554   # hermético: não precisa da stack
```

Importante:
- `flutter test` é hermético e não substitui validações com stack local real;
- os testes de integração e validação de conexão vivem fora do `flutter test` e utilizam a stack Docker/VM;
- o CI do projeto valida seis jobs separados: `serverpod-backend`, `backend-docker-build`, `patient-app`, `acs-app`, `admin-app` e `admin-android-build` (único que executa Gradle, compilando o APK do admin).

## Observações finais

Este repositório já não é apenas um conjunto de especificações. Ele contém um protótipo funcional validado localmente em stack Docker, com backend, apps reais e infraestrutura mínima operável para desenvolvimento.

O estado atual não é produção: não há autenticação institucional real, não há mTLS no broker, e não existe deploy de produção concluído. Mesmo assim, qualquer mudança deve preservar a direção arquitetural do projeto e os invariantes de negócio definidos no PRD.

A documentação do produto, a arquitetura e os comandos de execução já estão no repositório; a implementação deve seguir o que está ali registrado e não inventar novos padrões sem alinhamento técnico e funcional.

## Graphify

Este projeto possui um grafo de conhecimento em [graphify-out](graphify-out), com nós e relações entre arquivos e conceitos.

Quando estiver explorando o código e precisar entender ligações entre módulos, prefira:
- `graphify query "<pergunta>"` quando o grafo existir;
- `graphify path "<A>" "<B>"` para traçar relações;
- `graphify explain "<conceito>"` para foco em um tema específico;
- `graphify update .` após alterações de código para manter o grafo atualizado.

Se o diretório [graphify-out/wiki](graphify-out/wiki) existir, use-o para navegação ampla antes de navegar por arquivos isolados.
