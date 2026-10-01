---
marp: true
theme: sinalacs
paginate: true
size: 16:9
lang: pt-BR
---

<!-- _class: cover -->

# SinalACS

<p class="tagline">Priorização clínica de visitas domiciliares na Atenção Primária à Saúde</p>

<span class="kicker">Showcase — protótipo</span>

<!--
Equipe / autoria: completar antes da apresentação final.
-->

---

<!-- _class: statement -->

# A doença não segue o mapa.

O Agente Comunitário de Saúde visita as casas na ordem do roteiro geográfico —
rua por rua, sempre igual. Quem está pior pode ser a última visita do dia,
simplesmente por morar no fim da rua.

---

<!-- _class: statement -->

# Sinais clínicos estruturados → fila ranqueada por risco

Uma triagem de três perguntas, com regra determinística inspirada no
Protocolo de Manchester — sem inteligência artificial, sem campo editável.
A mesma resposta produz sempre a mesma cor, de forma auditável.

<div class="card-grid cols-3" style="margin-top: 32px;">
  <div class="card">
    <h3>e-SUS APS</h3>
    <p>Registra o que já aconteceu.</p>
  </div>
  <div class="card">
    <h3>WhatsApp</h3>
    <p>Desorganiza — comunicação sem estrutura nem prioridade.</p>
  </div>
  <div class="card" style="border-color: var(--acs-fill);">
    <h3 style="color: var(--acs-text);">SinalACS</h3>
    <p>Prioriza, com regra fechada e reproduzível.</p>
  </div>
</div>

---

# Arquitetura em um slide

<div class="card-grid cols-4" style="margin-top: 24px;">
  <div class="card">
    <h3>3 apps Flutter</h3>
    <p>Paciente, ACS e Admin — isomorfismo Dart de ponta a ponta com o backend.</p>
  </div>
  <div class="card">
    <h3>Backend Dart/Serverpod</h3>
    <p>RPC tipado, ORM e migrações geradas — não é REST.</p>
  </div>
  <div class="card">
    <h3>PostgreSQL + MQTT/TLS</h3>
    <p>Persistência relacional e entrega de alerta com confirmação (ACK).</p>
  </div>
  <div class="card">
    <h3>Traefik</h3>
    <p>Reverse proxy/edge gateway para tráfego RPC e WebSockets do MQTT.</p>
  </div>
</div>

<p style="margin-top: 24px; color: var(--text-muted); font-size: 16px;">
Offline-first: cache territorial em <code>sqflite</code> no app do ACS, com
sincronização em segundo plano assim que a rede volta.
</p>

---


<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/paciente-autenticacao.png" alt="Login do paciente com CPF e data de nascimento" />
    </div>
  </div>
  <div class="info-col">
    <h2>Paciente — Autenticação inclusiva</h2>
    <ul>
      <li>Acesso com CPF e data de nascimento, sem senha</li>
      <li>Atalho de QR Code visível na tela (leitura ainda depende de integração)</li>
      <li>Pensado para baixo letramento digital: fricção mínima no primeiro acesso</li>
    </ul>
  </div>
</div>

<span class="app-tag patient">Paciente</span>

---


<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/paciente-emergencia.png" alt="Alerta de urgência" />
    </div>
  </div>
  <div class="info-col">
    <h2>Paciente — Alerta de urgência</h2>
    <ul>
      <li>Botão circular de emergência domina a hierarquia visual</li>
      <li>Confirmação explícita antes de qualquer mudança de estado</li>
      <li>O alerta é <strong>registrado e enfileirado</strong> — a entrega ponta a
        ponta com confirmação (ACK) é a prova técnica do próximo bloco</li>
    </ul>
  </div>
</div>

<span class="app-tag patient">Paciente</span>

---


<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/paciente-triagem.png" alt="Triagem com resultado de risco" />
    </div>
  </div>
  <div class="info-col">
    <h2>Paciente — Triagem rápida</h2>
    <ul>
      <li>Três perguntas, uma resposta por vez, com indicador de progresso</li>
      <li>Classificação <strong>determinística</strong>, sem campo editável —
        nem para o paciente, nem para o ACS</li>
      <li>Mesma resposta → mesma cor, sempre. Regra fechada e auditável</li>
    </ul>
    <div class="risk-chip red" style="margin-top: 8px;">Risco: Vermelho</div>
  </div>
</div>

