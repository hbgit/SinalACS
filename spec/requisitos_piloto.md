# Requisitos priorizados para o piloto

As prioridades abaixo seguem as decisões aprovadas P-09, P-10 e P-11 ([`escopo_projeto.md#pendencias`](escopo_projeto.md#pendencias)). Se alguma for revista e rejeitada:

- **P-09 rejeitada:** RF03 volta ao texto original do PRD **e passa a Futuro** no piloto. Rejeitar P-09 **nunca** significa manter o alerta com rótulo de urgência no piloto: sem a reformulação como pedido de contato, a função simplesmente não entra. Rejeitar P-09 retira o RF03 do piloto; nunca reintroduz o rótulo de urgência.
- **P-10 rejeitada:** RF24 sai do piloto e RF01 volta a Desejável, com a forma de login escolhida pela equipe. Se a escolha incluir CPF, **RNF09 é revisto** (deixa de dizer "sem CPF no piloto" e passa a exigir justificativa registrada da coleta) e C-05 é refeito para essa forma de login.
- **P-11 rejeitada:** RF04 passa a **Futuro** até haver parecer jurídico — não Desejável, porque Desejável ainda permitiria levar ao piloto a autoavaliação com cores e classificação de risco, que é o que gera o risco de enquadramento como software dispositivo médico. C-08 sai do portão, e **C-04 é revisto**: sem as três saídas não existe a saída "Ligar 192", então o caminho que não envia nada perde a definição; o botão "Ligar 192" permanece como ação fixa antes de qualquer pedido de contato.

> Conteúdo educativo. Não substitui atendimento profissional. Emergência: ligue 192.

Este documento atribui a cada requisito do [PRD](PRD_system.md) uma prioridade
no piloto e acrescenta os requisitos novos. **Os identificadores existentes não
mudam de significado nem são renumerados** — o código, os testes e as issues os
citam. Requisitos novos começam em RF20 e RNF07. Pilares e papéis estão em
[`escopo_projeto.md`](escopo_projeto.md); as mudanças de código citadas (C-NN)
estão em [`docs/escopo/mudancas-de-codigo-recomendadas.md`](../docs/escopo/mudancas-de-codigo-recomendadas.md).

Prioridades: **Essencial** (o piloto não começa sem), **Desejável** (entra se
estiver pronto), **Futuro** (fora do piloto; ver
[`trabalhos_futuros.md`](trabalhos_futuros.md)). Nenhum requisito Essencial
depende de unidade de saúde, de sistema oficial ou de serviço pago sem
alternativa gratuita.

## Requisitos funcionais

| ID | Requisito | Pilar | Prioridade no piloto | Depende de instituição ou serviço pago? | Observação |
|---|---|---|---|---|---|
| RF01 | Autenticação passwordless (CPF + data de nascimento + OTP) | — | Futuro | Sim (gateway SMS pago) | Sem CPF e sem SMS no piloto (P-10); substituído por RF24. |
| RF02 | Onboarding por QR Code (agente gera, participante escaneia) | B | Essencial | Não | Convite emitido pelo agente participante; base do RF24. |
| RF03 | Envio do participante ao agente (no PRD, "botão de alerta de urgência") | B | Desejável | Não | No piloto: **pedido de contato com o agente participante**, sem rótulo de urgência. Maior gravidade na autoavaliação → só "Ligar 192", sem envio (P-09, C-04). INV-03 vale para o pedido (ver [INV-03 no piloto](#inv-03-no-piloto)). |
| RF04 | Formulário de autoavaliação estruturada (árvore de decisão) | A | Essencial **somente** com as três saídas de P-11; se P-11 for rejeitada, Futuro | Não | Orientação educativa com as saídas "Cuidar-se em casa", "Procurar atendimento" e "Ligar 192"; nunca "classificação de risco". No pilar A roda localmente, sem sessão e sem registro no servidor (C-11; hoje exige login). |
| RF05 | Painel de status da solicitação | B | Desejável | Não | Estados descritivos do pedido de contato; sem "Atendido" como promessa. |
| RF06 | Lembretes de saúde locais | A | Essencial | Não | Sem servidor. |
| RF07 | Login do agente (identificador + senha + TOTP) | B | Essencial | Não | Identificador emitido pela equipe do projeto, não por Secretaria. |
| RF08 | Territorialização (download da microárea) | B | Essencial | Não | Território do grupo do piloto. |
| RF09 | Dashboard de priorização da fila | B | Essencial | Não | — |
| RF10 | Mapa interativo | B | Essencial | Não | Geocélula arredondada, como já implementado. |
| RF11 | Registro de visitas offline | B | Essencial | Não | — |
| RF12 | Geofencing (check-in passivo) | — | Futuro | Não | Exige política de localização em segundo plano na loja. |
| RF13 | Escalonamento para SAMU/UBS | — | Futuro | Sim (UBS) | Fica só a discagem local para 192, que não é integração (C-07). |
| RF14 | Avisos segmentados (push) | B | Desejável | Não | FCM sem custo; o app funciona sem push. |
| RF15 | Sincronização bidirecional | B | Essencial | Não | — |
| RF16 | Motor de autoavaliação determinístico | A | Essencial | Não | "Motor de autoavaliação determinístico por árvore de decisão fechada"; validação clínica é Futuro. |
| RF17 | Logs de auditoria (LGPD) | B | Essencial | Não | — |
| RF18 | Modo escuro | — | Desejável | Não | — |
| RF19 | Escalonamento de pedido sem confirmação | B | Desejável | Não | Para a coordenação do piloto, não para UBS. |
| **RF20** | Conteúdo educativo offline (biblioteca de temas, sem cadastro) | A | Essencial | Não | Fontes: materiais públicos do Ministério da Saúde e da BVS, sempre citados; revisão por preceptores do PET-Saúde antes de cada versão (P-07); conteúdo autoral sob CC BY 4.0, trechos de terceiros só com licença compatível ou em paráfrase com citação. C-03. |
| **RF21** | Aviso educativo na primeira abertura, em "Sobre" e no texto legal | A | Essencial | Não | Texto canônico de [`escopo_projeto.md#aviso-educativo`](escopo_projeto.md#aviso-educativo) (M-08). C-01, C-02. |
| **RF22** | Uso sem cadastro (conteúdo e lembretes) | A | Essencial | Não | — |
| **RF23** | Questionários do piloto (pré/pós, SUS, reconhecimento do aviso) | — | Desejável | Não | Pode ser formulário externo sem dado de saúde; nesse caso o serviço é **operador de dados pessoais** e precisa constar no TCLE (P-04) e na §0 de [`lgpd_design.md`](lgpd_design.md). Instrumentos e serviço: decisão proposta P-12 (status: Proposta). |
| **RF24** | Acesso do participante ao acompanhamento por convite QR + PIN local, identificador pseudônimo, sem e-mail, sem CPF e sem SMS no login; recuperação de acesso por novo convite QR do agente participante, vinculado ao mesmo identificador pseudônimo, após confirmação presencial pelo agente, invalidando a sessão do aparelho anterior (C-12) | B | Essencial | Não | P-10, C-05. |

## Requisitos não funcionais

| ID | Requisito | Prioridade no piloto | Depende de instituição ou serviço pago? | Observação |
|---|---|---|---|---|
| RNF01 | Latência MQTT < 500 ms (p95) | Desejável | Não | Só relevante com RF03 ativo. |
| RNF02 | Sincronização offline > 99,5% | Essencial | Não | — |
| RNF03 | Criptografia AES-256 em repouso | Essencial | Não | — |
| RNF04 | TLS 1.3 em todas as comunicações | Essencial | Não | Certificado por Let's Encrypt pelo Traefik, sem cert-manager. |
| RNF05 | Acessibilidade WCAG AA | Essencial | Não | — |
| RNF06 | RBAC | Essencial | Não | — |
| **RNF07** | Implantável por terceiros com um `docker compose` **e** APK assinado publicado em GitHub Releases, custo mensal ≤ teto de P-08 | Essencial | Não | M-03. |
| **RNF08** | Nenhum componente Essencial depende de serviço pago sem alternativa gratuita (SMS e Play Store incluídos) | Essencial | Não | — |
| **RNF09** | Coleta mínima: nenhum dado pessoal para o pilar A; sem CPF e sem e-mail no piloto; dados da visita (microárea, endereço ou ponto de referência) só o necessário, conforme RF09/RF10 | Essencial | Não | Revisto se P-10 for rejeitada (ver topo). |
| **RNF10** | Documentação em pt-BR; licença MIT para o código; conteúdo educativo autoral sob CC BY 4.0 (P-07) | Essencial | Não | — |

<a id="inv-03-no-piloto"></a>
## INV-03 no piloto

1. INV-03 vale para todo pedido de contato com o agente participante: um pedido enviado nunca é descartado em silêncio (entrega com ACK, reserva HTTP, escalonamento RF19).
2. A saída "Ligar 192" da autoavaliação **não gera pedido de contato** — é uma mudança de comportamento do sistema (C-04), não só de apresentação. Ela não é descarte silencioso porque: (a) a orientação "Ligar 192", com o botão de discagem, é exibida ao participante antes de qualquer outra ação e não pode ser fechada sem uma escolha explícita; (b) a exibição fica registrada localmente na trilha de auditoria do aparelho — trilha local cifrada criada na C-04 (#127): tabela `local_events` do banco SQLCipher do app do paciente — (evento com data, hora e versão do motor; sem respostas em texto claro).

   Esse evento é **dado de saúde** (revela que a pessoa recebeu a orientação de maior gravidade), mesmo sem as respostas. Fica só no aparelho, cifrado, é apagado automaticamente após **30 dias** (prazo proposto, ajustável no TCLE, P-04) e pode ser apagado a qualquer momento pela opção "Apagar meus dados" (C-10).
3. Se o participante, depois de ver a orientação, quiser também falar com o agente, o pedido de contato é um ato separado e volta a estar sob INV-03.
