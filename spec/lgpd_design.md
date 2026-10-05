# Documento de Conformidade LGPD - SinalACS

## Sumário Executivo

Este documento apresenta a especificação completa de requisitos de conformidade com a Lei Geral de Proteção de Dados Pessoais (LGPD - Lei nº 13.709/2018) para a plataforma SinalACS. A análise considera a arquitetura *offline-first*, o fluxo bidirecional de dados entre pacientes e Agentes Comunitários de Saúde (ACS), e a natureza sensível dos dados de saúde processados pela solução.

A estratégia de conformidade adota os princípios de **Privacy by Design** e **Privacy by Default**, integrando controles de proteção de dados desde a concepção arquitetural até a interface com o usuário final.

---

## 1. Requisitos de Conformidade LGPD para o Sistema

### Implementação atual do hash de localização

O app do paciente lê a localização somente em primeiro plano, quando a pessoa
confirma um alerta. Latitude e longitude não são enviadas ao backend nem ao
MQTT: são normalizadas em seis casas decimais e transformadas em um digest
SHA-256 truncado para `locationHash`. Quando a permissão, o serviço ou o GPS
falham, o alerta continua sendo enviado com `unknownLocationHash`, e a tela
informa que a localização não foi anexada.

Esse hash é pseudonimização, não anonimização. A precisão atualmente adotada
pode permitir reidentificação por força bruta ou correlação com a microárea,
especialmente em áreas rurais. A validação em dispositivo ainda é obrigatória
para fechar L-02.

