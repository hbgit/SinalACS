# PRD de Engenharia e Arquitetura de Produto - SinalACS

**Role:** Principal Product Architect & Staff Systems Engineer  
**Versão:** 1.0  
**Data:** 29/08/2026  
**Status:** Draft para Revisão Técnica

---

## 1. Fundações e Visão de Produto

### 1.1 Resumo Executivo & JTBD

**Problema Central:** O modelo atual de visitas domiciliares na Atenção Primária à Saúde opera de forma reativa e baseada em roteiros geográficos fixos, criando um desalinhamento crítico entre a urgência clínica do paciente e o momento em que ele efetivamente recebe atendimento. Sistemas existentes (como e-SUS APS) funcionam como registros passivos, enquanto ferramentas genéricas (WhatsApp) geram comunicação desestruturada que sobrecarrega o Agente Comunitário de Saúde (ACS).

**Jobs-to-be-Done (JTBD):**

| Job | Ator | Situação | Motivação | Resultado Esperado |
|-----|------|----------|-----------|-------------------|
| **Priorizar atendimento por risco clínico** | ACS | Recebe múltiplas solicitações simultâneas | Necessidade de alocar recursos escassos onde há maior impacto | Dashboard dinâmico ordenado por gravidade |
| **Disparar alerta de urgência** | Paciente | Sente sintomas graves que requerem atenção imediata | Medo de não ser atendido a tempo | Alerta em tempo real com geolocalização para o ACS |
| **Registrar visita offline** | ACS | Está em zona rural ou área sem cobertura de dados | Evitar retrabalho e perda de informação | Registro local com sincronização automática posterior |
| **Territorializar microárea** | ACS | Necessita conhecer todos os pacientes sob sua responsabilidade | Planejar rotas e acompanhamento | Cache local dos dados da microárea |
| **Autotriagem assistida** | Paciente | Dúvida se o sintoma justifica uma visita ou pode esperar | Evitar deslocamento desnecessário | Classificação de risco determinística (Verde/Amarelo/Vermelho) |

**Proposta de Valor Técnica:**

O SinalACS transforma dados clínicos estruturados em ação imediata através de:
1. **Motor de Triagem Determinístico:** Algoritmo fechado inspirado no Protocolo de Manchester que calcula risco sem dependência de IA ou LLMs.
2. **Arquitetura Offline-First:** Resiliência em zonas de sombra de rede via cache territorial em `sqflite`.
3. **Mensageria IoT de Baixa Latência:** Protocolo MQTT para entrega de alertas críticos mesmo em redes 3G instáveis.
4. **Isomorfismo Dart:** Type-safety end-to-end entre Flutter e Serverpod, eliminando discrepâncias de contrato.

### 1.2 Hipóteses e Invariantes de Negócio

**Hipóteses a Validar (MVP):**

| ID | Hipótese | Métrica de Validação | Critério de Sucesso |
|----|----------|---------------------|---------------------|
| H1 | ACS conseguem priorizar visitas mais rapidamente com o dashboard dinâmico | Tempo médio entre recebimento do alerta e início da visita | Redução ≥ 40% vs. modelo atual |
| H2 | Pacientes com baixo letramento digital conseguem usar o app | Taxa de conclusão do onboarding sem assistência | ≥ 80% dos pacientes completam o fluxo |
| H3 | A classificação de risco determina corretamente a urgência | Concordância entre classificação do app e avaliação médica posterior | ≥ 90% de concordância |
| H4 | O registro offline não gera perda de dados | Taxa de sincronização bem-sucedida após restauração de rede | ≥ 99.5% dos registros sincronizam |

**Invariantes de Negócio (Jamais podem ser violadas):**

| Invariante | Descrição | Verificação |
|------------|-----------|-------------|
| **INV-01** | Um ACS **nunca** pode visualizar dados de pacientes fora de sua microárea | Verificação em todas as queries: `WHERE micro_area_id = user.micro_area_id` |
| **INV-02** | A classificação de risco **nunca** pode ser alterada por um humano no momento da triagem | O cálculo é determinístico e imutável no frontend |
| **INV-03** | Um alerta vermelho **nunca** pode ser perdido ou silenciosamente descartado | Confirmação de entrega (ACK) no MQTT com retry até confirmação |
| **INV-04** | Dados de saúde sensíveis **nunca** podem ser persistidos em texto plano | Criptografia AES-256 em `sqflite` e PostgreSQL |
| **INV-05** | O paciente **nunca** pode acessar dados de outro paciente | Autenticação com segregação por `patient_id` |

### 1.3 Métricas de Sucesso (North Star)

**Métrica North Star:** **Tempo Médio de Resposta a Alerta Vermelho** (TMRAV) - intervalo entre o acionamento do botão de pânico pelo paciente e a confirmação de recebimento pelo ACS, com eventual registro de início de atendimento.

**Métricas de Produto:**

| Métrica | Descrição | Captura Técnica | Target (MVP) |
|---------|-----------|-----------------|--------------|
| **TMRAV** | Tempo entre alerta e resposta | Timestamp no publish MQTT vs. timestamp do ACK no app ACS | < 90 segundos |
| **Taxa de Sincronização Offline** | % de registros offline que sincronizam com sucesso | Evento `sync_success` / `sync_attempts` | > 99.5% |
| **Aderência à Classificação** | % de visitas onde a classificação do app foi mantida | Comparação classificação_app vs. classificação_médica | > 90% |
| **Engajamento do ACS** | Número médio de visitas registradas por ACS/dia | Contagem de registros no `visits` table | ≥ 8 visitas/dia |
| **Retenção de Pacientes** | % de pacientes ativos após 30 dias | Último login < 30 dias | > 70% |

**Captura Técnica:**

```yaml
# Eventos de telemetria estruturados
events:
  - name: alert_triggered
    fields: [patient_id, risk_level, timestamp, location_hash, mqtt_topic]
  - name: alert_received_acs
    fields: [acs_id, alert_id, timestamp, latency_ms]
  - name: sync_attempt
    fields: [device_id, records_count, timestamp, network_type]
  - name: sync_result
    fields: [device_id, success_count, failure_count, conflict_count]
  - name: visit_registered
    fields: [acs_id, patient_id, visit_type, offline_flag, sync_status]
```

---

## 2. Escopo Funcional e Comportamental

