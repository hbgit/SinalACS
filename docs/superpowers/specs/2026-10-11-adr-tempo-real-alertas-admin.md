# ADR: tempo real do backoffice por polling (issue #44)

**Data:** 2026-10-11
**Status:** Aprovado (decisão do usuário)
**Issue:** #44 (alertas: escalonar e atualizar em tempo quase real)
**Substitui:** nada. Não altera a decisão T4 do PRD (MQTT para os alertas do ACS), que continua valendo.

Arquivos envolvidos: `apps/admin/lib/app/app.dart` (`AlertsScreen`, `IndicatorsScreen`) e `backend/sinalacs_server/lib/src/application/admin/admin_read_service.dart`.

## Contexto

O backoffice (`apps/admin`) lê alertas e indicadores por RPC, sob demanda. A #44 exige que o coordenador veja alertas novos e vencidos sem recarregar a tela. É supervisão: quem responde ao alerta continua sendo o ACS.

Fatos verificados no repositório:

- O ACS recebe alertas e reforços de escalonamento por MQTT. Isso não muda, qualquer que seja a opção abaixo.
- A meta de TMRAV do PRD (< 90 s, `spec/PRD_system.md`) mede o intervalo entre o acionamento e a confirmação do ACS, não a latência da tela do coordenador.
- O broker (`infra/docker/mosquitto/aclfile`) tem dois usuários: `backend` (`readwrite sinalacs/v1/#`) e `acs-area-12`, que lê o tópico `sinalacs/v1/microareas/<UUID da microárea>/alerts` e escreve em `sinalacs/v1/alerts/+/acks`. Os tópicos são por microárea. Não existe tópico por UBS, então uma ACL não expressa "UBS do coordenador".
- `mosquitto.conf` exige certificado de cliente (`require_certificate true`) além de senha e ACL. O provisionamento de certificado por aparelho em produção é pendência declarada: mTLS só existe na stack local (`CLAUDE.md`).
- `AdminReadService` já resolve papel e escopo por UBS em todo método e grava a auditoria antes de devolver dado: usa `record`, não `recordSafely`, de modo que, se a linha não grava, nenhum dado sai.

## Opções

| Critério | A. Polling (30 s) | B. MQTT com ACL própria do admin |
|----------|-------------------|----------------------------------|
| **Latência** | até 30 s mais o RTT. Supervisão tolera 30 s; o TMRAV de 90 s diz respeito à resposta do ACS | menos de 1 s |
| **Custo** | 1 requisição leve por coordenador a cada 30 s | 1 conexão longa por coordenador |
| **Complexidade** | nenhuma infraestrutura nova; reusa o JWT e o escopo por UBS já provados | usuário e senha de broker, mais certificado de cliente por aparelho (sem provisionamento de produção). Exigiria criar tópicos por UBS, que hoje não existem |
| **Offline** | falha mantém o último dado e mostra o selo "desatualizado"; retoma sozinho | reconexão e QoS 1 reentregam, mas a UI precisaria do mesmo selo |
| **Privacidade** | resposta pseudonimizada, escopo checado no servidor a cada chamada | o payload repetiria o filtro de UBS fora do banco: segunda implementação da regra de escopo |
| **Segurança** | superfície já auditada | superfície nova: ACL e credenciais de broker dentro do app do admin |

## Decisão

**Opção A: polling a cada 30 s** em `AlertsScreen` e `IndicatorsScreen`, por meio de um endpoint novo, `admin.alertsPulse`. A opção B fica registrada como evolução futura (ver "Quando reavaliar").

### Política de auditoria da monitoração (D5)

Hoje o servidor audita **toda** leitura do backoffice: `AdminReadService._auditar` grava uma linha `read` (`resourceType` `admin_alerts` ou `admin_indicators`) via `audit.record`, fail-closed, antes de devolver o dado. O `recordAccess` do app (`backend_admin_data_source.dart`) é um no-op justamente por isso. Com polling, esse desenho geraria uma linha por coordenador a cada 30 s. A tela de monitoração (lista de alertas e dashboard) passa a ser tratada como uma **sessão**:

