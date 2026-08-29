# Backend SinalACS

Este módulo representa a camada central do sistema conforme o PRD.

## Visão
- Serverpod como backend principal
- PostgreSQL como fonte de verdade transacional
- MQTT como transporte para alertas urgentes
- arquitetura offline-first com sincronização local/central

## Estrutura esperada
- lib/src/config
- lib/src/core/auth
- lib/src/core/encryption
- lib/src/core/telemetry
- lib/src/domain/entities
- lib/src/domain/repositories
- lib/src/application/auth
- lib/src/application/patients
- lib/src/application/acs
- lib/src/application/alerts
- lib/src/application/triage
- lib/src/application/visits
- lib/src/application/sync
- lib/src/infrastructure/database
- lib/src/infrastructure/mqtt
- lib/src/infrastructure/http
- lib/src/infrastructure/cache
- lib/src/infrastructure/logging
- lib/src/api/controllers
- lib/src/api/routes
- lib/src/api/dto

## Regras
- respeitar os invariantes do PRD
- manter a classificação de risco determinística
- aderir à microárea do ACS em todas as consultas
- usar versionamento e fila de sincronização