### 2.1 Arquitetura de Módulos (Bounded Contexts)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SINALACS - BOUNDED CONTEXTS                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────────┐  ┌───────────────────────┐  ┌───────────────────┐│
│  │   PACIENTE (P-APP)    │  │     ACS (ACS-APP)     │  │  ADMIN (BACKOFFICE)││
│  ├───────────────────────┤  ├───────────────────────┤  ├───────────────────┤│
│  │ Autenticação          │  │ Login Institucional   │  │ Gestão de UBS     ││
│  │ Onboarding QR Code    │  │ Territorialização     │  │ Gestão de ACS     ││
│  │ Alerta de Urgência    │  │ Dashboard Dinâmico    │  │ Relatórios        ││
│  │ Triagem Estruturada   │  │ Mapa Interativo       │  │ Auditoria         ││
│  │ Mensageria (Tickets)  │  │ Registro de Visitas   │  │ Configurações     ││
│  │ Perfil Clínico        │  │ Geofencing (Check-in) │  │                  ││
│  │ Status de Solicitações│  │ Avisos à Comunidade   │  │                  ││
│  │ Lembretes de Saúde    │  │ Escalonamento (SAMU)  │  │                  ││
│  └───────────────────────┘  └───────────────────────┘  └───────────────────┘│
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    NÚCLEO COMPARTILHADO (CORE)                       │  │
│  ├───────────────────────────────────────────────────────────────────────┤  │
│  │  Motor de Triagem (Manchester)  │  Motor de Sincronização (FSM)      │  │
│  │  Modelos de Dados (Patient, Visit, Alert)                           │  │
│  │  Utilitários de Criptografia  │  Logging Estruturado                │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    INFRAESTRUTURA (INFRA)                            │  │
│  ├───────────────────────────────────────────────────────────────────────┤  │
│  │  MQTT Broker (Mosquitto)  │  Edge Gateway (Traefik)                  │  │
│  │  PostgreSQL (ACID)        │  Serverpod (Backend ORM)                │  │
│  │  Pulumi (IaC)             │  OpenTelemetry (Observabilidade)        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Matriz de Capacidades

| ID | Requisito | Ator | Complexidade | Risco | Dependência |
|----|-----------|------|--------------|-------|-------------|
| **RF01** | Autenticação Passwordless (CPF + Data Nasc + OTP) | Paciente | M | Médio | SMS Gateway |
| **RF02** | Onboarding via QR Code (ACS gera, paciente escaneia) | Paciente | M | Médio | Câmera, `qr_code_scanner` |
| **RF03** | Botão de Alerta de Urgência (MQTT) | Paciente | M | **Crítico** | Mosquitto, GPS |
| **RF04** | Formulário de Triagem Estruturada (árvore de decisão) | Paciente | S | Médio | Nenhuma (local) |
| **RF05** | Painel de Status de Solicitação | Paciente | S | Baixo | API Serverpod |
| **RF06** | Lembretes de Saúde (Local Notifications) | Paciente | S | Médio | `flutter_local_notifications` |
| **RF07** | Login Institucional (Matrícula/Senha) | ACS | S | Médio | Serverpod Auth |
| **RF08** | Territorialização (Download de Microárea para cache) | ACS | M | Médio | `sqflite`, API |
| **RF09** | Dashboard de Priorização Dinâmica (FSM de fila) | ACS | M | Alto | Motor de Triagem |
| **RF10** | Mapa Interativo (Google Maps) | ACS | M | Médio | `google_maps_flutter` |
| **RF11** | Registro Rápido de Visitas (Offline-first) | ACS | M | **Crítico** | `sqflite`, `connectivity_plus` |
| **RF12** | Geofencing (Check-in Passivo) | ACS | M | Médio | GPS em segundo plano |
| **RF13** | Escalonamento para SAMU/UBS (`url_launcher`) | ACS | S | Baixo | `url_launcher` |
| **RF14** | Avisos Segmentados à Comunidade (Push) | ACS | M | Médio | FCM/APNs |
| **RF15** | Sincronização Bidirecional (Local ↔ Central) | Sistema | **L** | **Crítico** | ORM Serverpod |
| **RF16** | Motor de Triagem Determinístico (Manchester) | Sistema | **L** | **Crítico** | Nenhuma (local) |
| **RF17** | Logs de Auditoria e Conformidade (LGPD) | Sistema | M | Alto | PostgreSQL |
| **RF18** | Dark Mode Nativo (Modo Escuro) | UI | S | Baixo | Tema Flutter |
| **RNF01** | Latência MQTT < 500ms (p95) | Sistema | - | Alto | Mosquitto, Traefik |
| **RNF02** | Sincronização Offline > 99.5% | Sistema | - | **Crítico** | `sqflite`, FSM |
| **RNF03** | Criptografia AES-256 em repouso | Sistema | - | **Crítico** | SQLCipher |
| **RNF04** | TLS 1.3 em todas as comunicações | Sistema | - | **Crítico** | Traefik, cert-manager |
| **RNF05** | Acessibilidade WCAG 2.1 Nível AA | UI | - | Médio | `accessibility_test` |
| **RNF06** | RBAC (Role-Based Access Control) | Sistema | - | Alto | Serverpod Auth |

### 2.3 Modelagem de Fluxos Críticos como Máquinas de Estados (FSM)

#### 2.3.1 FSM - Fluxo de Alerta de Urgência

**Definição Formal:** $A_{Alert} = (Q, \Sigma, \delta, q_0, F)$

- $Q = \{Idle, Geolocating, Publishing, AwaitingACK, Delivered, Failed, Persisted\}$
- $\Sigma = \{trigger, gps_ready, publish, ack, timeout, network_down, network_restored\}$
- $q_0 = Idle$
- $F = \{Delivered, Failed, Persisted\}$

**Matriz de Transição:**

| Estado Atual | Evento | Guarda | Ação | Próximo Estado |
|--------------|--------|--------|------|----------------|
| Idle | `trigger` | - | Iniciar GPS, timer 5s | Geolocating |
| Geolocating | `gps_ready` | - | Construir payload MQTT | Publishing |
| Geolocating | `timeout` | GPS indisponível | Usar última posição conhecida | Publishing |
| Publishing | `publish` | Rede disponível | Enviar via MQTT QoS 1 | AwaitingACK |
| Publishing | `network_down` | SocketException | Persistir no `sqflite` com retry | Persisted |
| AwaitingACK | `ack` | - | Notificar UI, registrar telemetria | Delivered |
| AwaitingACK | `timeout` | 3 retries | Incrementar contagem | Publishing |
| Persisted | `network_restored` | Fila não vazia | Iniciar sincronização em background | Publishing |

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Geolocating : trigger
    Geolocating --> Publishing : gps_ready
    Geolocating --> Publishing : timeout (5s)
    
    Publishing --> AwaitingACK : publish (rede ok)
    Publishing --> Persisted : network_down
    
    AwaitingACK --> Delivered : ack_received
    AwaitingACK --> Publishing : timeout (3 retries)
    
    Persisted --> Publishing : network_restored
    
    Delivered --> [*]
    Persisted --> [*] : atendido offline
```

#### 2.3.2 FSM - Sincronização Offline-First (Núcleo Crítico)

**Definição Formal:** $A_{Sync} = (Q, \Sigma, \delta, q_0, F)$

- $Q = \{Idle, LocalWrite, Queued, Syncing, Conflict, Synced, Error\}$
- $\Sigma = \{save, enqueue, network_up, network_down, sync_start, sync_ack, conflict, sync_ok, sync_error\}$
- $q_0 = Idle$
- $F = \{Synced, Conflict, Error\}$

**Invariantes da FSM:**

| Invariante | Expressão Lógica | Verificação |
|------------|------------------|-------------|
| **Vivacidade** | $\neg (Q_{Syncing} \land \text{timeout} = \infty)$ | Timeout máximo de 30s |
| **Segurança** | $Q_{Syncing} \implies \text{versão\_local} = \text{versão\_central}$ | Verificação hash SHA-256 |
| **Fairness** | $Q_{Queued} \land \text{rede\_ativa} \implies \Diamond Q_{Syncing}$ | Garantia de saída eventual |

```mermaid
stateDiagram-v2
    [*] --> Idle
    
    Idle --> LocalWrite : save (offline)
    Idle --> Syncing : save (online)
    
    LocalWrite --> Queued : persistido em sqflite
    Queued --> Syncing : network_up
    
    Syncing --> Synced : sync_ok
    Syncing --> Conflict : sync_conflict
    Syncing --> Error : sync_error
    
    Conflict --> [*] : resolução manual
    Synced --> [*]
    Error --> Idle : retry
