# Auditoria de Dados e Conformidade LGPD - SinalACS

## 1. Inventário de Dados e Classificação de Sensibilidade

A tabela abaixo consolida o mapeamento exaustivo de dados persistidos pelo backend do SinalACS, contemplando as 11 tabelas de domínio do sistema, os modelos de transporte/persistência intermediária e as tabelas operacionais geradas pelo framework Serverpod. A classificação adota os parâmetros da LGPD (Lei nº 13.709/2018, Art. 5º, I e II), confrontando-os com as invariantes de negócio (INV-01 a INV-05) e os requisitos funcionais de privacidade (LGPD-RF01 a RF21).

| Tabela / Entidade | Coluna / Atributo | Tipo de Dado | Classificação LGPD | Tratamento Atual | Risco / Avaliação de Conformidade |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **users** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador técnico interno; sem vazamento direto isoladamente. |
| | `cpfHash` | `text` | Identificável / Pseudonimizado | Hash SHA-256 em texto plano | **Crítico:** O CPF possui espaço de busca restrito ($10^9$ combinações válidas); vulnerável a ataques de força bruta e rainbow tables se não utilizar salt/pepper secreto no backend. |
| | `name` | `text` | Identificável (PII Direto) | Texto claro | Necessário para identificação presencial pelo ACS no território; requer controle rigoroso de acesso e segregação estrita por microárea (INV-01). |
| | `birthDate` | `timestamp without time zone` | Identificável (PII Direto) | Timestamp exato | Permite reidentificação por cruzamento com bases cadastrais externas; avaliar truncamento para apenas data (`date`) ou idade calculada. |
| | `role` | `text` | Metadado Técnico | String (`PATIENT`, `ACS`, `ADMIN`) | Controle de perfil e permissões de acesso da aplicação (RBAC). |
| | `microAreaId` | `uuid` | Pseudonimizado / Territorial | Chave estrangeira (`micro_areas.id`) | Essencial para a aplicação da invariante de privacidade INV-01 (delimitação estrita de acesso por microárea). |
| | `createdAt` | `timestamp without time zone` | Metadado Técnico | Timestamp de criação | Registro temporal técnico de auditoria. |
| | `updatedAt` | `timestamp without time zone` | Metadado Técnico | Timestamp de modificação | Rastreabilidade do ciclo de vida cadastral. |
| **patients** | `id` | `uuid` | Pseudonimizado | UUID (vínculo 1:1 com `users.id`) | Identificador do paciente no domínio clínico; sem risco direto de identificação sem junção com a tabela `users`. |
| | `emergencyContact` | `text` | Identificável (PII de Terceiro) | Texto claro (telefone/nome) | **Alto:** Armazena dados de contato de pessoa externa sem gestão documentada de consentimento desse terceiro titular. |
| | `isChronic` | `boolean` | Sensível (Saúde - Art. 5º, II) | Flag booleana | Sinaliza formalmente a existência de condição médica crônica. |
| | `chronicConditions` | `json` | Sensível (Saúde - Art. 5º, II) | JSON estruturado em texto claro | **Crítico:** Lista de comorbidades (ex: diabetes, hipertensão) exposta sem proteção criptográfica; viola a invariante INV-04 e LGPD-RF09 (ausência de `pgcrypto`/AES-256). |
| | `lastLocationHash` | `text` | Pseudonimizado | Geohash (ex: 7 caracteres base32) | Não é irreversível: codifica latitude e longitude com resolução de ~150m; pode revelar o endereço residencial exato do paciente. |
| | `lastTriageAt` | `timestamp without time zone` | Sensível (Metadado Clínico) | Timestamp | Indica data/hora de eventos de triagem clínica recente. |
| **triage_sessions** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador sintético da sessão de triagem. |
| | `patientId` | `uuid` | Pseudonimizado | Chave estrangeira (`patients.id`) | Liga o histórico clínico diretamente ao perfil do paciente no território. |
| | `answers` | `json` | Sensível (Saúde - Art. 5º, II) | JSON contendo lista de `TriageAnswer` | **Crítico:** Contém sintomas declarados e relatos de dor; viola a invariante INV-04 enquanto persistido sem criptografia de repouso. |
| | `resultRisk` | `text` | Sensível (Saúde - Art. 5º, II) | Enum textual (`VERMELHO`, `AMARELO`, etc.) | Classificação determinística calculada no frontend/backend; uso restrito à priorização da fila de atendimento do ACS. |
| | `resultDisplay` | `text` | Sensível (Saúde - Art. 5º, II) | Texto descritivo | Descrição textual com diretivas clínicas associadas aos sintomas avaliados. |
| | `createdAt` | `timestamp without time zone` | Metadado Técnico | Timestamp | Marco temporal para aplicação da política de retenção legal de 5 anos (LGPD-RF07). |
| | `deviceId` | `text` | Identificador de Dispositivo | String de identificador de hardware | Se atrelado a identificadores fixos do sistema (IMEI, MAC, Android ID), caracteriza dado pessoal rastreável; requer pseudonimização com salt efêmero. |
| **triage_answer** *(DTO)* | `questionId`, `value`, `details` | `String` / Estrutura serializada | Sensível (Saúde - Art. 5º, II) | Payload unitário de resposta | Estrutura unitária persistida dentro do campo `triage_sessions.answers`. |
| **visits** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador do registro de visita domiciliar. |
| | `patientId` | `uuid` | Pseudonimizado | Chave estrangeira (`patients.id`) | Identifica o titular do atendimento de saúde. |
| | `acsId` | `uuid` | Pseudonimizado | Chave estrangeira (`acs.id`) | Identifica o profissional responsável pelo atendimento presencial. |
| | `scheduledAt` | `timestamp without time zone` | Metadado Operacional | Timestamp agendado | Data e horário previstos para o atendimento. |
| | `startedAt` | `timestamp without time zone` | Metadado Operacional | Timestamp de início | Registro do início da intervenção no domicílio. |
| | `completedAt` | `timestamp without time zone` | Metadado Operacional | Timestamp de conclusão | Registro da finalização da visita pelo ACS. |
| | `status` | `text` | Metadado Operacional | Enum textual (`SCHEDULED`, `IN_PROGRESS`, etc.) | Estado operacional do ciclo de vida da visita. |
| | `riskLevelBefore` | `text` | Sensível (Saúde - Art. 5º, II) | Enum textual | Avaliação clínica de gravidade anterior à intervenção. |
| | `riskLevelAfter` | `text` | Sensível (Saúde - Art. 5º, II) | Enum textual | Reavaliação clínica executada pelo ACS após o atendimento presencial. |
| | `notes` | `json` | Sensível (Saúde - Art. 5º, II) | JSON em texto claro | **Crítico:** Campo de anotações não estruturadas do ACS; elevado risco de conter diagnósticos, prescrições e relatos sobre terceiros sem anonimização. |
| | `syncStatus` | `text` | Metadado Técnico | Enum textual (`PENDING`, `SYNCED`, `CONFLICT`) | Controle da máquina de estados (FSM) de sincronização offline-first. |
| | `localId` | `uuid` | Pseudonimizado | UUID gerado no SQLite do cliente | Chave de controle de concorrência e idempotência offline. |
| | `syncAt` | `timestamp without time zone` | Metadado Técnico | Timestamp de sincronização | Momento da persistência no banco central. |
| | `version` | `bigint` | Metadado Técnico | Inteiro incremental | Controle de concorrência otimista (OCC) para resolução de conflitos. |
| **alerts** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador do alerta de emergência disparado. |
| | `patientId` | `uuid` | Pseudonimizado | Chave estrangeira (`patients.id`) | Identifica o paciente em risco clínico. |
| | `acsId` | `uuid` | Pseudonimizado | Chave estrangeira (`acs.id`) | Agente que confirmou ou assumiu o atendimento (nulo até o ACK). |
| | `microAreaId` | `uuid` | Pseudonimizado / Territorial | Chave estrangeira (`micro_areas.id`) | Delimita o escopo geográfico da rota de notificação MQTT. |
| | `triggeredAt` | `timestamp without time zone` | Metadado Operacional | Timestamp de acionamento | Base para medição da métrica TMRAV (< 90 segundos). |
| | `receivedAt` | `timestamp without time zone` | Metadado Operacional | Timestamp de entrega | Telemetria de entrega no dispositivo do agente comunitário. |
| | `respondedAt` | `timestamp without time zone` | Metadado Operacional | Timestamp de ação | Telemetria de início de resposta do ACS. |
| | `acknowledgedAt` | `timestamp without time zone` | Metadado Operacional | Timestamp de confirmação | Registro formal de visualização do alerta vermelho (garantia da INV-03). |
| | `riskLevel` | `text` | Sensível (Saúde - Art. 5º, II) | Enum textual (`VERMELHO`, `AMARELO`) | Grau de urgência do acionamento. |
| | `locationHash` | `text` | Pseudonimizado | Geohash (ex: `'6gyf4bf'`) | Delimitação territorial codificada; requer validação de precisão para não fixar o endereço domiciliar exato. |
| | `status` | `text` | Metadado Operacional | Enum textual (`PENDING`, `ACKNOWLEDGED`, etc.) | Estado da máquina de alerta de urgência. |
| | `mqttTopic` | `text` | Metadado Técnico / Territorial | String (`/alerts/{micro_area_id}`) | Canal de mensageria; não deve conter identificadores diretos do paciente no caminho do tópico. |
| | `deviceId` | `text` | Identificador de Dispositivo | String de identificador do hardware | Rastreamento técnico da origem do botão de pânico. |
| | `retryCount` | `bigint` | Metadado Técnico | Inteiro incremental | Controle de resiliência e retentativas na entrega da mensagem. |
| | `version` | `bigint` | Metadado Técnico | Inteiro incremental | Controle de concorrência e idempotência. |
| **alert_deliveries** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador de entrega. |
| | `alertId` | `uuid` | Pseudonimizado | Chave estrangeira (`alerts.id`) | Referência ao alerta entregue. |
| | `acsId` | `uuid` | Pseudonimizado | Chave estrangeira (`acs.id`) | Agente que confirmou a leitura do alerta. |
| | `acknowledgedAt` | `timestamp without time zone` | Metadado Técnico / Legal | Timestamp de confirmação | Prova técnica de recebimento em cumprimento à invariante INV-03. |
| **alert_delivery_record** *(DTO)* | Payload de entrega | `class` Dart | Metadado Operacional / Trânsito | Estrutura de dados em memória | Objeto serializado para publicação MQTT; não deve ser despejado em logs de infraestrutura. |
| **alert_outbox_entry** *(Model/DB)* | `alertId`, `payload`, `status` | Vários | Sensível / Metadado Técnico | Registro transacional da outbox | Garante atomicidade transacional com o broker; o payload retém dados clínicos e geográficos do alerta até o despacho. |
| **alert_idempotency_keys** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador do registro de controle de duplicação. |
| | `key` | `text` | Metadado Técnico | String única de idempotência | Previne múltiplos envios de alertas em rede instável; não deve concatenar PII. |
| | `alertId` | `uuid` | Pseudonimizado | Chave estrangeira (`alerts.id`) | Referência ao alerta vinculado. |
| | `locationHash` | `text` | Pseudonimizado | Geohash | Geohash associado à tentativa original. |
| | `createdAt` | `timestamp without time zone` | Metadado Técnico | Timestamp de expiração | Controle temporal da janela de deduplicação. |
| **consent_logs** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador do log de consentimento (LGPD-RF04). |
| | `userId` | `uuid` | Pseudonimizado | Chave estrangeira (`users.id`) | Identifica o titular do consentimento. |
| | `purpose` | `text` | Metadado Legal | String declarativa de finalidade | Registro da finalidade específica outorgada (LGPD-RF02). |
| | `action` | `text` | Metadado Legal | Enum textual (`GRANT`, `REVOKE`, etc.) | Ação exercida sobre o consentimento pelo titular. |
| | `version` | `text` | Metadado Legal | String de versão semântica | Versão dos termos aceita no momento da ação (LGPD-RT04). |
| | `timestamp` | `timestamp without time zone` | Metadado Legal | Timestamp de registro | Comprovação temporal imutável da manifestação de vontade. |
| | `ipHash` | `text` | Pseudonimizado | Hash SHA-256 do IP | Se gerado para IPv4 sem salt ($2^{32}$ combinações), é reversível por força bruta imediata; requer salt rotativo. |
| | `userAgent` | `text` | Metadado Técnico / Fingerprint | String de cabeçalho User-Agent | Auxilia na caracterização do dispositivo utilizado. |
| | `signature` | `text` | Metadado Legal / Prova Criptográfica | Assinatura digital/hash | Garantia de não repúdio e integridade do consentimento (LGPD-RT05). |
| **audit_logs** | `id` | `uuid` | Pseudonimizado | UUID v4 (`gen_random_uuid()`) | Identificador do registro de auditoria (LGPD-RF11). |
| | `userId` | `uuid` | Pseudonimizado | Chave estrangeira (`users.id`) | Identifica o operador que executou a ação auditada. |
| | `actionType` | `text` | Metadado Técnico | Enum textual (`READ`, `WRITE`, `DELETE`, etc.) | Operação registrada. |
| | `resourceType` | `text` | Metadado Técnico | String de recurso | Entidade ou endpoint manipulado. |
| | `resourceId` | `uuid` | Pseudonimizado | Identificador do recurso | ID do registro visualizado ou modificado. |
| | `timestamp` | `timestamp without time zone` | Metadado Legal / Técnico | Timestamp do evento | Linha temporal imutável de acesso. |
| | `ipHash` | `text` | Pseudonimizado | Hash SHA-256 do IP | Mesma vulnerabilidade de reversão caso não haja salt/HMAC com chave rotativa. |
| | `result` | `text` | Metadado Técnico | Enum textual (`SUCCESS`, `FAILURE`, `DENIED`) | Desfecho da tentativa de acesso. |
| **acs** | `id` | `uuid` | Pseudonimizado | UUID (vínculo com `users.id`) | Identificador de cadastro funcional do agente de saúde. |
| | `enrollmentId` | `text` | Identificável (Funcional) | Matrícula funcional em texto claro | Identificador de agente público; passível de correlação direta com portais municipais de transparência. |
| | `ubsId` | `uuid` | Pseudonimizado / Organizacional | Chave estrangeira (`ubs.id`) | Lotação institucional do profissional de saúde. |
| | `active` | `boolean` | Metadado Operacional | Booleano | Status funcional de permissão de acesso ao sistema. |
| | `lastSyncAt` | `timestamp without time zone` | Metadado Técnico | Timestamp | Última sincronização do app do ACS com o backend. |
| **micro_areas** | `id` | `uuid` | Pseudonimizado / Territorial | UUID v4 (`gen_random_uuid()`) | Identificador do território sanitário de cobertura. |
| | `name` | `text` | Dado Institucional / Organizacional | String | Nome ou código descritivo da microárea na UBS. |
| | `ubsId` | `uuid` | Pseudonimizado / Organizacional | Chave estrangeira (`ubs.id`) | Vinculação com a Unidade Básica de Saúde gestora. |
| | `geoJsonBoundary` | `text` | Dado Territorial / Cartográfico | String GeoJSON | Delimitação dos polígonos geográficos da microárea sanitária. |
| **ubs** | `id` | `uuid` | Pseudonimizado / Organizacional | UUID v4 (`gen_random_uuid()`) | Identificador da unidade de saúde. |
| | `name` | `text` | Dado Institucional Público | String | Razão social ou denominação do posto de atendimento. |
| | `address` | `text` | Dado Institucional Público | String de endereço | Endereço físico do equipamento de saúde pública. |
| | `city` | `text` | Dado Territorial Público | String de município | Município de lotação da UBS. |
| | `state` | `text` | Dado Territorial Público | String UF | Estado da federação de lotação da UBS. |
| **serverpod_query_log** | `query` | `text` | **Risco Crítico de Fuga Indireta** | Texto SQL completo de queries lentas/falhas | **Crítico:** Se comandos `INSERT`/`UPDATE` com `name`, `emergencyContact`, `chronicConditions` ou `notes` falharem ou forem lentos, o comando SQL completo com dados sensíveis em texto claro será gravado nesta tabela técnica. |
| | Demais colunas | Vários | Metadados de Sistema | Timestamps, durações e IDs numéricos | Métricas de telemetria e depuração de queries do banco de dados. |
| **serverpod_message_log** | `error` / `stackTrace` | `text` | Risco Moderado de Vazamento | Dump de exceções não tratadas | Risco de exposição de payloads RPC contendo dados clínicos sensíveis ou identificadores em stacktraces não sanitizados. |
| | Demais colunas | Vários | Metadados Operacionais | Nomes de métodos RPC, durações e flags | Rastreabilidade de chamadas da API interna. |
| **serverpod_session_log** | `authenticatedUserId` / `userId` | `bigint` / `text` | Pseudonimizado / Técnico | Identificadores de sessão Serverpod | Rastreamento técnico da sessão HTTP/RPC. |
| | Demais colunas | Vários | Metadados de Diagnóstico | Timestamps, contadores de queries e status de erro | Métricas técnicas de desempenho do servidor. |
| **serverpod_cloud_storage*** | Todas as colunas | `bytea`, `text`, etc. | Infraestrutura Interna | Tabelas de blobs e uploads do Serverpod | Devem ser mantidas com permissões estritas para evitar persistência indevida de dados não estruturados de pacientes. |
| **serverpod_health_*** / **future_call** / **migrations** | Todas as colunas | Vários | Metadados de Infraestrutura | Métricas de CPU/memória, controle de jobs e migrações | Neutro sob a ótica de privacidade de titulares de dados pessoais. |

