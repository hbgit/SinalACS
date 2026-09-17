## 1. Stack Principal & Persistência

* **Frontend & Backend (Isomorfismo Dart):** Flutter no client e Dart no backend. A decisão original era usar **Serverpod** no backend, com ORM e *endpoints* de cliente Dart gerados automaticamente. Essa decisão ficou por um tempo não implementada — o backend era um servidor `dart:io` puro, roteado manualmente — e foi executada depois: o backend real (`backend/`) é hoje um workspace Serverpod 3.4.13, com ORM, migrações geradas e o cliente Dart tipado em `sinalacs_client`. Ver [CLAUDE.md](../CLAUDE.md) para a arquitetura atual e a seção "Migração para Serverpod" do [PROGRESS.md](../PROGRESS.md) para o histórico.


* **Persistência Relacional:** PostgreSQL acoplado ao `sqflite` local. A escolha relacional reflete a necessidade estruturada da matriz de triagem fechada inspirada no Protocolo de Manchester.


* **Mensageria IoT:** Eclipse Mosquitto (MQTT) atua como *broker* de mensagens leve e de baixo consumo. Isso garante a entrega do botão de alerta de urgência do paciente para o ACS mesmo sob redes instáveis.


* **Estratégia Offline-First:** O download de cache territorial para a microárea utiliza `sqflite`. O aplicativo do ACS registra a visita offline e sincroniza em *background* assim que houver conectividade.



## 2. DX, Autenticação & Infraestrutura

* **IaC:** Pulumi (com TypeScript) para provisionar os containers em VPS robustas. Abstrai a infraestrutura como código com forte tipagem, sem o *vendor lock-in* do AWS CDK.
* **Autenticação na Borda:** Módulo de autenticação na camada de aplicação do backend acoplado ao **Traefik** como *Reverse Proxy/Edge Gateway*. O Traefik roteia tráfego REST e os WebSockets do MQTT. Ainda não implementado — hoje o backend só tem um endpoint de login de desenvolvimento, sem autenticação institucional real.
* **Login Fricção Zero:** A entrada *passwordless* por OTP ou QR Code no app do paciente é delegada à camada de aplicação.



## 3. Análise de Risco: O Elo Mais Fraco

A **Sincronização Bidirecional Offline-First** é o componente de maior risco arquitetônico neste MVTS.

* **Vendor Lock-in:** Soluções maduras de sincronização (como PowerSync) mitigam conflitos, mas introduzem forte dependência de fornecedor e custo atrelado à infraestrutura proprietária deles.
* **Custo de Escala:** Desenvolver um motor customizado `sqflite` <-> PostgreSQL exige manutenção constante e encarece as horas de engenharia a longo prazo.
* **Migração Técnica:** Se houver colisões frequentes de estado (ex: ACS registrando visitas offline que já foram alteradas na central), a migração futura exigirá refatoração pesada para modelos complexos de CRDTs (*Conflict-free Replicated Data Types*).

## 4. Docker-Compose MVTS

A decisão arquitetural é usar Postgres + Mosquitto + Traefik como reverse proxy na stack local, orquestrados via Docker Compose. A topologia concreta (serviços de inicialização de banco/broker, TLS no MQTT, variáveis de ambiente de produção, healthchecks) evoluiu bastante desde a concepção inicial deste documento — o [`docker-compose.yml`](../docker-compose.yml) na raiz do repositório é a fonte da verdade operacional atual, não um exemplo espelhado aqui (evita os dois arquivos divergirem silenciosamente ao longo do tempo, como já havia acontecido).

## 5. Decisões de stack pendentes de implementação (2026-09-16)

`spec/validation_report.md` identificou lacunas que exigiam decisão de
arquitetura antes de qualquer código novo. As decisões abaixo estão
detalhadas em `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`
e ainda **não foram implementadas**:

* **Criptografia de colunas no PostgreSQL (RNF03/INV-04):** decidido usar
  criptografia de aplicação (AES-256-GCM em Dart, na camada de repositório),
  não `pgcrypto` em SQL — evita que o dado de saúde em texto claro passe pelo
  `serverpod_query_log` antes de virar ciphertext. A chave segue o mesmo
  padrão de segredo por variável de ambiente já usado para `JWT_SECRET`/
  `AUDIT_CHAIN_SECRET` (gerado por `scripts/dev/bootstrap_env.sh`), sem
  introduzir um KMS externo nesta fase.
* **Push segmentado (RF14):** Firebase Cloud Messaging é o provedor
  escolhido, mas a decisão está **bloqueada externamente** — não existe
  projeto Firebase provisionado neste repositório.
* **Geofencing (RF12):** rejeitado rastreamento contínuo em segundo plano do
  ACS; adotado geofence único atrelado a uma visita ativa, com serviço em
  primeiro plano e notificação persistente, para evitar a política mais
  restritiva de "background location" da Play Store.
