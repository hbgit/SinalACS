# AGENTS.md

## Visão geral do projeto

Este repositório contém a definição do produto, arquitetura e protótipos do SinalACS, uma plataforma para priorização de atendimentos em Atenção Primária à Saúde.

A intenção principal do projeto é apoiar dois fluxos centrais:
- paciente: autenticação simples, alerta de urgência, triagem estruturada e acompanhamento de status;
- ACS: priorização dinâmica, territorialização, registro offline e acompanhamento de microárea.

## Documentos fundamentais

Antes de implementar qualquer funcionalidade, consulte primeiro estes arquivos:
- [README.md](README.md) – visão geral do produto e contexto de negócio;
- [spec/idea.md](spec/idea.md) – conceito e objetivo do produto;
- [spec/PRD_system.md](spec/PRD_system.md) – requisitos, JTBD, invariantes e métricas;
- [spec/stack.md](spec/stack.md) – arquitetura de stack, infraestrutura e decisões técnicas;
- [spec/ui_design.md](spec/ui_design.md) – linguagem visual e comportamento de UX;
- [spec/ui_acs](spec/ui_acs) – protótipos das telas do ACS;
- [spec/ui_paciente](spec/ui_paciente) – protótipos das telas do paciente;
- [CLAUDE.md](CLAUDE.md) – guia de arquitetura e comandos para agentes de IA, mais atualizado que este arquivo quanto ao estado de implementação;
- [PROGRESS.md](PROGRESS.md) – status real dos milestones já implementados;
- [backend/](backend) – backend Dart real (não Serverpod, ver nota abaixo);
- [apps/acs](apps/acs) e [apps/patient](apps/patient) – apps Flutter implementados;
- [docs/](docs) – documentação visual das telas dos apps.

## Regras de trabalho para agentes de IA

### 1) Preserve o contexto do produto
- A solução é orientada por risco clínico, não por roteiros geográficos fixos.
- O foco do MVP é priorização e resposta rápida a urgências.
- O idioma principal do projeto e da documentação é o português.

### 2) Respeite a arquitetura definida
- O produto combina Flutter no cliente, um backend Dart puro (`dart:io`, sem framework — a decisão original de usar Serverpod nunca foi implementada) e PostgreSQL como persistência central.
- O modelo offline-first é crítico; o ACS deve operar mesmo com rede instável.
- O MQTT é usado para entrega de alertas de urgência em tempo real.
- A sincronização local/central deve ser tratada como risco arquitetural principal.

### 3) Preserve invariantes de negócio e segurança
- A microárea da pessoa ACS deve restringir o acesso somente ao seu território.
- A classificação de risco deve ser determinística e não alterável por intervenção humana na triagem.
- Alertas vermelhos não podem ser descartados silenciosamente.
- Dados sensíveis de saúde devem seguir o padrão de privacidade e LGPD.

### 4) Ao criar ou alterar código
- Prefira soluções simples, previsíveis e alinhadas com a arquitetura já definida.
- Evite inventar recursos que não estejam no PRD ou no stack do projeto.
- Quando houver conflito entre convenções gerais e documentação do projeto, a documentação do projeto vence.
- Mantenha a lógica de priorização e triagem consistente com o modelo do Protocolo de Manchester e regras determinísticas.

### 5) Quando o trabalho for de UI
- Siga a linguagem visual do dark mode, alta legibilidade e baixo ruído visual.
- Use a lógica de cores somente para sinalizar gravidade: vermelho, amarelo e verde são sinais clínicos, não elementos decorativos.
- Mantenha foco em mobile-first e acessibilidade.

### 6) Quando o trabalho for de backend ou dados
- Considere cache local em SQLite/sqflite para uso offline.
- Planeje sincronização com retry, fila e resolução de conflitos.
- Preserve auditabilidade e rastreabilidade dos eventos de triagem e sincronização.

## Estrutura relevante do repositório

- [spec/](spec) — artefatos de produto, arquitetura, requisitos e protótipos;
- [spec/ui_acs](spec/ui_acs) — fluxos do ACS;
- [spec/ui_paciente](spec/ui_paciente) — fluxos do paciente;
- [backend/](backend) — backend Dart real;
- [apps/acs](apps/acs), [apps/patient](apps/patient) — apps Flutter reais;
- [docs/](docs) — documentação visual das telas.

## Observações para agentes

Este repositório já tem um protótipo funcional implementado (backend Dart, apps Flutter de paciente e ACS, CI validando os três), validado localmente via Docker Compose — não é mais só especificação/prototipação. Qualquer código adicionado deve refletir as decisões capturadas em [spec/stack.md](spec/stack.md), [spec/PRD_system.md](spec/PRD_system.md) e [spec/ui_design.md](spec/ui_design.md) quando ainda válidas, mas note que alguns detalhes desses documentos (em especial menções a "Serverpod" como framework de backend) descrevem a decisão arquitetural original e não o que foi de fato implementado — consulte [CLAUDE.md](CLAUDE.md) e [PROGRESS.md](PROGRESS.md) para o estado real de implementação antes de assumir que a spec reflete o código atual.

Se a tarefa solicitar implementação, priorize a consistência com os documentos acima e mantenha o comportamento alinhado ao MVP definido no PRD.