```

**Estratégias de Recuperação:**

| Estado de Erro | Estratégia | Ação |
|----------------|------------|------|
| **Conflict** | Resolução Manual | UI informa ACS sobre conflito; compara versões; ACS decide qual prevalece ou gera nova versão |
| **Error** | Exponential Backoff | Retry com intervalo: 1s, 2s, 4s, 8s, 16s (máx 5 tentativas) + jitter randômico |
| **Network Down** | Persistência Local | Armazenamento em `sqflite` com flag `pending_sync`; sincronização na próxima conectividade |

#### 2.3.3 FSM - Dashboard de Priorização do ACS

**Definição Formal:** $A_{Dashboard} = (Q, \Sigma, \delta, q_0, F)$

- $Q = \{Loading, Prioritizing, Displaying, Refreshing, Filtering\}$
- $\Sigma = \{load, recalc, display, refresh, filter\}$
- $q_0 = Loading$
- $F = \{Displaying, Refreshing\}$

**Regra de Priorização (Algoritmo de Ordenação):**

```
Score(patient) = 
    (risk_weight × 10) + 
    (chronic_condition_weight × 5) + 
    (time_since_last_visit × 2) +
    (proximity_to_current_location × 3)

Onde:
    risk_weight: Vermelho=10, Amarelo=5, Verde=1
    chronic_condition_weight: 0-3 (soma de crônicos)
    time_since_last_visit: dias desde última visita (cap em 30)
    proximity: 1 - (distancia_km / 10) (cap em 0)
