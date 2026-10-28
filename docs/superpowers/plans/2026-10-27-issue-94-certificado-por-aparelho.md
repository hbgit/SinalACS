# Issue #94 — Certificado de cliente MQTT por aparelho — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans tarefa a tarefa. Os passos usam checkbox (`- [ ]`). **Decisão do dono registrada em 2026-10-27: os seis itens do "Ponto de decisão" foram respondidos (1–5 aprovados, com condições; 6 é posição inicial, não decisão) e as cinco lacunas da revisão viraram passos nas tarefas** — nenhuma condição é opcional. Entre a Task 4 (broker) e a Task 5 (app) o app do ACS fica sem conexão ao broker dentro do branch; é esperado e está anotado nas duas tarefas.

**Objetivo:** cada instalação do app do ACS gera o próprio par de chaves, manda um CSR ao backend autenticado pela sessão, recebe um certificado curto amarrado ao `deviceId` e à microárea, e conecta ao broker com ele; a limpeza remota da #81 (e a desativação/troca de microárea da #43) revoga o certificado por CRL, o broker recarrega a CRL sem reiniciar, a sessão aberta do aparelho revogado é derrubada e a reconexão é recusada; o certificado compartilhado `acs-area-12` e a senha compilada `SINALACS_MQTT_PASSWORD` saem do APK.

**Arquitetura:** o `dart:io` só aceita a chave privada em bytes (`SecurityContext.usePrivateKeyBytes`) e o `mqtt_client` 10.5.1 abre o socket por `SecureSocket.connect(context:)` sem ponto de injeção, logo a chave fica em RAM durante o TLS: ela nasce em Dart (EC P-256, `basic_utils`), vive em repouso só no `flutter_secure_storage` (AES embrulhado pelo Android Keystore, o mesmo mecanismo da chave do SQLCipher) e nunca entra em asset, APK, git ou rede (o CSR leva só a pública). O backend assina com uma **CA de aparelhos de desenvolvimento** emitida pelo `mosquitto-init` e lida pelo `openssl` da própria imagem (sem dependência X.509 nova no servidor), grava `device_certificates`, revoga em transação junto com o pedido de wipe/desativação/troca de microárea e publica a CRL por escrita atômica num volume compartilhado; um sidecar no namespace de pid do broker manda `SIGHUP` quando a CRL muda (medido: é o único canal de recarga do Mosquitto 2.1.2). O broker passa a `use_identity_as_username`: a ACL é derivada do CN do certificado (`pattern read sinalacs/v1/microareas/%u/alerts`), a senha deixa de existir, e o `deviceId` vai no SAN e na serial para a revogação.