## 2. Avaliação de Mecanismos Criptográficos e Pseudonimização

A análise técnica do schema e da base de código do backend (`backend/sinalacs_server`) aponta discrepâncias críticas entre os requisitos de segurança formalizados na especificação do sistema (`spec/PRD_system.md` e `spec/lgpd_design.md`) e a implementação concreta persistida nas migrações do PostgreSQL. Em diversos pontos, mecanismos de mascaramento tratam dados identificáveis e de saúde sob pseudonimização frágil ou texto claro.

---

### 2.1. Análise de Entropia e Fragilidades de Hashing

A inspeção estática demonstrou que o backend não calcula hashes criptográficos; ele se limita a persistir strings pré-calculadas fornecidas pelos clientes via RPC ou scripts de seed. Isso transfere o risco para os nós de borda e expõe campos críticos a ataques de força bruta e tabelas de busca pré-computadas (*rainbow tables*).

#### Fragilidade Estrutural em `users.cpfHash`
* **Mapeamento:** Coluna `cpfHash text NOT NULL` indexada via B-tree na tabela `users`.
* **Implementação de Referência:** O helper de seed no PRD documenta o uso de `sha256('123.456.789-00')`.
* **Vulnerabilidade de Entropia:** O CPF é composto por 11 dígitos decimais, dos quais os 2 últimos são dígitos verificadores calculados diretamente sobre os 9 primeiros. Consequentemente, existem apenas $10^9$ combinações possíveis no espaço amostral do documento.
* **Risco de Segurança:** Uma GPU moderna executa bilhões de operações SHA-256 por segundo. Sem a utilização de *salt* individual ou chave secreta global (*pepper*), todo o espaço de CPFs pode ser pré-computado em *rainbow tables* em questão de segundos, anulando o efeito da pseudonimização e convertendo o hash em dado nominal reversível.