```

---

## 3. Arquitetura de Dados e Integridade

### 3.1 Modelo de Dados Conceitual

```mermaid
erDiagram
    USER {
        uuid id PK
        string cpf_hash "SHA-256 do CPF"
        string name
        date birth_date
        string role "PATIENT | ACS | ADMIN"
        string micro_area_id FK "FK para MicroArea"
        timestamp created_at
        timestamp updated_at
    }
    
    PATIENT {
        uuid user_id PK, FK "FK para User"
        string emergency_contact
        boolean is_chronic
        json chronic_conditions "['diabetes','hipertensao']"
        string last_location_hash
        timestamp last_triage_at
    }
    
    ACS {
        uuid user_id PK, FK "FK para User"
        string enrollment_id
        string ubs_id FK "FK para UBS"
        boolean active
        timestamp last_sync_at
    }
    
    MICRO_AREA {
        uuid id PK
        string name
        string ubs_id FK
        json geojson_boundary
    }
    
    UBS {
        uuid id PK
        string name
        string address
        string city
        string state
    }
    
    VISIT {
        uuid id PK
        uuid patient_id FK
        uuid acs_id FK
        timestamp scheduled_at
        timestamp started_at
        timestamp completed_at
        string status "SCHEDULED | IN_PROGRESS | COMPLETED"
        string risk_level_before "VERMELHO | AMARELO | VERDE"
        string risk_level_after
        json notes
        string sync_status "PENDING | SYNCED | CONFLICT"
        uuid local_id "ID no dispositivo"
        timestamp sync_at
        uuid version "Controle de concorrência"
    }
    
    ALERT {
        uuid id PK
        uuid patient_id FK
        uuid acs_id FK "Quem respondeu (null se não respondido)"
        timestamp triggered_at
        timestamp received_at
        timestamp responded_at
        string risk_level
        string location_hash
        string status "PENDING | ACKNOWLEDGED | RESOLVED | ESCALATED"
        string mqtt_topic
        string device_id
        integer retry_count
    }
    
    TRIAGE_SESSION {
        uuid id PK
        uuid patient_id FK
        json answers "Array de respostas do formulário"
        string result_risk "VERMELHO | AMARELO | VERDE"
        string result_display "Descrição textual"
        timestamp created_at
        string device_id
    }
    
    CONSENT_LOG {
        uuid id PK
        uuid user_id FK
        string purpose
        string action "GRANT | REVOKE | UPDATE"
        string version
        timestamp timestamp
        string ip_hash
        string user_agent
        string signature
    }
    
    AUDIT_LOG {
        uuid id PK
        uuid user_id FK
        string action_type
        string resource_type
        uuid resource_id
        timestamp timestamp
        string ip_hash
        string result "SUCCESS | FAILURE | DENIED"
    }
    
    USER ||--o{ PATIENT : is
    USER ||--o{ ACS : is
    USER ||--o{ CONSENT_LOG : has
    USER ||--o{ AUDIT_LOG : generates
    PATIENT ||--o{ VISIT : receives
    ACS ||--o{ VISIT : performs
    PATIENT ||--o{ ALERT : triggers
    ACS ||--o{ ALERT : responds_to
    PATIENT ||--o{ TRIAGE_SESSION : completes
    MICRO_AREA ||--o{ USER : contains
    MICRO_AREA }o--|| UBS : belongs_to
    UBS ||--o{ ACS : employs
    UBS ||--o{ MICRO_AREA : has
```

### 3.2 Estratégia de Persistência

| Módulo | Tecnologia | Justificativa |
|--------|------------|---------------|
| **Dados Transacionais** | PostgreSQL (ACID) | Necessidade de consistência forte, transações, integridade referencial (FKs), e SSOT para dados clínicos |
| **Cache Local (ACS)** | `sqflite` (SQLite) | Leveza, embarcado no Flutter, suporte a queries SQL complexas, operação offline-first |
| **Cache Local (Paciente)** | `sqflite` (SQLite) | Simplicidade, armazenamento de triagens e alertas pendentes, baixo consumo de bateria |
| **Mensageria** | Mosquitto (MQTT) | Protocolo leve, QoS nativo, ideal para IoT/baixa latência, suporte a WebSockets |
| **Logs e Telemetria** | PostgreSQL + TimescaleDB | Dados temporais estruturados para análise de desempenho e auditoria |

**Justificativa da Escolha Relacional (PostgreSQL + SQLite):**

1. **Estrutura de Triagem:** A matriz de triagem é fechada e estruturada (Manchester), adequada para schemas relacionais fixos.
2. **Integridade Referencial:** Necessidade crítica de FK entre `VISIT` ↔ `PATIENT` ↔ `ACS`.
3. **Transações ACID:** Operações como "registrar visita + atualizar status do paciente" devem ser atômicas.
4. **Queries Complexas:** O dashboard do ACS requer joins e ordenações complexas.

### 3.3 Evolução de Schema (Migrações Sem Downtime)

**Estratégia:** Migrações Blue-Green com Versionamento Semântico.

```
├── migrations/
│   ├── v1.0.0/
│   │   ├── 01_initial_schema.sql
│   │   └── 02_consent_logs.sql
│   ├── v1.1.0/
│   │   ├── 01_add_visits_risk_after.sql (ADD COLUMN, NOT NULL DEFAULT)
│   │   └── 02_create_alert_table.sql
│   └── v1.2.0/
│       ├── 01_rename_micro_area_to_territory.sql
│       └── 02_migrate_data_territory.sql
└── rollback/
    ├── v1.1.0_rollback.sql
    └── v1.2.0_rollback.sql
```

**Políticas de Migração:**

| Tipo de Mudança | Estratégia | Exemplo |
|-----------------|------------|---------|
| ADD COLUMN (NULLABLE) | Sem downtime | `ALTER TABLE visits ADD COLUMN risk_after TEXT NULL` |
| ADD COLUMN (NOT NULL) | 3 fases: ADD NULLABLE → Populate → ALTER NOT NULL | `ALTER TABLE visits ADD COLUMN risk_after TEXT NULL` → `UPDATE visits SET risk_after = risk_before` → `ALTER TABLE visits ALTER COLUMN risk_after SET NOT NULL` |
| RENAME TABLE | Criar nova tabela, migrar, renomear antiga | Fase 1: Criar `visits_v2`; Fase 2: Trigger de sync; Fase 3: Swap |
| DROP COLUMN | Marcar como deprecated por 1 versão | `ALTER TABLE visits DROP COLUMN old_field` (apenas após verificação) |

### 3.4 Sincronização e Concorrência

**Estratégia de Versionamento Otimista:**

Cada registro possui um campo `version` (inteiro incremental). No momento da sincronização:

```
1. Cliente envia: { id, data, version: 5 }
2. Servidor verifica: SELECT version FROM visits WHERE id = ?
3. Se version(servidor) == 5 → UPDATE SET data = ?, version = 6 WHERE id = ? AND version = 5
4. Se version(servidor) != 5 → Retorna 409 Conflict com dados atuais
5. Cliente resolve conflict (UI ou automático baseado em timestamp)
```

**Idempotência em Operações:**

| Operação | Estratégia de Idempotência |
|----------|---------------------------|
| **Registro de Visita** | UUID local + hash do payload; servidor deduplica por `local_id` |
| **Alerta MQTT** | UUID no payload; ACS ignora duplicatas (verifica `alert_id` processado) |
| **Sincronização** | `sync_token` sequencial; servidor rejeita tokens menores que o último processado |

**Sincronização Bidirecional (FSM detalhada):**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CICLO DE SINCRONIZAÇÃO COMPLETO                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   DISPOSITIVO (OFFLINE)          ──┐    SERVIDOR (ONLINE)              │
│                                      │                                  │
│   1. Operação Local                   │   2. Fila de Pendentes          │
│      ┌──────────────────┐            │      ┌──────────────────┐       │
│      │ INSERT INTO       │            │      │ SELECT * FROM    │       │
│      │ visits (local)    │────────────│─────▶│ sync_queue       │       │
│      │ status=PENDING    │            │      │ WHERE status=0   │       │
│      └──────────────────┘            │      └──────────────────┘       │
│                                      │                                  │
│   3. Rede Restaurada                  │   4. Envio Batch                │
│      ┌──────────────────┐            │      ┌──────────────────┐       │
│      │ connectivity_plus│            │      │ POST /api/sync   │       │
│      │ event triggered  │────────────│─────▶│ payload: [ ... ] │       │
│      └──────────────────┘            │      └──────────────────┘       │
│                                      │                                  │
│   5. Resposta do Servidor           │   6. Processamento               │
│      ┌──────────────────┐            │      ┌──────────────────┐       │
│      │ 200 OK (Synced)  │◀───────────│──────┤ 409 Conflict     │       │
│      │ 409 Conflict     │            │      │ 201 Created      │       │
│      └──────────────────┘            │      └──────────────────┘       │
│                                      │                                  │
│   7. Resolução (se conflict)         │   8. Atualização Local          │
│      ┌──────────────────┐            │      ┌──────────────────┐       │
│      │ UI: Escolher versão│           │      │ UPDATE visits    │       │
│      │ Or merge automático│           │      │ SET sync_status=1│       │
│      └──────────────────┘            │      └──────────────────┘       │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Requisitos Não Funcionais e Segurança (Baseline)

### 4.1 Performance & Latência (SLOs)

| Endpoint/Operação | SLO (p95) | Critério de Falha | Estratégia de Mitigação |
|-------------------|-----------|-------------------|-------------------------|
| Autenticação (Login) | < 1s | > 2s | Cache JWT, MFA via TOTP |
| Alerta MQTT (Publish → ACK) | < 500ms | > 1s | QoS 1 + sessões persistentes |
| Dashboard ACS (Carregamento) | < 1.5s | > 3s | Cache `sqflite` + paginação (20 itens) |
| Registro de Visita (Offline) | < 200ms | > 500ms | Inserção local, sem IO de rede |
| Sincronização Batch (50 itens) | < 5s | > 15s | Compression gzip + batch |
| Mapa Interativo (Renderização) | < 2s | > 4s | Clusterização de pinos (50+ pacientes) |
| Triagem (Cálculo) | < 50ms | > 100ms | Algoritmo em Dart puro, sem IO |

**Capacity Planning (MVP):**

| Métrica | Valor Estimado | Justificativa |
|---------|----------------|---------------|
| Usuários Ativos (Pacientes) | 5.000 | 2 UBS × 2.500 pacientes |
| Usuários Ativos (ACS) | 100 | 2 UBS × 50 ACS |
| Alertas por dia | 50 | 5% dos pacientes ativos/mês |
| Visitas por dia | 500 | Média de 5 visitas/ACS/dia |
| Conexões MQTT Simultâneas | 150 | Todos os ACS + pacientes online |
| Armazenamento PostgreSQL | 50 GB | 365 dias de logs + histórico |

### 4.2 Segurança por Design

#### 4.2.1 Modelo de Ameaças Simplificado (STRIDE)

| Ameaça | Descrição | Mitigação |
|--------|-----------|-----------|
| **Spoofing** | Injeção de mensagens falsas no MQTT | Autenticação MQTT via certificados TLS; ACLs por tópico |
| **Tampering** | Alteração de dados de triagem no dispositivo | Assinatura digital dos dados; integridade via hash SHA-256 |
| **Repudiation** | ACS nega ter registrado visita | Logs imutáveis (append-only) com timestamp e assinatura |
| **Information Disclosure** | Vazamento de PII no dispositivo | SQLCipher (AES-256) para `sqflite` |
| **Denial of Service** | Ataque de inundação MQTT | Rate limiting no Mosquitto; firewall no Edge Gateway |
| **Elevation of Privilege** | ACS acessa dados de outra microárea | RBAC rigoroso no Serverpod; verificação em todas as queries |

#### 4.2.2 Gestão de Identidade (RBAC/ABAC)

**Matriz de Permissões:**

| Recurso | Paciente | ACS (Microárea) | Coordenador (UBS) | Administrador (Sistema) |
|---------|----------|-----------------|-------------------|------------------------|
| Próprios dados | R/W | - | - | R (auditado) |
| Dados da Microárea | - | R/W | R | R |
| Dados de outras microáreas | - | - | R (justificado) | R (auditado) |
| Alertas da Microárea | - | R (tempo real) | R | R |
| Histórico de visitas | R | R (próprias) | R (UBS) | R |
| Configurações de sistema | - | - | - | R/W |
| Logs de auditoria | R (próprios) | - | R (UBS) | R/W |

**Política ABAC (Atribute-Based Access Control):**

```dart
// Exemplo de verificação no Serverpod
Future<bool> canAccessPatient(Session session, String patientId) async {
  final user = await session.auth.getUser();
  switch (user.role) {
    case 'PATIENT':
      return user.id == patientId;
    case 'ACS':
      final patient = await db.patient.findUnique(patientId);
      return patient.microAreaId == user.microAreaId;
    case 'COORDINATOR':
      final patient = await db.patient.findUnique(patientId);
      final acs = await db.acs.findUnique(user.id);
      return patient.ubsId == acs.ubsId;
    case 'ADMIN':
      return true;
    default:
      return false;
  }
}
```

#### 4.2.3 Criptografia em Repouso e em Trânsito

| Camada | Tecnologia | Chave | Justificativa |
|--------|------------|-------|---------------|
| **App Flutter (Local)** | SQLCipher (AES-256-GCM) | Chave derivada do PIN/Biometria (PBKDF2) | Proteção contra acesso físico ao dispositivo |
| **App Flutter (Cache)** | SQLCipher | Chave rotativa (mudança de dispositivo) | Dados sensíveis em repouso |
| **Comunicação App ↔ Traefik** | TLS 1.3 | Certificado Let's Encrypt (auto-renovável) | Proteção contra MITM |
| **Comunicação Traefik ↔ Serverpod** | TLS 1.3 | Certificado interno (mTLS) | Segurança na rede interna |
| **PostgreSQL (SSOT)** | pgcrypto (AES-256) | Chave gerenciada por Vault/HashiCorp | Proteção contra acesso ao banco |
| **Logs de Auditoria** | Assinatura Hash Chain | - | Integridade e não-repúdio |

#### 4.2.4 Conformidade LGPD (Resumo)

**Requisitos Críticos (ver documento completo `lgpd_design.md`):**

| ID | Requisito | Implementação Técnica |
|----|-----------|----------------------|
| LGPD-RF01 | Coleta Mínima | Checklist de dados por funcionalidade |
| LGPD-RF02 | Consentimento Granular | Checkboxes independentes no onboarding |
| LGPD-RF09 | Proteção de Dados Sensíveis | SQLCipher + pgcrypto + RBAC |
| LGPD-RF11 | Controle de Acesso RBAC | Matriz de permissões (acima) |
| LGPD-RF07 | Retenção e Exclusão | Política de retenção + job de expurgo |
| LGPD-RF08 | Direitos do Titular | Painel "Meus Dados" + exportação JSON |

### 4.3 Acessibilidade e UX Técnica

**Baseline WCAG 2.1 Nível AA:**

| Critério | Requisito | Implementação |
|----------|-----------|---------------|
| **1.4.3 Contraste (Mínimo)** | Razão de contraste ≥ 4.5:1 | `flutter_test` com `accessibility_test` verifica contraste automático |
| **1.4.11 Contraste Não Textual** | Elementos UI com contraste ≥ 3:1 | Validação visual nos Golden Tests |
| **2.5.1 Gestos de Toque** | Botões mín. 44x44 dp | Alvos de toque ≥ 48x48 dp (WCAG recomenda 44x44) |
| **2.5.6 Área de Clique** | Botão de pânico ≥ 60x60 dp | Área de toque ampliada (mínimo 60x60 para emergências) |
| **2.4.7 Foco Visível** | Indicador de foco claro | `FocusNode` com outline personalizado |
| **3.3.2 Rótulos/Instruções** | Campos com label associado | `Semantics` no Flutter para leitores de tela |

**Performance de Interface (Core Web Vitals adaptados para Mobile):**

| Métrica | Alvo | Critério |
|---------|------|----------|
| **LCP (Largest Contentful Paint)** | < 1.5s | Primeiro frame visível do dashboard |
| **FID (First Input Delay)** | < 100ms | Resposta ao toque no botão de pânico |
| **CLS (Cumulative Layout Shift)** | < 0.1 | Layout estável durante carregamento |

---

## 5. Estratégia de Desenvolvimento e DX

### 5.1 Ambiente de Desenvolvimento

**Requisitos para Reprodutibilidade (DevContainers):**

```yaml
# .devcontainer/devcontainer.json
{
  "name": "SinalACS Dev",
  "dockerComposeFile": "../docker-compose.dev.yml",
  "service": "dev",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/flutter:1": {}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "dart-code.flutter",
        "ms-azuretools.vscode-docker",
        "eamodio.gitlens",
        "github.copilot"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "zsh",
        "dart.flutterSdkPath": "/usr/local/flutter"
      }
    }
  }
}
```

**docker-compose.dev.yml (recorte):**

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: dev_user
      POSTGRES_PASSWORD: dev_password
      POSTGRES_DB: sinalacs_dev
    ports:
      - "5432:5432"
    volumes:
      - ./db/seed:/docker-entrypoint-initdb.d

  mosquitto:
    image: eclipse-mosquitto:2
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto-dev.conf:/mosquitto/config/mosquitto.conf

  serverpod:
    build:
      context: ./backend
      dockerfile: Dockerfile.dev
    depends_on:
      - postgres
      - mosquitto
    ports:
      - "8080:8080"
    volumes:
      - ./backend:/app
    environment:
      DATABASE_URL: postgresql://dev_user:dev_password@postgres:5432/sinalacs_dev
      MQTT_BROKER: mosquitto:1883

  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8081:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

**Local LLMs para Suporte (Ollama):**

Para auxílio no desenvolvimento de código e testes de regressão:

```bash
# Setup do Ollama local (opcional, para devs que desejam assistência)
ollama pull codellama:7b-instruct
ollama pull deepseek-coder:6.7b-instruct
```

### 5.2 Contratos de Interface

**Padrões de Comunicação:**

| Contexto | Protocolo | Justificativa |
|----------|-----------|---------------|
| **App ↔ Serverpod** | REST (JSON) via HTTP/2 | Simplicidade, tipagem forte via Serverpod ORM |
| **App ↔ Mosquitto** | MQTT sobre WebSockets (WSS) | Baixa latência, QoS, suporte a redes instáveis |
| **Serverpod ↔ PostgreSQL** | PostgreSQL Wire Protocol (libpq) | ORM nativo do Serverpod |
| **Traefik ↔ Services** | gRPC (para Serverpod) + WebSockets (MQTT) | Performance, multiplexação |

**Versionamento de API:**

| Estratégia | Implementação |
|------------|---------------|
| **URL Versioning** | `/api/v1/visits` vs `/api/v2/visits` |
| **Header Versioning** | `Accept: application/vnd.sinalacs.v1+json` |
| **Deprecação** | `Deprecation: true` + `Sunset: Fri, 31 Dec 2027` |
| **Backward Compatibility** | Novos campos são opcionais (nullable) |

**Exemplo de Contrato REST (Serverpod):**

```dart
// backend/lib/src/models/visit.dart
class Visit extends Table {
  @Id()
  int? id;
  
  @Column()
  String patientId;
  
  @Column()
  String acsId;
  
  @Column()
  DateTime scheduledAt;
  
  @Column()
  DateTime? startedAt;
  
  @Column()
  DateTime? completedAt;
  
  @Column()
  String status; // SCHEDULED | IN_PROGRESS | COMPLETED
  
  @Column()
  String riskLevelBefore;
  
  @Column()
  String? riskLevelAfter;
  
  @Column()
  @JsonKey(name: 'syncStatus')
  String syncStatus; // PENDING | SYNCED | CONFLICT
  
  @Column()
  @Version()
  int version;
}
```

**Contrato AsyncAPI para MQTT:**

```yaml
# asyncapi.yaml
asyncapi: 2.6.0
info:
  title: SinalACS MQTT API
  version: 1.0.0
channels:
  /alerts/{micro_area_id}:
    subscribe:
      summary: "Alerta de urgência enviado por paciente"
      message:
        payload:
          type: object
          properties:
            alert_id:
              type: string
              format: uuid
            patient_id:
              type: string
              format: uuid
            risk_level:
              type: string
              enum: ["VERMELHO", "AMARELO"]
            location:
              type: object
              properties:
                lat:
                  type: number
                  format: float
                lng:
                  type: number
                  format: float
            timestamp:
              type: string
              format: date-time
            device_id:
              type: string
          required: [alert_id, patient_id, risk_level, location, timestamp]
```

### 5.3 Testabilidade

**Distribuição do Esforço de Testes (Pirâmide Invertida para Offline-First):**

| Camada | Cobertura Alvo | Foco Principal | Ferramentas |
|--------|----------------|----------------|-------------|
| **Unitários** | 70% | Motor de Triagem (MCDC), FSM de Sincronização, Modelos | `flutter_test`, `mockito`, `bloc_test` |
| **Integração** | 20% | `sqflite` ↔ Serverpod ORM, MQTT Pub/Sub, Concorrência | Testcontainers, Toxiproxy |
| **E2E (Ponta-a-Ponta)** | 10% | Caminho Crítico: Alerta → Dashboard → Visita | `integration_test`, App Actions |

**Testes de Unidade (FSM):**

```dart
// test/domain/sync_fsm_test.dart
void main() {
  group('Sync FSM - Offline-First', () {
    test('Deve transitar para LocalWrite quando offline', () {
      final fsm = SyncFSM.initial();
      fsm.trigger(SyncEvent.save, context: {'network': false});
      
      expect(fsm.state, SyncState.localWrite);
      expect(fsm.localQueue.length, 1);
    });
    
    test('Deve transitar para Syncing e depois Synced quando online', () async {
      final fsm = SyncFSM.initial();
      fsm.trigger(SyncEvent.save, context: {'network': true});
      await fsm.trigger(SyncEvent.syncStart);
      await fsm.trigger(SyncEvent.syncAck);
      
      expect(fsm.state, SyncState.synced);
    });
    
    test('Deve transitar para Conflict quando versão diverge', () {
      final fsm = SyncFSM.initial();
      fsm.trigger(SyncEvent.save, context: {'network': false});
      fsm.trigger(SyncEvent.syncStart);
      fsm.trigger(SyncEvent.syncConflict); // 409 Conflict
      
      expect(fsm.state, SyncState.conflict);
    });
  });
}
```

**Testes de Integração com Testcontainers:**

```dart
// test/integration/serverpod_sync_test.dart
void main() {
  late PostgreSQLContainer postgres;
  late MQTTServer mosquitto;
  
  setUpAll(() async {
    postgres = await PostgreSQLContainer.start();
    mosquitto = await MQTTServer.start();
  });
  
  test('Deve sincronizar visita offline quando rede restaurada', () async {
    // Simula visita offline
    final visit = Visit(
      patientId: 'p1',
      acsId: 'acs1',
      scheduledAt: DateTime.now(),
      status: 'SCHEDULED',
    );
    
    await LocalDatabase.instance.insertVisit(visit);
    expect(LocalDatabase.instance.pendingCount, 1);
    
    // Simula restauração de rede
    await NetworkSimulator.restore();
    await SyncEngine.instance.syncAll();
    
    // Verifica no PostgreSQL
    final syncedVisits = await ServerpodClient.instance.visits.findMany();
    expect(syncedVisits.length, 1);
    expect(syncedVisits.first.status, 'SCHEDULED');
  });
}
```

**Testes E2E com App Actions (Substituindo Page Objects):**

```dart
// test/e2e/alert_flow_test.dart
void main() {
  testWidgets('Fluxo completo: Alerta até Dashboard', (tester) async {
    // Usa App Actions para simular estado (evita navegação frágil)
    await tester.pumpApp(
      overrides: [
        authProvider.overrideWith(() => mockPatientAuth),
        mqttProvider.overrideWith(() => mockMqttClient),
        locationProvider.overrideWith(() => mockLocation),
      ],
    );
    
    // Ação: Acionar botão de pânico
    await tester.tap(find.byKey(Key('panic_button')));
    await tester.pumpAndSettle();
    
    // Verifica: Estado de "enviando"
    expect(find.text('Enviando alerta...'), findsOneWidget);
    
    // Verifica: MQTT publish foi chamado
    verify(mockMqttClient.publish(
      topic: '/alerts/microarea1',
      payload: any,
      qos: 1,
    )).called(1);
    
    // Simula ACK do MQTT
    mockMqttClient.acknowledge();
    await tester.pumpAndSettle();
    
    // Verifica: Status "Alerta enviado com sucesso"
    expect(find.text('Alerta enviado para sua equipe'), findsOneWidget);
  });
}
```

---

## 6. Roadmap de Entrega e Mitigação

### 6.1 Definição de MVP (v1.0)

**Núcleo Duro que Prova a Hipótese:**

| Componente | Feature | Critério de Pronto |
|------------|---------|--------------------|
| **App Paciente** | Login Passwordless (CPF + SMS OTP) | 10 pacientes conseguem logar em < 60s |
| **App Paciente** | Botão de Alerta de Urgência | Alerta chega ao ACS em < 2s (MQTT QoS 1) |
| **App Paciente** | Formulário de Triagem (3 perguntas) | Classificação determinística (Vermelho/Amarelo/Verde) |
| **App Paciente** | Painel de Status | Paciente visualiza "Enviado → Visualizado → Atendido" |
| **App ACS** | Login Institucional | ACS loga com matrícula e senha |
| **App ACS** | Territorialização (Download Microárea) | ACS carrega dados da sua microárea em < 30s |
| **App ACS** | Dashboard Dinâmico (Priorização) | Lista ordenada: Vermelho → Amarelo → Verde |
| **App ACS** | Registro Básico de Visitas (Offline) | Registro salvo localmente e sincronizado em background |
| **Infra** | MQTT Broker (Mosquitto) | 100 dispositivos simultâneos, latência < 500ms |
| **Infra** | PostgreSQL + Serverpod | Migração automática via ORM, logs estruturados |

**Fora do Escopo MVP (v1.5+):**
- Mapa Interativo (Google Maps)
- Geofencing (Check-in passivo)
- Avisos Segmentados (Push)
- Mensageria Assíncrona (Tickets)
- Integração SAMU (escalonamento automático)

### 6.2 Milestones Técnicos

#### Fase 1: Proof of Concept (Semanas 1-3)

| Milestone | Entregável | Critério de Aceite |
|-----------|------------|-------------------|
| M1.1 | Docker-Compose local (Stack completa) | `docker-compose up` sobe PostgreSQL, Mosquitto, Serverpod, Traefik |
| M1.2 | CI Pipeline básica | `flutter test` + `dart analyze` rodam no GitHub Actions |
| M1.3 | Motor de Triagem (algoritmo) | Cobertura 100% MCDC; classifica 50 cenários de teste |
| M1.4 | FSM de Sincronização | Testes unitários validam transições, conflitos e erros |
| M1.5 | SQLCipher (local) | Dados do `sqflite` são criptografados (AES-256) |

#### Fase 2: Alpha/Beta (Semanas 4-8)

| Milestone | Entregável | Critério de Aceite |
|-----------|------------|-------------------|
| M2.1 | App Paciente - MVP | Login + Alerta + Triagem + Status |
| M2.2 | App ACS - MVP | Login + Territorialização + Dashboard + Registro |
| M2.3 | MQTT com TLS | Conexão segura via WebSockets (WSS) |
| M2.4 | Sincronização Offline-First | 100 registros offline sincronizam em < 5s após rede |
| M2.5 | Testes de Caos (Toxiproxy) | Simulação de latência, jitter, e particionamento de rede |
| M2.6 | Testes de Usabilidade | 5 ACS e 10 pacientes testam em campo (Beta fechado) |

#### Fase 3: General Availability (Semanas 9-12)

| Milestone | Entregável | Critério de Aceite |
|-----------|------------|-------------------|
| M3.1 | Deploy em Produção (Pulumi) | Infraestrutura imutável provisionada em VPS |
| M3.2 | Monitoramento (OpenTelemetry) | Traces e métricas em produção (Prometheus/Grafana) |
| M3.3 | Testes de Carga | 100 ACS simultâneos, 500 alertas/hora |
| M3.4 | LGPD Compliance | Documentação de privacidade + painel de consentimento |
| M3.5 | Lançamento Oficial v1.0 | 1 UBS piloto (2 microáreas, 50 pacientes) |

### 6.3 Matriz de Riscos

| Risco | Impacto (1-5) | Probabilidade (1-5) | Estratégia de Contingência | Dependência |
|-------|---------------|---------------------|----------------------------|-------------|
| **R1: Colisão de Sincronização** | 5 | 4 | UI de resolução manual + comparação de versões; migrar para CRDTs na v1.5 | Equipe Backend |
| **R2: Falha no MQTT em rede 3G** | 5 | 3 | Fallback para HTTP + retry com backoff; persistência em `sqflite` | Equipe Mobile |
| **R3: Vazamento de PII no dispositivo** | 5 | 2 | SQLCipher + chave derivada de biometria; remote wipe via API | Segurança |
| **R4: Rejeição do ACS (baixa adesão)** | 4 | 3 | Treinamento intensivo + UX simplificada + feedback constante | Product, UBS |
| **R5: Performance do PostgreSQL** | 4 | 3 | Índices otimizados + particionamento por microárea | DevOps |
| **R6: Dependência de SMS Gateway** | 3 | 4 | Fallback para QR Code + biometria; múltiplos providers (Twilio, Zenvia) | PM, Parceiros |
| **R7: Mudanças regulatórias (LGPD)** | 4 | 2 | Comitê de compliance + revisão semestral + DPO dedicado | Jurídico |
| **R8: SPOF no Traefik** | 5 | 2 | Implantação de 2 instâncias + DNS Round-Robin; failover manual | DevOps |

**Matriz de Risco (Visual):**

```
Impacto ↑
  │
5 │  R1 (Sync)  R2 (MQTT)  R8 (Traefik)
  │  R7 (LGPD)  R4 (Adesão) R3 (PII)
4 │  R5 (DB)
  │  R6 (SMS)
3 │
  │
  └─────────────────────────────────→ Probabilidade
     1    2    3    4    5
```

**Planos de Contingência Detalhados:**

| Risco | Plano de Contingência | Tempo de Recuperação | Responsável |
|-------|----------------------|----------------------|-------------|
| **R1 (Colisão)** | 1. ACS resolve via UI (comparação lado a lado) <br>2. Se frequente, migrar para CRDTs | 4h (UI), 2 semanas (CRDTs) | Tech Lead |
| **R2 (MQTT)** | 1. Fallback para REST API <br>2. Buffer local com retry exponencial | 1h | Mobile Lead |
| **R3 (PII)** | 1. Remote wipe via API <br>2. Rotação de chaves imediata | 15 min | Security Lead |
| **R4 (Adesão)** | 1. Pesquisa de NPS semanal <br>2. Iteração rápida (sprints de 1 semana) | Contínuo | Product |
| **R8 (Traefik)** | 1. IP flutuante para segunda instância <br>2. Script de failover manual | 5 min | DevOps |

---

## 7. Trade-off Analysis

### T1: SQL vs NoSQL para Dados de Saúde

| Aspecto | Opção A: PostgreSQL | Opção B: MongoDB | Decisão |
|---------|---------------------|------------------|---------|
| **Schema** | Rígido, define constraints | Flexível, sem constraints | **A** - Estrutura de triagem é fixa e conhecida |
| **Integridade Referencial** | FK nativas | Sem suporte nativo | **A** - Crítico para `PATIENT` ↔ `VISIT` |
| **Transações ACID** | Suporte completo | Suporte limitado | **A** - Registro de visita é transacional |
| **Consultas Complexas** | Joins otimizados | Aggregation mais lenta | **A** - Dashboard requer joins |
| **Escalabilidade** | Vertical (máx 100k pacientes) | Horizontal (sharding) | **B** - MVP não escala horizontalmente |
| **Isomorfismo Dart** | Serverpod ORM nativo | Driver não oficial | **A** - Menos código boilerplate |

**Decisão:** **PostgreSQL**. A necessidade de integridade referencial e consistência ACID supera a flexibilidade do NoSQL. O volume de dados (5k pacientes, 500 visitas/dia) é perfeitamente atendido por um banco relacional.

---

### T2: Sincronização Customizada vs PowerSync

| Aspecto | Opção A: Custom (`sqflite` + FSM) | Opção B: PowerSync | Decisão |
|---------|-----------------------------------|-------------------|---------|
| **Vendor Lock-in** | Nenhum | Alto (API proprietária) | **A** - Evita dependência crítica |
| **Custo Inicial** | Baixo (apenas engenharia) | Médio (licenciamento) | **A** - MVP com orçamento limitado |
| **Custo de Manutenção** | Alto (time dedicado) | Baixo (manutenção pelo fornecedor) | **B** - Longo prazo |
| **Complexidade de Conflito** | Alta (manual) | Baixa (CRDTs automatic) | **B** - Conflitos são raros no MVP |
| **Performance** | Otimizável manualmente | Otimizada pelo fornecedor | **A** - Temos controle total |
| **Migração Futura** | Difícil (engenharia pesada) | Fácil (troca de provider) | **B** - Mas PowerSync não é garantido |

**Decisão:** **Custom (Opção A)** para MVP. O risco de conflitos é mitigado pela UI de resolução manual. A longo prazo, planejamos migrar para CRDTs (v1.5) ou PowerSync (v2.0) se o volume de conflitos justificar.

---

### T3: Flutter + Serverpod vs React Native + Node.js

| Aspecto | Opção A: Flutter + Serverpod | Opção B: React Native + Node.js | Decisão |
|---------|------------------------------|----------------------------------|---------|
| **Type Safety** | 100% (Dart isomórfico) | Parcial (TypeScript) | **A** - Elimina bugs de contrato |
| **Offline-First** | `sqflite` + `connectivity_plus` | `realm` + `realm-graphql` | **A** - Mais maduro no ecossistema Flutter |
| **MQTT** | `mqtt_client` (maduro) | `mqtt` (maduro) | Empate |
| **Time de Desenvolvimento** | Alta (Dart nativo) | Média (JS + TS) | **A** - Escopo do projeto permite especialização |
| **Comunidade** | Crescente | Gigantesca | **B** - Mais suporte na comunidade JS |
| **Performance (UI)** | Melhor (renderização nativa) | Boa (bridge JS ↔ Native) | **A** - App precisará de alta performance para mapas |

**Decisão:** **Flutter + Serverpod**. A homogeneidade da linguagem é crítica para a estratégia offline-first e a garantia de contratos entre frontend e backend.

---

### T4: MQTT vs WebSockets + REST

| Aspecto | Opção A: MQTT | Opção B: WebSockets + REST | Decisão |
|---------|---------------|----------------------------|---------|
| **Latência** | Muito Baixa (< 100ms) | Baixa (> 200ms) | **A** - Alertas de urgência exigem < 500ms |
| **QoS** | Nativas (0, 1, 2) | Não nativas | **A** - QoS 1 garante entrega crítica |
| **Consumo de Bateria** | Extremamente Baixo | Médio (WebSocket mantido) | **A** - Dispositivos móveis com bateria limitada |
| **Complexidade de Setup** | Média (mosquitto + ACLs) | Baixa (HTTP/2) | **B** - Setup inicial mais complexo |
| **Firewall/NAT** | Suporte via WebSockets (WSS) | Suporte nativo | Empate (ambos usam WSS) |
| **Maturidade em IoT** | Alta (padrão M2M) | Média | **A** - Caso de uso clássico de IoT |

**Decisão:** **MQTT (Opção A)**. O benefício em latência e QoS é crítico para alertas de urgência. O Trade-off de complexidade é compensado pela confiabilidade.

---

### T5: Pulumi vs Terraform (IaC)

| Aspecto | Opção A: Pulumi (TypeScript) | Opção B: Terraform (HCL) | Decisão |
|---------|------------------------------|---------------------------|---------|
| **Curva de Aprendizado** | Baixa (TypeScript conhecido) | Média (HCL novo) | **A** - Time já conhece TS |
| **Testabilidade** | Testes unitários em TS | Testes com Terratest (Go) | **A** - Testes mais simples em TS |
| **Vendor Lock-in** | Baixo (multi-cloud) | Baixo (multi-cloud) | Empate |
| **Performance** | Rápida (Node.js) | Rápida (Go) | Empate |
| **Suporte a Estado** | Gerenciado pelo Pulumi | Gerenciado pelo Terraform | Empate |
| **Community** | Crescente | Madura (maior) | **B** - Mais exemplos em Terraform |

**Decisão:** **Pulumi (Opção A)**. A familiaridade com TypeScript acelera a curva de aprendizado e reduz erros na infraestrutura. O time é pequeno e precisa de agilidade.

---

## 8. Anexos Técnicos

### A1. Docker-Compose de Produção (recorte)

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./pg_hba.conf:/var/lib/postgresql/pg_hba.conf
    networks:
      - internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 3

  serverpod:
    image: ${REGISTRY}/sinalacs-backend:${VERSION}
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}
      MQTT_BROKER: mosquitto:1883
      JWT_SECRET: ${JWT_SECRET}
    networks:
      - internal
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s

  mosquitto:
    image: eclipse-mosquitto:2
    volumes:
      - ./mosquitto.prod.conf:/mosquitto/config/mosquitto.conf
      - ./certs:/mosquitto/certs
    networks:
      - internal
    ports:
      - "1883:1883"
      - "9001:9001"

  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.email=${LETSENCRYPT_EMAIL}"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/certs
    networks:
      - internal

networks:
  internal:
    driver: bridge

volumes:
  pg_data:
```

---

### A2. Script de Seeding para Testes

```dart
// test/helpers/seed_database.dart
class TestDataSeeder {
  static const microAreaId = 'micro-001';
  static const ubsId = 'ubs-001';
  
  static Future<void> seedPatientData() async {
    final patients = [
      Patient(
        id: 'p1',
        name: 'Maria Silva',
        cpfHash: sha256('123.456.789-00'),
        birthDate: DateTime(1950, 5, 15),
        chronicConditions: ['diabetes', 'hipertensao'],
        microAreaId: microAreaId,
      ),
      Patient(
        id: 'p2',
        name: 'João Santos',
        cpfHash: sha256('987.654.321-00'),
        birthDate: DateTime(1980, 12, 1),
        chronicConditions: ['asma'],
        microAreaId: microAreaId,
      ),
      // ... 48 pacientes adicionais
    ];
    
    await LocalDatabase.instance.patient.insertAll(patients);
  }
}
```

---

### A3. Configuração de Logs Estruturados (Fluentd)

```yaml
# fluentd.conf
<source>
  @type tail
  path /var/log/containers/*.log
  pos_file /var/log/fluentd-containers.log.pos
  tag kubernetes.*
  format json
</source>

<filter kubernetes.**>
  @type parser
  key_name log
  format json
  replace_invalid_sequence true
  reserve_data true
</filter>

<match **>
  @type elasticsearch
  host elasticsearch
  port 9200
  index_name sinalacs-logs-%Y.%m.%d
  include_timestamp true
  logstash_format true
</match>
```

---

### A4. Referências Técnicas

| Componente | Versão | Documentação |
|------------|--------|--------------|
| Flutter | 3.24.0 | https://flutter.dev/docs |
| Serverpod | 1.2.0 | https://docs.serverpod.dev |
| PostgreSQL | 15 | https://www.postgresql.org/docs/15/ |
| Mosquitto | 2.0 | https://mosquitto.org/documentation/ |
| SQLCipher | 4.5.0 | https://www.zetetic.net/sqlcipher/ |
| Pulumi | 3.100+ | https://www.pulumi.com/docs/ |
| OpenTelemetry | 1.25 | https://opentelemetry.io/docs/ |

---

**Próximos Passos:**

1. Revisão técnica do PRD com equipe de engenharia (Staff Engineer + Tech Leads)
2. Validação de custos (VPS, SMS, infraestrutura)
3. Sprint 0: Setup de DevContainers e CI Pipeline
4. Sprint 1: Motor de Triagem + FSM de Sincronização
5. Início do desenvolvimento em **DD/MM/YYYY** (estimativa)

---

*Documento elaborado sob os princípios de Privacy by Design e Security by Default, alinhado com a LGPD (Lei nº 13.709/2018).*
