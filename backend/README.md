# Backend SinalACS

Este módulo representa a camada central do sistema conforme o PRD.

## Visão
- Servidor HTTP `dart:io` puro, sem framework, roteamento manual (Serverpod foi a decisão de stack original registrada em `spec/stack.md`, mas nunca foi implementada dessa forma — a dependência não usada foi removida do `pubspec.yaml`)
- PostgreSQL como fonte de verdade transacional
- MQTT como transporte para alertas urgentes
- arquitetura offline-first com sincronização local/central

## Estrutura real
- lib/src/config — `app_config.dart`, configuração via variáveis de ambiente
- lib/src/domain/entities — entidades de domínio, sem I/O
- lib/src/domain/enums
- lib/src/application/alerts — `red_alert_service.dart`
- lib/src/application/triage — `triage_engine.dart`
- lib/src/application/sync — `sync_fsm.dart`
- lib/src/application/auth — `development_auth_service.dart` (auth de desenvolvimento, não institucional)
- lib/src/infrastructure/database — `postgres_alert_store.dart`, `migrations/`, `seeds/`
- lib/src/infrastructure/mqtt — `mqtt_alert_dispatcher.dart`

Ver [CLAUDE.md](../CLAUDE.md) para a descrição completa da arquitetura e
[DEPLOY.md](DEPLOY.md) para o runbook de deploy em serviços free-tier.

## Regras
- respeitar os invariantes do PRD
- manter a classificação de risco determinística
- aderir à microárea do ACS em todas as consultas
- usar versionamento e fila de sincronização