#### Fragilidade em `consent_logs.ipHash` e `audit_logs.ipHash`
* **Mapeamento:** Colunas `ipHash text NOT NULL` registradas para atendimento aos requisitos LGPD-RF04 e LGPD-RF11.
* **Vulnerabilidade de Entropia:** O espaço de endereçamento público do IPv4 é limitado a $2^{32} \approx 4,29 \times 10^9$ combinações possíveis.
* **Risco de Segurança:** A ausência de segredo computacional torna a reversão de IPs por força bruta quase instantânea, expondo o histórico de navegação e a localização geográfica de rede do titular.

---

### 2.2. Risco de Reidentificação Espacial via `locationHash`

Os campos `patients.lastLocationHash`, `alerts.locationHash` e `alert_idempotency_keys.locationHash` são descritos formalmente como "hash de localização". O app do paciente atualmente calcula um digest SHA-256 sobre latitude/longitude normalizadas em seis casas e armazena apenas os primeiros 12 caracteres; outros fluxos históricos/testes ainda usam valores no formato de geohash. Em ambos os casos, o valor deve ser tratado como pseudonimização, não anonimização.

* **Natureza Algorítmica:** Geohash não é uma função criptográfica unidirecional; o digest SHA-256 também não torna o local anônimo quando o domínio de busca é limitado e o atacante conhece a microárea ou dispõe de pontos candidatos.
* **Resolução Geométrica:** A implementação do paciente usa seis casas decimais antes do digest, aproximadamente na ordem de centímetros; o digest truncado não revela a coordenada por decodificação direta, mas mantém risco de correlação/força bruta. Em áreas rurais, poucos pontos candidatos podem tornar o risco especialmente relevante.
* **Consequência LGPD:** A precisão atual de 7 caracteres permite identificar indiretamente a residência do titular quando combinada com a delimitação de microárea sanitária (`microAreaId`), contrariando a premissa de desidentificação do dado em repouso.

