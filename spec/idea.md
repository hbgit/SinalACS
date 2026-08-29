# SinalACS: Plataforma de Triagem e Otimização para Atenção Primária

## Visão Geral do Produto

* **Nome do Conceito:** SinalACS.
* **Pitch de Uma Frase:** Um aplicativo de mapeamento e classificação de risco que otimiza a rotina da atenção primária, transformando visitas sequenciais em um fluxo de trabalho dinâmico baseado na gravidade do paciente.
* **Problema Central:** A ineficiência e a falta de priorização no modelo atual de visitas domiciliares, que historicamente opera de forma reativa e baseada em roteiros geográficos fixos, em vez de ser orientado pelo risco clínico em tempo real. Isso gera um desalinhamento crítico entre o paciente que mais precisa de ajuda e o momento em que ele efetivamente a recebe.
* **Conceito e Escopo:** O aplicativo atua como uma plataforma bidirecional de triagem e gestão de fluxo de trabalho para a Atenção Primária à Saúde. Seu propósito fundamental é substituir o modelo tradicional de visitas domiciliares – que é estático e baseado puramente em roteiros geográficos – por um sistema de roteamento dinâmico e inteligente. A ferramenta organiza e direciona a atuação da equipe de saúde com base na urgência clínica e nas necessidades em tempo real da comunidade, garantindo intervenções precisas e oportunas. Tudo isso estruturado sob sólidas regras de negócio e algoritmos tradicionais, garantindo precisão determinística sem o uso de IA.
* **Vantagem Competitiva (Moat):** A maioria das soluções existentes na Atenção Primária à Saúde (como o e-SUS APS) funciona como sistemas de registro passivo, focados em consolidação de dados e faturamento. Ferramentas de comunicação genéricas (como o WhatsApp) geram comunicação desestruturada que sobrecarrega o ACS. O diferencial deste aplicativo reside na sua capacidade de transformar dados em ação imediata e estruturada, criando um fosso competitivo através da triagem algorítmica e roteamento inteligente.
* **Pré-requisitos Técnicos:** Conhecimento em Flutter (Dart). Familiaridade com bibliotecas como `riverpod` (gerência de estado), `json_serializable`, `geolocator`, `google_maps_flutter`, `sqflite` (banco de dados offline), `connectivity_plus`, `mqtt_client` (mensageria leve), `flutter_local_notifications`, `flutter_form_builder` e `url_launcher`.

---

## Detalhamento de Funcionalidades e Automações Criativas

Para garantir a máxima eficiência operacional utilizando regras lógicas de negócio e automação de processos, o escopo de funcionalidades é dividido entre os dois atores principais:

### Funcionalidades do Aplicativo do Paciente

1. **Módulo de Autenticação e Onboarding Inclusivo (Login):**
* **Acesso Fricção Zero (Passwordless):** Entrada baseada no CPF e Data de Nascimento, validados por um código SMS (OTP) ou biometria do dispositivo.
* **Onboarding Assistido (QR Code):** Para idosos ou pessoas com baixo letramento digital, o ACS gera um QR Code em seu próprio aparelho durante uma visita. O paciente escaneia e o app SinalACS é configurado e logado automaticamente.
* **Sessão Persistente:** O aplicativo não desloga, garantindo que em uma emergência o acesso seja instantâneo.


2. **Botão de Alerta de Urgência:** Uma interface de acionamento rápido (botão de pânico) que dispara um alerta vermelho em tempo real (via protocolo MQTT) para o dispositivo do ACS, anexando a geolocalização exata.
3. **Formulário Estruturado de Triagem:** Um menu de múltipla escolha simples. Utiliza uma árvore de decisão fechada (matriz algorítmica inspirada no Protocolo de Manchester) que calcula uma pontuação matemática para classificar a gravidade instantaneamente (Vermelho, Amarelo, Verde).
4. **Canal de Dúvidas com Gatilhos (Mensageria Assíncrona):** Sistema de chamados (tickets) com respostas automáticas baseadas em regras de palavras-chave. Exemplo: se a mensagem contiver "vacina", o sistema envia o calendário local automaticamente antes de alocar o tempo do ACS.
5. **Perfil Clínico e Cadastro de Crônicos:** Histórico em formato de *checkboxes* mantido pelo paciente (diabetes, hipertensão, uso contínuo de insulina), fundamental para adicionar peso ao algoritmo de priorização das visitas.
6. **Acompanhamento de Status de Solicitação:** Um painel visual simples (estilo rastreamento de encomendas) que informa: *Enviado -> Visualizado pelo ACS -> Em Análise -> Visita Agendada/Respondido*.
7. **Lembretes Automatizados de Saúde:** Configuração de alarmes locais (`flutter_local_notifications`) sem dependência de internet, avisando sobre horários de medicação ou dias de pesagem.

### Funcionalidades do Aplicativo do ACS