<span class="app-tag patient">Paciente</span>

---


<h2>Paciente — Acompanhamento, lembretes e meus dados</h2>

<div style="display: flex; justify-content: center; gap: 48px; margin-top: 16px;">
  <figure style="margin: 0; text-align: center;">
    <div class="phone-frame" style="width: 170px;">
      <img src="images/paciente-acompanhamento.png" alt="Status da solicitação" />
    </div>
    <figcaption style="margin-top: 10px; font-size: 14px; color: var(--text-muted);">Status da solicitação</figcaption>
  </figure>
  <figure style="margin: 0; text-align: center;">
    <div class="phone-frame" style="width: 170px;">
      <img src="images/paciente-lembretes.png" alt="Lembretes de medicamentos e rotina" />
    </div>
    <figcaption style="margin-top: 10px; font-size: 14px; color: var(--text-muted);">Lembretes</figcaption>
  </figure>
  <figure style="margin: 0; text-align: center;">
    <div class="phone-frame" style="width: 170px;">
      <img src="images/paciente-perfil.png" alt="Perfil clínico e meus dados" />
    </div>
    <figcaption style="margin-top: 10px; font-size: 14px; color: var(--text-muted);">Perfil clínico · meus dados</figcaption>
  </figure>
</div>


<span class="app-tag patient">Paciente</span>

---

<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/acs-login.png" alt="Login institucional do ACS" />
    </div>
  </div>
  <div class="info-col">
    <h2>ACS — Login institucional</h2>
    <ul>
      <li>Matrícula/CNS e senha, com indicador de operação offline</li>
      <li>Mesmo padrão visual do login do Admin</li>
      <li>Autenticação institucional real (SSO/gov.br) é passo seguinte do roadmap</li>
    </ul>
  </div>
</div>

<span class="app-tag acs">ACS</span>

---

<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/acs-territorializacao.png" alt="Territorialização" />
    </div>
  </div>
  <div class="info-col">
    <h2>ACS — Territorialização</h2>
    <ul>
      <li>Microárea, quantidade de pacientes e status do cache local</li>
      <li><strong>O ACS só acessa dados do próprio território</strong> —
        invariante do sistema, não uma configuração (INV-01)</li>
      <li>Cache territorial via <code>sqflite</code>, para operar sem rede</li>
    </ul>
  </div>
</div>

<span class="app-tag acs">ACS</span>

---

<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/acs-dashboard.png" alt="Fila priorizada por risco" />
    </div>
  </div>
  <div class="info-col">
    <h2>ACS — Fila de priorização</h2>
    <ul>
      <li>Ordem por gravidade clínica: vermelho → amarelo → verde</li>
      <li>Cor é <strong>exclusiva</strong> da classificação de risco — avisos
        técnicos (sem conexão, falha ao salvar) usam azul, nunca vermelho/amarelo</li>
      <li>Falha transitória ganha botão "Tentar agora", mesmo com reconexão
        automática já em curso</li>
    </ul>
  </div>
</div>

<span class="app-tag acs">ACS</span>

---

<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/acs-visita.png" alt="Registro de visita offline" />
    </div>
  </div>
  <div class="info-col">
    <h2>ACS — Registro de visita offline</h2>
    <ul>
      <li>Desfecho e observações registrados na porta da casa, com ou sem sinal</li>
      <li>Enfileiramento local; sincronização automática ao voltar a rede</li>
      <li>Em zona rural, é a diferença entre ter o dado e perder o dia</li>
    </ul>
  </div>
</div>

<span class="app-tag acs">ACS</span>

---

<div class="split">
  <div class="frame-col">
    <div class="phone-frame">
      <img src="images/acs-acionamento.png" alt="Tela de acionamento e escalonamento" />
    </div>
  </div>
  <div class="info-col">
    <h2>ACS — Acionamento e escalonamento</h2>
    <ul>
      <li>Resume paciente, risco e endereço para acionar SAMU ou UBS</li>
      <li>Botões deixam explícito que discagem e encaminhamento reais ainda não
        estão integrados</li>
      <li>Integração SAMU <span class="badge-roadmap">roadmap</span></li>
    </ul>
  </div>
</div>

<span class="app-tag acs">ACS</span>

---