---

### 2.3. Armazenamento em Texto Claro de Dados Sensíveis de Saúde (Violação INV-04)

A invariante de negócio **INV-04** estabelece categoricamente: *"Dados de saúde sensíveis nunca podem ser persistidos em texto plano. Criptografia AES-256 em sqflite e PostgreSQL"*. Adicionalmente, os requisitos **LGPD-RF09** e **LGPD-RT02** determinam o uso de criptografia em repouso para mitigar o risco de vazamento em caso de comprometimento do banco.

A inspeção do schema físico (`definition.sql` e modelos `.spy.yaml`) revelou que três colunas contêm dados sensíveis (Art. 5º, II da LGPD) persistidos como tipos `json` ou `text` nativos, sem qualquer camada de cifra criptográfica:

1. **`patients.chronicConditions` (`json`):** Persiste diretamente diagnósticos clínicos estruturados (ex: `['diabetes', 'hipertensao']`).
2. **`triage_sessions.answers` (`json`):** Armazena a listagem de respostas de triagem com a descrição de sintomas, localização corporal e intensidade de dores.
3. **`visits.notes` (`json`):** Armazena anotações livres e não estruturadas realizadas pelo ACS durante o atendimento domiciliar, com alto risco de retenção de dados clínicos circunstanciais e menções a terceiros.