**Decisão de produto (2026-09-16):** a alternativa aprovada para o mapa do
ACS (RF10, achado L-05) é a **geocélula arredondada** — reduzir a precisão da
normalização antes do hash (de seis para três casas decimais por padrão) e
transmitir, além do `locationHash` já existente, uma célula espacial de baixa
resolução (`locationCell`) só para desenho do mapa, nunca a coordenada crua.
Essa decisão ainda não foi implementada — nenhuma migração, endpoint ou app
foi alterado por ela. Ver
`docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §1 para
o desenho completo (quem lê cada dado, retenção e o que muda no envelope
MQTT). `spec/validation_report.md` continua classificando L-05/RF10 como
bloqueador até essa implementação existir com teste.

### LGPD-RF01 - Coleta Mínima e Transparente

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Coleta Mínima e Transparente de Dados |
| **Descrição** | O sistema deve coletar exclusivamente os dados estritamente necessários para cada funcionalidade, informando claramente ao usuário quais dados estão sendo coletados, para que finalidade e por quanto tempo serão armazenados. |
| **Objetivo** | Garantir que a coleta de dados seja proporcional, necessária e transparente, evitando excessos e respeitando a autodeterminação informativa do titular. |
| **Base Legal** | Art. 6º (Finalidade, Adequação e Necessidade), Art. 9º (Acesso à informação), Art. 18 (Direitos do titular) |
| **Artigos LGPD** | 6º, I, II e III; 9º; 18, V |
| **Critério de Aceite** | ✓ Checklist de dados por funcionalidade documentado<br>✓ Todas as telas de coleta exibem finalidade específica<br>✓ Nenhum dado é coletado sem justificativa documentada<br>✓ Usuário pode visualizar todos os dados coletados sobre si |

### LGPD-RF02 - Consentimento Explicitado e Granular

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Consentimento Explicitado e Granular |
| **Descrição** | O consentimento deve ser obtido de forma livre, informada e inequívoca, com opções granulares para diferentes finalidades de tratamento (ex: alertas de saúde, comunicação geral, compartilhamento com equipe de saúde). |
| **Objetivo** | Assegurar que o titular tenha controle efetivo sobre o tratamento de seus dados, podendo consentir com finalidades específicas de forma independente. |
| **Base Legal** | Art. 5º, XII e XIII; Art. 7º, I; Art. 8º |
| **Artigos LGPD** | 5º, XII; 7º, I; 8º, §1º, §2º, §3º, §4º, §5º, §6º |
| **Critério de Aceite** | ✓ Consentimento é requerido para cada finalidade distinta<br>✓ Opções de consentimento são independentes (não agrupadas)<br>✓ Registro de consentimento com timestamp e versão<br>✓ Possibilidade de revogação por finalidade específica |

**Estado atual (verificado 2026-09-18):** `consent_logs` é gravada por
`OnboardingService.completeEnrollment` para as três finalidades (§2 de
`docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`).
Do lado da leitura: `ConsentPurpose.localReminders` agora é respeitada —
`RemindersScreen` (`apps/patient/lib/app/app.dart`) só agenda notificações
locais quando o consentimento espelhado no aparelho
(`core/consent/consent_preferences.dart`) é `true`, com padrão de recusa
(`false`) quando não há registro local.

**`ConsentPurpose.segmentedPush` tem leitor, no servidor e no aparelho.** RF14
(avisos segmentados por push) respeita o consentimento no **servidor**:
`notices.sendSegmented` usa a linha de consentimento **mais recente** de cada
titular (não a existência do token) antes de montar a lista, e
`devices.registerPushToken` só guarda o token com o consentimento vigente. O envio
foi provado de ponta a ponta num emulador Android em 2026-09-30 (ver PROGRESS.md,
"RF14: Gorush e FCM provados no emulador").

**Aparelho (2026-09-30):** o app só pede o token ao FCM depois de
`patients.hasGrantedConsent(segmentedPush)` devolver `true` (um `bool`, teto de 3 s;
falha, estouro ou "nunca decidiu" = não pergunta; resposta tardia é descartada).
A consulta **não** lê o painel "Meus dados" e não grava auditoria de leitura: a
primeira versão usava `myData`, que decifra e devolve o dossiê clínico e grava uma
linha "titular abriu o painel" a cada login — trocada na revisão independente. Quem
acabou de gravar a concessão (onboarding ou interruptor em "Meus dados") registra
sem perguntar. O auto-init do FCM, que falaria com o Google em toda abertura, está
desligado no manifesto.

**Limite conhecido:** se o consentimento for revogado (neste ou em outro aparelho)
entre a resposta do servidor e o pedido do token, o aparelho pode falar com o
Google uma vez depois da revogação. O servidor continua certo: `registerPushToken`
relê o consentimento sob lock e não guarda token sem base legal. O texto do aviso
também passa pelo FCM (Google): decisão de produto da §3.2, não tratada aqui.

### LGPD-RF03 - Gerenciamento de Preferências de Privacidade

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Gerenciamento de Preferências de Privacidade |
| **Descrição** | O sistema deve disponibilizar um painel centralizado onde o usuário pode visualizar e modificar todas as suas preferências de privacidade, incluindo quais dados são coletados, como são usados e com quem são compartilhados. |
| **Objetivo** | Empoderar o titular com controle centralizado e intuitivo sobre suas informações pessoais, fortalecendo a transparência e a autodeterminação. |
| **Base Legal** | Art. 9º, Art. 18, V e VI |
| **Artigos LGPD** | 9º, §1º; 18, V e VI |
| **Critério de Aceite** | ✓ Painel de privacidade acessível em até 3 cliques<br>✓ Opções incluem: aceitar/revogar consentimentos, exportar dados, solicitar correção<br>✓ Alterações são refletidas em tempo real no sistema |

### LGPD-RF04 - Registro e Auditoria de Consentimentos

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Registro e Auditoria de Consentimentos |
| **Descrição** | Todo consentimento fornecido ou revogado deve ser registrado com metadados completos: timestamp, versão do termo, IP (anonimizado), dispositivo, e agente (paciente ou ACS). Os registros devem ser imutáveis e auditáveis. |
| **Objetivo** | Garantir rastreabilidade e comprovação documental dos consentimentos, atendendo ao princípio da responsabilização e prestação de contas. |
| **Base Legal** | Art. 8º, §2º e §6º; Art. 37 |
| **Artigos LGPD** | 8º, §2º, §6º; 37 |
| **Critério de Aceite** | ✓ Tabela `consent_logs` com campos: id, user_id, purpose, action (grant/revoke), timestamp, version, ip_hash<br>✓ Registros não podem ser alterados ou deletados<br>✓ Interface de consulta para auditoria interna |

### LGPD-RF05 - Revogação de Consentimento

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Revogação de Consentimento |
| **Descrição** | O titular deve poder revogar seu consentimento a qualquer momento, por meio de um processo claro, gratuito e tão simples quanto o processo de obtenção. A revogação deve ser efetiva em até 15 dias. |
| **Objetivo** | Assegurar o direito do titular de retirar seu consentimento sem prejuízos, garantindo que a revogação seja eficaz e documentada. |
| **Base Legal** | Art. 8º, §5º e §6º |
| **Artigos LGPD** | 8º, §5º, §6º |
| **Critério de Aceite** | ✓ Botão "Revogar Consentimento" acessível no perfil<br>✓ Confirmação explícita antes da revogação<br>✓ Dados deixam de ser processados para a finalidade revogada em até 15 dias<br>✓ Usuário é notificado da efetivação da revogação |

### LGPD-RF06 - Compartilhamento com Terceiros

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Compartilhamento com Terceiros |
| **Descrição** | O sistema deve documentar e comunicar todos os compartilhamentos de dados pessoais com terceiros (ex: SAMU, UBS, Secretaria de Saúde), incluindo finalidade, categorias de dados compartilhados, e medidas de proteção adotadas. |
| **Objetivo** | Garantir transparência sobre o fluxo de dados e responsabilizar os operadores pelo tratamento adequado. |
| **Base Legal** | Art. 7º, §1º; Art. 33; Art. 39 |
| **Artigos LGPD** | 7º, §1º; 33; 39 |
| **Critério de Aceite** | ✓ Lista de terceiros aprovados documentada<br>✓ Contratos com cláusulas de proteção de dados<br>✓ Registro de todos os compartilhamentos realizados<br>✓ Usuário informado sobre quais dados são compartilhados e com quem |

### LGPD-RF07 - Retenção e Exclusão de Dados

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Retenção e Exclusão de Dados |
| **Descrição** | O sistema deve implementar políticas de retenção baseadas na finalidade do tratamento. Dados de saúde (alertas, triagens, visitas) devem ser retidos pelo prazo mínimo legal (5 anos) e, após esse período, anonimizados ou eliminados de forma segura. |
| **Objetivo** | Cumprir obrigações legais de guarda documental, garantindo que dados não sejam mantidos por tempo superior ao necessário. |
| **Base Legal** | Art. 15, I e II; Art. 16, I e II; Art. 17; Política Nacional de Atenção Básica |
| **Artigos LGPD** | 15, I e II; 16, I e II; 17 |
| **Critério de Aceite** | ✓ Política de retenção documentada e aprovada<br>✓ Mecanismo automático de expurgo após prazo legal<br>✓ Dados de pacientes que revogam consentimento são excluídos em até 15 dias<br>✓ Logs de exclusão registrados |

### LGPD-RF08 - Direitos do Titular dos Dados

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Direitos do Titular dos Dados |
| **Descrição** | O sistema deve implementar mecanismos para que o usuário exerça todos os direitos previstos no Art. 18 da LGPD: confirmação da existência de tratamento, acesso aos dados, correção, anonimização, bloqueio, eliminação, portabilidade, informação sobre compartilhamento, e revogação do consentimento. |
| **Objetivo** | Garantir que todos os direitos do titular sejam exercíveis de forma simples e efetiva, cumprindo integralmente o Art. 18 da LGPD. |
| **Base Legal** | Art. 18 (todos os incisos) |
| **Artigos LGPD** | 18, I a IX |
| **Critério de Aceite** | ✓ Todos os direitos mapeados em funcionalidades<br>✓ Interface para solicitação de cada direito<br>✓ Processo de atendimento documentado<br>✓ SLA de 15 dias para atendimento |

### LGPD-RF09 - Segurança da Informação (Dados Sensíveis)

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Segurança da Informação para Dados Sensíveis |
| **Descrição** | Dados sensíveis de saúde (condições crônicas, classificações de risco, alertas de urgência) devem ser protegidos com criptografia em repouso (AES-256) e em trânsito (TLS 1.3). O acesso deve ser estritamente controlado e auditado. |
| **Objetivo** | Proteger dados de saúde contra acesso não autorizado, violação de segurança e uso indevido, atendendo à natureza sensível dessas informações. |
| **Base Legal** | Art. 11 (Dados sensíveis); Art. 46 (Segurança); Art. 47 e 48 |
| **Artigos LGPD** | 11, I a III; 46; 47 e 48 |
| **Critério de Aceite** | ✓ Criptografia AES-256 para `sqflite` local<br>✓ TLS 1.3 para todas as comunicações<br>✓ Dados sensíveis não são logados em texto plano<br>✓ Testes de penetração realizados anualmente |

### LGPD-RF10 - Transparência no Tratamento de Dados

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Transparência no Tratamento de Dados |
| **Descrição** | O sistema deve fornecer informações claras, acessíveis e atualizadas sobre todas as operações de tratamento realizadas, incluindo fluxo de dados, finalidades, prazos de retenção e direitos do titular. |
| **Objetivo** | Cumprir o princípio da transparência, permitindo que o titular compreenda plenamente como seus dados são tratados. |
| **Base Legal** | Art. 6º, VI; Art. 9º |
| **Artigos LGPD** | 6º, VI; 9º |
| **Critério de Aceite** | ✓ Política de Privacidade com linguagem clara e acessível<br>✓ Resumo visual do fluxo de dados no app<br>✓ Notificações sobre mudanças nas políticas<br>✓ Canal de dúvidas sobre tratamento de dados |

> **Estado (2026-09-29):** implementado no app paciente — ver PROGRESS.md "QR Code do onboarding e documentos legais". Pendentes: revisão jurídica do texto e canal digital de dúvidas. O aviso com 15 dias de antecedência existe (`TermsChangeSchedule`, `patients.termsChangeNotice` e um cartão dispensável na home), mas a agenda está vazia e o canal é só dentro do app.

### LGPD-RF11 - Controle de Acesso e RBAC

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Controle de Acesso Baseado em Perfis (RBAC) |
| **Descrição** | O sistema deve implementar um modelo de controle de acesso rigoroso, onde: pacientes acessam apenas seus próprios dados; ACS acessam apenas dados da sua microárea; administradores têm acesso limitado e auditado. |
| **Objetivo** | Garantir que cada usuário tenha acesso apenas aos dados estritamente necessários para suas funções, prevenindo vazamentos e acessos indevidos. |
| **Base Legal** | Art. 46 (Segurança), Art. 50 (Governança) |
| **Artigos LGPD** | 46; 50, I e II |
| **Critério de Aceite** | ✓ Matriz de permissões documentada<br>✓ Autenticação com MFA para ACS<br>✓ Logs de acesso com quem, quando e quais dados<br>✓ Separação de microáreas garantida por código |

### LGPD-RF12 - Comunicação de Incidentes de Segurança

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Comunicação de Incidentes de Segurança |
| **Descrição** | O sistema deve ter um plano de resposta a incidentes que inclua a notificação à ANPD e aos titulares afetados em até 48 horas (recomendado) ou 72 horas (legal) da ciência do incidente, quando houver risco ou dano relevante. |
| **Objetivo** | Cumprir obrigação legal de comunicação de incidentes e minimizar danos aos titulares. |
| **Base Legal** | Art. 48 (Comunicação de incidente) |
| **Artigos LGPD** | 48, §1º e §2º |
| **Critério de Aceite** | ✓ Plano de resposta a incidentes documentado<br>✓ Template de comunicação à ANPD e titulares<br>✓ Registro de todos os incidentes<br>✓ Capacidade de identificar titulares afetados em até 24 horas |

### LGPD-RF13 - Tratamento de Dados Sensíveis (Saúde)

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Tratamento de Dados Sensíveis de Saúde |
| **Descrição** | Dados sensíveis (classificação de risco, condições crônicas, histórico de triagem) só podem ser tratados com consentimento específico e destacado do titular, ou quando necessário para cumprimento de obrigação legal ou execução de políticas públicas de saúde. |
| **Objetivo** | Garantir proteção adicional para dados de saúde, respeitando o Art. 11 da LGPD e a natureza sensível dessas informações. |
| **Base Legal** | Art. 11, I, II e III |
| **Artigos LGPD** | 11, I a III; 11, §1º e §2º |
| **Critério de Aceite** | ✓ Consentimento específico para dados de saúde<br>✓ Coleta mínima de dados sensíveis<br>✓ Acesso restrito a profissionais autorizados<br>✓ Anonimização quando possível |

### LGPD-RF14 - Cookies e Rastreamento

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Cookies e Rastreamento |
| **Descrição** | Considerando que o app móvel não utiliza cookies, mas pode ter integrações web, a plataforma deve garantir que qualquer rastreamento (analytics, crash reporting) seja transparente, opcional e não comprometa a privacidade do usuário. |
| **Objetivo** | Atender à LGPD no que tange ao rastreamento digital, mesmo em contexto de aplicativo móvel. |
| **Base Legal** | Art. 6º (Transparência); Art. 7º (Consentimento) |
| **Artigos LGPD** | 6º, VI; 7º, I |
| **Critério de Aceite** | ✓ Ferramentas de analytics com anonimização<br>✓ Opção de desativar rastreamento<br>✓ Documentação de todas as ferramentas de tracking<br>✓ Consentimento granular para analytics |

### LGPD-RF15 - E-mail Marketing e Comunicações

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | E-mail Marketing e Comunicações |
| **Descrição** | Comunicações de marketing (ex: campanhas de vacinação, informativos) devem ser enviadas apenas com consentimento prévio do titular. Mensagens transacionais (alertas, confirmações) são isentas de consentimento, mas devem ser limitadas ao necessário. |
| **Objetivo** | Cumprir requisitos de marketing consentido, evitando spam e respeitando a vontade do titular. |
| **Base Legal** | Art. 7º, I; Art. 8º |
| **Artigos LGPD** | 7º, I; 8º |
| **Critério de Aceite** | ✓ Consentimento específico para marketing<br>✓ Link de descadastramento em todos os e-mails<br>✓ Sistema de opt-in com dupla confirmação<br>✓ Registro de consentimento para marketing |

### LGPD-RF16 - Anúncios Personalizados

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Anúncios Personalizados |
| **Descrição** | A plataforma não utilizará anúncios personalizados ou publicidade comportamental, considerando a natureza sensível dos dados de saúde e o perfil do usuário (pacientes em vulnerabilidade). |
| **Objetivo** | Evitar a comercialização de dados sensíveis e proteger a dignidade dos pacientes. |
| **Base Legal** | Art. 11 (Dados sensíveis) |
| **Artigos LGPD** | 11, I a III |
| **Critério de Aceite** | ✓ Nenhuma integração com redes de anúncios<br>✓ Política de Privacidade explicita ausência de publicidade<br>✓ Comitê de ética valida novas parcerias comerciais |

### LGPD-RF17 - Integração com APIs e Serviços Externos

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Integração com APIs e Serviços Externos |
| **Descrição** | Todas as integrações com APIs externas (ex: Gov.br, SAMU, sistemas da Secretaria de Saúde) devem ser documentadas, com cláusulas contratuais de proteção de dados (DPA) e avaliação de conformidade do parceiro. |
| **Objetivo** | Garantir que fornecedores externos também estejam em conformidade com a LGPD, estendendo a responsabilidade a toda a cadeia de tratamento. |
| **Base Legal** | Art. 33, 34, 35, 36, 37, 38, 39 e 40 (Controlador e Operador) |
| **Artigos LGPD** | 33, 34, 35, 36, 37, 38, 39 e 40 |
| **Critério de Aceite** | ✓ DPAs assinados com todos os parceiros<br>✓ Avaliação de conformidade de cada integração<br>✓ Monitoramento de compliance dos parceiros<br>✓ Cláusula de segurança documentada em contratos |

---

### Dados sintéticos em teste e2e (CPF gerado)

A stack de e2e (`docker-compose.e2e.yml`, `bin/seed_e2e_fixtures.dart`) gera CPFs
aleatórios **com dígito verificador válido**, porque o login exige essa validade. Não
existe faixa de CPF reconhecidamente fictícia: um valor gerado pode, por acaso,
coincidir com o CPF de uma pessoa real. O risco é aceito porque o valor nunca aparece
sozinho: vem com nome, nascimento e contato inventados, vive só num banco efêmero
(apagado ao final), só é gravado como HMAC (`users.cpfHash`), o manifesto que o guarda
é `0600` e apagado ao final, e nenhum log, mensagem de erro ou `toString` o imprime.
Se a coincidência virar preocupação, a saída é trocar a geração por uma lista fixa de
CPFs de documentação (como faz `seed_cpf_hashes.dart` para a stack de desenvolvimento).

## 2. Requisitos para Termo de Uso e Política de Privacidade

### LGPD-RF18 - Termo de Uso

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Termo de Uso |
| **Descrição** | O sistema deve disponibilizar um Termo de Uso claro, acessível, e atualizado, que estabeleça as regras de utilização da plataforma, responsabilidades das partes e condições de acesso. |
| **Objetivo** | Estabelecer o contrato entre o usuário e o prestador de serviço, definindo direitos e obrigações de forma transparente. |
| **Conteúdo Mínimo** | Regras de uso, responsabilidades, proibições, propriedade intelectual, limitação de responsabilidade, jurisdição, alterações no termo. |
| **Critério de Aceite** | ✓ Texto em linguagem simples (acessibilidade para idosos e baixo letramento)<br>✓ Disponibilizado no app e no site<br>✓ Aceite explícito no cadastro<br>✓ Controle de versões disponível para consulta |

> **Estado (2026-09-29):** implementado no app paciente — ver PROGRESS.md "QR Code do onboarding e documentos legais". Pacientes que entram por OTP sem onboarding são convidados a aceitar no primeiro login (`patients.acceptTermsOfUse`), e de novo quando a versão mudar; o convite não é obrigatório para acessar o alerta de emergência. Pendentes: revisão jurídica do texto. O aviso com 15 dias de antecedência existe (`TermsChangeSchedule`, `patients.termsChangeNotice`, cartão dispensável na home, fora da aba de urgência; agenda vazia. Quando o app já embarca o texto da versão anunciada, o cartão também oferece lê-lo antes de valer).

### LGPD-RF19 - Política de Privacidade

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Política de Privacidade |
| **Descrição** | Documento abrangente que explica como o SinalACS coleta, usa, armazena, compartilha e protege os dados pessoais dos usuários, em conformidade com a LGPD. |
| **Objetivo** | Garantir transparência total sobre o tratamento de dados, cumprindo o Art. 9º da LGPD. |
| **Conteúdo Mínimo** | Identificação do controlador, dados coletados (por funcionalidade), finalidades específicas, bases legais, compartilhamento, transferências, retenção, direitos, medidas de segurança, DPO/encarregado. |
| **Critério de Aceite** | ✓ Linguagem acessível para leigos (recomendado: Nível de leitura 8º ano)<br>✓ Tópicos claros e organizados<br>✓ Versão resumida (sumário visual) e versão completa<br>✓ Atualização comunicada com no mínimo 15 dias de antecedência |

> **Estado (2026-09-29):** implementado no app paciente — ver PROGRESS.md "QR Code do onboarding e documentos legais". Pendentes: revisão jurídica do texto. O aviso com 15 dias de antecedência existe (`TermsChangeSchedule`, `patients.termsChangeNotice`, cartão dispensável na home, fora da aba de urgência; agenda vazia. Quando o app já embarca o texto da versão anunciada, o cartão também oferece lê-lo antes de valer) e o reaceite a cada nova versão também (`hasAcceptedCurrentTerms`).

### LGPD-RF20 - Aviso de Consentimento (Banner/Modal)

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Aviso de Consentimento |
| **Descrição** | No primeiro acesso, o usuário deve visualizar um aviso claro e destacado, solicitando seu consentimento para o tratamento de dados, com opções granulares por finalidade. |
| **Objetivo** | Obter consentimento informado e explícito do titular, cumprindo os requisitos do Art. 8º da LGPD. |
| **Conteúdo Mínimo** | Quem está coletando, quais dados serão coletados, finalidades principais, direitos do titular, links para Política de Privacidade completa, opções de consentimento granular. |
| **Critério de Aceite** | ✓ Modal centralizado no primeiro acesso<br>✓ Opções de consentimento por finalidade (checkboxes)<br>✓ Botão "Negar" tão visível quanto "Aceitar"<br>✓ Registro de todas as escolhas |

### LGPD-RF21 - Banner de Cookies (Se Aplicável)

| Propriedade | Descrição |
|-------------|-----------|
| **Nome** | Banner de Cookies (Se Aplicável) |
| **Descrição** | Caso a versão web utilize cookies, deve existir um banner inicial informando sobre seu uso e obtendo consentimento para cookies não essenciais. |
| **Objetivo** | Atender à LGPD no que tange ao uso de cookies, garantindo consentimento prévio e informado. |
| **Conteúdo Mínimo** | Informação sobre o uso de cookies, categorias (essenciais, analytics, marketing), opção de aceitar/recusar, link para Política de Privacidade. |
| **Critério de Aceite** | ✓ Banner no primeiro acesso à versão web<br>✓ Distinção entre cookies essenciais e não essenciais<br>✓ Armazenamento da preferência do usuário<br>✓ O usuário pode alterar preferências posteriormente |

---

## 3. Bases Legais da LGPD por Cenário

### 3.1 Cadastro de Usuários

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Consentimento (Art. 7º, I) |
| **Justificativa** | O paciente fornece ativamente seus dados (CPF, Data de Nascimento) para criar um perfil, sendo o consentimento a base mais adequada para coleta inicial. |
| **Riscos Associados** | Possibilidade de consentimento viciado (desequilíbrio de poder); revogação pode inviabilizar o serviço. |
| **Cuidados Necessários** | Consentimento livre, destacado e informado; garantia de que o paciente compreende os dados fornecidos; opção de revogação clara. |

### 3.2 Login/Autenticação

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Legítimo Interesse (Art. 7º, IX) |
| **Justificativa** | Necessário para a segurança e operacionalidade do sistema; protege tanto o paciente quanto a equipe de saúde; é esperado que o usuário autentique para acessar seus dados. |
| **Riscos Associados** | Legítimo interesse não pode violar direitos fundamentais; deve ser equilibrado e minimamente invasivo. |
| **Cuidados Necessários** | Análise de legítimo interesse documentada; coleta mínima para autenticação; registro de tentativas de acesso. |

### 3.3 Envio de E-mails

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Consentimento (Marketing) ou Legítimo Interesse (Transacionais) |
| **Justificativa** | E-mails transacionais (alertas de urgência, confirmações) podem ser enviados por legítimo interesse (Art. 7º, IX). E-mails de marketing exigem consentimento específico (Art. 7º, I). |
| **Riscos Associados** | Confundir as categorias; enviar marketing sem consentimento; abusar de e-mails transacionais. |
| **Cuidados Necessários** | Clareza na distinção entre transacional e marketing; link de descadastramento; consentimento granular. |

### 3.4 Marketing (Campanhas de Vacinação, Informativos)

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Consentimento (Art. 7º, I) |
| **Justificativa** | Comunicações de marketing não são essenciais ao serviço e não são esperadas pelo usuário; o consentimento é a base mais protetiva e transparente. |
| **Riscos Associados** | Baixa adesão; necessidade de gerenciar opt-outs; risco de spam. |
| **Cuidados Necessários** | Consentimento explícito e destacado; opção de opt-out em todas as comunicações; registro de consentimento. |

### 3.5 Personalização de Anúncios

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Não aplicável (Não haverá anúncios personalizados) |
| **Justificativa** | A plataforma não utiliza anúncios personalizados para evitar a comercialização de dados sensíveis de saúde. |
| **Riscos Associados** | Uso indevido de dados de saúde para segmentação; violação da dignidade do paciente. |
| **Cuidados Necessários** | Política explícita de não uso de anúncios; auditoria interna para garantir conformidade. |

### 3.6 Compartilhamento com Terceiros (SAMU, UBS, Secretaria)

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Consentimento Específico (Art. 7º, I) ou Execução de Políticas Públicas (Art. 7º, V) |
| **Justificativa** | O compartilhamento para atendimento de urgência é essencial; quando não for possível obter consentimento (emergência), a base pode ser a execução de políticas públicas de saúde. |
| **Riscos Associados** | Compartilhamento excessivo; violação de confidencialidade; falta de controle pelo titular. |
| **Cuidados Necessários** | Consentimento específico para cada tipo de compartilhamento; minimização de dados; DPAs com os parceiros. |

### 3.7 Cumprimento de Obrigações Legais

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Obrigação Legal ou Regulatória (Art. 7º, II) |
| **Justificativa** | A legislação exige a guarda de prontuários e informações de saúde (Código de Ética Médica, Política Nacional de Atenção Básica), sendo obrigação legal manter esses registros. |
| **Riscos Associados** | Sobrecarga de dados; manutenção além do necessário. |
| **Cuidados Necessários** | Mapeamento de todas as obrigações legais aplicáveis; política de retenção alinhada com prazos legais; segurança reforçada para retenção prolongada. |

### 3.8 Emissão de Documentos Fiscais

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Obrigação Legal ou Regulatória (Art. 7º, II) |
| **Justificativa** | Emissão de notas fiscais e documentos fiscais é obrigação legal (ICMS/ISS), justificando o tratamento de dados para esse fim. |
| **Riscos Associados** | Dados fiscais expostos a riscos; necessidade de guarda por 5 anos. |
| **Cuidados Necessários** | Acesso restrito a dados fiscais; guarda segura; destruição após prazo legal. |

### 3.9 Atendimento e Suporte

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Legítimo Interesse (Art. 7º, IX) |
| **Justificativa** | O atendimento ao paciente é essencial para a operacionalidade do serviço; o paciente espera ter seus dados disponíveis quando contata o suporte. |
| **Riscos Associados** | Suporte acessa dados sensíveis desnecessariamente; falta de controle do paciente. |
| **Cuidados Necessários** | Treinamento da equipe de suporte; acesso mínimo necessário; registro de atendimentos. |

### 3.10 Analytics e Métricas de Uso

| Propriedade | Descrição |
|-------------|-----------|
| **Base Legal Recomendada** | Legítimo Interesse (Art. 7º, IX) ou Consentimento (Art. 7º, I) |
| **Justificativa** | Analytics são importantes para melhoria do serviço, mas podem ser considerados invasivos; recomenda-se consentimento para dados de saúde e legítimo interesse para dados agregados anonimizados. |
| **Riscos Associados** | Rastreamento excessivo; identificação de indivíduos; dados sensíveis em analytics. |
| **Cuidados Necessários** | Anonimização prévia; agregação de dados; consentimento separado para analytics específicos. |

---

## 4. Princípios da LGPD e Aplicação no Sistema

### 4.1 Finalidade

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Só vamos usar seus dados para as finalidades que explicamos claramente quando os coletamos." |
| **Aplicação no Sistema** | O SinalACS coleta dados apenas para: (a) identificação e autenticação do paciente; (b) classificação de risco e priorização de atendimento; (c) comunicação com o ACS; (d) registro de histórico de saúde; (e) cumprimento de obrigações legais. Cada dado está vinculado a pelo menos uma finalidade documentada. |
| **Exemplo Prático** | O CPF é coletado para autenticação e identificação única, não sendo utilizado para marketing ou vendas. A classificação de risco (Vermelho/Amarelo/Verde) é usada exclusivamente para priorizar o atendimento, não para avaliação de crédito ou seguros. |

### 4.2 Adequação

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Só coletamos dados que são realmente úteis para o que vamos fazer com eles." |
| **Aplicação no Sistema** | Coleta apenas dados pertinentes: para triagem de urgência, coleta-se dor, localização e condições crônicas conhecidas; não se coleta religião, orientação sexual ou outros dados irrelevantes. O formulário de triagem tem perguntas fechadas e objetivas, alinhadas ao Protocolo de Manchester. |
| **Exemplo Prático** | No formulário de triagem, as perguntas são específicas sobre sintomas e dor, sem perguntas sobre estilo de vida, renda ou preferências pessoais. |

### 4.3 Necessidade

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Coletamos apenas o mínimo necessário para atender você bem." |
| **Aplicação no Sistema** | O sistema adota o princípio da minimização: dados sensíveis de saúde são coletados apenas quando estritamente necessários. O ACS não tem acesso a histórico completo de todos os pacientes, apenas às informações relevantes para a visita agendada. |
| **Exemplo Prático** | Para uma visita de rotina, o ACS vê apenas o nome, endereço e condições crônicas cadastradas. Detalhes de outras visitas ou triagens anteriores são acessados apenas com justificativa específica. |

### 4.4 Livre Acesso

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Você pode ver, a qualquer momento, todos os dados que temos sobre você." |
| **Aplicação no Sistema** | O paciente tem acesso a um painel de dados pessoais no app, onde pode visualizar todos os dados coletados: perfil, histórico de triagens, alertas enviados, status de solicitações, e visitas realizadas. |
| **Exemplo Prático** | O paciente acessa "Meus Dados" no app e vê sua lista de condições crônicas, histórico de classificações de risco, e dados de contato, podendo solicitar correções ou atualizações. |

### 4.5 Qualidade dos Dados

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Mantemos seus dados atualizados e corretos, e você pode nos ajudar com isso." |
| **Aplicação no Sistema** | O sistema incentiva a atualização periódica de dados, especialmente condições crônicas e contatos. O paciente pode corrigir seus dados a qualquer momento, e o sistema valida informações críticas (ex: CPF com algoritmo de validação). |
| **Exemplo Prático** | O app envia uma notificação a cada 6 meses solicitando que o paciente confirme seus dados de contato e condições de saúde, garantindo a acurácia das informações. |

### 4.6 Transparência

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Explicamos de forma clara e simples tudo o que fazemos com seus dados." |
| **Aplicação no Sistema** | A Política de Privacidade é apresentada em linguagem acessível, com ícones e resumos visuais. Notificações explicam o que está sendo feito quando dados são compartilhados (ex: "Seu alerta de urgência foi compartilhado com o ACS da sua região"). |
| **Exemplo Prático** | Quando o paciente envia um alerta de urgência, o app mostra: "Enviando sua localização e classificação de risco para o Agente de Saúde da sua microárea - [Nome do ACS]". |

### 4.7 Segurança

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Protegemos seus dados com as melhores práticas de segurança disponíveis." |
| **Aplicação no Sistema** | Criptografia de ponta a ponta, TLS 1.3 em todas as comunicações, AES-256 para dados locais, controle de acesso rigoroso (RBAC), autenticação MFA para ACS, e monitoramento contínuo de acessos suspeitos. |
| **Exemplo Prático** | Os dados de saúde do paciente são criptografados no dispositivo móvel antes de serem sincronizados, protegendo-os mesmo em caso de perda do celular ou acesso físico ao dispositivo. |

### 4.8 Prevenção

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Tomamos medidas para evitar que seus dados sejam usados de forma errada ou indevida." |
| **Aplicação no Sistema** | Treinamento obrigatório de todos os ACS sobre proteção de dados e ética; auditoria de acessos para identificar padrões suspeitos; bloqueio automático de IPs com múltiplas tentativas de acesso não autorizado. |
| **Exemplo Prático** | O sistema monitora se um ACS consulta dados de um paciente fora de sua microárea sem justificativa, gerando alerta para auditoria. |

### 4.9 Não Discriminação

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Usamos seus dados para cuidar melhor de você, nunca para te julgar ou excluir." |
| **Aplicação no Sistema** | Os dados de saúde são usados exclusivamente para priorização de atendimento e planejamento de visitas, nunca para avaliar crédito, seguro, emprego ou qualquer outro propósito discriminatório. O sistema não compartilha dados com instituições financeiras ou seguradoras. |
| **Exemplo Prático** | A classificação Vermelho/Amarelo/Verde é usada exclusivamente dentro da equipe de saúde para organização do fluxo de trabalho, não sendo divulgada fora da UBS ou para outros pacientes. |

### 4.10 Responsabilização e Prestação de Contas

| Aspecto | Descrição |
|---------|-----------|
| **Explicação Simples** | "Somos responsáveis pelo que fazemos com seus dados e prestamos contas a você e à lei." |
| **Aplicação no Sistema** | O sistema mantém logs detalhados de todas as operações, possui um Encarregado (DPO) designado, e realiza auditorias regulares. Relatórios de privacidade são disponibilizados periodicamente. |
| **Exemplo Prático** | A Secretaria de Saúde pode solicitar um relatório de acessos aos dados de um paciente; o sistema gera um log completo com quem acessou, quando, e para qual finalidade. |

---

## 5. Checklist de Segurança e Boas Práticas

### 5.1 Criptografia de Dados

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Proteger dados em repouso e em trânsito contra acesso não autorizado. |
| **Implementação** | TLS para todas as comunicações (Flutter ↔ backend), AES-256 para dados locais no `sqflite`, criptografia de campos sensíveis (CPF, condições crônicas) no banco central PostgreSQL. |
| **Riscos Mitigados** | Interceptação de dados (MITM), violação de dados por acesso físico ao dispositivo, vazamento em caso de comprometimento do banco de dados. |

#### Decisão de custódia da chave (app do ACS)

| Propriedade | Descrição |
|-------------|-----------|
| **Decisão** | A chave do SQLCipher é aleatória (256 bits) e fica no Android Keystore / iOS Keychain, via `flutter_secure_storage`. Não é derivada de PIN nem de biometria. |
| **Contexto** | `spec/PRD_system.md` (4.2.3) prescreve "chave derivada do PIN/Biometria (PBKDF2)"; `spec/test_plan.md` (item 1 da matriz de risco) fala em "chave gerada pelo TEE do hardware". Adotamos a segunda leitura. |
| **Motivo** | Não existe nenhum fluxo de PIN nos apps — a autenticação é `auth.developmentLogin`, sem credencial. Derivar de PIN exigiria projetar definição, desbloqueio, política de tentativas e recuperação; e um PIN esquecido significaria perder visitas ainda não sincronizadas. O keystore protege contra o risco que esta seção nomeia (acesso físico ao dispositivo) sem inventar produto. **Atualização (2026-09-18):** no app do ACS a autenticação deixou de ser o `developmentLogin` — passou a ser institucional (matrícula + senha, RF07), com a credencial só em memória e nada em disco. A decisão da chave não muda: continua não existindo fluxo de PIN em app nenhum, e o `developmentLogin` segue para as ferramentas de desenvolvimento e para o login do app do paciente, que RF01 ainda não substituiu. **Atualização (2026-09-19):** o app do paciente também deixou de usar o `developmentLogin` — o login dele é passwordless (CPF + data de nascimento + código OTP, RF01) —, então o token de desenvolvimento ficou só nas ferramentas (`tool/`, `integration_test/`) nos dois apps, como o parágrafo anterior já registrava para o ACS. Nada nesta linha muda com isso: segue não existindo fluxo de PIN em app nenhum, e a custódia da chave continua no keystore. |
| **Reversibilidade** | A interface `DatabaseKeyStore` aceita um segundo fator depois, envelopando a chave, **sem migrar dados**. O caminho do PRD segue aberto. |
| **Limite conhecido** | Num aparelho comprometido (root) com o usuário autenticado, a chave é alcançável. Proteger contra isso exigiria o fator de posse do PIN. |
| **Verificação** | `apps/acs/integration_test/encrypted_storage_test.dart` lê o arquivo do banco e afirma que ele não contém o conteúdo em texto plano. Roda em dispositivo — no CI (Linux) o caminho é o FFI, que não criptografa, e por isso a abertura fora de Android/iOS lança por padrão. |

#### Decisão de custódia do refresh token do ACS (2026-10-05)

| Propriedade | Descrição |
|-------------|-----------|
| **Decisão** | O refresh token do ACS fica num **envelope**: uma chave AES-256-GCM descartável, gerada a cada gravação, cifra o token; essa chave AES é cifrada com a pública de um par **RSA-2048/OAEP** (SHA-256, MGF1 com SHA-1, que é o que o provedor do Keystore usa) do Android Keystore, gerado com `setUserAuthenticationRequired(true)` e autenticação **a cada uso** (validade 0). Só o blob cifrado (`IV.chaveAES_RSA.token`, Base64) fica num SharedPreferences privado. Cifrar usa só a pública e não pede prompt (a rotação de 15 min segue silenciosa); **decifrar** exige o `BiometricPrompt` com `CryptoObject` sobre a privada — uma vez por partida a frio. Na API 30+ o prompt aceita biometria forte **ou** o PIN/padrão do aparelho; antes da API 30, só biometria forte. Código: `KeystoreVault.kt` (canal `br.com.prismrr.sinalacs.acs/keystore_vault`) e `AuthBoundSessionTokenStore`. |
| **Motivo** | Antes o token ficava no `flutter_secure_storage` e a biometria era só portão de interface: num aparelho com root, ou lendo o armazenamento do app, o token saía sem autenticação nenhuma. Agora a decifra é cobrada pelo TEE: sem a digital ou o PIN do aparelho, o blob em repouso não vale nada. RSA (e não AES direto no Keystore) porque a pública cifra sem prompt; o envelope porque o RSA-2048/OAEP só cifra ~190 bytes. |
| **Invalidação** | Remover o bloqueio de tela faz o Android apagar/invalidar a chave: a partida seguinte apaga o blob e cai no login completo com "Sua sessão expirou. Entre novamente." (provado no emulador). A chave é gerada com `setInvalidatedByBiometricEnrollment(true)`, mas **na API 30+, com o PIN aceito no prompt, uma digital nova não invalida a chave**: a chave carrega o SID do bloqueio de tela, e o token de autenticação da digital também o carrega. Provado no emulador API 36 (2026-10-05): depois de cadastrar a segunda digital, o prompt abre e a digital antiga entra. O ganho que a invalidação daria é pequeno com o PIN aceito, porque quem cadastra uma digital já precisa saber o PIN, e o PIN sozinho já abre o cofre. Antes da API 30 (só biometria) a invalidação por digital nova deveria valer, mas não foi provada. |
| **Fora do vínculo (por desenho)** | A chave do SQLCipher (decisão acima) e o token de envio diferido (`acs_upload_token|<userId>`) seguem no `flutter_secure_storage`, **sem** vínculo à autenticação: a fila offline e o envio diferido de outro dono precisam funcionar sem o dono presente. Depois do desbloqueio, o token fica em RAM durante o processo; o `AppLockGate` (30 s em segundo plano) continua portão de interface sobre ele. |
| **Degradação** | Aparelho sem bloqueio de tela, ou API 24–29 sem biometria forte: o token fica só em RAM e morre com o processo, então cada partida a frio exige login completo (matrícula + senha e, com MFA, o código). Uma falha ao selar degrada do mesmo jeito. |
| **Limite conhecido** | Com root e o app já aberto e desbloqueado, o token em RAM é alcançável. O ganho é contra a leitura **em repouso** e contra a partida a frio. |
| **Verificação** | `scripts/qa/acs_keystore_bound_e2e.sh` no emulador (prompt na partida a frio, digital certa/errada, cancelar, segundo plano com o prompt aberto, nova digital, remoção do bloqueio). Testes de unidade: `auth_bound_session_token_store_test.dart`, `keystore_vault_channel_test.dart`, `session_resume_test.dart`. API 24–29 e aparelho físico não foram provados. |

**Captura de tela (2026-10-02).** A janela do app do ACS é `FLAG_SECURE`: o sistema não permite captura de tela, gravação nem miniatura nos apps recentes. Decisão: a janela inteira, porque a lista da microárea (nome e condições crônicas) aparece em mais de uma tela. Consequência aceita: `adb screencap` do ACS sai preto. Provado por `scripts/qa/acs_secure_window.sh`. **Exceção de desenvolvimento (2026-10-05):** a captura só é liberada em build de **debug**, por uma constante de compilação (`BuildConfig.ALLOW_SCREEN_CAPTURE`, `false` por padrão, ligada só com `-Psinalacs.allowScreenCapture=true`); o Gradle recusa a propriedade em release e nada em execução (menu, intent, preferência) a altera. Serve a QA e à gravação de demonstração com dados sintéticos; a build que vai ao ACS em campo, com paciente real, é release e permanece `FLAG_SECURE`.

### 5.2 Controle de Acesso por Perfil (RBAC)

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Garantir que cada usuário acesse apenas os dados estritamente necessários para sua função. |
| **Implementação** | Matriz de permissões: Paciente (próprios dados), ACS (dados da microárea), Coordenador (dados da UBS), Administrador (dados sistêmicos, auditado). Autenticação com MFA para ACS e coordenadores. |
| **Riscos Mitigados** | Acesso indevido a dados sensíveis, violação de privacidade por funcionários, erro humano na exposição de dados. |

### 5.3 Logs e Auditoria

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Rastrear todas as operações de dados e garantir responsabilização. |
| **Implementação** | Tabelas de log com: `user_id`, `action`, `resource`, `timestamp`, `ip_hash`, `user_agent`, `result`. Registro de todos os acessos, alterações, exclusões e compartilhamentos. Logs imutáveis com integridade garantida por hashing. |
| **Riscos Mitigados** | Negação de responsabilidade, auditoria impossível, detecção tardia de violações, falta de transparência. |

### 5.4 Backup Seguro

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Garantir a disponibilidade e recuperação de dados em caso de desastre ou incidente. |
| **Implementação** | Backups automáticos diários do PostgreSQL para localidade geograficamente distinta; backups criptografados com chave separada; teste de restauração mensal; cópia de segurança dos registros de consentimento. |
| **Riscos Mitigados** | Perda de dados por falha de hardware, ataque ransomware, desastre natural, erro humano. |

### 5.5 Gestão de Consentimento

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Capturar, registrar, e gerenciar consentimentos de forma confiável e auditável. |
| **Implementação** | Tabela `consent_logs` com registro imutável; interface de gestão de preferências para o usuário; notificações de mudanças na política; registros com versão, timestamp e assinatura eletrônica. |
| **Riscos Mitigados** | Consentimento não documentado, revogação não efetiva, falta de comprovação em auditoria, violação do direito de revogação. |

### 5.6 Política de Retenção de Dados

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Garantir que dados sejam mantidos apenas pelo tempo necessário e eliminados de forma segura. |
| **Implementação** | Tabela com política de retenção por categoria de dado: alertas (2 anos), visitas (5 anos conforme legislação), logs de acesso (1 ano), dados de consentimento (indeterminado). Processo automatizado de expurgo com anonimização. |
| **Riscos Mitigados** | Acumulação excessiva de dados, violação do princípio da necessidade, armazenamento desnecessário de dados sensíveis. |

#### Retenção no aparelho do ACS (implementada)

| Propriedade | Descrição |
|-------------|-----------|
| **Decisão** | O banco local guarda **apenas** visitas ainda não sincronizadas. `SqlCipherVisitStore.save()` reescreve **as linhas do dono** (`WHERE owner = ?`) a partir da lista de pendentes dele, então a visita confirmada pelo servidor deixa o dispositivo na gravação seguinte. |
| **Por dono** | Cada linha de `offline_visits` tem `owner` = `userId` do ACS que a registrou (schema v7). Um ACS não carrega, conta, envia, descarta nem apaga visita de outro (RNF06); o `save()` de um dono nunca toca nas linhas de outro. O dono não vira dado novo: é o mesmo UUID pseudonimizado que o servidor grava como `acsId`. |
| **Legado em quarentena** | Linhas gravadas antes do schema v7 não têm dono (`owner IS NULL`) e **nenhum ACS as adota**: adotá-las atribuiria dado clínico a quem não o registrou. Ficam invisíveis até subirem por `visits.syncLegacy`, que as grava com `authorship = legacyUnclaimed` e `acsId` nulo (autoria desconhecida, registrada como "migração v7"); o ACS que apenas transportou o lote fica só em `audit_logs`. |
| **Envio diferido, com a autoria certa** | Quem sai do aparelho com visita pendente deixa no Keystore um **token de envio** (`acs_upload_tokens` no servidor: só hash, 7 dias, escopo único `visits.syncDeferred`/`visits.revokeUploadToken`, por usuário + aparelho). Ele sobe as visitas do dono sem sessão e sem poder de leitura, sob a autoria dele e no território dele relido do banco. O envio é disparado com o painel aberto, na retomada, quando a conexão volta e no "Sair"; a visita só sai do disco quando o servidor responde `synced`, e o token é revogado e apagado quando a fila do dono zera. |
| **Limpar este aparelho** | O ACS pode apagar `offline_visits`, o cursor e o cache da microárea (§5.11), **só se não houver nenhuma linha** — de qualquer dono, do legado, recusada ou em revisão — nem fila só em memória; do contrário a ação é recusada sem apagar nada. O arquivo cifrado e a chave ficam. |
| **O que NÃO fecha** | Não há envio em segundo plano do SO (só em primeiro plano). Token de envio vencido (7 dias) ou recusado deixa a fila do dono presa até ele entrar de novo e bloqueia o wipe; não há wipe forçado por supervisor (não existe login de supervisor). **Dono que nunca volta**: suas visitas permanecem cifradas no aparelho, sem prazo de expurgo, até haver envio ou desinstalação — a retenção local dele depende do envio e é um risco aberto (`PROGRESS.md`, seção Fila de visitas por dono e corrida do login). **Token que sobrevive ao "Sair" sem rede:** se o "Sair" não alcança o servidor, o token de envio do dono continua válido (no aparelho e no servidor) por até 7 dias, mesmo sem visita pendente, até um envio diferido rodar com rede e revogá-lo; desativar a conta o corta. |
| **Estado** | Passou a valer de fato quando o `BackendVisitSynchronizer` foi ligado em produção. Antes, o app montava a fila sem sincronizador: `sync()` devolvia erro, nada era confirmado e nada era apagado — a retenção estava implementada e testada, mas nunca disparava. |
| **O que é gravado** | `patient_id` (UUID), risco, status, desfecho, data e versão. **Não** é gravado nome, rótulo legível nem endereço. As observações de campo digitadas na tela ainda não são persistidas nem enviadas. |
| **Por que o identificador, e não o rótulo** | A tela antes gravava `'Paciente ' + 8 dos 32 dígitos hex` e descartava o UUID. Era pior nos dois sentidos: texto legível sobre a pessoa no disco, e um identificador irrecuperável — `visits.sync` só aceita UUID, então a visita nunca poderia sair do aparelho e a retenção nunca a alcançaria. Guardar o identificador e montar o rótulo na tela é o desenho de minimização correto (LGPD-RF01). |
| **Consequência de produto** | Sem alerta vinculado não há paciente, logo a tela de visita não grava. Um seletor de pacientes da microárea exigiria um endpoint de listagem que não existe. |
| **Verificação** | `apps/acs/integration_test/encrypted_storage_test.dart` afirma que nem o conteúdo da visita nem o `patient_id` aparecem legíveis no arquivo do banco; `apps/acs/integration_test/red_alert_cycle_test.dart` ("a visita confirmada SAI do disco criptografado") prova a retenção contra o servidor real, em dispositivo. |

### 5.7 Anonimização/Pseudonimização

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Reduzir riscos em dados que não precisam ser identificados, especialmente para analytics. |
| **Implementação** | Separar dados de identificação (nome, CPF) de dados clínicos; aplicar pseudonimização em relatórios e análises; dados de analytics são agregados e anonimizados antes do processamento. |
| **Riscos Mitigados** | Identificação de titulares em análises, violação de privacidade em relatórios, reidentificação acidental. |

### 5.8 Plano de Resposta a Incidentes

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Responder rápida e efetivamente a incidentes de segurança, minimizando danos. |
| **Implementação** | Procedimento documentado: detecção → contenção → investigação → notificação (ANPD em até 72h, titulares em até 48h recomendado) → correção → pós-incidente. Time de resposta designado e treinado. |
| **Riscos Mitigados** | Atraso na resposta, falha na notificação, danos amplificados, sanções regulatórias. |

### 5.9 Treinamento da Equipe

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Conscientizar todos os envolvidos sobre privacidade e proteção de dados. |
| **Implementação** | Treinamento obrigatório para todos os ACS e equipe administrativa; módulos sobre LGPD, ética, segurança, e tratamento de dados sensíveis; reciclagem anual; teste de conhecimento. |
| **Riscos Mitigados** | Erro humano, violações acidentais, falta de conscientização, cultura de privacidade fraca. |

### 5.10 Gestão de Vulnerabilidades

| Propriedade | Descrição |
|-------------|-----------|
| **Objetivo** | Identificar e corrigir vulnerabilidades antes que sejam exploradas. |
| **Implementação** | Análise estática de código (SAST) no CI/CD; testes de penetração anuais; scanner de vulnerabilidades em dependências; processo de disclosure responsável; atualização regular de bibliotecas e frameworks. |
| **Riscos Mitigados** | Exploração de vulnerabilidades conhecidas, zero-days, falhas de segurança introduzidas por dependências. |

### 5.11 Cache local da microárea (RF08)

| | |
|---|---|
| **Decisão** | O ACS guarda no aparelho a última lista da microárea (`patients.listMicroArea`) para registrar visita **sem rede**. |
| **O que guarda** | Só o que a tela de visita já mostra: `patientId`, nome, `isChronic` e condições crônicas — o mesmo conjunto da retenção no aparelho (§5.6). Nada de contato de emergência, endereço, histórico ou triagem. |
| **Onde** | Tabelas `micro_area_cache` e `micro_area_cache_meta` na **mesma base SQLCipher** das visitas offline (INV-04; chave no Keystore, §5.1). |
| **Dono** | A lista pertence a `userId\|microAreaId` da sessão que a baixou. Outro usuário ou outra microárea **apaga** o cache e não o serve (RNF06). |
| **Validade** | 72 horas desde o último download bem-sucedido. Vencida, **não é usada e é apagada**. |
| **Quando entra** | Só no lugar de uma falha **recuperável** de rede. Uma recusa do servidor (sessão inválida, território negado, `isRecoverable: false`) nunca cai no cache. |
| **Transparência** | A tela diz que a lista é do cache e de quando. |
| **Retenção** | Some pela validade, pela troca de dono, pelo "Limpar este aparelho" (§5.6) e com a desinstalação; nunca é enviada a lugar nenhum. |
| **Se for revisto** | Reduzir `microAreaCacheMaxAge` ou apagar a tabela v6 é migração aditiva reversível. |

---

## 6. Direitos dos Titulares dos Dados

### 6.1 Direitos Previstos na LGPD (Art. 18)

| Direito | Descrição | Implementação no Sistema |
|---------|-----------|--------------------------|
| **Confirmação de Tratamento** | O titular pode confirmar se seus dados estão sendo tratados. | Painel "Meus Dados" → Confirmação de existência de tratamento. |
| **Acesso aos Dados** | O titular pode acessar seus dados pessoais. | Painel "Meus Dados" com lista completa de dados, histórico de alterações e compartilhamentos. |
| **Correção de Dados** | O titular pode corrigir dados incompletos, inexatos ou desatualizados. | Formulário de edição de perfil; solicitação de correção para dados históricos. |
| **Anonimização, Bloqueio ou Eliminação** | O titular pode solicitar anonimização, bloqueio ou eliminação de dados desnecessários, excessivos ou tratados em desconformidade. | Botão "Solicitar Exclusão" no painel; processo documentado de atendimento. |
| **Portabilidade** | O titular pode solicitar a portabilidade dos dados a outro fornecedor. | Exportação de dados em formato JSON/CSV; transferência segura para terceiro indicado. |
| **Eliminação de Dados com Consentimento** | O titular pode eliminar dados tratados com base em consentimento. | Revogação de consentimento → eliminação automática em até 15 dias. |
| **Informação sobre Compartilhamento** | O titular pode obter informações sobre entidades com quem seus dados foram compartilhados. | Histórico de compartilhamentos no painel; lista de terceiros autorizados. |
| **Informação sobre Possibilidade de Não Consentir** | O titular pode ser informado sobre as consequências de não fornecer consentimento. | No ato da coleta, explicação clara sobre obrigatoriedade ou não dos dados. |
| **Revogação do Consentimento** | O titular pode revogar o consentimento a qualquer momento. | Botão "Revogar Consentimento" → processo simples e rápido. |

### 6.2 Fluxos de Atendimento aos Direitos

| Direito | Fluxo Recomendado | Prazo | Responsável |
|---------|-------------------|-------|-------------|
| **Acesso e Confirmação** | 1. Usuário acessa painel "Meus Dados"<br>2. Sistema exibe dados completos<br>3. Opção de exportação | Imediato | Sistema (automatizado) |
| **Correção** | 1. Usuário edita dados no painel<br>2. Sistema valida e atualiza<br>3. Registro de alteração é criado<br>4. Notificação de confirmação | Imediato (simples)<br>15 dias (complexo) | Sistema (automatizado) / Suporte |
| **Exclusão/Anonimização** | 1. Usuário solicita exclusão<br>2. Sistema verifica obrigações legais<br>3. Processa exclusão ou anonimização<br>4. Notifica usuário do resultado<br>5. Registra operação | 15 dias | Suporte (com automação) |
| **Portabilidade** | 1. Usuário solicita exportação<br>2. Sistema gera arquivo (JSON/CSV)<br>3. Notifica para download seguro<br>4. Usuário baixa ou indica terceiro | 15 dias | Sistema (automatizado) |
| **Revogação de Consentimento** | 1. Usuário acessa preferências<br>2. Revoga finalidade específica<br>3. Sistema interrompe tratamento<br>4. Registra revogação<br>5. Notifica efetivação | Imediato (tratamento) / 15 dias (eliminação) | Sistema (automatizado) |
| **Informação sobre Compartilhamento** | 1. Usuário acessa histórico<br>2. Visualiza lista de compartilhamentos | Imediato | Sistema (automatizado) |

### 6.3 Registros de Auditoria para Direitos

| Operação | Campos Registrados | Finalidade |
|----------|-------------------|------------|
| Solicitação de Acesso | `user_id`, `request_date`, `method`, `ip_hash`, `result` | Demonstrar atendimento em auditoria |
| Correção de Dados | `user_id`, `field`, `old_value_hash`, `new_value_hash`, `timestamp` | Manter histórico de alterações (rastreabilidade) |
| Exclusão de Dados | `user_id`, `reason`, `authorized_by`, `timestamp`, `method` | Comprovar atendimento à solicitação e conformidade |
| Portabilidade | `user_id`, `request_date`, `format`, `download_date`, `ip_hash` | Rastrear exportações e prevenir acessos indevidos |
| Revogação de Consentimento | `user_id`, `purpose`, `revocation_date`, `method` | Demonstrar efetivação da revogação |

---

## 7. Requisitos Técnicos de Implementação

### LGPD-RT01 - APIs com Autenticação e Controle de Acesso

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Todas as APIs devem exigir autenticação (JWT) e implementar controle de acesso (RBAC) para garantir que apenas usuários autorizados acessem dados específicos. |
| **Implementação** | Middleware de autenticação na camada de aplicação do backend; validação de permissões por endpoint; tokens JWT com expiração curta; refresh token seguro. Ainda não implementado no código atual — hoje só existe um endpoint de login de desenvolvimento sem autenticação institucional real (ver `CLAUDE.md`). **Atualização (2026-09-18):** o login institucional existe (`auth.loginInstitutional`, RF07) — matrícula + senha verificadas com Argon2id contra `user_credentials`, com bloqueio por tentativas e auditoria em `audit_logs` — e a verificação de token dos endpoints sensíveis está centralizada (`Authorization.require`; os endpoints estendem `AuthenticatedEndpoint`). O que segue pendente desta linha: o token expira em 15 minutos, **não há refresh token** (LGPD-RT06) e os papéis `coordinator`/`admin` continuam sem caminho de emissão. **Atualização (2026-09-19):** o TTL deixou de ser um só. A sessão emitida pelo **login do paciente** (passwordless, RF01) vale **1 hora**, aplicando LGPD-RT06 — o código OTP é de uso único e não se reapresenta, então não existe renovação silenciosa desse lado; a do **ACS** continua em **15 minutos** (JWT), renovada em silêncio pelo refresh token (ver **Atualização (2026-10-03)** abaixo; a credencial em memória deixou de existir). A assimetria é deliberada, e é a diferença entre as duas que precisa ser lida como decisão e não como inconsistência. Dentro do lado do paciente há uma exceção conhecida: o *onboarding* (`onboarding.completeEnrollment`, RF02) ainda emite o padrão de 15 minutos, porque o caminho dele não passa por esta decisão — lacuna com dono no `PROGRESS.md`. O que segue pendente: **o paciente não tem refresh token** (LGPD-RT06) — é ele que permitiria devolver o TTL do paciente aos 15 minutos sem quebrar a experiência —, e os papéis `coordinator`/`admin` continuam sem caminho de emissão. **Atualização (2026-10-03):** o refresh token do **ACS** está implementado (`auth.refreshSession`/`auth.logout`, tabela `acs_refresh_tokens`): rotativo, guardado só como hash SHA-256, amarrado ao aparelho (o `deviceId` é o identificador da instalação — UUID aleatório —, não uma atestação de hardware: protege contra token vazado sem ele, não contra comprometimento do aparelho), com janela ociosa de 2 h e teto absoluto de 8 h contado do login por senha + TOTP; reuso fora da tolerância de 30 s, aparelho diferente ou conta inativa revogam a família, e a recusa é sempre a mesma mensagem. O app não retém mais a senha; o token fica no Keystore. O desbloqueio por biometria/bloqueio de tela do aparelho (partida a frio e após 30 s em segundo plano) também existe, mas é **portão de interface**: não liga a chave do SQLCipher nem o refresh token ao `BiometricPrompt` (a chave segue aleatória no Keystore, §5.1). **Atualização (2026-10-05):** o refresh token passou a ser decifrado só depois do `BiometricPrompt` com `CryptoObject` (envelope AES-256-GCM + RSA-OAEP do Keystore, ver §5.1, "Decisão de custódia do refresh token do ACS"); a chave do SQLCipher segue sem esse vínculo. |
| **Critério de Aceite** | ✓ Todas as APIs autenticadas<br>✓ Testes de acesso não autorizado<br>✓ RBAC implementado e testado |

### LGPD-RT02 - Criptografia de Dados Sensíveis no Banco

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Dados sensíveis (CPF, condições crônicas, histórico de saúde) devem ser criptografados em repouso no PostgreSQL. |
| **Implementação** | Extensão `pgcrypto` para criptografia de colunas; chave de criptografia gerenciada pela aplicação; rotação de chaves documentada. Ainda não implementado no código atual (ver GitHub issue de análise LGPD dos dados armazenados). |
| **Critério de Aceite** | ✓ Dados sensíveis criptografados<br>✓ Chave não exposta em logs<br>✓ Plano de rotação de chaves documentado |

### LGPD-RT03 - Logs Estruturados e Imutáveis

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Todos os acessos e operações devem ser registrados em logs estruturados (JSON), imutáveis, e auditáveis. |
| **Implementação** | Tabela `audit_logs` no PostgreSQL; assinatura criptográfica dos logs (hash chain); armazenamento em tabela imutável (append-only). A tabela existia desde a migração-base sem escritor nenhum; os dois primeiros — `patients.listMicroArea` e a recusa por território em `visits.sync` (`AuditTrail`, `backend/sinalacs_server/lib/src/application/audit/`) — foram ligados, sempre com `ipHash` (nunca IP em claro) e best-effort (uma falha na trilha não derruba a operação clínica). **A assinatura em hash chain está implementada** (`AuditChain`, no mesmo diretório): cada linha carrega `sequence`, `previousHash` e `entryHash` — um HMAC-SHA256 sobre o conteúdo da linha, com um segredo próprio (`AUDIT_CHAIN_SECRET`) que nunca deriva do `JWT_SECRET`, para que rotacionar um não afete o outro. A escrita é serializada por `pg_advisory_xact_lock` dentro da mesma transação do apêndice, e um índice único em `sequence` é o segundo cinto contra bifurcação por concorrência. `AuditChainVerifier` (mesmo pacote) e `bin/audit_chain_check.dart` verificam a cadeia inteira sob demanda, detectando edição, remoção ou reordenação de qualquer linha — inclusive por quem tem acesso de escrita direto ao Postgres, já que o segredo fica fora do banco. **O que ainda falta**: o append-only em si não é imposto pelo banco (nenhum trigger/`REVOKE` bloqueia `UPDATE`/`DELETE` em `audit_logs` — a cadeia só *detecta* a violação, não a impede), e os demais endpoints que tocam dado sensível (alertas, ack, triagem) ainda não escrevem na trilha. |
| **Critério de Aceite** | ✓ Todos os endpoints geram logs (parcial: só `patients.listMicroArea` e a recusa territorial de `visits.sync`)<br>✓ Logs têm assinatura em hash chain verificável (`AuditChainVerifier`)<br>✗ Logs são imutáveis por construção do banco (append-only ainda é só convenção, sem trigger/`REVOKE`)<br>✓ Logs incluem data, usuário, ação, IP (anonimizado) |

### LGPD-RT04 - Consentimento Versionado

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | O sistema deve armazenar a versão do termo de consentimento aceito, permitindo rastrear mudanças ao longo do tempo. |
| **Implementação** | Tabela `consent_versions` com versionamento semântico; referência à versão em `consent_logs`; notificação de novas versões. |
| **Critério de Aceite** | ✓ Versionamento implementado<br>✓ Novo consentimento requerido para mudanças significativas<br>✓ Histórico de versões disponível |

### LGPD-RT05 - Registro de Aceite com Prova Legal

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | O aceite do Termo de Uso e Política de Privacidade deve ser registrado com provas robustas (timestamp, IP, device ID, hash do documento). |
| **Implementação** | Tabela `terms_acceptance` com: `user_id`, `term_type`, `version`, `hash`, `timestamp`, `ip_hash`, `device_id_hash`, `signature`. |
| **Critério de Aceite** | ✓ Todos os aceites registrados<br>✓ Hash do documento armazenado<br>✓ Registro imutável e auditável |

### LGPD-RT06 - Sessões e Autenticação Segura

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Sessões devem ter tempo de vida limitado, com autenticação forte para ACS (MFA) e mecanismos de segurança (biometria para pacientes). |
| **Implementação** | Pacientes: JWT de 1h, sem refresh token (o OTP é de uso único). ACS: o JWT segue em **15 min**; as **8h** são o teto absoluto do refresh token rotativo (janela ociosa de 2h), contado do login por senha + TOTP — implementado em 2026-10-03. MFA com TOTP para ACS. Autenticação biométrica nativa do dispositivo no app do **ACS** (`local_auth`), como portão de interface: não amarra a chave do SQLCipher nem o refresh token ao `BiometricPrompt`. No app do paciente não há biometria. Provado no emulador (API 36), não em aparelho físico. |
| **Critério de Aceite** | ✓ Sessões expiram<br>✓ MFA para ACS implementada<br>✓ Biometria de desbloqueio no app do ACS (portão de interface; paciente: não implementada)<br>✓ Logout automático documentado |

### LGPD-RT07 - Backup Criptografado e Testado

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Backups devem ser criptografados e testados periodicamente para garantir recuperação. |
| **Implementação** | Script de backup com criptografia; armazenamento separado da chave; teste de restauração mensal em ambiente de homologação; logs de backup. |
| **Critério de Aceite** | ✓ Backup diário automático<br>✓ Criptografia AES-256<br>✓ Teste de restauração documentado<br>✓ Plano de recuperação de desastres |

### LGPD-RT08 - Monitoramento e Alertas de Segurança

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Monitoramento contínuo de acessos suspeitos, tentativas de brute force, e padrões anômalos. |
| **Implementação** | Sistema de monitoramento (ex: Prometheus/Grafana) com regras: múltiplas falhas de login (alerta), acessos fora de horário (alerta), tentativas de acesso a dados de outras microáreas. |
| **Critério de Aceite** | ✓ Alertas configurados<br>✓ Equipe de resposta notificada<br>✓ Dashboards de monitoramento disponíveis |

### LGPD-RT09 - Exclusão Segura (Data Wiping)

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | A exclusão de dados deve ser segura, garantindo que não possam ser recuperados após a operação. |
| **Implementação** | Para exclusão lógica: flag `deleted` + anonimização de identificadores. Para exclusão física: comando `DELETE` + verificação de integridade referencial; ferramenta de wiping para dados locais. |
| **Critério de Aceite** | ✓ Processo de exclusão documentado<br>✓ Dados não recuperáveis<br>✓ Logs de exclusão mantidos<br>✓ Anonimização antes da exclusão física |

### LGPD-RT10 - Integração com Provedores Externos (DPAs)

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Toda integração com terceiros deve ser precedida de Data Processing Agreement (DPA) assinado. |
| **Implementação** | Portal de parceiros com documentação; checklist de conformidade; DPA assinado antes da integração técnica; monitoramento contínuo de conformidade. |
| **Critério de Aceite** | ✓ DPAs assinados para todos os parceiros<br>✓ Validação de conformidade prévia<br>✓ Monitoramento trimestral de compliance |

### LGPD-RT11 - Anonimização para Analytics

| Propriedade | Descrição |
|-------------|-----------|
| **Descrição** | Dados utilizados para analytics e métricas devem ser anonimizados ou agregados. |
| **Implementação** | Pipeline de dados que remove identificadores (CPF, nome, endereço) antes do processamento analítico; agregação por região e faixa etária; impossibilidade de reidentificação. |
| **Critério de Aceite** | ✓ Pipeline de anonimização implementado<br>✓ Teste de reidentificação negativo<br>✓ Dados agregados não identificam indivíduos |

---

## 8. Modelo Estruturado de Tabela de Requisitos

| ID | Categoria | Requisito | Descrição | Prioridade | Base Legal | Artigo LGPD | Critério de Aceitação |
|----|-----------|-----------|-----------|------------|------------|-------------|----------------------|
| LGPD-RF01 | Coleta de Dados | Coleta Mínima e Transparente | Coletar apenas dados necessários, com finalidade informada | Alta | Finalidade, Adequação, Necessidade | Art. 6º, I, II, III; Art. 9º | Checklist documentado, telas com finalidade específica |
| LGPD-RF02 | Consentimento | Consentimento Explicitado e Granular | Consentimento por finalidade, com opções independentes | Alta | Consentimento | Art. 7º, I; Art. 8º | Checkboxes por finalidade, registro com timestamp |
| LGPD-RF03 | Preferências | Gerenciamento de Preferências | Painel centralizado de privacidade | Média | Transparência, Autodeterminação | Art. 9º; Art. 18, V, VI | Painel acessível em 3 cliques |
| LGPD-RF04 | Auditoria | Registro de Consentimentos | Log imutável de consentimentos com metadados | Alta | Responsabilização | Art. 8º, §2º, §6º; Art. 37 | Tabela `consent_logs` com versão e timestamp |
| LGPD-RF05 | Consentimento | Revogação de Consentimento | Processo simples e gratuito de revogação | Alta | Direito de Revogação | Art. 8º, §5º, §6º | Botão de revogação, efetivação em 15 dias |
| LGPD-RF06 | Compartilhamento | Compartilhamento com Terceiros | Documentação de todos os compartilhamentos | Média | Transparência | Art. 7º, §1º; Art. 33 | DPAs assinados, lista de terceiros documentada |
| LGPD-RF07 | Retenção | Retenção e Exclusão de Dados | Política de retenção baseada em finalidade | Alta | Necessidade, Obrigação Legal | Art. 15, I, II; Art. 16, I, II | Mecanismo automático de expurgo |
| LGPD-RF08 | Direitos | Direitos do Titular dos Dados | Implementação de todos os direitos do Art. 18 | Alta | Direitos do Titular | Art. 18, I a IX | Todos os direitos mapeados em funcionalidades |
| LGPD-RF09 | Segurança | Proteção de Dados Sensíveis | Criptografia e controle de acesso para dados de saúde | Crítica | Segurança | Art. 11; Art. 46 | AES-256, TLS 1.3, RBAC |
| LGPD-RF10 | Transparência | Transparência no Tratamento | Informações claras e acessíveis sobre tratamento | Alta | Transparência | Art. 6º, VI; Art. 9º | Política em linguagem simples, resumo visual |
| LGPD-RF11 | Acesso | Controle de Acesso RBAC | Modelo rigoroso de permissões por perfil | Crítica | Segurança | Art. 46; Art. 50 | Matriz de permissões, MFA, logs de acesso |
| LGPD-RF12 | Incidentes | Comunicação de Incidentes | Plano de resposta com notificação em 72h | Alta | Segurança | Art. 48 | Plano documentado, templates de notificação |
| LGPD-RF13 | Dados Sensíveis | Tratamento de Dados de Saúde | Consentimento específico para dados de saúde | Crítica | Proteção Especial | Art. 11, I a III | Consentimento destacado, acesso restrito |
| LGPD-RF14 | Cookies | Cookies e Rastreamento | Transparência e opção de desativar rastreamento | Média | Transparência | Art. 6º, VI; Art. 7º, I | Ferramentas anonimizadas, opção de desativação |
| LGPD-RF15 | Marketing | E-mail Marketing | Consentimento específico para marketing | Média | Consentimento | Art. 7º, I; Art. 8º | Opt-in com dupla confirmação, link de descadastro |
| LGPD-RF16 | Publicidade | Anúncios Personalizados | Ausência de publicidade comportamental | Média | Proteção de Dados Sensíveis | Art. 11 | Nenhuma integração com redes de anúncios |
| LGPD-RF17 | Integrações | APIs e Serviços Externos | DPAs e avaliação de conformidade | Alta | Responsabilidade | Art. 33 a 40 | DPAs assinados, monitoramento de compliance |
| LGPD-RF18 | Documentos | Termo de Uso | Termo de Uso claro e acessível | Alta | Transparência | Art. 9º | Linguagem simples, aceite no cadastro |
| LGPD-RF19 | Documentos | Política de Privacidade | Documento abrangente e compreensível | Alta | Transparência | Art. 9º | Nível de leitura 8º ano, versão resumida |
| LGPD-RF20 | Consentimento | Aviso de Consentimento | Modal/banner de consentimento inicial | Alta | Consentimento | Art. 8º | Checkboxes granulares, registro de escolhas |
| LGPD-RF21 | Cookies | Banner de Cookies | Banner para cookies não essenciais | Média | Consentimento | Art. 8º | Distinção essenciais/não essenciais |

---

## 9. Recomendações para Implementação

### 9.1 Plano de Ação Imediato (Pré-Lançamento)

| Etapa | Ação | Responsável | Prazo |
|-------|------|-------------|-------|
| 1 | Revisar e aprovar Política de Privacidade e Termo de Uso | Jurídico/Compliance | 2 semanas |
| 2 | Implementar registro de consentimento granular | Dev Team | 3 semanas |
| 3 | Configurar criptografia do banco de dados | DevOps | 1 semana |
| 4 | Implementar RBAC e MFA | Dev Team | 4 semanas |
| 5 | Configurar logging e auditoria | Dev Team | 2 semanas |
| 6 | Treinar equipe em LGPD | RH/Compliance | 1 semana |

### 9.2 Melhorias Contínuas (Pós-Lançamento)

| Etapa | Ação | Periodicidade |
|-------|------|---------------|
| 1 | Auditoria de conformidade | Anual |
| 2 | Testes de penetração | Anual |
| 3 | Revisão da Política de Privacidade | Semestral |
| 4 | Treinamento de reciclagem | Anual |
| 5 | Avaliação de impacto (DPIA) | Mudanças significativas |
| 6 | Revisão de DPAs com parceiros | Semestral |

### 9.3 Contatos e Responsabilidades

| Função | Responsabilidade |
|--------|------------------|
| **Encarregado (DPO)** | Fiscalizar a conformidade, atender solicitações de titulares, orientar sobre práticas de proteção de dados, comunicar incidentes à ANPD. |
| **Equipe de Desenvolvimento** | Implementar requisitos técnicos de privacidade e segurança, seguir padrões de *Secure Coding*. |
| **Equipe de Compliance/Jurídico** | Elaborar políticas e termos, monitorar mudanças regulatórias, realizar auditorias. |
| **Líder de Segurança** | Gerenciar criptografia, monitoramento, e resposta a incidentes. |

---

## 10. Glossário

| Termo | Significado |
|-------|-------------|
| **LGPD** | Lei Geral de Proteção de Dados Pessoais (Lei nº 13.709/2018) |
| **Titular** | Pessoa natural a quem se referem os dados pessoais |
| **Controlador** | Quem decide as finalidades do tratamento (ex: Secretaria de Saúde) |
| **Operador** | Quem trata os dados em nome do controlador (ex: prestadores de serviço) |
| **Encarregado/DPO** | Pessoa designada para atuar como canal entre controlador, titulares e ANPD |
| **Dados Sensíveis** | Dados sobre origem racial, convicções religiosas, saúde, vida sexual, dados genéticos ou biométricos |
| **Consentimento** | Manifestação livre, informada e inequívoca pela qual o titular concorda com o tratamento |
| **ANPD** | Autoridade Nacional de Proteção de Dados |
| **DPA** | Data Processing Agreement (Contrato de Processamento de Dados) |
| **RBAC** | Role-Based Access Control (Controle de Acesso Baseado em Perfis) |
| **Privacy by Design** | Princípio de incorporar privacidade desde a concepção do sistema |
| **Privacy by Default** | Princípio de que a configuração padrão do sistema deve ser a mais protetiva |

---

*Este documento foi elaborado com base na Lei Geral de Proteção de Dados Pessoais (Lei nº 13.709/2018) e deve ser revisado periodicamente para garantir conformidade contínua com atualizações regulatórias e jurisprudenciais.*