1. **Acesso Institucional (Login):** Login restrito utilizando matrícula/senha da Secretaria de Saúde ou integração oficial via Gov.br, garantindo rastreabilidade e segurança (LGPD).
2. **Seleção de Pacientes por Localidade (Territorialização):** Módulo que permite ao ACS carregar especificamente a sua "Microárea". O sistema faz o download (cache local no `sqflite`) apenas dos dados daquela região, garantindo o funcionamento e a busca de pacientes mesmo quando o ACS estiver em zonas rurais ou sem sinal de internet.
3. **Dashboard de Priorização (Fila de Trabalho Dinâmica):** A tela inicial do ACS. Uma lista de tarefas diárias auto-ordenável. O algoritmo empurra para o topo os alertas vermelhos, seguidos pelas visitas amarelas (crônicos descompensados) e por último os verdes (dúvidas e rotina).
4. **Mapa Interativo de Pacientes (Geolocalização):** Integração com `google_maps_flutter`. Transforma a lista do dashboard em uma visualização espacial. Pinos coloridos mostram onde estão as urgências, permitindo ao ACS traçar rotas eficientes (ex: agrupar 3 visitas amarelas na mesma rua).
5. **Módulo de Acionamento e Escalonamento:** Botão de emergência (usando `url_launcher`) que compila os dados do paciente (ID, risco, endereço) para o ACS ditar rapidamente ao SAMU ou encaminhar diretamente via sistema para a triagem da Unidade Básica de Saúde (UBS).
6. **Registro Rápido de Visitas (Offline-first):** Formulário objetivo para dar "baixa" no atendimento. Funciona 100% offline. Assim que o `connectivity_plus` detecta sinal de internet, os dados são sincronizados em background com o servidor central.
7. **Automação por Geofencing (Check-in Passivo):** Utilizando o GPS em segundo plano, o aplicativo detecta quando o ACS entra no raio de 30 metros da residência de um paciente prioritário e abre automaticamente a tela de registro de visita daquele cidadão, economizando cliques.
8. **Sistema de Avisos à Comunidade:** Disparo segmentado de notificações push (ex: "Campanha de vacinação amanhã" enviado apenas para mães de crianças menores de 5 anos na microárea X).

---

## Estilo Visual e UX

* **Tema Base:** Minimalista, interface limpa sem excesso de botões.
* **Dark Mode Nativo (Modo Escuro):** Padrão do aplicativo para reduzir a fadiga visual do ACS (que passa horas sob o sol olhando para a tela) e economizar drasticamente a bateria dos dispositivos móveis.
* **Paleta de Cores:** Fundo cinza-chumbo, fontes em branco/cinza claro, detalhes em tons frios (azul e verde medicina).
* **Uso Estratégico da Cor:** Vermelho, Laranja e Amarelo são estritamente banidos de elementos decorativos, sendo usados exclusivamente para sinalizar gravidade, alertas vitais ou ações críticas.

---

## Definição do MVP (Produto Mínimo Viável - v1.0)

Para validar a solução no mercado o mais rápido possível (reduzindo tempo e custo de desenvolvimento), a versão 1.0 focará exclusivamente no fluxo de socorro e priorização:

* **App Paciente (MVP):**
* Login Passwordless/QR Code.
* Botão de Alerta de Urgência.
* Formulário Estruturado de Triagem (3 perguntas para ranquear a dor).
* Painel de Status.


* **App ACS (MVP):**
* Login Institucional.
* Download da Localidade/Microárea (Offline cache).
* Dashboard Dinâmico (Lista de priorização por cores).
* Registro Básico de Visitas (Baixa no chamado, operando offline).
*(O mapa interativo e o sistema de mensagens em massa ficam para a v1.5).*



---

## Marcos de Entrega (Milestones)

Abaixo o plano tático para levar a plataforma da ideia à produção.

* Fase 1: Wireframes e Arquitetura
Esboço das telas principais focando em alvos de toque grandes (acessibilidade). Mapeamento dos fluxos do usuário e modelagem do banco de dados relacional local (`sqflite`).


* Fase 2: Protótipo Funcional (UI/UX)
Design interativo no Figma. Validação do Modo Escuro e testes de usabilidade com ACS e pacientes idosos para confirmar a fricção zero do login por QR Code.


* Fase 3: Configuração do Backend e Infraestrutura
Setup do servidor central, estruturação das APIs RESTful, e implementação do servidor MQTT para garantir a entrega dos alertas de urgência mesmo em redes 3G instáveis.


* Fase 4: Desenvolvimento de Módulos (Sprints)
Construção iterativa.
Sprint 1: Módulo de Autenticação e Sincronização Local (Territorialização).
Sprint 2: Motor Lógico de Triagem e Dashboard do ACS.
Sprint 3: Botão de Alerta e Registro Offline.


* Fase 5: Testes de Usabilidade e Desempenho
Testes de stress simulando áreas de sombra (sem internet). Auditoria de segurança para garantir a conformidade com a LGPD e testes de consumo de bateria em campo.


* Fase 6: Teste de Aceitação do Usuário (UAT)
Implantação piloto (Beta fechado) com 2 a 3 Agentes Comunitários em uma única UBS. Ajustes no algoritmo de priorização com base no feedback real dos médicos da unidade.


* Fase 7: Operações e Manutenção (Lançamento)
Rollout oficial da v1.0. Monitoramento contínuo de logs de erro, suporte ativo aos usuários e início do desenvolvimento das features da v1.5 (Mapas e Geofencing).