A exposição desses campos em repouso gera vulnerabilidade crítica: qualquer leitura indevida decorrente de dump de banco, backup comprometido ou injeção de logs expõe de imediato o histórico clínico completo do paciente.

---

### 2.4. Identificadores de Dispositivo (`deviceId`)

As tabelas `alerts` e `triage_sessions` retêm a coluna `deviceId text NOT NULL`.
* Caso os aplicativos enviem identificadores imutáveis do sistema operacional (como `android_id`, IMEI ou endereço MAC), esse valor atua como PII indireto perene, permitindo correlacionar o histórico de atendimentos a um aparelho físico mesmo após a troca de usuário.
* Para conformidade com os princípios da necessidade e minimização (Art. 6º, I e III da LGPD), o identificador de dispositivo deve ser restrito a uma chave de instalação pseudoaleatória gerada localmente no app móvel ou mascarada antes da persistência.

---

### 2.5. Dados Cadastrais e Credenciais de Autenticação (`users` e `patients`)

* **`users.name`:** Mantido em texto claro no banco por necessidade estrita da operação assistencial domiciliar do ACS (Art. 6º, I e Art. 7º, V da LGPD). Requer controle de acesso rígido por microárea (INV-01) para que outros agentes não visualizem a listagem nominal.
* **`users.birthDate` como Fator de Autenticação (RF01):** Conforme definido no requisito RF01 do PRD, a data de nascimento atua conjuntamente com o CPF como credencial no fluxo de *Login Passwordless*.
  * **Minimização de Tipo:** Como a autenticação exige a data exata, o truncamento para ano/idade é inviável sem quebrar o login. No entanto, o tipo de dado atual no PostgreSQL (`timestamp without time zone`) deve ser alterado para o tipo `date`, descartando horas, minutos e segundos desnecessários.
  * **Risco de Correlação:** Armazenar a data de nascimento em texto claro ao lado de um `cpfHash` frágil amplia exponencialmente o risco de reidentificação por cruzamento com bases públicas vazadas. A proteção de `users.cpfHash` via HMAC-SHA-256 com segredo (*pepper*) do backend torna-se mandatória para impedir que a credencial de login do paciente seja quebrada em caso de vazamento do banco.