**Tecnologias:** Flutter/Dart (`basic_utils` ^5.8.2 → `pointycastle` 4), `flutter_secure_storage` (já na stack), `mqtt_client` 10.5.1, Serverpod 3.4.13 (fork pinado, #90), OpenSSL 3 (CLI no container do backend e no `mosquitto-init`), Eclipse Mosquitto 2.1.2 (`crlfile`, `use_identity_as_username`, ACL `pattern`), Docker Compose (`pid: "service:mosquitto"`), bash (`scripts/qa`), emulador Android `emulator-5554`.

**Spec:** issue #94 (`gh issue view 94`), continuação da #81 (D8; `PROGRESS.md:1721`, plano `docs/superpowers/plans/2026-10-17-*issue-81*`). Auditoria do PRD: linha STRIDE-S (`docs/auditoria-prd/2026-10-15-lacunas-prd.md:82`), R3 (`:215`), item 7 do backlog (`:234`). `spec/stack.md:78` ("Broker com mTLS"). Fora do escopo (a issue é explícita): mTLS Traefik ↔ backend (#90, entregue) e iOS.

## Restrições globais

- Português em código, comentários, mensagens, commits e documentação. Sem atribuição de IA em commits e PR (`CLAUDE.md`).
- **Nenhuma chave privada no git nem em asset:** tudo que é chave nasce em `infra/docker/mosquitto/runtime/` (gitignored, `.gitignore:28`) ou no Keystore do aparelho. `apps/acs/assets/certs/` passa a conter **só** `dev_ca.crt` e `dev_rpc_ca.crt`.
- **Nenhuma dependência no `pubspec.yaml` antes da entrada aprovada em `spec/stack.md`** (Task 1 escreve a entrada e só então adiciona `basic_utils`).
- **Não quebrar a #81:** `RemoteWipeCoordinator`, `DeviceEraser`, `WipeJournal`, `VisitDatabase.destroy` e `scripts/qa/acs_remote_wipe_e2e.sh` continuam valendo; a revogação é um passo **a mais** na mesma transação de `orderWipe`, e o e2e da #81 só ganha asserções.
- **Sondas negativas sempre com controle positivo antes** (desenho de `mtls_invariants.sh` e `tls_invariants.sh`): "recusado" com a stack no chão não conta; código 2/4 nunca é recusa.
- **Escrita da CRL sempre atômica** (arquivo temporário no mesmo diretório + `rename`) e **validada contra a CA** (`openssl crl -in <tmp> -CAfile ca.crt -noout`, assinatura e não só sintaxe — no publisher e no sidecar) antes de qualquer `SIGHUP`: medido em 2026-10-27 que o Mosquitto 2.1.2 **termina** ("mosquitto version 2.1.2 terminating") ao recarregar uma `crlfile` vazia ou inválida.
- **A CRL nunca pode expirar:** `nextUpdate` = 30 dias, republicada no boot do backend, a cada revogação e a cada 24 h; o Grupo H de `mtls_invariants.sh` acusa quando faltam menos de 7 dias. Uma CRL vencida faz o OpenSSL recusar **todos** os clientes do broker, backend incluído.
- Testes de integração do backend: `dart test -j 1`. Nenhum dado real. Testes que chamam `openssl` falham com mensagem clara se o binário não existe (o runner `ubuntu-24.04` o tem).
- O `deviceId` **nunca** vem do cliente na emissão: é `AuthenticatedUser.deviceId`, a claim `device_id` do JWT (`development_auth_service.dart:52`).
- A triagem e o despacho de alertas não mudam. INV-03 intocado: nada aqui chama `acknowledge`/`resolve`.

## Diagnóstico e reprodução (feito em 2026-10-27, `develop` em `5706fee`)

Estado atual, medido com a stack de desenvolvimento de pé e o APK de debug de `apps/acs/build/app/outputs/flutter-apk/app-debug.apk`: o certificado e a chave de cliente são extraíveis do APK com `unzip`, são **idênticos** a `runtime/certs/acs-area-12.{crt,key}` (`cmp`), e um `mosquitto_pub`/`mosquitto_sub` qualquer conecta ao broker como o ACS da microárea: publica no tópico de ACK e assina o tópico de alertas da microárea do seed.

```bash
# Comando-evidência (vira a base do caso D de scripts/qa/mtls_invariants.sh, Task 4).
# Roda no host, com a stack de pé e o .env carregado (a senha também é compartilhada:
# é a constante de compilação SINALACS_MQTT_PASSWORD, backend_config.dart:66).
set -a; source .env; set +a
apk=apps/acs/build/app/outputs/flutter-apk/app-debug.apk; tmp="$(mktemp -d)"
for f in acs_client.crt acs_client.key dev_ca.crt; do
  unzip -p "$apk" "assets/flutter_assets/assets/certs/$f" > "$tmp/$f"; done; chmod 644 "$tmp"/*
openssl x509 -in "$tmp/acs_client.crt" -noout -subject      # subject=CN=acs-area-12
MQTT_PW="$MQTT_ACS_PASSWORD" docker run --rm --network host -v "$tmp:/f:ro" -e MQTT_PW \
  eclipse-mosquitto:2 sh -c 'mosquitto_pub -h localhost -p 8883 --cafile /f/dev_ca.crt \
    --cert /f/acs_client.crt --key /f/acs_client.key -u acs-area-12 -P "$MQTT_PW" \
    -t sinalacs/v1/alerts/00000000-0000-4000-8000-00000000dead/acks -m "{\"forjado\":true}" -d'
# Medido: "received CONNACK (0)" e "sending PUBLISH (... 'sinalacs/v1/alerts/.../acks')", rc=0.
# O mesmo par com mosquitto_sub em sinalacs/v1/microareas/00000000-0000-4000-8000-000000000003/alerts
# recebe SUBACK. (Atenção ao `sh -c '...'` com aspas simples: a senha é expandida DENTRO do container;
# com aspas duplas no host ela vai vazia e o broker devolve CONNACK 5, que parece "recusa" e não é.)
```

Consequência: o servidor não tem como cortar **um** aparelho — a identidade no broker é a da microárea inteira, e a única revogação possível hoje é trocar `MQTT_ACS_PASSWORD` e recompilar o APK de todos.

## Investigações que decidem o desenho (feitas em 2026-10-27)

### I1 — Chave no Keystore vs. TLS no Dart

Medido no SDK do Flutter instalado (`dart-sdk/lib/io/security_context.dart`) e em `mqtt_client-10.5.1/lib/src/connectionhandling/server/mqtt_client_mqtt_server_secure_connection.dart:36`:

- `SecurityContext` só tem `usePrivateKey(String file)` / `usePrivateKeyBytes(List<int>)`: a chave entra como PEM/DER em memória. Não há provedor, handle opaco ou callback de assinatura; o TLS do Dart é o BoringSSL embutido na VM.
- O `mqtt_client` constrói o socket com `SecureSocket.connect(server, port, onBadCertificate:, context:)`. Não aceita um `Socket` pronto. Logo **uma chave não exportável do Android Keystore não pode alimentar o TLS do app como ele existe**.

| Alternativa | "A privada nunca sai" | Custo | Veredito |
|---|---|---|---|
| **A. Túnel TLS nativo** (Kotlin: `SSLSocket` com `KeyManager` do AndroidKeyStore, escutando em `127.0.0.1:<porta>`; o `mqtt_client` conecta em texto claro no loopback) | Sim: a chave fica no Keystore/TEE | ~300 linhas de Kotlin, verificação de hostname à mão, **porta de loopback aberta a qualquer app do aparelho** (precisa de preâmbulo secreto por sessão), prova só no emulador, componente de arquitetura novo fora de `spec/stack.md` | Caminho de endurecimento futuro; não agora |
| B. Cliente MQTT nativo (Paho Android/HiveMQ) atrás de platform channel | Sim | Substitui `mqtt_client`, reescreve sessão persistente, reconexão, fila de alertas; fora de `spec/stack.md` | Rejeitado |
| **C. Par gerado em Dart; privada em repouso só no `flutter_secure_storage`** (AES-256 embrulhado por chave do Keystore, sem autenticação do usuário para a reconexão em segundo plano funcionar); decifrada para a RAM só no `SecurityContext` | Em repouso, no APK, no backup (`allowBackup=false`) e na rede: sim (o CSR leva só a pública). Contra aparelho com root/depurador lendo a RAM: **não** — o mesmo risco residual que a chave do SQLCipher e o token de envio diferido já aceitam por desenho (`apps/CLAUDE.md`, "stay unbound by design") | Nenhuma dependência de plataforma nova; `basic_utils` para o par EC e o CSR | **Recomendado** |

Recomendação: **C agora, A registrada como evolução** no `PROGRESS.md`. O texto da issue ("a privada nunca sai") passa a ser lido como "nunca sai do aparelho e nunca existe em claro em disco", e isso fica escrito no `spec/stack.md` (Task 1) para ninguém ler como descuido.

### I2 — Spike da CRL no Mosquitto 2.1.2 (imagem `eclipse-mosquitto:2`, digest de 2026-10-27)

Broker descartável na porta 18883 com `require_certificate true`, `crlfile`, CA própria e dois aparelhos A e B; sessão longa de A com `mosquitto_sub -i acs-dev-A`. Roteiro completo em `scripts/qa/spikes/mosquitto_crl_spike.sh` (Task 4 o versiona a partir do rascunho usado hoje). Resultados:

| Passo | Resultado medido |
|---|---|
| CRL regravada em disco (revoga A), **sem** sinal | A continua aceito (rc 0). A CRL só é lida na carga. |
| `kill -HUP` no broker | "Reloading config."; A recusado no handshake (`mosquitto_pub` rc 7, "connection lost"); B aceito (rc 0). |
| Sessão longa de A depois do `SIGHUP` | **Viva**, e continua recebendo o que B publica. A CRL só vale no próximo handshake. |
| Takeover: qualquer cliente conecta com o **mesmo client id** de A | A sessão de A é derrubada na hora (`mosquitto_sub` sai com 7; "Client acs-dev-A disconnected"). É semântica MQTT, não precisa de plugin. |
| A tenta reconectar depois do takeover | Recusado pela CRL (rc 7). |
| Takeover **antes** da recarga (Task 7, e2e no emulador) | O app reconecta com o cert revogado; medido no e2e: derrubado 32 ms depois de `revokedAt`, reconectou em porta nova, "CRL recarregada" 1,2 s depois — e ficou conectado. A derrubada só vale **depois** do `SIGHUP`: o sidecar grava `crl.loaded` (sha256 da `crl.pem` sinalizada) e o backend espera esse marcador (≤ 15 s, a cada 250 ms) antes do takeover (Task 7a). |
| `crlfile` vazia/inválida + `SIGHUP` | `OpenSSL Error ... no crl found` e **"mosquitto version 2.1.2 terminating"**: o broker sai. |
| Canais de recarga | `mosquitto_ctrl broker` só tem `listPlugins`/`listListeners`; `mosquitto_signal` é um invólucro de `kill`. **Só `SIGHUP`.** |
| `use_identity_as_username true` + `password_file` | Senha errada aceita, `-u outro` ignorado: o username passa a ser o CN e a senha deixa de contar. |
| ACL `pattern read sinalacs/v1/microareas/%u/alerts` com CN = UUID da microárea | Aparelho lê a própria microárea; `PUBLISH` no tópico de alertas é negado ("Denied PUBLISH"); `PUBLISH` em `sinalacs/v1/alerts/+/acks` aceito. |

Desenho que decorre: (1) revogar = gravar `revokedAt` + republicar a CRL (tmp + `rename`) + `SIGHUP` pelo sidecar `mosquitto-crl-reload` (`pid: "service:mosquitto"`, `user: root`, laço de 2 s sobre inode/mtime de `crl.pem`, `openssl crl -noout` antes do `kill -HUP`); (2) derrubar a sessão ativa = o backend conecta como `backend` com o **client id do aparelho** (`sinalacs-acs-<acsId>-<deviceId>`, clean session) e desconecta — isso também descarta a fila QoS 1 persistente daquele aparelho; (3) impedir a reconexão = a CRL. **Todas as folhas de cliente** (backend, ferramentas de QA e aparelhos) passam a ser emitidas pela **mesma CA de aparelhos**, porque o OpenSSL com `X509_V_FLAG_CRL_CHECK` exige uma CRL do emissor da folha: uma folha do backend assinada por outra CA sem CRL seria recusada com "unable to get certificate CRL".

### I3 — Dependência X.509/CSR em Dart (pub.dev em 2026-10-27)

| Pacote | Versão / publicação | Pontos | Gera CSR | Assina com CA alheia | CRL | Dependências | Observação |
|---|---|---|---|---|---|---|---|
| `pointycastle` | 4.0.0 / 2025-02-19 | 140/160, 418 likes | Não (só primitivas) | Não | Não | `collection`, `convert` | Exigiria codificar o CSR em ASN.1 à mão |
| `asn1lib` | 1.6.7 / 2026-10-26 | 150/160 | Não (só ASN.1) | — | — | nenhuma | Idem, junto com `pointycastle` |
| **`basic_utils`** | 5.8.2 / 2025-02-23 | 140/160, 381 likes | **Sim**: `X509Utils.generateEccCsrPem(attributes, priv, pub, {san})`, `CryptoUtils.generateEcKeyPair(curve: 'prime256v1')` | **Não** (só `generateSelfSignedCertificate`) | Só parse (`crlDataFromPem`) | `pointycastle`, `http`, `logging`, `json_annotation`, `archive` (tudo Dart puro) | API de uma chamada, código já exercitado por muita gente |
| `x509` | 0.2.4+3 / 2024-09-20 | 160/160, 13 likes | Não (parse) | Não | Não | `asn1lib`, `quiver`, `crypto_keys` | Nicho, sem geração |
| `cryptography` | 2.9.0 (já no backend) | 130/160 | Não | Não | Não | — | Sem ASN.1 |

Recomendação: **app: `basic_utils` ^5.8.2** (par EC P-256 + CSR em duas chamadas; o custo é o peso transitivo de `archive`/`http`, aceitável — nenhuma é nativa). **Backend: nenhuma dependência Dart nova**: assinar o CSR e gerar a CRL por `openssl` (`Process.run`) na imagem Alpine do backend (`apk add openssl` ao lado de `curl`, `Dockerfile:8`), porque nenhum pacote Dart maduro assina com CA alheia nem gera CRL, e o `openssl` já é o que todos os `*-init` do Compose usam. Em produção a assinatura sai do backend de qualquer forma (item 5).

## Ponto de decisão — respondido pelo dono em 2026-10-27

1. **Dependência e entrada no `spec/stack.md` — APROVADO.** `basic_utils` ^5.8.2 **só** no app do ACS e **só** para par EC e CSR; backend por `openssl` CLI, sem pacote Dart novo. Condição: a entrada do `spec/stack.md` diz explicitamente que o pacote **não assina nem gera CRL**, para ninguém expandir o uso depois → Task 1.
2. **Desenho Keystore/TLS, alternativa C — SIM, explicitamente.** A I1 prova que a alternativa A exige TLS nativo e uma porta de loopback aberta no aparelho, o que troca um risco por outro. A leitura "a privada nunca sai do aparelho e nunca existe em claro em disco" é defensável desde que escrita no `spec/stack.md` e no `PROGRESS.md` com a alternativa A como endurecimento futuro. Condição: **abrir a issue da alternativa A agora** (Task 8), para o adiamento não se perder como aconteceu com o D8. Medido depois da revisão: as três lojas do app já usam `AndroidOptions(encryptedSharedPreferences: true)` (`database_key_store.dart:46`, `secure_session_token_store.dart:10`, `secure_upload_token_store.dart:13`); a loja do certificado usa o **mesmo** modo, guardado por teste (Task 5). O `basic_utils` semeia o `FortunaRandom` com 32 bytes de `Random.secure()` (`CryptoUtils.getSecureRandom`, 5.8.2) — revisado em código; a Task 1 deixa isso em comentário ao lado do `pubspec`.
3. **Broker — APROVADO.** `use_identity_as_username true`, **fim da senha MQTT** (`MQTT_ACS_PASSWORD`, `MQTT_BACKEND_PASSWORD`, `SINALACS_MQTT_PASSWORD`, `password_file`, guarda Gradle `allowMissingMqttPassword` — todos removidos), identidade = CN, ACL por `pattern %u` = UUID da microárea, CRL com sidecar, derrubada por takeover. Risco residual entre irmãos da mesma microárea aceito: exige conhecer o `deviceId` do outro, e a reconexão mais a reserva HTTP da #80 limitam o dano. Condições: **o sidecar verifica a assinatura da CRL contra a CA** (`openssl crl -CAfile ca.crt -noout`; só sintaxe deixaria uma CRL de outra CA passar e o broker recusar todo mundo, backend incluído) → Task 4; e **`kick` de todos os aparelhos do ACS também na troca de microárea** → item 5 e Task 3.
4. **Validade e renovação — APROVADO, com ressalva de calibração.** 30 dias, renovação a partir de 10 restantes, `notBefore` recuado 1 h, 5 emissões por hora, CRL 30 dias republicada no boot, na revogação e a cada 24 h: tudo fica. A janela de 20 dias com rede é apertada em áreas de Roraima; como `DEVICE_CERT_DAYS` já é variável, 30 é o padrão de **dev** e o `PROGRESS.md` registra que produção decide o valor com dados de conectividade (Task 8). O comportamento offline (feed transitório, reserva HTTP, reemissão automática) é o que importa.
5. **Gatilhos além do wipe — SIM aos dois.** Desativação e troca de microárea revogam, e a troca de microárea **deve cortar o MQTT até a reemissão**: é LGPD, não só segurança, porque o aparelho leria alertas de um território que não é mais dele. Pela tabela I2 a CRL só vale no próximo handshake, logo o `kick` de todos os aparelhos ativos do ACS é obrigatório em `setAcsMicroArea` tanto quanto em `setAcsActive(false)` → Task 3.
6. **PKI de produção — posição inicial, não decisão.** (a) A chave da CA de aparelhos não vive no processo do backend em produção: KMS/HSM do provedor ou serviço de assinatura separado; se a primeira versão precisar de arquivo em volume, isso tem prazo e dono. (b) Uma CA por ambiente; intermediária por UBS só com necessidade operacional concreta. (c) Revogação de emergência por endpoint administrativo auditado, e runbook para comprometimento da CA: CA nova, sobreposição no `cafile`, reemissão progressiva pelo próprio fluxo de renovação do app. (d) Rotação com janela de sobreposição, duas CAs no `cafile`, cada uma com CRL — o desenho atual suporta. (e) Arquivo + `SIGHUP` enquanto o broker for este Mosquitto; broker gerenciado reavalia. (f) `deviceId` basta agora; Play Integrity é endurecimento posterior, junto com a alternativa A. (g) O dono do runbook é quem opera a infra de produção; se essa pessoa não existe, essa é a primeira decisão. Condição: **abrir uma issue só para este item, com as sete perguntas, antes do PR** (Task 8), e a linha STRIDE-S aponta para ela.

### Lacunas apontadas na revisão do plano (2026-10-27) e onde entraram

| # | Lacuna | Correção | Tarefa |
|---|---|---|---|
| 1 | Troca de microárea revogava mas não derrubava a sessão; a CRL só vale no próximo handshake | `setAcsMicroArea` faz `kick` de todos os aparelhos ativos do ACS, igual a `setAcsActive(false)`; teste de integração com o broker de teste | Task 3 |
| 2 | `openssl` falhando depois do commit da revogação deixava o broker confiando até o timer de 24 h | `DeviceCrlPublisher` ganha nova tentativa com recuo exponencial (2 s → 5 min, sem teto de tentativas, única por vez) e o estado `pendingSince` observável; teste "falha no publish → republica sozinho depois"; a revogação continua sendo o corte duro, nunca o timer | Task 3 |
| 3 | Sidecar só validava sintaxe da CRL | `openssl crl -in crl.pem -CAfile ca.crt -noout`; mutação I ganha o caso "CRL válida de **outra** CA não é recarregada e o broker segue aceitando" | Task 4 |
| 4 | ACK sem identidade de aparelho: `pattern write sinalacs/v1/alerts/+/acks` deixa qualquer aparelho válido confirmar qualquer alerta, e o broker não repassa o CN ao backend | Não é regressão (hoje todos compartilham o certificado; ids de alerta são UUIDs). **Issue de continuação**: `%c` na ACL ou `deviceId` no payload do ACK validado contra a microárea do alerta; registrada no `PROGRESS.md` e aberta na Task 8 | Task 8 |
| 5 | Modo do `flutter_secure_storage` e semente do gerador EC não conferidos | Conferidos (item 2 acima); teste da loja fixa `encryptedSharedPreferences: true`; comentário no `pubspec` cita `CryptoUtils.getSecureRandom` | Tasks 1 e 5 |

## Mapa de arquivos

- **Backend (`backend/sinalacs_server/`):**
  - Criar `lib/src/models/device_certificate.spy.yaml` (tabela `device_certificates`), `lib/src/models/enums/device_cert_revocation_reason.spy.yaml`, `lib/src/models/api/device_certificate_issue_result.spy.yaml`; regenerar `lib/src/generated/` e a migração (`serverpod create-migration` + `./scripts/dev/append_audit_append_only.sh`).
  - Criar `lib/src/config/device_ca_config.dart` (variáveis `DEVICE_CA_CERT_PATH`, `DEVICE_CA_KEY_PATH`, `DEVICE_CRL_PATH`, `DEVICE_CERT_DAYS`, `DEVICE_CRL_DAYS`).
  - Criar `lib/src/infrastructure/pki/openssl_device_ca.dart` (assina CSR, gera CRL, valida CSR — tudo por `openssl`), `lib/src/infrastructure/pki/atomic_file.dart` (tmp + `rename`).
  - Criar `lib/src/application/devices/device_certificate_service.dart` (+ `DeviceCertificateStore`), `lib/src/infrastructure/database/orm_device_certificate_store.dart`, `lib/src/infrastructure/mqtt/mqtt_session_kicker.dart`, `lib/src/application/devices/device_crl_publisher.dart`.
  - Modificar `lib/src/endpoints/devices_endpoint.dart` (novo `issueCertificate`), `lib/src/runtime/alert_runtime.dart` (fábricas + republicação periódica), `lib/src/infrastructure/database/orm_device_wipe_store.dart:84-125` (terceira tabela no laço de revogação), `lib/src/application/devices/device_wipe_service.dart:121-165` (CRL + kick depois do `created`), `lib/src/application/admin/admin_account_service.dart:305-420` (`setAcsMicroArea`, `setAcsActive`), `Dockerfile:8` (`openssl`).
  - Testes: `test/unit/openssl_device_ca_test.dart`, `test/unit/atomic_file_test.dart`, `test/integration/device_certificate_service_test.dart`, `test/integration/device_certificate_endpoint_test.dart`, `test/integration/device_wipe_store_test.dart` (ampliado), `test/integration/admin_account_revocation_test.dart`, `test/unit/mqtt_session_kicker_test.dart`.
- **Broker e Compose:** `infra/docker/mosquitto/init.sh` (CA de aparelhos, CRL inicial, folhas `backend` e `qa-tools`, sem `acs-area-12`, sem `passwordfile`), `mosquitto.conf`, `aclfile`, novo `infra/docker/mosquitto/crl_reload.sh` (sidecar), `docker-compose.yml` (serviço `mosquitto-crl-reload`, montagens `runtime/devices`, variáveis do backend, remoção das senhas), `.env.example`, `scripts/dev/bootstrap_env.sh` (+ `_test.sh`).
- **App do ACS (`apps/acs/`):** `pubspec.yaml`; criar `lib/core/security/device_certificate_store.dart` (interface + `SecureStorageDeviceCertificateStore` + `InMemoryDeviceCertificateStore`), `lib/core/services/device_certificate_enroller.dart`, `lib/core/services/device_csr.dart`; modificar `lib/core/services/alert_feed.dart:118-165`, `lib/core/network/backend_client.dart` (`AcsBackend.issueDeviceCertificate`), `lib/core/network/backend_config.dart:43-82` (remover username/senha/assets de cliente), `lib/app/app.dart` (`DeviceEraser` apaga o certificado), `lib/main.dart` (liga a loja real), `android/app/build.gradle.kts:119-175,222-233`, `tool/live_check.dart:115,210`.
  - Testes: `test/device_csr_test.dart`, `test/device_certificate_enroller_test.dart`, `test/alert_feed_enrollment_test.dart`, `test/backend_client_test.dart` (ampliado), `test/device_wipe_test.dart` (ampliado), `test/session_store_wiring_test.dart` (ampliado), `integration_test/device_cert_e2e.dart`.
- **Scripts e QA:** `scripts/qa/mtls_invariants.sh` (reescrito, Grupos A–H) + novo `scripts/qa/mtls_invariants_test.sh` (estrutura, hermético), `scripts/qa/spikes/mosquitto_crl_spike.sh`, novo `scripts/qa/acs_apk_no_client_key.sh`, novo `scripts/qa/acs_device_cert_e2e.sh` (+ `_test.sh`), `scripts/qa/acs_remote_wipe_e2e.sh` (asserções novas), `scripts/dev/sync_dev_ca.sh` (+ `_test.sh`), `scripts/dev/run_acs.sh`, `scripts/qa/run_android_e2e.sh`, `scripts/qa/e2e.sh`, `scripts/qa/mqtt_resiliencia_e2e.sh`, `scripts/qa/measure_latency.dart`, `scripts/qa/dev_key_permissions_test.sh`, `video/rpc_demo/watch_mqtt.sh`, `.github/workflows/ci.yml` (só onde passa `SINALACS_MQTT_PASSWORD`).
- **Documentação:** `spec/stack.md`, `spec/lgpd_data_audit.md` (tabela nova), `PROGRESS.md`, `docs/auditoria-prd/2026-10-15-lacunas-prd.md`, `CLAUDE.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`, `README.md`, `.claude/skills/validacao-e2e/SKILL.md`.

## Review Focus

Entradas que a issue implica mas nenhum critério de aceite exercita; cada linha ganhou um teste na tarefa dona:

1. **CRL vencida derruba o broker inteiro.** Esperado: nunca acontece — republicação periódica e Grupo H (`nextUpdate` ≥ 7 dias). → Task 3 (timer de 24 h, teste do publisher) e Task 4 (Grupo H).
2. **CRL inválida no `SIGHUP` termina o Mosquitto.** Esperado: o sidecar só sinaliza o que o `openssl crl` lê, e o publisher nunca deixa um arquivo parcial no caminho final. → Task 3 (`atomic_file_test`), Task 4 (sidecar valida; mutação: gravar lixo em `crl.pem` e provar que o broker segue de pé).
3. **Aparelho semanas sem rede com certificado vencido.** Esperado: feed falha como transitório, reserva HTTP segue, reemissão na volta da rede sem intervenção do ACS. → Task 5 (`device_certificate_enroller_test`: "vencido e offline" e "volta da rede").
4. **Relógio do aparelho adiantado/atrasado.** Esperado: `notBefore` = emissão − 1 h, e o app compara validade com o relógio do **servidor** (`notAfter` devolvido na emissão, não só o do PEM). → Task 2 (teste do `-not_before`/`-startdate`), Task 5 (teste com relógio 30 min adiantado).
5. **Troca de microárea do ACS (#43) com certificado vivo do CN antigo.** Esperado: o certificado antigo é revogado na mesma transação e o aparelho reemite com o CN novo. → Task 3 (`admin_account_revocation_test`), Task 5 (enroller reemite quando `microAreaId` da sessão ≠ CN guardado).
6. **Dois aparelhos do mesmo ACS com o client id antigo (`sinalacs-acs-<acsId>`) se derrubam mutuamente.** Esperado: client id por aparelho. → Task 5 (`alert_feed_enrollment_test`: client id contém `deviceId`), Task 7 (dois aparelhos conectados ao mesmo tempo).
7. **Revogação gravada no banco com a CRL não publicada (openssl/disco falham depois do commit).** Esperado: o publisher insiste sozinho com recuo até publicar; nunca espera o timer de 24 h. → Task 3 (`device_crl_publisher_test`: "falha no publish → republica sozinho depois").
8. **CRL válida de outra CA chega ao arquivo.** Esperado: nem o publisher nem o sidecar a aceitam; o broker continua aceitando backend e aparelhos. → Task 3 (validação com `-CAfile`), Task 4 (mutação I-ii).
9. **Takeover antes de o broker recarregar a CRL.** Esperado: o aparelho revogado com reconexão automática NÃO volta — o backend só derruba depois de `crl.loaded` bater com o sha256 da CRL publicada (ou de uma mais nova); prazo de 15 s esgotado → derruba assim mesmo e loga aviso sem serial; CRL em recuo → derruba na hora. → Task 7a (`device_revocation_effects_test`: marcador antes do kick, atrasado 3 s, nunca bate → 15 s com aviso, publish em recuo → imediato; `mtls_invariants.sh` Grupo F com laço `while true` e zero conexões de A em 10 s depois do takeover; Grupo I: CRL recusada não muda o marcador).
10. **Recusa TLS na reconexão automática do mqtt_client escapava como erro não tratado; medido no e2e.** Esperado: a `TlsException`/`SocketException` que o `mqtt_client` 10.5.1 deixa escapar (o `done` do `SecureSocket` e o laço `autoReconnect`) é capturada pela zona de `MqttSecureClient.connect` e vira queda `MqttDropReason.tlsRefused` (sem `autoReconnect`, sem nova tentativa); o feed descarta o certificado (`DeviceCertificateEnroller.discard`), consulta a limpeza remota da #81 e avisa o painel por `AlertFeed.onFailure` como `certificateUnavailable` transitório, e a retentativa do painel reemite; recusa no primeiro `connect` (`MqttTlsRefused`) tem o mesmo tratamento. → Task 7b (`mqtt_tls_refused_test` com broker TLS real em `dart:io`, `device_certificate_enroller_test`: discard, `alert_feed_enrollment_test`: queda e primeiro connect, `login_flow_test`: `onFailure` no painel).

---

### Task 1: Entrada no `spec/stack.md`, dependência `basic_utils` e CSR verificado pelo OpenSSL

**Files:**
- Modify: `spec/stack.md` (depois da nota de 2026-10-02 em `:78`)
- Modify: `apps/acs/pubspec.yaml` (`dependencies:`), `apps/acs/pubspec.lock`
- Create: `apps/acs/lib/core/services/device_csr.dart`
- Test: `apps/acs/test/device_csr_test.dart`

**Interfaces:**
- Produces: `class DeviceKeyPair { final String privateKeyPem; final String publicKeyPem; }`, `DeviceKeyPair generateDeviceKeyPair()` (EC P-256, `CryptoUtils.generateEcKeyPair(curve: 'prime256v1')`, PEM por `CryptoUtils.encodeEcPrivateKeyToPem`/`encodeEcPublicKeyToPem`), `String buildDeviceCsrPem({required DeviceKeyPair keyPair, required String microAreaId})` (CN = `microAreaId`, sem SAN: o servidor é quem põe os SANs). Tudo Dart puro, sem `dart:ui` (o `live_check` importa a árvore de `backend_client.dart`).

- [ ] **Step 1: Escrever a entrada no `spec/stack.md`** como nota datada "**Certificado de cliente por aparelho (2026-10-27, #94)**": decisão I1-C com a frase explícita "a chave privada existe em claro só na RAM do processo durante o TLS; em repouso vive apenas no `flutter_secure_storage`", a alternativa A como evolução, `basic_utils` ^5.8.2 **só no app do ACS** e **só** para par EC/CSR (não assina, não gera CRL), backend por `openssl` CLI sem pacote Dart novo, broker com `use_identity_as_username` e **sem senha**, CRL + sidecar, e o limite "entregue na stack local; PKI de produção é o item 6 do ponto de decisão". Atualizar a nota de 2026-10-02 em `:78` com "superada pela #94".

- [ ] **Step 2: Escrever o teste** `apps/acs/test/device_csr_test.dart`:

```dart
test('CSR gerado em Dart é verificado pelo openssl e leva CN = microárea', () async {
  final par = generateDeviceKeyPair();
  final csr = buildDeviceCsrPem(keyPair: par, microAreaId: '00000000-0000-4000-8000-000000000003');
  final dir = await Directory.systemTemp.createTemp('csr');
  final f = File('${dir.path}/d.csr')..writeAsStringSync(csr);
  final r = await Process.run('openssl', ['req', '-in', f.path, '-noout', '-verify', '-subject', '-pubkey']);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  expect('${r.stdout}${r.stderr}', contains('subject=CN=00000000-0000-4000-8000-000000000003'));
  expect('${r.stdout}', contains('BEGIN PUBLIC KEY'));
  expect(par.privateKeyPem, contains('BEGIN EC PRIVATE KEY'));
  expect(csr, isNot(contains('PRIVATE')));
});
test('dois pares gerados são diferentes', () { expect(generateDeviceKeyPair().privateKeyPem, isNot(generateDeviceKeyPair().privateKeyPem)); });
```

- [ ] **Step 3: Rodar e ver falhar** — `cd apps/acs && flutter test test/device_csr_test.dart` → FAIL (`device_csr.dart` não existe).
- [ ] **Step 4: Adicionar `basic_utils: ^5.8.2`** em `apps/acs/pubspec.yaml` com comentário de três linhas: a entrada do `spec/stack.md`, "só par EC e CSR: não assina nem gera CRL" e "gerador semeado com 32 bytes de `Random.secure()` (`CryptoUtils.getSecureRandom`, revisado na 5.8.2; reconferir a cada upgrade)"; `flutter pub get`. Conferir `git diff --stat apps/patient apps/admin backend` vazio.
- [ ] **Step 5: Implementar `device_csr.dart`** com as duas funções da interface.
- [ ] **Step 6: Rodar** `flutter test test/device_csr_test.dart` → PASS; `flutter analyze` limpo.
- [ ] **Step 7: Commit** — `docs(stack): entrada do certificado por aparelho (#94)` e `feat(acs): par EC e CSR do aparelho com basic_utils (#94)` (dois commits).

### Task 2: CA de aparelhos de desenvolvimento e invólucro `openssl` no backend

**Files:**
- Modify: `infra/docker/mosquitto/init.sh` (depois de `issue_client backend`, antes do `passwordfile`), `docker-compose.yml` (serviço `serverpod`: montagem `./infra/docker/mosquitto/runtime/devices:/app/devices` **rw**, variáveis `DEVICE_CA_CERT_PATH=/app/devices/ca.crt`, `DEVICE_CA_KEY_PATH=/app/devices/ca.key`, `DEVICE_CRL_PATH=/app/devices/crl.pem`, `DEVICE_CERT_DAYS=30`, `DEVICE_CRL_DAYS=30`; **`MQTT_CLIENT_CERT_PATH`/`KEY_PATH` continuam em `/app/certs/backend.*` até a Task 4** — o broker só passa a confiar na CA de aparelhos lá, e trocar antes recusaria o backend), `backend/sinalacs_server/Dockerfile:8` (`openssl`)
- Create: `backend/sinalacs_server/lib/src/config/device_ca_config.dart`, `lib/src/infrastructure/pki/openssl_device_ca.dart`, `lib/src/infrastructure/pki/atomic_file.dart`
- Test: `backend/sinalacs_server/test/unit/openssl_device_ca_test.dart`, `test/unit/atomic_file_test.dart`, `scripts/qa/dev_key_permissions_test.sh` (ampliado)

**Interfaces:**
- Produces: `class DeviceCaConfig { final String caCertPath, caKeyPath, crlPath; final int certDays, crlDays; static DeviceCaConfig? fromEnvironment(Map<String,String> env) }` (as três de caminho vêm juntas ou nenhuma, `StateError` nomeando as três; `null` = sem CA, emissão responde `AlertPermissionException('emissão de certificado indisponível neste ambiente')`).
- `class OpensslDeviceCa { OpensslDeviceCa(DeviceCaConfig cfg, {String opensslBinary = 'openssl'}); Future<CsrInfo> inspectCsr(String csrPem)` (`CsrInfo{commonName, keyAlgorithm /* 'id-ecPublicKey' */, curve /* 'prime256v1' */}`; CSR inválido ou assinatura ruim → `FormatException`); `Future<String> sign({required String csrPem, required BigInt serial, required String commonName, required List<String> sanUris, required DateTime notBefore, required DateTime notAfter})` → PEM; `Future<String> buildCrl({required List<RevokedEntry> revoked, required BigInt crlNumber, required DateTime now, required int days})` → PEM (`RevokedEntry{BigInt serial; DateTime revokedAt; DateTime notAfter; String commonName}`).
- `Future<void> writeFileAtomically(String path, String contents, {Future<void> Function(String tmpPath)? validate})` em `atomic_file.dart`: grava `<path>.tmp-<pid>-<rand>` no mesmo diretório, chama `validate`, `rename`; qualquer falha apaga o temporário e relança.

- [ ] **Step 1: Escrever `openssl_device_ca_test.dart`** (gera uma CA descartável no `setUpAll` com `openssl req -x509`, e um CSR EC com `openssl req -newkey ec`):

```dart
test('sign emite folha clientAuth com serial, CN, SANs e validade pedidos', () async {
  final pem = await ca.sign(csrPem: csr, serial: BigInt.parse('0a1b', radix: 16), commonName: microArea,
      sanUris: ['urn:sinalacs:device:dev-1', 'urn:sinalacs:acs:acs-1'],
      notBefore: DateTime.utc(2026,10,27,11), notAfter: DateTime.utc(2026,11,26,12));
  final txt = await x509Text(pem); // openssl x509 -noout -text -serial -dates
  expect(txt, contains('serial=0A1B')); expect(txt, contains('CN = $microArea'));
  expect(txt, contains('URI:urn:sinalacs:device:dev-1')); expect(txt, contains('TLS Web Client Authentication'));
  expect(txt, contains('notBefore=Oct 27 11:00:00 2026 GMT')); expect(txt, contains('CA:FALSE'));
  expect((await verify(pem, caCert)).exitCode, 0);
});
test('sign recusa CSR com CN diferente do pedido', ...);           // FormatException
test('inspectCsr identifica EC prime256v1 e recusa RSA', ...);     // CsrInfo.curve == 'prime256v1'; RSA → keyAlgorithm 'rsaEncryption'
test('inspectCsr recusa CSR com assinatura adulterada', ...);      // FormatException
test('buildCrl lista a serial revogada, com nextUpdate em now+days e assinatura válida', () async {
  final crl = await ca.buildCrl(revoked: [RevokedEntry(serial: BigInt.from(10), revokedAt: t, notAfter: t2, commonName: 'x')],
      crlNumber: BigInt.from(7), now: DateTime.utc(2026,10,27,12), days: 30);
  final txt = await crlText(crl); expect(txt, contains('Serial Number: 0A')); expect(txt, contains('Next Update: Nov 26 12:00:00 2026 GMT'));
  expect(txt, contains('X509v3 CRL Number:')); expect((await verifyCrl(crl, caCert)).exitCode, 0);
});
test('buildCrl vazia ainda é uma CRL válida', ...);
```

- [ ] **Step 2: Escrever `atomic_file_test.dart`**: "o caminho final nunca contém conteúdo parcial" (validate que lança → arquivo anterior intacto, nenhum `.tmp-*` sobra), "sem arquivo anterior e validate que lança → caminho final não existe", "sucesso → conteúdo novo e nenhum temporário".
- [ ] **Step 3: Rodar e ver falhar** — `cd backend/sinalacs_server && dart test test/unit/openssl_device_ca_test.dart test/unit/atomic_file_test.dart` → FAIL (classes inexistentes).
- [ ] **Step 4: Implementar `DeviceCaConfig`, `OpensslDeviceCa` e `writeFileAtomically`.** `sign` usa `openssl x509 -req -in <csr> -CA -CAkey -set_serial 0x<hex> -extfile <ext> -not_before <YYYYMMDDHHMMSSZ> -not_after <...>` (OpenSSL ≥ 3.4; **medir** com `openssl version` na imagem `alpine:latest` e no host; se `-not_before` não existir, usar `-days` e `openssl ca -startdate` com `index.txt` temporário — o teste acima é o mesmo). `ext`: `basicConstraints=CA:FALSE`, `keyUsage=digitalSignature`, `extendedKeyUsage=clientAuth`, `subjectAltName=URI:...,URI:...`. `buildCrl` gera `index.txt` (`R\t<notAfter>\t<revokedAt>\t<serial hex par>\tunknown\t/CN=<cn>` por entrada), `crlnumber`, config mínima, e roda `openssl ca -gencrl -crldays <days>`. Tudo em `Directory.systemTemp.createTemp` apagado no `finally`; `stderr` do openssl vai para a exceção, **nunca** o conteúdo da chave.
- [ ] **Step 5: `init.sh`:** criar `runtime/devices/` com `ca.{crt,key}` (CN `sinalacs-dev-devices-ca`, 3650 dias, mesma regra de renovação da CA atual), `serial`, `crl.pem` inicial (vazia, 30 dias, por `openssl ca -gencrl` com `index.txt` vazio), e emitir **por esta CA** `backend.{crt,key}` (CN `backend`) e `qa-tools.{crt,key}` (CN `00000000-0000-4000-8000-000000000003`, o UUID da microárea do seed — ferramentas de QA, nunca asset). Permissões: medir o uid de `USER app` da imagem (`docker run --rm --entrypoint id <imagem>`); `ca.key` `chown <uid>` + `600`; `crl.pem` e o diretório gravados pelo backend (`chown <uid>` no diretório); o resto `644` (regra de `PROGRESS.md:1525`). **Manter** `issue_client acs-area-12` nesta tarefa (sai na Task 4).
- [ ] **Step 6: `dev_key_permissions_test.sh`** ganha as asserções de `runtime/devices/` (ca.key 600 do uid do app; crl.pem legível por todos).
- [ ] **Step 7: Rodar** os dois testes Dart → PASS; `docker compose up -d --build mosquitto-init serverpod` e `ls -la infra/docker/mosquitto/runtime/devices/`; `bash scripts/qa/dev_key_permissions_test.sh` → OK; `./scripts/qa/mtls_invariants.sh` (versão atual) ainda OK (o broker não mudou).
- [ ] **Step 8: Commit** — `feat(pki): CA de aparelhos de desenvolvimento e invólucro openssl no backend (#94)`.

### Task 3: Emissão, registro, revogação em transação, CRL e derrubada de sessão

**Files:**
- Create: modelos `device_certificate.spy.yaml` (`DeviceCertificate`: `id`, `userId` relation users, `deviceId` String, `microAreaId` UuidValue, `serial` String (hex, índice único), `fingerprintSha256` String, `notBefore`/`notAfter`/`issuedAt` DateTime, `revokedAt` DateTime?, `revocationReason` `DeviceCertRevocationReason?`; índices `device_certificates_device_idx` em `deviceId`, único em `serial`), `enums/device_cert_revocation_reason.spy.yaml` (`wipe`, `deactivated`, `microAreaChanged`, `renewed`), `api/device_certificate_issue_result.spy.yaml` (`certificatePem` String, `serial` String, `notAfter` DateTime, `serverNow` DateTime); `device_certificate_service.dart`, `orm_device_certificate_store.dart`, `device_crl_publisher.dart`, `mqtt_session_kicker.dart`
- Modify: `devices_endpoint.dart`, `alert_runtime.dart`, `orm_device_wipe_store.dart:84-125`, `device_wipe_service.dart:70-165`, `admin_account_service.dart:305-420`, `spec/lgpd_data_audit.md` (linha da tabela nova: só identificadores, sem PII; o `userId` é o do ACS)
- Test: `test/integration/device_certificate_service_test.dart`, `test/integration/device_certificate_endpoint_test.dart`, `test/integration/device_wipe_store_test.dart`, `test/integration/admin_account_revocation_test.dart`, `test/unit/device_crl_publisher_test.dart`, `test/unit/mqtt_session_kicker_test.dart`

**Interfaces:**
- Consumes: `OpensslDeviceCa`, `DeviceCaConfig`, `writeFileAtomically` (Task 2); `AuthenticatedUser{id, role, microAreaId, deviceId}`; `InstitutionalAuthService.deviceIdAbsent`; `DeviceWipeService.ensureDeviceNotMarked`.
- Produces: `abstract interface class DeviceCertificateStore { Future<DeviceCertificate> insert(DeviceCertificate c, {Transaction? transaction}); Future<List<DeviceCertificate>> activeFor(String deviceId); Future<int> issuedSince(String deviceId, DateTime since); Future<int> revoke({required String deviceId, required DeviceCertRevocationReason reason, required DateTime at, Transaction? transaction}); Future<int> revokeForUser({required String userId, required DeviceCertRevocationReason reason, required DateTime at, Transaction? transaction}); Future<List<DeviceCertificate>> revokedUnexpired(DateTime now); Future<BigInt> nextCrlNumber(); }`.
- `class DeviceCertificateService { Future<DeviceCertificateIssueResult> issue(AuthenticatedUser user, String csrPem, {DateTime? now}) }` — recusas (`StateError` → `AlertPermissionException` no endpoint): papel ≠ `acs`, `microAreaId == null`, `deviceId == deviceIdAbsent`, aparelho com pedido de wipe; `ArgumentError` → `AlertValidationException`: CSR inválido, chave ≠ EC prime256v1, CN ≠ microárea da sessão, mais de 5 emissões na última hora. Efeitos, numa transação: revoga as ativas do `deviceId` como `renewed`, insere a nova (serial = 16 bytes de `Random.secure()`, `notBefore = now − 1 h`, `notAfter = now + certDays`), auditoria `device_cert_issued` (actor = ACS, `resourceId` = serial); depois do commit, `DeviceCrlPublisher.publish()`. SANs: `urn:sinalacs:device:<deviceId>`, `urn:sinalacs:acs:<userId>`.
- `class DeviceCrlPublisher { DeviceCrlPublisher({..., Duration initialBackoff = const Duration(seconds: 2), Duration maxBackoff = const Duration(minutes: 5)}); Future<void> publish({DateTime? now}); DateTime? get pendingSince; Future<void> close() }` — lê `revokedUnexpired`, `nextCrlNumber`, `buildCrl`, grava com `writeFileAtomically(crlPath, validate: openssl crl -CAfile ca.crt -noout)`; single-flight (uma publicação por vez, a seguinte enfileirada); **falha (openssl, disco, validação) não é engolida pelo timer diário**: marca `pendingSince`, loga o tipo do erro (nunca o conteúdo) e agenda nova tentativa com recuo exponencial 2 s → 4 s → … → 5 min, sem teto de tentativas, até uma publicação completa, quando `pendingSince` volta a `null`; `publish()` chamado durante a espera faz a tentativa na hora e zera o recuo. Loga só contagem e número.
- `class MqttSessionKicker { MqttSessionKicker({required MqttDispatcherTlsConfig config}); Future<void> kick(String clientId, {Duration timeout = const Duration(seconds: 5)}) }` — conecta com o client id dado, clean session, `username: 'backend'`, mesmo `SecurityContext` do despachante, desconecta; falha vira log (melhor esforço: a CRL é o corte duro). `static String clientIdFor({required String acsId, required String deviceId}) => 'sinalacs-acs-$acsId-$deviceId'` (**o app usa a mesma função**, copiada com teste de igualdade em `apps/acs/test/alert_feed_enrollment_test.dart`).
- `DeviceWipeService.orderWipe` ganha, depois de `created`, `await crl.publish()` e `await kicker.kick(clientIdFor(...))` (colaboradores opcionais, `null` nos testes antigos). `AdminAccountService.setAcsActive(false)` e `setAcsMicroArea` revogam (`deactivated`/`microAreaChanged`) na **mesma** transação da conta, publicam a CRL depois do commit e **ambos** derrubam (`kick`) todos os aparelhos ativos do ACS (lista = `activeFor` por `deviceId` dos certificados revogados nessa chamada): a CRL só vale no próximo handshake (I2), e um aparelho com o CN da microárea antiga seguiria lendo o território antigo até a sessão cair sozinha — lacuna 1, decisão 5.

- [ ] **Step 1: Escrever os testes de integração** (`withServerpod`, fixtures sintéticas; o `OpensslDeviceCa` real contra uma CA temporária, `DEVICE_*` apontando para `Directory.systemTemp`):
  - `device_certificate_service_test.dart`: "emite para ACS com microárea e grava a linha com o deviceId da sessão" (CN e SANs conferidos por `openssl x509`), "segunda emissão revoga a anterior como renewed e a CRL publicada contém a serial antiga", "recusa papel patient", "recusa ACS sem microárea", "recusa deviceIdAbsent", "recusa aparelho com pedido de wipe pendente", "recusa CN diferente da microárea da sessão", "recusa RSA", "sexta emissão na mesma hora é recusada", "auditoria device_cert_issued com a serial".
  - `device_wipe_store_test.dart` (ampliar): "orderWipe revoga o certificado ativo do aparelho como wipe na mesma transação" e "repetir o pedido não revoga de novo".
  - `admin_account_revocation_test.dart` (com o broker de teste do projeto e um `kicker` real): "setAcsActive(false) revoga todos os certificados do ACS como deactivated e derruba a sessão aberta de cada aparelho", "setAcsMicroArea revoga como microAreaChanged **e derruba a sessão aberta** (uma assinatura viva com o client id do aparelho cai em ≤ 2 s)", "setAcsActive(true) não revoga nem derruba nada", "setAcsMicroArea para a mesma microárea não revoga".
  - `device_certificate_endpoint_test.dart`: `devices.issueCertificate(accessToken, csrPem)` devolve `certificatePem` verificável contra a CA e `serverNow`; `StateError` → `AlertPermissionException`; `ArgumentError` → `AlertValidationException`; sem `DeviceCaConfig` → `AlertPermissionException` com a mensagem fixa.
  - `device_crl_publisher_test.dart` (unit, loja em memória, `openssl` falso injetável, relógio/timers falsos via `fake_async`): "publica CRL válida com as revogadas não vencidas e número crescente", "duas chamadas concorrentes resultam em uma CRL final válida", "falha do openssl não deixa temporário nem corrompe a anterior", "**falha no publish → republica sozinho depois**: openssl falha duas vezes, `pendingSince` fica marcado, as tentativas vêm em 2 s e 4 s, a terceira grava e `pendingSince` volta a null", "recuo nunca passa de 5 min", "publish() durante a espera tenta na hora e zera o recuo", "close() cancela a tentativa pendente", "CRL assinada por outra CA é recusada na validação (não substitui a anterior)".
  - `mqtt_session_kicker_test.dart` (unit, broker de teste do projeto — o mesmo que `mqtt_alert_dispatcher_resilience_test.dart` usa): "kick derruba a sessão com o mesmo client id" e "broker fora do ar vira log, não exceção".
- [ ] **Step 2: Rodar e ver falhar** — `dart test -j 1 test/integration/device_certificate_service_test.dart` (e os demais) → FAIL.
- [ ] **Step 3: Modelos + `serverpod generate` + `serverpod create-migration` + `./scripts/dev/append_audit_append_only.sh`**; conferir que `test/integration/audit_schema_test.dart` segue verde.
- [ ] **Step 4: Implementar** loja, serviço, publisher, kicker, endpoint, fábricas no `AlertRuntime` (`deviceCertificateServiceFor`, `deviceCrlPublisher`, `mqttSessionKicker`) e a republicação periódica (24 h, mais uma no boot, dentro do `runZonedGuarded` existente). Ligar os ganchos em `orderWipe`, `setAcsActive`, `setAcsMicroArea`.
- [ ] **Step 5: Rodar** `dart test -j 1` completo → PASS (contar: a suíte inteira, não só os novos); `dart analyze` limpo.
- [ ] **Step 6: `spec/lgpd_data_audit.md`:** linha de `device_certificates` (identificadores técnicos; retenção = até `notAfter` + 30 dias, expurgo fora do escopo, anotado em `PROGRESS.md`).
- [ ] **Step 7: Commit** — `feat(devices): emissão e revogação do certificado do aparelho, CRL e derrubada da sessão (#94)`.

### Task 4: Broker — identidade pelo certificado, CRL com recarga, ACL por padrão, `mtls_invariants.sh`

> A partir deste commit o app do ACS **não conecta** ao broker até a Task 5 (o `acs-area-12` deixa de ser emitido e a senha deixa de valer). As ferramentas de QA passam a usar `runtime/devices/qa-tools.*`.

**Files:**
- Modify: `infra/docker/mosquitto/mosquitto.conf`, `aclfile`, `init.sh` (remove `acs-area-12` e `passwordfile`), `docker-compose.yml` (serviço `mosquitto-crl-reload`; `mosquitto` monta `runtime/devices:/mosquitto/devices:ro`; o `serverpod` passa a `MQTT_CLIENT_CERT_PATH=/app/devices/backend.crt` e `MQTT_CLIENT_KEY_PATH=/app/devices/backend.key`; remove `MQTT_ACS_PASSWORD`/`MQTT_BACKEND_PASSWORD`/`MQTT_PASSWORD`), `.env.example`, `scripts/dev/bootstrap_env.sh` (+ `_test.sh`), `scripts/qa/mqtt_resiliencia_e2e.sh`, `scripts/qa/measure_latency.dart`, `video/rpc_demo/watch_mqtt.sh`
- Create: `infra/docker/mosquitto/crl_reload.sh`, `scripts/qa/spikes/mosquitto_crl_spike.sh`, `scripts/qa/mtls_invariants_test.sh`
- Rewrite: `scripts/qa/mtls_invariants.sh`

**Interfaces:**
- `mosquitto.conf`: `cafile /mosquitto/devices/ca.crt`, `crlfile /mosquitto/devices/crl.pem`, `require_certificate true`, `use_identity_as_username true`, `allow_anonymous false`, `acl_file`, **sem** `password_file`; `certfile`/`keyfile`/`tls_version tlsv1.3` ficam.
- `aclfile`: `user backend` / `topic readwrite sinalacs/v1/#`; `pattern read sinalacs/v1/microareas/%u/alerts`; `pattern write sinalacs/v1/alerts/+/acks`.
- `crl_reload.sh` (sidecar, `image: eclipse-mosquitto:2`, `pid: "service:mosquitto"`, `user: root`, `entrypoint: ["/bin/sh","-c","apk add --no-cache openssl && sh /crl_reload.sh"]`): a cada 2 s compara `stat -c '%i %Y' /mosquitto/devices/crl.pem`; mudou → `openssl crl -in /mosquitto/devices/crl.pem -CAfile /mosquitto/devices/ca.crt -noout` OK (sintaxe **e assinatura**: lacuna 3) → `kill -HUP "$(pidof mosquitto)"` e loga "CRL recarregada (<data>)"; inválida ou de outra CA → loga "CRL recusada pelo sidecar, não recarregada" e **não** sinaliza.
- `mtls_invariants.sh` (cada negativo precedido do positivo; `publicar <cn-ou-arquivo> [...]` sem senha): **A** sem certificado → recusado; **B** `backend` (CA de aparelhos) → aceito; **C** folha de outra CA → recusado; **D** o certificado compartilhado antigo: emitido **na hora** pela CA do servidor (`runtime/certs/ca.key`, via `docker run --user root`), CN `acs-area-12` → recusado (é o comando-evidência do diagnóstico, agora negativo); **E** dois aparelhos A e B emitidos pela CA de aparelhos (CN = microárea do seed, SAN URI por aparelho) → ambos aceitos; revoga A (índice + `openssl ca -gencrl`, grava `crl.pem.tmp` + `mv`), espera até 10 s o sidecar logar a recarga → A recusado, **B aceito**, e a assinatura longa de B aberta antes da recarga **continua recebendo**; **F** takeover: sessão longa de A aberta antes da revogação continua viva depois do `SIGHUP`; o script conecta como `backend` com o client id de A → a sessão cai em ≤ 2 s; A não reconecta; **G** ACL: aparelho da microárea X com `-u backend` **não** publica no tópico de alertas (o username do CONNECT é ignorado) e não recebe nada de `sinalacs/v1/microareas/outra/alerts` enquanto X recebe o seu (controle positivo pelo `backend`); **H** estático: `crl.pem` verifica contra a CA e `nextUpdate` ≥ 7 dias; **I** mutação do sidecar, dois casos: (i) grava lixo em `crl.pem` (tmp + mv), espera 5 s, o broker **continua de pé** e B continua aceito; (ii) grava uma CRL **válida de outra CA** (a `fora-ca` do caso C, `openssl ca -gencrl`), espera 5 s, o log do sidecar diz "recusada", o broker continua de pé e B e `backend` continuam aceitos; restaura. Ao final restaura a CRL original (cópia feita no início; `trap EXIT`).
- `mtls_invariants_test.sh`: hermético (sem Docker): confere que cada caso negativo é precedido de um positivo no texto do script, que o `trap` restaura a CRL, que nenhuma senha aparece e que `set -euo pipefail` está presente (mesmo padrão de `acs_remote_wipe_e2e_test.sh`).

- [ ] **Step 1: Versionar o spike** em `scripts/qa/spikes/mosquitto_crl_spike.sh` (rascunho de 2026-10-27, porta 18883, broker descartável) com cabeçalho dizendo o que mediu; `bash` nele → as oito linhas da tabela I2 na saída.
- [ ] **Step 2: Escrever `mtls_invariants_test.sh`** e o novo `mtls_invariants.sh`; rodar `bash scripts/qa/mtls_invariants_test.sh` → OK; `./scripts/qa/mtls_invariants.sh` contra a stack **atual** → FALHA em D (aceito), E (CA de aparelhos não é confiada), G.
- [ ] **Step 3: Implementar** `mosquitto.conf`, `aclfile`, `init.sh`, `crl_reload.sh`, Compose, `.env.example`, `bootstrap_env.sh` (deixa de gerar `MQTT_ACS_PASSWORD`/`MQTT_BACKEND_PASSWORD`; `.env` antigo com as variáveis segue válido: nenhum `:?` as exige mais), ferramentas de QA para `qa-tools.*` sem `-u/-P`.
- [ ] **Step 4: `docker compose down && docker compose up -d --build`**; `./scripts/qa/mtls_invariants.sh` → "OK" nos grupos A–I; `bash scripts/dev/bootstrap_env_test.sh` → OK; `./scripts/qa/tls_invariants.sh` → inalterado (Grupo F do broker continua TLS 1.3).
- [ ] **Step 5: `grep -rn 'MQTT_ACS_PASSWORD\|MQTT_BACKEND_PASSWORD\|acs-area-12' --exclude-dir={build,pg_data,graphify-out,.git} .`** devolve só histórico (`PROGRESS.md`, planos, auditoria) e os pontos que a Task 5/6 ainda vai trocar (anotar a lista no commit).
- [ ] **Step 6: Commit** — `feat(broker): identidade pelo certificado, CRL com recarga por sidecar e ACL por microárea; mtls_invariants cobre o desenho (#94)`.

### Task 5: App do ACS — emissão no aparelho, loja segura, feed, client id por aparelho, wipe

**Files:**
- Create: `apps/acs/lib/core/security/device_certificate_store.dart`, `lib/core/services/device_certificate_enroller.dart`
- Modify: `lib/core/services/alert_feed.dart:30-45,118-165`, `lib/core/network/backend_client.dart` (`AcsBackend.issueDeviceCertificate`), `lib/core/network/backend_config.dart` (remover `mqttUsername`, `mqttPassword`, `mqttPasswordMissing`, `mqttClientCertAsset`, `mqttClientKeyAsset`), `lib/app/app.dart` (`DeviceEraser` + banner do feed), `lib/main.dart`, `android/app/build.gradle.kts:119-175` (remover a guarda da senha) e `:222-233` (a guarda da chave de dev **fica**, agora como regressão), `test/support/fakes.dart`
- Test: `test/device_certificate_store_test.dart`, `test/device_certificate_enroller_test.dart`, `test/alert_feed_enrollment_test.dart`, `test/backend_client_test.dart`, `test/device_wipe_test.dart`, `test/session_store_wiring_test.dart`, `test/secure_window_test.dart` (se citar a senha)

**Interfaces:**
- Consumes: `generateDeviceKeyPair`, `buildDeviceCsrPem` (Task 1); `devices.issueCertificate` (Task 3).
- Produces: `class StoredDeviceCertificate { final String acsId, deviceId, microAreaId, serial, certificatePem, privateKeyPem; final DateTime notAfter; }`; `abstract interface class DeviceCertificateStore { Future<StoredDeviceCertificate?> read({required String acsId, required String deviceId}); Future<void> write(StoredDeviceCertificate c); Future<void> delete({required String deviceId}); }` com `SecureStorageDeviceCertificateStore` (`flutter_secure_storage` com `AndroidOptions(encryptedSharedPreferences: true)`, o **mesmo** modo das três lojas existentes — `database_key_store.dart:46` —, chave `acs_device_cert|<acsId>|<deviceId>`, valor JSON; `test/device_certificate_store_test.dart` fixa o modo lendo `aOptions` da instância padrão, para a frase do `spec/stack.md` nunca ficar falsa) e `InMemoryDeviceCertificateStore`; `AcsBackend.issueDeviceCertificate(String csrPem) → Future<IssuedDeviceCertificate{certificatePem, serial, notAfter, serverNow}>` (`DeviceWipeRequiredException` → `DeviceWipeRequiredFailure`, as demais → `BackendFailure`).
- `class DeviceCertificateEnroller { DeviceCertificateEnroller({required DeviceCertificateStore store, required AcsBackend backend, DateTime Function() now = DateTime.now, Duration renewWithin = const Duration(days: 10)}); Future<StoredDeviceCertificate> ensure({required String acsId, required String deviceId, required String microAreaId}) }` — regras: guardado, mesma microárea, `notAfter − now > renewWithin` → devolve sem rede; perto de vencer e rede OK → reemite (par novo + CSR + `issueDeviceCertificate`, grava, devolve); perto de vencer e rede falha (`BackendFailure.isRecoverable`) → devolve o guardado; vencido/ausente/microárea diferente e rede falha → lança `DeviceCertificateUnavailable(expired: bool)`; `DeviceWipeRequiredFailure` sobe como está. Compara validade com `serverNow` da última emissão ajustado pelo relógio local (`offset = serverNow − now()` guardado junto), não só com o relógio do aparelho. Single-flight por `deviceId`.
- `AlertFeedFailureKind` perde `missingPassword` e `missingClientCertificate`, ganha `certificateUnavailable` (transitório; título "Sem certificado deste aparelho para a central", detalhe "Será emitido quando houver rede."). `AlertFeed` recebe `DeviceCertificateEnroller` e usa `clientId: deviceClientId(acsId: acsId, deviceId: deviceId)` — função nova em `mqtt_secure_client.dart`, `String deviceClientId({required String acsId, required String deviceId}) => 'sinalacs-acs-$acsId-$deviceId'`, string idêntica à de `MqttSessionKicker.clientIdFor` no servidor (o app não importa o servidor; o teste da Task 5 fixa a igualdade com a constante copiada e o caminho do arquivo do servidor em comentário) —, sem `username`/`password`.
- `DeviceEraser` chama `DeviceCertificateStore.delete(deviceId: antigo)` antes de apagar o `deviceId`.

- [ ] **Step 1: Escrever `device_certificate_enroller_test.dart`** (fake backend que conta emissões e pode falhar como recuperável; relógio falso): "sem certificado emite, grava e devolve", "válido e longe de vencer não chama o servidor", "faltando 9 dias reemite", "faltando 9 dias e sem rede devolve o guardado", "vencido e sem rede lança DeviceCertificateUnavailable(expired: true)", "vencido, sem rede, depois rede volta → reemite na chamada seguinte", "microárea da sessão diferente do CN reemite", "relógio do aparelho 30 min adiantado não reemite um certificado recém-emitido (usa serverNow)", "duas chamadas simultâneas fazem uma emissão", "DeviceWipeRequiredFailure sobe sem gravar nada".
- [ ] **Step 2: Escrever `alert_feed_enrollment_test.dart`**: "o feed pede o certificado ao enroller e monta o SecurityContext com ele (sem username/senha)", "client id é sinalacs-acs-<acsId>-<deviceId>" (igualdade com a constante do servidor, copiada em comentário com o caminho), "DeviceCertificateUnavailable vira AlertFeedFailureKind.certificateUnavailable transitório", "DeviceWipeRequiredFailure vira o fluxo da #81 (RemoteWipeCoordinator.check)". Ampliar `backend_client_test.dart` (mapeamento das exceções), `device_wipe_test.dart` ("a limpeza apaga o certificado do deviceId antigo"), `session_store_wiring_test.dart` ("main.dart liga SecureStorageDeviceCertificateStore; o enroller não importa dart:ui").
- [ ] **Step 3: Rodar e ver falhar** — `cd apps/acs && flutter test test/device_certificate_enroller_test.dart test/alert_feed_enrollment_test.dart` → FAIL.
- [ ] **Step 4: Implementar** loja, enroller, `AcsBackend.issueDeviceCertificate`, mudanças no feed, `BackendConfig`, `DeviceEraser`, `main.dart`, Gradle (remover a guarda e o aviso da senha; o `run_acs.sh` deixa de passar `SINALACS_MQTT_USER/PASSWORD` — Task 6), `fakes.dart`.
- [ ] **Step 5: Rodar** `flutter test` completo e `flutter analyze` → PASS/limpo; `grep -rn 'mqttPassword\|SINALACS_MQTT_PASSWORD\|mqttClientCertAsset' apps/acs` vazio.
- [ ] **Step 6: Commit** — `feat(acs): certificado por aparelho emitido pelo backend e guardado no Keystore; sem senha nem certificado compartilhado (#94)`.

### Task 6: Ferramentas, scripts de desenvolvimento, APK sem chave de cliente

**Files:**
- Modify: `scripts/dev/sync_dev_ca.sh` (+ `_test.sh`: deixa de copiar `acs_client.*` e **apaga** um `acs_client.*` deixado por versão antiga), `scripts/dev/run_acs.sh` (+ `run_acs_captura_test.sh`), `scripts/qa/run_android_e2e.sh`, `scripts/qa/e2e.sh`, `.github/workflows/ci.yml` (remover `SINALACS_MQTT_PASSWORD` onde for passado), `apps/acs/tool/live_check.dart:115-116,210-211` (`runtime/devices/qa-tools.*`, sem `-u/-P`), `scripts/qa/acs_release_signing.sh` (cenário 4 passa a provar que o release **falha** com um `acs_client.key` plantado e **passa** sem ele)
- Create: `scripts/qa/acs_apk_no_client_key.sh` (+ `_test.sh`)

**Interfaces:**
- `acs_apk_no_client_key.sh [--debug|--release] [caminho.apk]`: `unzip -l` sem `assets/certs/acs_client.*`; nenhuma entrada do APK (assets, `libapp.so`, `kernel_blob.bin`) contém `PRIVATE KEY`; e `assets/certs/` lista exatamente `dev_ca.crt` e `dev_rpc_ca.crt`. Sai 1 com o nome da entrada ofensora (nunca o conteúdo).

- [ ] **Step 1: Escrever `acs_apk_no_client_key_test.sh`** (hermético: monta um zip com e sem chave plantada e espera 1/0) e o script; rodar o teste → OK.
- [ ] **Step 2: Ajustar** `sync_dev_ca.sh` e seu teste ("remove acs_client.* legado", "não cria acs_client.*"), `run_acs.sh`, `run_android_e2e.sh`, `e2e.sh`, `ci.yml`, `live_check.dart`, `acs_release_signing.sh`.
- [ ] **Step 3: Rodar** `bash scripts/dev/sync_dev_ca_test.sh`, `bash scripts/dev/run_acs_captura_test.sh`, `./scripts/qa/ci_invariants.sh && bash scripts/qa/ci_invariants_test.sh`, `./scripts/dev/run_acs.sh --build` e `./scripts/qa/acs_apk_no_client_key.sh --debug` → OK; `./scripts/qa/acs_release_signing.sh` → três cenários OK; `./scripts/qa/acs_apk_no_client_key.sh --release` sobre o APK que o cenário gerou → OK; `cd apps/acs && dart run tool/live_check.dart` (stack de pé, `ENABLE_DEV_LOGIN=true`) → conecta ao broker com `qa-tools`.
- [ ] **Step 4: Commit** — `chore(dev): ferramentas e scripts sem o certificado compartilhado; APK provado sem chave de cliente (#94)`.

### Task 7: E2E no emulador — emissão → conexão → dois aparelhos → limpeza remota → recusa

**Files:**
- Create: `apps/acs/integration_test/device_cert_e2e.dart`, `apps/acs/tool/device_cert_second_device.dart`, `scripts/qa/acs_device_cert_e2e.sh` (+ `_test.sh`)
- Modify: `scripts/qa/acs_remote_wipe_e2e.sh` (asserções), `apps/acs/integration_test/red_alert_cycle_test.dart` (só se citar a senha/asset)

**Interfaces:**
- `tool/device_cert_second_device.dart` (VM, como `live_check.dart`): entra como o **mesmo** ACS da fixture com `deviceId` próprio (`E2E_FIXTURES_FILE`), gera par + CSR, chama `issueDeviceCertificate`, conecta ao broker com `clientIdFor` e fica assinando o tópico da microárea; imprime linhas marcadoras `E2E_DEV2_CONECTADO`, `E2E_DEV2_ALERTA_RECEBIDO <alertId>`, `E2E_DEV2_DERRUBADO`, `E2E_DEV2_RECONEXAO_RECUSADA`; guarda a chave só em memória.
- `acs_device_cert_e2e.sh`: anatomia de `acs_remote_wipe_e2e.sh` (`e2e_stack.sh`, relé `/acs` e `/coordenador`, `adb reverse`). Sequência: (1) o teste no emulador entra e o painel abre → o script lê no banco **uma** linha de `device_certificates` do `deviceId` do emulador com CN da microárea da fixture, e no log do broker `New client connected ... u'<microAreaId>'`; (2) sobe o segundo aparelho (tool) → segunda linha, outro `deviceId`, outra serial; (3) o script insere um alerta vermelho por SQL (como `acs_alert_fallback_e2e.sh`) e dispara o despacho → o emulador mostra o cartão **e** o tool imprime `E2E_DEV2_ALERTA_RECEBIDO`; (4) o coordenador pede o wipe do **segundo aparelho** → `E2E_DEV2_DERRUBADO` em ≤ 5 s, `E2E_DEV2_RECONEXAO_RECUSADA`, a linha dele com `revokedAt` e `wipe`, a serial na CRL (`openssl crl -text`), log do sidecar com a recarga; (5) novo alerta → o emulador **ainda recebe** (revogar um não derruba o outro); (6) o coordenador pede o wipe do emulador → fluxo da #81 na tela (`device_wiped`), a linha do emulador revogada, a serial na CRL; "Entrar de novo" → `deviceId` novo, **terceira** linha emitida e conexão nova no log do broker; (7) `audit_chain_check` verde, `device_cert_issued` × 3 e `device_cert_revoked` × 2 na trilha.
- `acs_remote_wipe_e2e.sh` ganha: linha de `device_certificates` revogada como `wipe` e serial presente na CRL.

- [ ] **Step 1: Escrever `acs_device_cert_e2e_test.sh`** (estrutura: marcadores existem, `cleanup` derruba o tool e restaura a stack) → OK; escrever o teste de integração e o tool.
- [ ] **Step 2: Rodar `./scripts/qa/acs_device_cert_e2e.sh`** no `emulator-5554` (API 36) → OK ponta a ponta; guardar a saída em `docs/superpowers/plans/2026-10-27-issue-94-e2e.log` (sem segredo: o script nunca imprime chave nem token).
- [ ] **Step 3: Rodar `./scripts/qa/acs_remote_wipe_e2e.sh`** (regressão da #81 com as asserções novas) → OK; `./scripts/qa/e2e.sh --emulator --full` → OK (inclui `red_alert_cycle_test.dart`, que agora emite o certificado sozinho pelo feed).
- [ ] **Step 4: Commit** — `test(e2e): emissão, dois aparelhos, limpeza remota e recusa do certificado no emulador (#94)`.

### Task 8: Documentação, auditoria do PRD e PR

**Files:**
- Modify: `PROGRESS.md` (seção "Certificado de cliente por aparelho (#94) — <data>": decisões 1–6 com as respostas do dono, as cinco lacunas da revisão e onde entraram, medições I1–I3, provas; abertos, cada um com o número da issue aberta no Step 0: alternativa A (túnel nativo, chave no TEE, risco do loopback), ACK sem identidade de aparelho (`%c` na ACL ou `deviceId` no payload validado contra a microárea do alerta), PKI de produção (as sete perguntas e a posição inicial do dono), **calibração de `DEVICE_CERT_DAYS`** (30 é padrão de dev; produção decide com dados de conectividade das áreas — janela de 20 dias com rede é apertada em partes de Roraima), expurgo de `device_certificates`, risco do takeover entre irmãos da mesma microárea, `peerCertificate` não logado no backend), `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (STRIDE-S → "entregue na stack local; produção depende da PKI — issue #<pki>", R3 e item 7 do backlog atualizados), `spec/stack.md` (já na Task 1; conferir), `CLAUDE.md` (parágrafo "Already delivered"/"Still missing"), `apps/CLAUDE.md` (parágrafo "mTLS to the broker"), `backend/CLAUDE.md` (variáveis `DEVICE_*`, endpoint, tabela), `README.md`, `.claude/skills/validacao-e2e/SKILL.md` (novo e2e), `docs/telas-acs.md` (banner novo, sem screenshot inventado)
- Test: `./scripts/qa/check_documentation_links.sh`

- [ ] **Step 0: Abrir as três issues de continuação** com `gh issue create` (antes do PR, para o `PROGRESS.md` e a STRIDE-S citarem os números): (a) "Chave do certificado do aparelho no TEE: túnel TLS nativo (alternativa A da #94)", com o custo e o risco do loopback medidos em I1; (b) "ACK com identidade de aparelho: `%c` na ACL ou `deviceId` no payload validado contra a microárea do alerta (continuação da #94)", registrando que não é regressão; (c) "PKI de produção da CA de aparelhos (escopo 5 da #94)", com as sete perguntas e a posição inicial do dono (item 6), e "dono do runbook" como primeira decisão. Sem texto gerado por IA assinado como tal; nenhuma solução de produção apresentada como decidida.
- [ ] **Step 1: Escrever a documentação** acima; `./scripts/qa/check_documentation_links.sh` → OK.
- [ ] **Step 2: `graphify update .`**
- [ ] **Step 3: Commit** — `docs: certificado por aparelho entregue na stack local; STRIDE-S e R3 atualizados (#94)`.
- [ ] **Step 4: PR** `feat/issue-94-certificado-por-aparelho` → `develop` (`gh pr create`), corpo com os critérios da tabela abaixo e os logs; CI 8/8 obrigatórios verdes e `android-e2e` verde (ele roda `red_alert_cycle_test.dart` com o feed novo).

## Critérios de aceite da issue → tarefa → prova

| Critério | Tarefa | Prova |
|---|---|---|
| Dois aparelhos do mesmo ACS usam certificados diferentes; revogar um não derruba o outro | 3, 5, 7 | `device_certificate_service_test` (serial única por emissão), `mtls_invariants.sh` Grupo E/F, `acs_device_cert_e2e.sh` passos 2–5 |
| Limpeza remota (#81) revoga o certificado; o broker recusa a nova conexão | 3, 4, 7 | `device_wipe_store_test` (revoga na transação), Grupo E (CRL recarregada) e F (takeover), `acs_device_cert_e2e.sh` passo 4, `acs_remote_wipe_e2e.sh` |
| Release sem chave privada de cliente; certificado compartilhado sai do APK de debug | 4, 5, 6 | `init.sh` sem `acs-area-12`, `sync_dev_ca.sh` não copia e apaga legado, `acs_apk_no_client_key.sh --debug/--release`, `acs_release_signing.sh` cenário 4, guarda Gradle mantida |
| `mtls_invariants.sh` cobre o novo desenho; e2e no emulador | 4, 7 | Grupos A–I com `mtls_invariants_test.sh`; `acs_device_cert_e2e.sh` + log |
| `spec/stack.md`, `PROGRESS.md`, auditoria do PRD (STRIDE-S) atualizados | 1, 8 | `check_documentation_links.sh`; diff das três linhas |
| CSR no aparelho, autenticado pela sessão (escopo 1) | 1, 3, 5 | `device_csr_test` (`openssl req -verify`), endpoint com `authenticate`, `deviceId` só da claim |
| CA de aparelhos no backend, amarração a `deviceId` e microárea, validade curta e renovação (escopo 2) | 2, 3, 5 | `openssl_device_ca_test` (SANs/CN/datas), enroller (renovação aos 10 dias, offline, relógio) |
| CRL no Mosquitto ligada ao wipe, com spike da recarga (escopo 3) | 3, 4 | Tabela I2, `scripts/qa/spikes/mosquitto_crl_spike.sh`, sidecar, Grupos E/H/I |
| Dependência escolhida com entrada no `spec/stack.md` antes do `pubspec` (escopo 4) | 1 | Ordem dos commits da Task 1 |
| PKI de produção (escopo 5) | 8 | Issue própria (Step 0 da Task 8) com as sete perguntas e a posição inicial do dono; `PROGRESS.md` e a linha STRIDE-S apontam para ela; nada de produção decidido no código |
| Troca de microárea corta o MQTT até a reemissão (decisão 5, LGPD) | 3, 5 | `admin_account_revocation_test` (revoga **e** derruba), enroller reemite com o CN novo |
| Falha ao publicar a CRL não deixa janela aberta (lacuna 2) | 3 | `device_crl_publisher_test` (recuo exponencial, `pendingSince`) |
| Sidecar só recarrega CRL assinada pela CA (lacuna 3) | 4 | Grupo I-ii |
| ACK com identidade de aparelho (lacuna 4) | 8 | Issue de continuação; `PROGRESS.md` |

## Checklist final

- [ ] Ponto de decisão respondido pelo dono e respostas coladas no topo deste plano (como no plano da #90).
- [ ] `grep -rn 'BEGIN .*PRIVATE KEY' apps/ backend/ infra/ scripts/ --exclude-dir={build,runtime,.dart_tool}` só em testes que geram chave descartável.
- [ ] `git status` sem `apps/acs/assets/certs/acs_client.*`; `.gitignore` inalterado.
- [ ] `./scripts/qa/mtls_invariants.sh`, `./scripts/qa/tls_invariants.sh`, `bash scripts/qa/mtls_invariants_test.sh`, `bash scripts/qa/dev_key_permissions_test.sh`, `bash scripts/dev/bootstrap_env_test.sh`, `bash scripts/dev/sync_dev_ca_test.sh` → OK.
- [ ] `cd backend/sinalacs_server && dart test -j 1`; `cd apps/acs && flutter analyze && flutter test`; `apps/patient` e `apps/admin` sem diff.
- [ ] `./scripts/qa/acs_device_cert_e2e.sh`, `./scripts/qa/acs_remote_wipe_e2e.sh`, `./scripts/qa/e2e.sh --emulator --full` → OK, logs guardados.
- [ ] `./scripts/qa/acs_apk_no_client_key.sh --debug` e `--release` → OK.
- [ ] `PROGRESS.md`, `spec/stack.md`, `spec/lgpd_data_audit.md`, `docs/auditoria-prd/2026-10-15-lacunas-prd.md`, os três `CLAUDE.md` e `README.md` atualizados; `check_documentation_links.sh` OK.
- [ ] Um `.env` antigo (com `MQTT_ACS_PASSWORD`/`MQTT_BACKEND_PASSWORD`) ainda sobe a stack; um `.env` novo também.
- [ ] Nenhuma atribuição de IA em commits e PR.
