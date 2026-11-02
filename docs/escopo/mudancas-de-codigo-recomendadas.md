# Mudanças de código recomendadas — não implementadas neste plano

Mudanças necessárias para alinhar os apps e o backend ao escopo educativo e
aberto ([`spec/escopo_projeto.md`](../../spec/escopo_projeto.md)). Este
documento só as registra; a implementação é um plano próprio. Os IDs são
estáveis: nunca renumerar. Prioridades e requisitos citados estão em
[`spec/requisitos_piloto.md`](../../spec/requisitos_piloto.md); o portão está
descrito em [`spec/plano_piloto.md`](../../spec/plano_piloto.md).

## Portão do piloto — segurança e legal

Nenhuma coleta com participantes antes destas (M-01).

| ID | Arquivo | Mudança | Motivo | Bloqueado por |
|---|---|---|---|---|
| C-01 | `apps/patient/lib/core/legal/legal_documents.dart` | Controlador e encarregado conforme P-02; retirar "da Secretaria" e "sua UBS"; incluir o aviso educativo canônico longo (M-08); nova `LegalVersion` e novo `consentPolicyVersion` (o próprio arquivo exige versão nova a cada troca de texto) | D6, RF21 | P-02 |
| C-02 | Apps do paciente e do agente (tela inicial e "Sobre") | Tela de primeira abertura e tela "Sobre" com o aviso educativo canônico | RF21, D12 | — |
| C-04 | App do paciente e backend (`alerts`) | **Mudança de comportamento, não só de texto:** o alerta vira pedido de contato sem rótulo de urgência; "Ligar 192" aparece antes de qualquer pedido; a saída "Ligar 192" da autoavaliação não gera pedido, exige escolha explícita do participante para fechar a orientação e grava um evento numa trilha local cifrada de eventos do aparelho (**inexistente hoje**: criar, cifrada, junto com esta mudança); o status não usa "Atendido" como promessa. INV-03 continua valendo — ver [`spec/requisitos_piloto.md` §INV-03 no piloto](../../spec/requisitos_piloto.md#inv-03-no-piloto). Testes exigidos: pedido enviado nunca some (os testes de INV-03 existentes seguem verdes); a saída 192 grava o evento local e não chama `alerts.createRedAlert` | RF03, RF05, D3 | P-09 |
| C-05 | `backend/sinalacs_server/lib/src/config/app_config.dart` e app do paciente | RF24: convite QR + PIN local, identificador pseudônimo, sem CPF e sem SMS, e-mail opcional. Hoje, fora de `development`, o servidor não sobe sem `SMS_GATEWAY`; essa exigência deixa de valer no perfil do piloto | RF24, RNF08, RNF09, D7 | P-10 |
| C-06 | Textos "UBS" e "coordenação da UBS" nos três apps — ex.: `apps/patient/lib/app/app.dart:1966,2035`, `apps/acs/lib/app/device_wiped_screen.dart:46-47`, `apps/admin/lib/app/app.dart:341,716`, `apps/admin/lib/app/admin_accounts.dart:421,507,681`, `apps/admin/lib/app/audit_log_screen.dart:498` | Trocar por "grupo do piloto" e "coordenação do piloto". Entra no portão porque "UBS" aparece hoje a participantes. Renomear `ubs.spy.yaml` (migração) fica como dívida técnica separada, fora do portão | D4 | — |
| C-08 | App do paciente (tela de resultado da triagem) | Autoavaliação com três saídas — "Cuidar-se em casa", "Procurar atendimento", "Ligar 192" — sem cor ou rótulo de risco clínico ao participante. O cálculo do motor determinístico (`TriageEngine`) não muda: mesma entrada, mesmo resultado, nunca alterável manualmente (INV-02). O que muda é o texto exibido **e**, para a saída "Ligar 192", o envio — essa parte do comportamento é a de C-04, da qual C-08 depende | RF04, RF16 | P-11 |
| C-10 | App do paciente | Opção "Apagar meus dados" em "Sobre"/configurações, disponível sem cadastro, que apaga banco local, lembretes e a trilha local de eventos do aparelho (criada em C-04; inexistente hoje) (e, se houver sessão do pilar B, encerra a sessão e abre o pedido de eliminação já existente); expiração automática dos eventos locais de auditoria em 30 dias. Motivo: dados de saúde locais do pilar A sem caminho de eliminação; o wipe (#81) só alcança aparelhos de agentes. Testes exigidos: depois de "Apagar meus dados" não resta nenhum evento local; evento com mais de 30 dias some na próxima abertura | RNF09, LGPD-RF07 | — |
| C-11 | `apps/patient/lib/core/network/backend_client.dart:450` (chamada a `triage.evaluate`) e `backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart` | No pilar A, a autoavaliação roda **localmente**, sem sessão e sem registro no servidor: o app executa a mesma árvore de decisão do `TriageEngine` no aparelho (mesma entrada, mesmo resultado — INV-02), sem `accessToken` e sem gravar em `triage_sessions`. Hoje `triage.evaluate` exige `accessToken` e grava a sessão no servidor, o que contradiz o pilar A "sem cadastro" e RNF09. A chamada remota fica só no pilar B, com sessão. Testes exigidos: sem login, a autoavaliação produz o mesmo resultado que o motor do backend para as 64 combinações de sinais e não faz nenhuma chamada de rede | RF04, RF16, RF22, RNF09 | P-11 |

## Portão do piloto — funcional

Obrigatório se o pilar A estiver no piloto.

| ID | Arquivo | Mudança | Motivo | Bloqueado por |
|---|---|---|---|---|
| C-03 | App do paciente | Biblioteca de conteúdo educativo offline, sem login, com fontes citadas | RF20, RF22; sem ela não se mede o objetivo (a) do piloto nem o ganho de conhecimento | P-07 |

## Demais

| ID | Arquivo | Mudança | Motivo | Bloqueado por |
|---|---|---|---|---|
| C-07 | `apps/acs/lib/app/app.dart:4017,4051`, `apps/acs/lib/core/services/emergency_dialer.dart`, `backend/sinalacs_server/lib/src/models/api/ubs_contact.spy.yaml` | Manter só a discagem para 192; retirar "Ligar para a UBS" | RF13 Futuro, D5 | — |
| C-09 | Toda ocorrência de "Manchester" em código encontrada no inventário ([`inventario-vinculo-institucional.md`](inventario-vinculo-institucional.md), I-48): `backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart:7` (que gera `backend/sinalacs_client/lib/src/protocol/client.dart:1291`) e `video/roteiro.timing.json:140`. Nenhuma ocorrência em `apps/` no levantamento de 2026-11-01 | Remover a marca de comentários e textos | M-05 | — |