* **`patients.emergencyContact`:** Armazena dados de contato de terceiros (telefone/nome) em texto claro sem termo de consentimento específico. Deve permanecer sob acesso restrito (RBAC), sendo descriptografado ou revelado ao ACS exclusivamente durante o tratamento de alertas de emergência confirmados (alerta vermelho).

---

### 2.6. Recomendações Técnicas de Remediação Criptográfica

| Campo Auditado | Vulnerabilidade Identificada | Remediação Técnica Recomendada |
| :--- | :--- | :--- |
| `users.cpfHash` | Espaço amostral $10^9$; reversível por força bruta em segundos. | Migrar para **HMAC-SHA-256** utilizando segredo corporativo (*pepper*) injetado via variável de ambiente restrita ao backend (`CPF_HASH_PEPPER`). O cálculo deve ser feito exclusivamente pelo servidor. |
| `users.birthDate` | Tipo com precisão excessiva de horário (`timestamp`) em credencial sensível. | Alterar a coluna para o tipo SQL `date`, preservando o valor exato para o login passwordless (RF01) e eliminando horas/minutos/segundos. |
| `patients.emergencyContact` | PII de terceiro exposto em texto claro sem consentimento formal direto. | Criptografar a coluna com chave simétrica da aplicação ou proteger o acesso via endpoint dedicado liberado apenas durante o ciclo de vida de um alerta ativo. |
| `consent_logs.ipHash` e `audit_logs.ipHash` | Espaço amostral de IPv4 ($2^{32}$) facilmente mapeável via rainbow table. | Utilizar **HMAC-SHA-256 com rotação periódica de salt** (chave de rotação diária/semanal), preservando a correlação de incidentes daquela janela sem permitir persistência do rastro de rede do titular. |
| `patients.chronicConditions` | Comorbidades e diagnósticos de saúde persistidos em texto plano (violação INV-04). | Criptografia em repouso no nível de aplicação (AES-256-GCM) antes do insert, ou adoção da extensão `pgcrypto` (`pgp_sym_encrypt`) no PostgreSQL, conforme previsto em LGPD-RT02. |
| `triage_sessions.answers` | Respostas clínicas e relatos de sintomas persistidos em JSON aberto. | Serializar e cifrar o payload de respostas com chave simétrica derivada ou chave mestra mantida fora do banco de dados (Envelope Encryption). |
| `visits.notes` | Texto livre do ACS sem higienização, contendo dados clínicos sensíveis. | Criptografia simétrica compulsória em repouso e implementação de máscara ou sanitização preventiva na sincronização. |
| `alerts.locationHash` | Digest truncado de localização precisa, correlacionável por força bruta em um domínio espacial pequeno; formatos geohash históricos têm risco adicional de decodificação direta. | Aprovar uma resolução espacial deliberadamente reduzida ou uma célula espacial não reversível para roteamento, limitar retenção e impedir que a coordenada crua saia do dispositivo. Validar a escolha com ameaça de reidentificação antes de produção. |
| `alerts.deviceId` e `triage_sessions.deviceId` | Rastreamento persistente de hardware do titular. | Substituir por identificador de instalação efêmero (UUID gerado no onboarding do app e descartado na limpeza de dados). |

## 3. Matriz de Pontos de Vazamento e Riscos Identificados

A auditoria estática do fluxo de dados, pontos de entrada RPC, rotinas em segundo plano e infraestrutura de deploy do `sinalacs_server` mapeou os vetores de exposição involuntária de dados pessoais, registros clínicos e credenciais.

---

### 3.1. Matriz de Riscos de Vazamento

