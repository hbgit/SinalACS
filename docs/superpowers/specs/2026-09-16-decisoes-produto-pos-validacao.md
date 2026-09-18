# Decisões de produto pós-validação — 2026-09-16

**Escopo:** Task 6 do plano `docs/superpowers/plans/2026-09-16-lacunas-pos-validacao.md`.
**Natureza:** documento de decisão. Nada aqui foi implementado; nenhum endpoint,
plugin ou fluxo novo foi criado por esta tarefa. Cada seção é um plano
independente — não devem ser executados como uma tarefa transversal única.
**Entrada:** `spec/validation_report.md` (L-05, RF02, RF06, RF10, RF12, RF14,
RF15, LGPD-RF02, RNF03) e `spec/lgpd_data_audit.md` (recomendações #5 e #9).

Convenção usada abaixo: **Aprovado** = decisão de produto/arquitetura tomada,
pronta para virar brief de implementação; **Bloqueio externo** = decisão não
pode ser fechada sem algo fora do controle deste repositório (credencial,
provedor, política de loja de apps); **Plano derivado** = decisão fechada, mas
a implementação é trabalho novo e não começou.

---

## 1. Mapa e localização (RF10, L-05)

### Estado atual (verificado nesta tarefa)

- `apps/patient/lib/core/privacy/location_hash.dart`: o app do paciente lê a
  posição só em primeiro plano, normaliza com `toStringAsFixed(6)` (~11 cm de
  resolução) e converte em SHA-256 truncado para 12 caracteres. **Nenhuma
  coordenada crua sai do dispositivo.**
- `backend/sinalacs_server/lib/src/domain/entities/alert_delivery.dart`: o
  envelope MQTT (`sinalacs/v1/microareas/<id>/alerts`) carrega só
  `location_hash`, nunca latitude/longitude. Confirmado por leitura direta do
  `toJson()`.
- O schema do Postgres (`alert.spy.yaml`, `patient.spy.yaml`) não tem nenhuma
  coluna de coordenada — só `locationHash` / `lastLocationHash`.
- **O mapa do ACS (RF10) não tem de onde vir**: `apps/acs/lib/app/app.dart`
  (`MapScreen.alertPositionFor`) deriva uma posição *sintética* a partir dos
  bytes do hash, plotada ao redor de Brasília. Isso não é um stub incompleto —
  é dado fabricado exibido como se fosse real, e é o achado L-05 do relatório
  de validação.
- `spec/lgpd_data_audit.md` recomendação #9 fala em truncar um "geohash" de 7
  para 5–6 caracteres. Essa recomendação descreve um esquema anterior; a
  implementação atual (Task 2) usa SHA-256 truncado, não geohash — o
  truncation lever real hoje é o número de casas decimais antes do hash
  (`toStringAsFixed(6)`), não o comprimento da string final.

### Alternativas avaliadas (conforme Passo 1 do brief)

| Alternativa | Descrição | Reidentificação | Utilidade para o ACS |
|---|---|---|---|
| A. Sem posição individual | Mapa mostra só a fila territorial (lista/prioridade), sem nenhum pino | Nenhuma | Baixa — ACS perde referência espacial |
| **B. Geocélula arredondada** | Servidor recebe/deriva uma célula de baixa resolução (não a coordenada exata); mapa desenha a célula, não um ponto | Baixa, ajustável pelo tamanho da célula | Média-alta — orienta a região, não o domicílio |
| C. Posição precisa sob autorização + auditoria | Coordenada exata trafega ponto-a-ponto só durante navegação ativa, nunca persistida, com log de acesso | Alta se mal implementada; aceitável se efêmera e auditada | Alta — navegação real até o domicílio |

### Decisão aprovada

**Adotar B (geocélula arredondada) como o único modo do mapa RF10 nesta fase.**
C fica registrada como incremento futuro condicionado a desenho de segurança
adicional (ver "Plano derivado" abaixo); A é rejeitada porque descarta
utilidade operacional sem necessidade — B já reduz o risco a um nível
aceitável para exibição em mapa.

Especificação da decisão:

1. **O que muda no dispositivo do paciente:** a normalização antes do hash
   passa de 6 casas decimais (~11 cm) para **3 casas decimais (~111 m)** por
   padrão, com um valor configurável menor em áreas rurais de baixa densidade
   (a definir por UBS/microárea, não por paciente — evita que o próprio
   usuário enfraqueça sua privacidade sem saber). Isso aumenta o conjunto de
   anonimato de qualquer hash específico sem adicionar nenhum dado novo ao
   payload.
2. **O que passa a existir no envelope, e só isso:** um campo adicional
   **`locationCell`** (string ou par de inteiros representando a célula, não
   a coordenada) é adicionado ao evento de alerta, calculado a partir da
   mesma leitura de GPS já feita em `GeolocatorLocationReader`, arredondada
   para a grade da célula (ex.: `floor(lat / 0.01) , floor(lng / 0.01)` para
   uma célula de ~1 km, valor final de exemplo — o tamanho exato é parâmetro
   de configuração de produto, não desta decisão). **`locationHash` continua
   existindo e servindo para idempotência/deduplicação; `locationCell` é
   estritamente para desenho do mapa e não substitui o hash.**
3. **O envelope MQTT continua minimizado:** `AlertDelivery.toJson()` ganha um
   campo `location_cell` opcional ao lado de `location_hash`; nenhuma
   coordenada com mais resolução do que a célula aprovada trafega em nenhum
   canal (MQTT, RPC, banco). Ausência de GPS continua caindo em
   `unknownLocationHash`/sem célula, nunca em coordenada inventada.
4. **Quem lê o quê:**
   - **ACS da microárea correspondente**: vê a célula no mapa (não a
     coordenada bruta, que nunca existiu no servidor).
   - **Admin (backoffice)**: não deve ter acesso a `locationHash` nem
     `locationCell` individual — só agregados (contagem por microárea), já
     que o backoffice de hoje é 0/7 integrado (L-01) e não deve herdar esse
     acesso quando for cabeado ao backend real.
   - **Paciente**: não lê a posição de ninguém além da própria (RF05, ainda
     inexistente — ver §4).
5. **Retenção:** `locationCell` (e `locationHash`) do alerta seguem o mesmo
   ciclo de vida do registro `alerts` — não há coluna nova de retenção
   dedicada. A rotina de expurgo já recomendada no item 8 do
   `spec/lgpd_data_audit.md` (soft-delete/anonimização após 5 anos) passa a
   cobrir também `locationCell` quando for implementada; isso **não** cria
   uma retenção mais curta específica para localização nesta decisão —
   registrar essa lacuna é preferível a inventar um prazo não acordado com
   produto/privacidade.
6. **RF10 (mapa interativo) deixa de exibir pino fabricado.** A tela do ACS
   deve desenhar a célula (ex.: um retângulo/círculo de incerteza), não um
   marcador de ponto exato. Enquanto o backend não emitir `location_cell`,
   `MapScreen.alertPositionFor` deve ser tratado como débito técnico
   conhecido (L-05), não removido silenciosamente nesta tarefa (ver
   observação de escopo abaixo).

### Bloqueio externo

Nenhum. A decisão B não depende de provedor externo, credencial ou política de
loja de app — é uma mudança de contrato de dados interna ao projeto.

### Plano derivado (não executado nesta tarefa)

- Adicionar `locationCell` ao modelo `Alert` (migração Serverpod), a
  `AlertDelivery.toJson()`/`tryParse`, ao `alerts.createRedAlert` e ao app do
  paciente (`GeolocatorLocationReader`/`location_hash.dart`), com testes de
  arredondamento e de ausência de coordenada.
- Substituir `MapScreen.alertPositionFor` (hash → posição sintética) por
  renderização de célula recebida do backend.
- Definir o tamanho de célula por UBS/microárea (parâmetro de configuração,
  não uma constante fixa no app) — decisão de produto complementar, fora do
  escopo desta tarefa.
- Alternativa C (posição precisa efêmera para navegação ativa) fica como
  incremento futuro: exigiria um canal MQTT efêmero por entrega, retenção
  zero no banco e log de auditoria de acesso — desenho de segurança adicional
  não coberto aqui.

### Observação de escopo (Passo 3 do brief)

`spec/validation_report.md` **não foi alterado por esta tarefa.** L-05 e o
veredicto de RF10 (`parcial`) continuam bloqueadores até existir código
(campo `locationCell` de ponta a ponta) e teste correspondente. Reclassificar
a matriz de rastreabilidade antes disso descreveria uma decisão como
implementação, o que o brief desta tarefa proíbe explicitamente.

---

## 2. Onboarding e consentimento (RF02, LGPD-RF02, `consent_logs`)

### Estado atual

- RF02 (onboarding via QR Code) é 100% stub:
  `apps/patient/lib/app/app.dart:170` emite um snackbar "será disponibilizada".
  Não existe endpoint de enrollment nem modelo de token de convite.
- `consent_logs` existe como tabela migrada e modelo Serverpod
  (`backend/sinalacs_server/lib/src/models/consent_log.spy.yaml`), com campos
  `purpose`, `action`, `version`, `timestamp`, `ipHash`, `userAgent`,
  `signature` — mas **nenhum código no repositório grava uma linha** (achado
  do relatório de validação, seção "Esquema morto").
- LGPD-RF02 exige checkboxes de consentimento independentes por finalidade no
  onboarding (`spec/lgpd_design.md`).

### Decisão aprovada

1. **QR Code é gerado pelo ACS, escopado a UBS + microárea, de uso único e
   curta validade** (ex.: 15 minutos) — não um link genérico de cadastro.
   O token é consumido atomicamente no primeiro scan válido; um segundo uso
   do mesmo token deve falhar de forma auditável, não silenciosa.
2. **Consentimento é por finalidade, não um aceite único.** No mínimo três
   finalidades distintas, cada uma com seu próprio registro em
   `consent_logs` no momento da decisão do usuário (aceite ou recusa, ambos
   gravados — `action` já suporta isso):
   - processamento de dados de saúde para triagem/alerta (obrigatório para
     usar o app — sem isso não há como operar RF03/RF04);
   - envio de lembretes locais (RF06) — pode ser recusado sem impedir o uso
     do restante do app;
   - recebimento de avisos segmentados por push (RF14) — idem, opcional.
3. **A gravação em `consent_logs` acontece no backend**, dentro do fluxo de
   conclusão do onboarding, nunca só no cliente — um consentimento que só
   existe localmente no aparelho não serve de evidência para auditoria/LGPD
   em caso de solicitação do titular ou fiscalização.
4. **`version` referencia o texto de política vigente** (mesmo padrão que
   `spec/lgpd_design.md` já define para o texto de privacidade), permitindo
   provar sob qual versão da política o consentimento foi obtido.

### Bloqueio externo

Nenhum. É engenharia interna (novo endpoint + novo fluxo de UI), sem
dependência de terceiro.

### Plano derivado (não executado nesta tarefa)

- Modelo/endpoint de token de enrollment (ACS gera, expira, é de uso único).
- `onboarding.completeEnrollment` (ou nome equivalente) no backend, exigindo
  as respostas de consentimento por finalidade antes de ativar a conta.
- Escrever em `consent_logs` a partir desse endpoint (primeiro escritor real
  da tabela).
- UI de checkboxes independentes no app do paciente (RF02 + LGPD-RF02
  reunidos, já que um não faz sentido sem o outro).

---

## 3. Lembretes e avisos (RF06, RF14)

Estes dois requisitos aparecem juntos no PRD sob "notificações", mas têm
dependências de infraestrutura completamente diferentes — por isso são
tratados como planos separados, não uma tarefa de "notificações" só.

### 3.1 RF06 — Lembretes de saúde (locais)

**Estado atual:** `RemindersScreen` em `apps/patient/lib/app/app.dart` tem
lista fixa; salvar descarta a entrada. `flutter_local_notifications` **já
está declarado** em `apps/patient/pubspec.yaml` (`^17.0.0`), mas não há
nenhum `import` dele em `apps/patient/lib/` — a dependência foi adicionada
sem nenhum consumidor.

**Decisão aprovada:** RF06 é **local ao dispositivo, sem endpoint de
backend**. O lembrete (texto, horário, recorrência) é definido pelo paciente
ou populado a partir do perfil clínico já existente localmente, persistido no
próprio aparelho (mesma cesta de armazenamento local já usada no app, sem
introduzir novo mecanismo de sync), e agendado via
`flutter_local_notifications`. Não há necessidade de sincronizar lembretes
entre dispositivos nesta fase — se o paciente trocar de aparelho, recria os
lembretes.

**Bloqueio externo:** nenhum. `flutter_local_notifications` é biblioteca
open-source sem dependência de provedor, e já está declarada.

**Plano derivado:** persistência local dos lembretes, tela de edição real
(hoje é decorativa) e o agendamento via `flutter_local_notifications` (usar a
dependência já declarada, hoje sem nenhum consumidor); consentimento
específico já decidido em §2.

### 3.2 RF14 — Avisos segmentados à comunidade (push)

**Estado atual:** `NoticesScreen` descarta a entrada. Não há FCM/APNs, não há
tabela de token de dispositivo, não há endpoint de envio segmentado por
microárea/UBS.

**Decisão aprovada (contrato, não implementação):**
- Provedor: **Firebase Cloud Messaging (FCM)**, por ser o caminho padrão para
  Android (plataforma primária hoje — os três apps só têm build Android) e
  compatível com iOS via APNs através do mesmo SDK, evitando manter dois
  backends de push.
- Contrato de backend: um endpoint de registro de token
  (`devices.registerPushToken`, tabela nova `push_tokens` associando
  `userId`/`microAreaId`/token/plataforma) e um endpoint de envio segmentado
  (`notices.sendSegmented`, restrito a ACS/admin da UBS/microárea alvo,
  auditado como os demais endpoints sensíveis).
- Conteúdo do aviso não deve carregar dado de saúde identificável — só o
  necessário para abrir o app na tela correta (mesma lógica de minimização já
  aplicada ao alerta).

**Bloqueio externo — este item está bloqueado, não só pendente de
implementação:**
- Não existe projeto Firebase configurado no repositório (sem
  `google-services.json`, sem `GoogleService-Info.plist`, sem chave de
  servidor FCM em `.env.example`).
- Criar esse projeto é uma decisão de produto/infra sobre qual conta
  organizacional o hospeda, quem tem acesso administrativo e qual orçamento
  cobre o uso em produção — decisão que este repositório não pode tomar
  sozinho.

**Plano derivado (após o bloqueio externo ser resolvido):** provisionar o
projeto Firebase, declarar as credenciais como segredo (padrão
`bootstrap_env.sh`), implementar os dois endpoints acima e a tela real de
avisos nos apps ACS (emissor) e paciente (receptor).

---

## 4. Geofencing (RF12)

### Estado atual

`apps/acs/lib/core/services/route_service.dart` calcula status de chegada
(`ArrivalStatus`) **só com o app em primeiro plano** — não há GPS em segundo
plano, não há geofence nativo registrado, e a permissão declarada no
`AndroidManifest.xml` não inclui localização em background.

### Decisão aprovada

**Rejeitar rastreamento contínuo em segundo plano do ACS.** Em vez de manter
a posição do ACS monitorada o tempo todo (o que exigiria
`ACCESS_BACKGROUND_LOCATION` no Android, revisão destacada da Google Play
Store para apps com "background location", e tipicamente um plugin comercial
como `flutter_background_geolocation`), adotar **geofencing atrelado a uma
visita ativa**:

1. O check-in passivo só é armado quando o ACS tem uma visita em andamento
   (`visits` com `startedAt` preenchido e `completedAt` nulo) — não há
   monitoramento de posição fora desse estado.
2. Enquanto a visita está ativa, o app roda um **serviço em primeiro plano
   com notificação persistente visível** ("Sinal ACS está monitorando sua
   chegada ao domicílio da visita") — atende à exigência de transparência do
   usuário e evita a categoria de política mais restritiva da Play Store
   ("always-on background location").
3. Um único geofence (raio ~100 m ao redor do destino da visita, mesmo dado
   que já alimenta `RouteService`) é registrado via API nativa de geofencing
   (Android `Geofencing API` / `geolocator` com callback de geofence), não
   via polling contínuo de posição.
4. Ao entrar no geofence, o app marca localmente o check-in; a confirmação
   ainda é enviada ao backend pelo mesmo caminho de `visits.sync` já
   existente (campo novo, ex. `arrivalMethod: geofence|manual`), preservando
   dedupe/versionamento sem inventar um segundo canal de sincronização.

### Bloqueio externo

**Parcial.** A abordagem escolhida (geofence atrelado a visita ativa, com
serviço em primeiro plano) evita a política mais restritiva da Play Store,
mas a escolha final de plugin/implementação nativa e o texto de divulgação
exibido ao ACS (exigido por política de privacidade de apps com localização)
ainda dependem de revisão de produto/jurídico antes de submissão à loja —
isso não bloqueia o desenho do contrato, mas bloqueia a submissão final.

### Plano derivado (não executado nesta tarefa)

- Declarar o novo estado "visita ativa" como gatilho de um serviço em
  primeiro plano com notificação.
- Escolher e integrar a API de geofence (nativa via `geolocator`/
  `geofence_service`, ou equivalente já auditado como gratuito para uso
  comercial — verificação de licença fica para quem implementar).
- Adicionar `arrivalMethod` ao contrato de `visits.sync` e sua migração.
- Ajustar `AndroidManifest.xml` (permissão de localização em primeiro plano
  contínuo durante serviço ativo — não `ACCESS_BACKGROUND_LOCATION` amplo) e
  o texto de divulgação ao usuário.

---

## 5. Sincronização central → dispositivo (RF15, metade ausente)

### Estado atual

`visits.sync` (dispositivo → central) existe, testado, com dedupe por
`localId`, versionamento e checagem de território. **O sentido central →
dispositivo não existe**: não há endpoint que devolva ao ACS visitas/alertas
alterados por outra fonte, nem um endpoint de leitura de status para o
paciente (RF05, dependência do mesmo problema).

### Decisão aprovada

Adotar **sincronização por cursor incremental (pull), não push completo**,
reaproveitando os campos que já existem para controle de versão/conflito:

1. **Para o ACS:** `visits.pull({microAreaId, since})` devolve todo registro
   de `visits`/`alerts` da microárea do ACS autenticado com `version`/
   `updatedAt` maior que `since`, na mesma territorialização já aplicada em
   `patients.listMicroArea` (INV-01 continua valendo — território restringe
   o que é devolvido, não é um filtro de UI).
2. **Para o paciente (RF05):** um endpoint mínimo e escopado ao próprio
   paciente pelo token — ex. `alerts.statusFor(patientId)` a partir do
   `accessToken` da sessão, nunca por `patientId` arbitrário no argumento —
   para fechar a lacuna de INV-05 ("vacuamente verdadeiro" hoje porque o
   endpoint não existe) no mesmo movimento em que a tela deixar de ser
   `const`.
3. **Sem canal novo de transporte.** Isso é RPC comum (o mesmo cliente
   Serverpod já usado pelos dois apps), não MQTT — MQTT continua reservado
   para o caminho de latência crítica (alerta vermelho), e um pull incremental
   não precisa da mesma garantia de entrega em tempo real.
4. **Cursor por dispositivo, não por usuário.** Cada instalação do app
   guarda seu próprio `since` (mesmo padrão que `visits.sync` já usa para
   `localId`/versionamento local), para que reinstalar o app não implique
   perda silenciosa de sincronização nem duplicação.

### Bloqueio externo

Nenhum. É extensão do mesmo padrão de RPC/territorialização já implementado.

### Plano derivado (não executado nesta tarefa)

- ~~`visits.pull` no backend, com teste de território~~ — feito (plano de
  2026-09-17/18, Task 10 + consumo pelo ACS).
- ~~`alerts.statusFor` escopado ao token do paciente~~ — feito
  (`docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md`, Tasks
  2-3): sem `patientId` como parâmetro, então um token só pode ler o
  próprio status por construção (INV-05).
- ~~Tela de Status do paciente deixa de ser `const`~~ — feito (mesmo plano,
  Task 4): fecha L-03 do relatório de validação.
- ~~Consumo do cursor pelo app ACS (fila)~~ — feito: `VisitPullService` (Task
  10 do plano de implementação) mais a tela "Área" que o aciona e mostra o
  resultado (`docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md`).
- ~~Sincronização periódica em segundo plano~~ — feito (mesmo plano, Tasks 5
  e 6): `Timer.periodic` no shell do ACS e na tela Status do paciente, além
  do disparo ao abrir e do botão manual, pausado fora do primeiro plano.

RF15 está completo dos dois lados (ACS e paciente). O que falta para RF08
completo — cache `sqflite` persistido, não só a chamada ao vivo — é
trabalho novo, não coberto aqui.

---

## 6. Criptografia de colunas no PostgreSQL (RNF03, INV-04)

### Estado atual

`SQLCipher` no dispositivo do ACS está provado em hardware
(`encrypted_storage_test.dart`, citado no relatório de validação). No
Postgres, **nenhuma coluna é criptografada** — `patients.chronicConditions`,
`triage_sessions.answers` e `visits.notes` trafegam e residem em texto claro,
violação de INV-04 no lado servidor. `spec/lgpd_data_audit.md` (item 5 do
plano de ação) já recomenda `pgcrypto` ou criptografia simétrica na aplicação
para esses três campos.

### Decisão aprovada

**Criptografia de aplicação (Dart, na borda do repositório ORM), não
`pgcrypto` em SQL.** Motivos, ambos verificáveis no repositório:

1. O próprio `spec/lgpd_data_audit.md` (item 6 do plano de ação) já sinaliza
   que o `serverpod_query_log` pode registrar SQL em texto claro. Se a
   criptografia for feita via função SQL (`pgp_sym_encrypt`), o texto claro
   do dado de saúde passa pela camada de log de query antes de virar
   ciphertext. Criptografar em Dart, antes de a query ser montada, garante
   que o valor que chega à camada de log — se algum dia for reativado ou mal
   configurado — já é ciphertext.
2. **Segue o mesmo padrão de segredo já usado no projeto**
   (`scripts/dev/bootstrap_env.sh` gera `JWT_SECRET`/`AUDIT_CHAIN_SECRET`
   como valores aleatórios por máquina, injetados por variável de ambiente).
   Uma chave de criptografia de dados de saúde
   (`HEALTH_DATA_ENCRYPTION_KEY`, nome proposto) segue o mesmo mecanismo —
   sem introduzir um KMS externo novo, o que não está no `spec/stack.md`
   nem é necessário para o estágio atual (protótipo, não produção).
3. Evita depender de uma extensão de banco (`pgcrypto`) cuja disponibilidade
   no provedor gerenciado de produção não foi confirmada nesta tarefa —
   `backend/DEPLOY.md` diz que o Neon free tier não exige "extensões
   especiais" para as migrations *atuais*, o que não é o mesmo que confirmar
   suporte a `pgcrypto`; a aplicação não depender da extensão remove essa
   verificação do caminho crítico.

Especificação:

- **Campos afetados (mesmos do item 5 da auditoria):**
  `patients.chronicConditions`, `triage_sessions.answers`, `visits.notes`.
- **Algoritmo:** AES-256-GCM (mesma família já citada em RNF03/SQLCipher no
  restante do projeto — não introduz um algoritmo novo à stack).
  Encriptação/decriptação ocorrem na camada de repositório
  (`orm_*_store.dart`), nunca em `application/`, para o domínio continuar
  operando sobre valor claro em memória e o texto cifrado nunca vazar para
  lógica de negócio ou log de aplicação.
- **Coluna de versão de chave** (`keyVersion` ou equivalente) em cada tabela
  afetada, para permitir rotação futura sem exigir reescrita simultânea de
  todas as linhas.
- **Chave:** variável de ambiente única para o MVP (`HEALTH_DATA_ENCRYPTION_KEY`),
  gerada por `bootstrap_env.sh` como as demais. Um KMS gerenciado (ex. rotação
  automática, HSM) fica registrado como melhoria de produção, não requisito
  deste MVP — coerente com o estado do projeto ("protótipo funcional... não é
  produção", conforme `AGENTS.md`).

### Bloqueio externo

Nenhum para o MVP local/protótipo. A adoção de um KMS gerenciado para
produção real (fora do escopo declarado do repositório hoje) fica registrada
como decisão futura, não uma dependência que bloqueia esta decisão.

### Plano derivado (não executado nesta tarefa)

- Utilitário de criptografia em `backend/sinalacs_server/lib/src/infrastructure/`
  (AES-256-GCM, chave de `AppConfig`), com teste de que o valor gravado no
  banco não é o texto claro (mesmo padrão de prova usado por
  `encrypted_storage_test.dart` no cliente).
- Migração Serverpod adicionando `keyVersion` aos três modelos afetados.
- Ajuste de `bootstrap_env.sh` e `.env.example` para gerar/documentar
  `HEALTH_DATA_ENCRYPTION_KEY`.
- Atualizar `spec/lgpd_data_audit.md` (item 5) apontando para este documento
  quando a implementação e o teste existirem — não antes.

---

## 7. Resumo por status

| Item | Requisito(s) | Status desta decisão | Bloqueio externo? |
|---|---|---|---|
| Mapa/localização | RF10, L-05 | Aprovado (geocélula) | Não |
| Onboarding/consentimento | RF02, LGPD-RF02 | Aprovado | Não |
| Lembretes locais | RF06 | Aprovado | Não |
| Avisos push | RF14 | Contrato aprovado | **Sim** — projeto FCM inexistente |
| Geofencing | RF12 | Aprovado (atrelado a visita ativa) | Parcial — submissão à loja pendente de revisão |
| Sync central→dispositivo | RF15 (leitura), RF05, INV-05 | Aprovado (pull incremental) | Não |
| Criptografia Postgres | RNF03, INV-04 | Aprovado (app-level AES-256-GCM) | Não (KMS de produção é melhoria futura) |

Todos os itens marcados "Aprovado" são **planos**, não implementações. Nenhum
código de produção, migração, endpoint ou dependência nova foi adicionado por
esta tarefa.

---

## 8. Validações executadas nesta tarefa

Esta tarefa é documental; as validações abaixo confirmam que as descrições
acima refletem o estado real do código, não são reafirmações do relatório de
validação anterior sem checagem.

```bash
# Confirma que o envelope MQTT não carrega coordenada, só hash
grep -n "toJson" -A 10 backend/sinalacs_server/lib/src/domain/entities/alert_delivery.dart

# Confirma que não existe coluna de coordenada no schema de alerts/patients
grep -rn "lat\|lng\|latitude\|longitude" backend/sinalacs_server/lib/src/models/

# Confirma zero escritores de consent_logs além do gerado
grep -rn "ConsentLog(" backend/sinalacs_server/lib/src --include=*.dart | grep -v /generated/

# Confirma que flutter_local_notifications está declarado mas sem consumidor,
# e que não há dependência de firebase
grep -n "flutter_local_notifications\|firebase" apps/patient/pubspec.yaml
grep -rln "flutter_local_notifications" apps/patient/lib/**/*.dart

# Confirma que RouteService não usa geofencing nativo nem background location
grep -n "Geofence\|background" apps/acs/lib/core/services/route_service.dart apps/acs/android/app/src/main/AndroidManifest.xml
```

Resultados (resumo — saída completa no relatório da tarefa):
- `alert_delivery.dart`: envelope confirmado com apenas `location_hash`.
- Nenhuma ocorrência de coluna de coordenada em `models/`.
- Nenhum escritor de `ConsentLog(` fora de `generated/`.
- `flutter_local_notifications` está declarado no `pubspec.yaml` do paciente,
  mas nenhum arquivo em `lib/` o importa — dependência sem consumidor, não
  ausência de dependência. Nenhuma dependência de Firebase/push existe.
- Nenhuma referência a geofence nativo ou permissão de background location
  no app ACS.
