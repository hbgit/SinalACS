## 0. Hospedagem e distribuição independentes e de baixo custo

> Conteúdo educativo. Não substitui atendimento profissional. Emergência: ligue 192.

Esta seção vale para o escopo atual do projeto ([`escopo_projeto.md`](escopo_projeto.md)): educação em saúde, código aberto, sem vínculo com unidades de saúde. As seções seguintes descrevem a stack implementada e as decisões de origem.

**Princípio.** Qualquer pessoa replica o SinalACS com o repositório, um `docker compose` e o APK publicado. Nenhum componente obrigatório depende de infraestrutura, sistema ou dado de unidade de saúde, nem de serviço pago sem alternativa gratuita (RNF07, RNF08).

**Perfis de implantação.**

| Perfil | Para quê | Como |
|---|---|---|
| Local/demonstração | Desenvolvimento, aulas, avaliação do código | Stack atual do `docker-compose.yml`, custo zero |
| Piloto | Piloto educativo ([`plano_piloto.md`](plano_piloto.md)) | Um host Docker em camada gratuita ou VPS mínima, Postgres no mesmo host, certificado Let's Encrypt pelo Traefik; roteiro em [`backend/DEPLOY.md`](../backend/DEPLOY.md) |
| Futuro | Operação com instituição de saúde | Pulumi, redes privadas, PKI de produção (#118); ver [`trabalhos_futuros.md`](trabalhos_futuros.md) |

**Componentes no piloto.**

| Componente | Obrigatório no piloto? | Alternativa gratuita / observação |
|---|---|---|
| PostgreSQL | Sim | Imagem oficial no mesmo host |
| Traefik | Sim | Let's Encrypt (ACME) gratuito |
| Mosquitto | Só no pilar B com RF03 ativo | Imagem oficial no mesmo host |
| Gorush + FCM | Não | FCM sem custo; o app funciona sem push |
| Gateway SMS | Não usado (P-10: sem CPF e sem SMS) | **Limite atual:** fora de `development` o backend não sobe sem `SMS_GATEWAY`; retirar essa exigência é a mudança C-05, pré-requisito do piloto |
| Play Store | Não (Futuro) | APK em GitHub Releases |

**Distribuição (M-03).** O app é distribuído como APK assinado publicado em GitHub Releases, gratuito. A Play Store exige conta de desenvolvedor paga e fica como Futuro. A chave de assinatura de release ainda precisa ser provisionada (pendência já registrada no `CLAUDE.md`). Custódia do repositório e da chave de assinatura: decisão proposta P-13 (status: Proposta).

**Custo.** Teto mensal de R$ 50 (decisão aprovada P-08), revisto na data da contratação. Nenhum preço de provedor é fixado aqui: verificar na data da contratação.

**Restrição.** Nenhum componente é hospedado em infraestrutura de unidade de saúde.

## 1. Stack Principal & Persistência

* **Frontend & Backend (Isomorfismo Dart):** Flutter no client e Dart no backend. A decisão original era usar **Serverpod** no backend, com ORM e *endpoints* de cliente Dart gerados automaticamente. Essa decisão ficou por um tempo não implementada — o backend era um servidor `dart:io` puro, roteado manualmente — e foi executada depois: o backend real (`backend/`) é hoje um workspace Serverpod 3.4.13, com ORM, migrações geradas e o cliente Dart tipado em `sinalacs_client`. Ver [CLAUDE.md](../CLAUDE.md) para a arquitetura atual e a seção "Migração para Serverpod" do [PROGRESS.md](../PROGRESS.md) para o histórico.


* **Persistência Relacional:** PostgreSQL acoplado ao `sqflite` local. A escolha relacional reflete a necessidade estruturada da matriz de triagem fechada (árvore de decisão fechada).


* **Mensageria IoT:** Eclipse Mosquitto (MQTT) atua como *broker* de mensagens leve e de baixo consumo. Isso garante a entrega do botão de alerta de urgência do paciente para o ACS mesmo sob redes instáveis.


* **Estratégia Offline-First:** O download de cache territorial para a microárea utiliza `sqflite`. O aplicativo do ACS registra a visita offline e sincroniza em *background* assim que houver conectividade.



## 2. DX, Autenticação & Infraestrutura

* **IaC:** Pulumi (com TypeScript) para provisionar os containers em VPS robustas (Futuro — o piloto não usa IaC; ver §0). Abstrai a infraestrutura como código com forte tipagem, sem o *vendor lock-in* do AWS CDK.
* **Autenticação na Borda:** Módulo de autenticação na camada de aplicação do backend acoplado ao **Traefik** como *Reverse Proxy/Edge Gateway*. O Traefik roteia tráfego REST e os WebSockets do MQTT. Ainda não implementado — hoje o backend só tem um endpoint de login de desenvolvimento, sem autenticação institucional real. **Atualização (2026-09-18):** a autenticação institucional existe (`auth.loginInstitutional`, RF07) — matrícula + senha com Argon2id contra `user_credentials`, bloqueio por tentativas e auditoria. O que segue não implementado é o desenho desta seção: a autenticação vive na camada de aplicação do backend, não acoplada ao Traefik, e o RPC segue sem TLS (L-08).
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
detalhadas em `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`.
Desse documento, já têm implementação (mesmo que parcial, com limitações
conhecidas): criptografia de colunas (§6), geocélula do mapa (§1, RF10),
onboarding e consentimento (§2, RF02) e a metade central→dispositivo da
sincronização (§5, RF15 — pull incremental; a leitura fica do lado do ACS,
não há geração de mudança do lado do paciente ainda). Lembretes locais
(§3.1, RF06) também têm implementação no app do paciente. Ainda **não**
implementados de ponta a ponta: push segmentado (§3.2, RF14 — provado no emulador Android em 2026-09-30, com Gorush; faltam iOS/APNs, aparelho físico e hospedar o Gorush fora do Compose local) e geofencing (§4, RF12 — só o contrato de dados
`arrivalMethod` foi desenhado, sem o serviço de geofence em primeiro plano):

* **Criptografia de colunas no PostgreSQL (RNF03/INV-04, §6 — implementada):**
  decidido usar criptografia de aplicação (AES-256-GCM em Dart, na camada de
  repositório, via `package:cryptography` ^2.7.0 — `backend/sinalacs_server/lib/src/infrastructure/crypto/health_data_cipher.dart`),
  não `pgcrypto` em SQL — evita que o dado de saúde em texto claro passe pelo
  `serverpod_query_log` antes de virar ciphertext. A chave (`HEALTH_DATA_ENCRYPTION_KEY`,
  hex de 64 caracteres) segue o mesmo padrão de segredo por variável de
  ambiente já usado para `JWT_SECRET`/`AUDIT_CHAIN_SECRET` — gerada por
  `scripts/dev/bootstrap_env.sh`, opcional em `development` (cai num valor
  público conhecido) e obrigatória fora dele —, sem introduzir um KMS externo
  nesta fase.
* **Push segmentado (RF14):** o envio é feito por **Gorush**, servidor de
  push open-source em Go, auto-hospedado no Docker Compose ao lado do backend
  (revisão de 2026-09-29, no lugar de integrar o Firebase). O app captura o
  token nativo (FCM no Android, APNs no iOS) atrás de `PushTokenSource` e o
  registra em `push_tokens` (PostgreSQL); a segmentação é uma consulta SQL
  restrita a quem consentiu (`segmentedPush`); o backend entrega a lista de
  tokens ao Gorush, que fala com o FCM/APNs. O app do paciente adota
  `flutter_riverpod` **somente** na captura e no registro do token
  (`pushTokenSourceProvider`); o resto da injeção segue por `InheritedWidget`. O Gorush precisa de credencial FCM (Android, já usada no teste) e chave
  APNs (iOS, ainda inexistente): a pendência é hospedar o Gorush e provisionar a
  chave APNs — decisão de infra, não de código.
* **Geofencing (RF12):** rejeitado rastreamento contínuo em segundo plano do
  ACS; adotado geofence único atrelado a uma visita ativa, com serviço em
  primeiro plano e notificação persistente, para evitar a política mais
  restritiva de "background location" da Play Store.

> **Traefik → backend com mTLS e fork pinado do Serverpod (2026-10-27, #90):** o backend exige certificado de cliente assinado pela CA de desenvolvimento do RPC na 8080 interna (recusa no handshake; `API_TLS_CLIENT_CA_PATH` obrigatória junto com `API_TLS_CERT_PATH`/`API_TLS_KEY_PATH`, TLS de mão única deixou de ser configuração válida) e o Traefik apresenta a folha `traefik-client.crt` pelo `serversTransport.certificates`. **Decisão de arquitetura, revertendo o "sem fork" da #78:** o Serverpod é consumido por um fork pinado por SHA (`hbgit/serverpod`, `dependency_overrides` em `backend/pubspec.yaml`, patch versionado em `backend/patches/`). *Motivo:* bloqueio upstream comprovado — `Server.start` chama `RelicApp.serve` fixo no 3.4.13, no 4.0.4 e no 4.1.0-rc.1; o `relic_io` não expõe `requestClientCertificate`; e o `HttpServer.bindSecure` do SDK não expõe `requireClientCertificate` (com `request` sozinho o handshake completa sem certificado, medido). O patch é um gancho genérico (`apiServerAdapterFactory`), sem semântica de mTLS, proposto upstream contra o `main`. *Critério de saída:* remover o `dependency_overrides` e voltar ao pub.dev quando uma versão oficial expuser o gancho ou recusar no handshake por configuração; o Grupo E de `scripts/qa/tls_invariants.sh` é a prova de equivalência. *Custo de upgrade:* todo upgrade do Serverpod, em especial para 4.x, começa pelo rebase do patch no fork e pela troca do SHA. Fora do escopo e ainda em texto claro na stack local: Postgres, Gorush, 8082/8083 e o painel 8081.

> **Broker com mTLS (2026-10-02):** `require_certificate true`; certificado de cliente por usuário MQTT (`backend`, `acs-area-12`), emitido pela CA de desenvolvimento pelo `mosquitto-init`; senha e ACL mantidos (sem `use_identity_as_username`); prova de recusa em `scripts/qa/mtls_invariants.sh`. Produção exige provisionamento por aparelho (aberto). *Nota superada pela #94 (2026-10-27): ver a entrada abaixo; o `use_identity_as_username` e a ausência de senha valem agora para o aparelho.*

> **Certificado de cliente por aparelho (2026-10-27, #94):** cada aparelho do ACS passa a ter o próprio certificado de cliente MQTT, no lugar do certificado compartilhado por usuário. **Decisão I1-C:** o par EC P-256 é gerado em Dart no app do ACS; a chave privada existe em claro só na RAM do processo durante o TLS; em repouso vive apenas no `flutter_secure_storage` (embrulhada pelo Keystore, `encryptedSharedPreferences: true`). A alternativa A, um túnel TLS nativo com a chave no TEE, fica registrada como evolução (endurecimento futuro), não como parte da #94. **Dependência nova:** `basic_utils` ^5.8.2, **só no app do ACS** e **só** para o par EC e o CSR; ela não assina certificados e não gera CRL. A assinatura é do backend, pelo CLI `openssl`, sem pacote Dart novo. No broker, `use_identity_as_username` e **sem senha** (a identidade é o CN do certificado), com lista de revogação (CRL) e um sidecar que a recarrega. **Limite:** entregue na stack local; a PKI de produção é o item 6 do ponto de decisão, aberto na issue #118 (a alternativa A é a #116).

> **App do paciente (C-04, #127):** `url_launcher` ^6.3.0, mesma versão e mesmo uso do ACS, só para o botão "Ligar 192" abrir o discador com `tel:192` (`ACTION_DIAL`, sem `CALL_PHONE`).

> **App do paciente (#136):** `flutter_secure_storage` ^9.2.2, mesma versão e mesmas opções do ACS (`encryptedSharedPreferences: true`), só para guardar a chave raw do banco SQLCipher local; `sqflite_sqlcipher` já estava declarado e passa a ser usado. **Nota:** o `EncryptedSharedPreferences` depende do `androidx.security:security-crypto`, descontinuado pelo Google. A migração (a linha 10 do `flutter_secure_storage` abandona esse modo) deve ser feita **no ACS e no paciente juntos**, com teste de leitura da chave antiga; fica fora da #136.