| ID | Componente / Arquivo | Severidade | Descrição do Risco | Mitigação Recomendada |
| :--- | :--- | :--- | :--- | :--- |
| **VAZ-01** | `lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart` (linhas 43, 103, 132), `lib/src/application/alerts/alert_outbox_dispatcher.dart` (linha 69) e `lib/server.dart` (linha 96) | **Média** | Despejo de exceções brutas via `stderr.writeln` em falhas de mensageria MQTT e varredura de outbox. Caso o `$error` interceptado contenha instâncias serializadas de `AlertOutboxEntry` ou `AlertDeliveryRecord`, dados sensíveis como `locationHash` e identificadores clínicos são despejados nos logs do console da hospedagem. | Sanitizar a mensagem antes de gravar em `stderr`, registrando apenas o tipo do erro e identificadores sintéticos (ex.: `alertId`), sem imprimir o objeto de domínio bruto ou payloads MQTT. |
| **VAZ-02** | `serverpod_query_log` (Tabela interna do Serverpod) | **Alta** | Persistência indireta de PII e dados sensíveis de saúde em texto claro. Caso transações com o ORM (como em `AlertsEndpoint.createRedAlert` ou sincronização de visitas) falhem ou sofram lentidão, o framework grava a instrução SQL completa na coluna `query`, expondo valores literais de inserções em `users`, `patients`, `triage_sessions` e `visits`. | Configurar `logSettings` em `serverpod_runtime_settings` para desativar o registro textual de queries SQL completas em ambientes com dados reais, assegurando o uso exclusivo de prepared statements parametrizados. |
| **VAZ-03** | `serverpod_message_log` e `serverpod_log` | **Média** | Vazamento de argumentos RPC e sessões em stacktraces. Exceções não tratadas durante chamadas de endpoint podem despejar argumentos serializados de requisições nas colunas `error` e `stackTrace` das tabelas de telemetria do Serverpod. | Implementar filtro global de exceções para expurgar cargas úteis e PII antes da gravação de stacktraces no banco de dados. |
| **VAZ-04** | Broker MQTT Gerenciado (HiveMQ Cloud / Piloto Free-Tier) | **Alta** | Ausência de ACLs dinâmicas por microárea e chaveamento compartilhado (`backend/DEPLOY.md`). O piloto adota credenciais globais estáticas (`MQTT_USERNAME`/`MQTT_PASSWORD`) sem segregação estrita por tópico, permitindo que qualquer nó autenticado assine `/alerts/#` e intercepte alertas de terceiros. | O ambiente free-tier deve permanecer restrito a dados sintéticos. Para produção, adotar broker corporativo (ex.: Mosquitto/EMQX) com autenticação mTLS e arquivos de ACL dinâmicos vinculados à microárea (garantia da INV-01). |
| **VAZ-05** | Topologia Neon / Render (Armazenamento e Computação em Nuvem Pública) | **Média** | Custódia e processamento de dados por operadores terceirizados sem salvaguardas contratuais formais (DPA - *Data Processing Agreement*). Viola o princípio da responsabilização e LGPD-RF17 caso dados reais trafeguem antes da celebração dos instrumentos legais. | Manter a infraestrutura gratuita estritamente restrita a seeds e testes sintéticos. Em ambiente assistencial, formalizar instâncias isoladas (VPC/on-premise institucional) ou contratos corporativos com DPA ativo. |
| **VAZ-06** | `config/passwords.yaml` (Higiene de Repositório) | **Baixa** | Risco de vazamento de segredos mestres do banco de dados em repositórios remotos. A checagem via `git check-ignore` confirmou que o arquivo está devidamente ignorado (.gitignore:15), mas exige monitoramento contínuo contra desvios de branch. | Manter bloqueio no pipeline de CI com ferramentas de *Secret Scanning* (ex: Gitleaks/TruffleHog) para impedir commits acidentais de senhas locais. |

---

### 3.2. Detalhamento dos Vetores de Vazamento

#### 3.2.1. Auditoria de Boot e Emissões em Console
A varredura estática por `print(` confirmou que o projeto não possui chamadas residuais de depuração direta em stdout. O vazamento originalmente citado na issue (`print('Database URL: ${config.databaseUrl}')`) pertencia à implementação legada `dart:io` e já foi sanado na migração para Serverpod. 

Contudo, a inspeção de fluxos de erro revelou 5 ocorrências de `stderr.writeln` associadas à resiliência do MQTT e ao outbox (`mqtt_alert_dispatcher.dart`, `alert_outbox_dispatcher.dart` e `server.dart`). Em plataformas como Render ou containers Docker, mensagens descarregadas em `stderr` são arquivadas sem tratamento em aggregators de log, criando o risco de expor atributos internos de alertas durante falhas transitórias de conexão.

#### 3.2.2. Efeito Colateral do Logging Técnico do Serverpod
O Serverpod gera nativamente tabelas de diagnóstico operacional (`serverpod_query_log`, `serverpod_session_log`, `serverpod_message_log`, `serverpod_log`). 
* Embora métodos como `AlertsEndpoint.createRedAlert` realizem validações seguras e encapsulem transações via `session.db.transaction`, uma falha de banco aciona a persistência do comando SQL textual em `serverpod_query_log.query`.
* Se dados sensíveis de saúde (`chronicConditions`, `answers`, `notes`) estiverem em texto claro no momento da inserção, a tabela de log passa a atuar como vetor secundário de retenção desprotegida de PII e dados clínicos.

#### 3.2.3. Superfície de Mensageria no Piloto Gratuito (HiveMQ Cloud)
Conforme detalhado no documento `backend/DEPLOY.md`, o piloto gratuito utiliza o HiveMQ Cloud em plano compartilhado, onde não há segregação de permissões de leitura por tópico baseada em território sanitário. Clientes que utilizarem as credenciais do piloto podem monitorar livremente as publicações da raiz `/alerts/*`, permitindo que um agente escute alertas emitidos em microáreas para as quais não possui atribuição assistencial, quebrando a garantia da invariante INV-01.

## 4. Retenção, Ciclo de Vida e Ambientes Não Produtivos (LGPD-RF07)

A gestão do ciclo de vida dos dados é um pilar da LGPD (Art. 15 e 16). O sistema precisa garantir que os dados pessoais não sejam mantidos indefinidamente sem justificativa e que ambientes de engenharia não sejam contaminados com dados reais de titulares.