1. **O app consulta só `admin.alertsPulse`** (endpoint novo, previsto na Task 9). O pulso embute os `AdminIndicators` completos (contagens e TMRAV), mais `overdueRed`, `maxChangedAt` e `serverNow`. Não traz identidade. O dashboard se atualiza pelo pulso; `admin.indicators` não é consultado em loop.
2. **A lista recarrega por `admin.alerts`** (existente) só quando `maxChangedAt` muda. Essa leitura continua auditada como hoje (`read`), porque lê dado de fato.
3. **`MONITORING_SESSION_START` é gravado no servidor** por `admin.alertsPulse` quando o chamador não tem sessão viva, isto é, nenhum pulso nos 90 s anteriores (3 vezes o intervalo). O servidor guarda um mapa em processo `userId -> lastPulseAt` (backend de instância única, conforme o PRD; um reinício só abre uma sessão nova, na direção conservadora). Não há endpoint de início separado. É fail-closed (`record`): o primeiro pulso ao abrir a tela grava START, e se a linha falha, nenhum dado sai.
4. **`MONITORING_SESSION_END`** vem de `admin.endMonitoringSession` (com checagem de papel e escopo), chamado ao descartar a tela ou perder o foco. É best-effort e usa `recordSafely`: a única exceção justificada à regra do projeto de usar `record`, porque a linha de fim não protege dado algum. O app pode ser morto ou perder a rede.
5. **Sessão órfã:** o servidor compensa. Um pulso que chega mais de 90 s depois do anterior, sem END, abre uma sessão nova e grava START de novo; as órfãs ficam visíveis na trilha.
6. **Recusas** (papel ou escopo) no pulso e no END são sempre auditadas.

### Intervalo e selo de desatualizado

- Intervalo de 30 s. O temporizador pausa com o app em segundo plano.
- Limite de "desatualizado": 60 s (2 vezes o intervalo, tolera um poll falho).
- Passado o limite, a UI mantém o último dado e mostra o banner "Dados de HH:mm:ss — sem atualização há N min". O banner usa ícone e texto, não só cor, e tem semântica de `liveRegion`. Some sozinho quando um poll volta a ter sucesso.

## Consequências

- Não há infraestrutura nova, nem credencial de broker no app do admin. O escopo por UBS continua com uma única implementação.
- Latência de supervisão de até 30 s mais o RTT. É aceita explicitamente.
- **Fim das linhas `read` por tela:** com polling, as chamadas de atualização das telas deixam de produzir uma linha `read` por leitura. Só geram linha o START, o END, as recusas e as recargas reais da lista por `admin.alerts` (quando `maxChangedAt` muda). Chamadas pontuais fora do polling (por exemplo, o primeiro carregamento) seguem auditadas como hoje.
- **Custo da D5:** "leitura contínua = sessão". A trilha deixa de ter uma linha por leitura e passa a ter início e fim de sessão. A granularidade é menor, e o END é best-effort. A compensação por sessão órfã (90 s) e a auditoria sempre ligada das recusas limitam a perda. Quem audita lê a duração de uma sessão, não cada poll.
- O endpoint de poll precisa guardar o instante do último poll por sessão para aplicar a regra dos 90 s.
- **Limite conhecido:** o app do ACS não tem som nem vibração no alerta. Isso é independente desta decisão e continua pendência do app do ACS.
- O ACS segue recebendo alertas e reforços por MQTT, sem mudança.

## Quando reavaliar

Reavaliar a opção B (MQTT para o backoffice) só se as duas condições valerem juntas:

1. existir provisionamento de certificado de cliente por aparelho em produção (hoje mTLS é só da stack local);
2. a latência de supervisão virar requisito (por exemplo, uma meta de tempo de percepção do coordenador menor que 30 s).

Antes disso seria preciso definir como a ACL expressa a UBS (tópicos por UBS) sem duplicar a regra de escopo fora do banco.