<div class="split">
  <div class="frame-col" style="flex-basis: 48%;">
    <div class="phone-pair">
      <div class="phone-frame" style="width: 240px;">
        <img src="images/admin-indicadores.png" alt="Painel de indicadores" />
      </div>
      <div class="phone-frame" style="width: 240px;">
        <img src="images/admin-microarea.png" alt="Microáreas e vínculo ACS" />
      </div>
    </div>
  </div>
  <div class="info-col">
    <h2>Admin — Indicadores e microáreas</h2>
    <ul>
      <li>Contadores por risco, alertas abertos vs. reconhecidos e o TMRAV</li>
      <li>Listagem somente leitura das microáreas e do ACS vinculado</li>
      <li>Desktop-first: <code>NavigationRail</code> em telas largas,
        <code>NavigationBar</code> abaixo de 640px</li>
    </ul>
  </div>
</div>

<span class="app-tag admin">Admin</span>

---

<div class="split">
  <div class="frame-col" style="flex-basis: 48%;">
    <div class="phone-pair">
      <div class="phone-frame" style="width: 240px;">
        <img src="images/admin-alertas.png" alt="Alertas da UBS" />
      </div>
      <div class="phone-frame" style="width: 240px;">
        <img src="images/admin-auditoria.png" alt="Logs de auditoria" />
      </div>
    </div>
  </div>
  <div class="info-col">
    <h2>Admin — Alertas, auditoria e layout responsivo</h2>
    <ul>
      <li>Alertas filtráveis por microárea e status — sem controle de
        reclassificação (a classificação não é alterável por humano, INV-02)</li>
      <li>Log de auditoria somente leitura; toda visita às telas sensíveis
        também é registrada</li>
      <li>Mesmo <code>ThemeData</code> se adapta de celular a tablet</li>
    </ul>
  </div>
</div>

<span class="app-tag admin">Admin</span>

---

# Segurança e LGPD

<div class="card-grid cols-3" style="margin-top: 24px;">
  <div class="card">
    <h3>Dados sensíveis</h3>
    <p>Colunas clínicas criptografadas (AES-256/pgcrypto) em repouso e TLS em trânsito.</p>
  </div>
  <div class="card">
    <h3>Restrição por microárea</h3>
    <p>INV-01 reforçada no backend, não só na interface — um ACS nunca lê dados
      fora do próprio território.</p>
  </div>
  <div class="card">
    <h3>Trilha de auditoria</h3>
    <p>Acesso a dado sensível registrado com quem, quando e o quê — inclusive
      no backoffice Admin.</p>
  </div>
</div>

<p style="margin-top: 24px; color: var(--text-muted); font-size: 15px;">
Conformidade LGPD documentada em <code>spec/lgpd_design.md</code>; análise de
cibersegurança baseada em NIST CSF 2.0 em <code>spec/security_assessment.md</code>.
</p>

---

# Estado atual e roadmap

<p>Protótipo validado localmente — ciclo de alerta vermelho roda ponta a ponta
com confirmação de entrega, CI verde nos quatro trilhos.</p>

<div class="roadmap">
  <div class="phase done">
    <div class="status">Concluída</div>
    <strong>Fase 1 — Prova de conceito</strong>
  </div>
  <div class="phase done">
    <div class="status">Concluída</div>
    <strong>Fase 2 — Alpha/Beta</strong>
  </div>
  <div class="phase pending">
    <div class="status">Em curso</div>
    <strong>Fase 3 — Disponibilidade geral</strong>
    <p style="font-size: 14px; margin-top: 8px;">Deploy monitorado, teste de
      carga e auditoria de conformidade LGPD</p>
  </div>
</div>

<p style="margin-top: 20px; font-size: 16px;">
Mapa interativo, geofencing, integração SAMU e avisos push
<span class="badge-roadmap">roadmap v1.5</span> — hoje são stubs no protótipo,
não capacidades ativas.
</p>

---

<!-- _class: closing -->

# O pedido: um piloto controlado

<div class="bignums">
  <div><div class="num">1</div><div class="label">UBS</div></div>
  <div><div class="num">2</div><div class="label">microáreas</div></div>
  <div><div class="num">50</div><div class="label">pacientes</div></div>
</div>

<p>
Para medir a única métrica que importa: quanto tempo leva, hoje, até alguém
chegar em quem está pior.
<span class="badge-target">alvo &lt; 90s (TMRAV)</span>
</p>

<p style="margin-top: 40px; color: var(--text-muted);">
SinalACS · github.com/hbgit/SinalACS · contato: completar antes da apresentação
</p>