### 4.1. Avaliação de Retenção e Exclusão (Ausência de Expurgo)
* **Requisito Legal:** O requisito **LGPD-RF07** estabelece que dados de saúde (alertas, triagens, visitas) devem ser retidos pelo prazo mínimo legal (5 anos) e, após esse período, anonimizados ou eliminados de forma segura por meio de um mecanismo automático de expurgo[cite: 4].
* **Cenário Atual:** A inspeção nas tabelas `alerts`, `visits` e `triage_sessions` (conforme as migrações geradas pelo Serverpod) confirma a ausência de qualquer *cron job*, *trigger* de banco de dados ou rotina em segundo plano (como *FutureCalls* do Serverpod) programada para limpar registros antigos[cite: 6]. 
* **Avaliação:** **Inconforme**. O acúmulo contínuo sem rotina de anonimização ou exclusão viola o princípio da necessidade da LGPD, aumentando a superfície de risco em caso de vazamento futuro.

### 4.2. Dados em Ambientes Não Produtivos e CI/CD
* **Diretriz:** A invariante de segurança do projeto proíbe estritamente o uso de dados reais de pacientes em testes, logs, capturas de tela ou configurações de desenvolvimento[cite: 5].
* **Cenário Atual:** A análise do seed em `backend/sinalacs_server/lib/src/infrastructure/database/seeds/development.sql` confirmou a aderência total à regra. Os dados são 100% fictícios:
  * Identificadores nominais declarativos (`'Paciente de desenvolvimento'`).
  * Hashes sintéticos (`'development-patient'`, `'development-acs'`) no lugar de CPFs formatados.
  * O `auth.developmentLogin` utiliza chaves e UUIDs fixos que não correspondem a nenhuma base real, impedindo colisão com titulares[cite: 5].
* **Avaliação:** **Conforme**. A higiene de dados sintéticos mitiga o risco de exposição de PII em ambientes de Integração Contínua (CI) e testes locais.

### 4.3. Restrições do Piloto Free-Tier
* **Cenário Atual:** O documento de deploy descreve a hospedagem do protótipo em serviços gratuitos gerenciados por terceiros (Render, Neon, HiveMQ Cloud)[cite: 1].
* **Avaliação:** Embora arquiteturalmente válido para validação (devido ao suporte a contêineres e hibernação transparente), **é inaceitável o uso de dados reais neste ambiente**[cite: 1]. A falta de Data Processing Agreements (DPAs) firmados com esses fornecedores e a ausência de controles rígidos de retenção tornam o piloto free-tier uma zona de alto risco regulatório se exposta à operação assistencial verdadeira.

---

## 5. Plano de Ação Recomendado

Com base nas vulnerabilidades e desvios de conformidade mapeados neste relatório, recomenda-se a seguinte ordem de priorização para adequação à LGPD e às invariantes do SinalACS:

### Prioridade Alta (Curto Prazo - Prevenção de Vazamento Imediato)
1. **Sanitizar Logs de Exceção:** Ajustar os blocos `try/catch` da varredura de outbox e do dispatcher MQTT no backend para não imprimir as entidades de domínio brutas no `stderr`.
2. **Fortalecer Hashes Autenticadores:** Migrar a geração de `users.cpfHash` (usado no login) para **HMAC-SHA-256** utilizando um segredo de servidor (*pepper*). O cálculo deve ocorrer exclusivamente no backend.
3. **Ajustar Tipagem da Data de Nascimento:** Converter a coluna `users.birthDate` para `date` no schema, eliminando a precisão desnecessária de horas/minutos exigida pelo `timestamp` atual.
4. **Isolar o Ambiente Free-Tier:** Reforçar bloqueios ou avisos na UI do piloto garantindo que ele seja alimentado estritamente pelo seed sintético de desenvolvimento.

### Prioridade Média (Médio Prazo - Criptografia em Repouso e Telemetria)
5. **Criptografar Campos de Saúde (Violação INV-04):** Implementar criptografia de coluna (via `pgcrypto` ou criptografia simétrica na aplicação) para proteger `patients.chronicConditions`, `triage_sessions.answers` e `visits.notes` contra leituras indevidas no banco.
6. **Mascarar Logs do Serverpod:** Desativar ou configurar máscaras para o `serverpod_query_log` em produção, impedindo que transações SQL lentas deixem rastros em texto claro de diagnósticos ou dados de anamnese.
7. **Anonimizar Origens de Rede:** Implementar salt rotativo no cálculo de `ipHash` para os registros de `consent_logs` e `audit_logs`.

### Prioridade Baixa (Longo Prazo - Ciclo de Vida e Infraestrutura)
8. **Rotina de Expurgo (LGPD-RF07):** Desenvolver um Serverpod *FutureCall* ou rotina periódica no banco para efetuar o *soft-delete* com anonimização de registros de visitas e alertas com mais de 5 anos[cite: 4].
9. **Reduzir Precisão do Geohash:** Avaliar com a área de produto o truncamento de `locationHash` de 7 para 5 ou 6 caracteres em áreas rurais, impedindo a reidentificação determinística do domicílio do paciente na base de dados.