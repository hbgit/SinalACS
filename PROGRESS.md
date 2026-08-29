# Progresso da Fase 1 - Milestones Técnicos

Este documento consolida o que já foi implementado em relação à Fase 1 da Seção 6.2, "Proof of Concept", do PRD.

## Resumo executivo

A maioria dos entregáveis da Fase 1 já foi implementada no repositório, com foco em infraestrutura, CI, motor de triagem, FSM de sincronização e proteção local dos dados. O estado geral é:

- M1.1: Implementado
- M1.2: Implementado
- M1.3: Implementado
- M1.4: Implementado
- M1.5: Implementado no código, com validação local em ambiente de teste

## Milestones Técnicos - Fase 1

| Milestone | Entregável | Status | Evidência |
|---|---|---|---|
| M1.1 | Docker-Compose local (Stack completa) | Implementado | [docker-compose.yml](docker-compose.yml) com PostgreSQL, Mosquitto, Serverpod e Traefik |
| M1.2 | CI Pipeline básica | Implementado | [.github/workflows/ci.yml](.github/workflows/ci.yml) com jobs do backend e dos apps Flutter |
| M1.3 | Motor de Triagem (algoritmo) | Implementado | [backend/lib/src/application/triage/triage_engine.dart](backend/lib/src/application/triage/triage_engine.dart) e [backend/test/triage_engine_test.dart](backend/test/triage_engine_test.dart) |
| M1.4 | FSM de Sincronização | Implementado | [backend/lib/src/application/sync/sync_fsm.dart](backend/lib/src/application/sync/sync_fsm.dart) e [backend/test/sync_fsm_test.dart](backend/test/sync_fsm_test.dart) |
| M1.5 | SQLCipher (local) | Implementado no código | [apps/patient/lib/core/database/encrypted_database.dart](apps/patient/lib/core/database/encrypted_database.dart) e [apps/acs/lib/core/database/encrypted_database.dart](apps/acs/lib/core/database/encrypted_database.dart) |

## O que já está pronto

### M1.1 - Stack local em containers

A infraestrutura local já foi criada em [docker-compose.yml](docker-compose.yml):

- PostgreSQL 15
- Mosquitto
- Serverpod
- Traefik

Esse componente atende ao critério do PRD de subir a stack completa em ambiente local via Docker Compose.

### M1.2 - CI básica

A pipeline de integração contínua foi criada em [.github/workflows/ci.yml](.github/workflows/ci.yml):

- backend: `dart analyze` + `dart test`
- app paciente: `flutter analyze` + `flutter test`
- app ACS: `flutter analyze` + `flutter test`

Isso atende ao requisito do PRD de rodar lint e testes em GitHub Actions.

### M1.3 - Motor de triagem

O motor de classificação de risco foi implementado em [backend/lib/src/application/triage/triage_engine.dart](backend/lib/src/application/triage/triage_engine.dart).

A lógica é determinística e mapeia sinais clínicos para risco vermelho, amarelo ou verde, em linha com a intenção do PRD.

Também há testes específicos em [backend/test/triage_engine_test.dart](backend/test/triage_engine_test.dart), demonstrando a validação do comportamento principal.

### M1.4 - FSM de sincronização

A máquina de estados de sincronização foi implementada em [backend/lib/src/application/sync/sync_fsm.dart](backend/lib/src/application/sync/sync_fsm.dart).

Ela cobre os estados principais de sincronização offline-first, incluindo:

- idle
- localWrite
- queued
- syncing
- conflict
- synced
- error

Os cenários de transição e conflito foram validados em [backend/test/sync_fsm_test.dart](backend/test/sync_fsm_test.dart).

### M1.5 - Criptografia local com SQLCipher

A camada de banco local criptografado foi adicionada em:

- [apps/patient/lib/core/database/encrypted_database.dart](apps/patient/lib/core/database/encrypted_database.dart)
- [apps/acs/lib/core/database/encrypted_database.dart](apps/acs/lib/core/database/encrypted_database.dart)

A implementação usa SQLCipher para plataformas móveis e fallback FFI para ambientes de teste/VM, preservando a exigência de proteção de dados sensíveis em repouso.

## Observações importantes

- A implementação da Fase 1 está no repositório e alinhada ao escopo do PRD.
- Os componentes centrais já foram construídos e testados isoladamente.
- O restante do trabalho da Fase 1 depende mais de validação de ambiente e integração real do que de criação de novos blocos de arquitetura.

## Status final do checklist da Fase 1

- [x] M1.1 - Docker Compose local
- [x] M1.2 - CI básica
- [x] M1.3 - Motor de triagem
- [x] M1.4 - FSM de sincronização
- [x] M1.5 - SQLCipher local

Atenção: a implementação está concluída no código e validada em parte por testes locais, mas ainda deve ser confirmada em execução real do ambiente completo para fechamento final de garantia de produção.
