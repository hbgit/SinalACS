# SinalACS

Plataforma para priorização de atendimentos na Atenção Primária à Saúde. O
SinalACS transforma sinais clínicos estruturados em uma fila de trabalho para
o Agente Comunitário de Saúde (ACS), priorizada por risco e preparada para
operação em conectividade instável.

> **Estado atual:** protótipo funcional, validado localmente em stack Docker
> (PostgreSQL, Mosquitto, backend Serverpod e Traefik) e em emulador Android.
> **Não está pronto para produção:** não há deploy de produção, iOS, nem
> integração com um provedor de identidade real. A lista completa do que falta,
> com responsáveis, está em [PROGRESS.md](PROGRESS.md).

## Funcionalidades atuais

**App do paciente** (`apps/patient`)
- Login sem senha: CPF + data de nascimento + código de uso único (OTP), e
  cadastro por convite em QR Code.
- Alerta de urgência real (`alerts.createRedAlert`) com acompanhamento de
  entrega, triagem estruturada determinística e status da solicitação.
- "Meus Dados" (LGPD): exportação, histórico de consentimentos, revogação e
  pedidos de correção e exclusão; aceite dos Termos de Uso.
- Lembretes locais e recebimento de avisos à comunidade por push (Gorush + FCM).

**App do ACS** (`apps/acs`)
- Login institucional com matrícula, senha (Argon2id) e TOTP; refresh token
  rotativo guardado no Keystore e liberado por biometria; bloqueio após 30 s em
  segundo plano e `FLAG_SECURE` na janela.
- Fila de visitas priorizada por risco, restrita à microárea do ACS (RBAC),
  com mapa, territorialização e geofencing.
- Registro de visitas offline em banco local cifrado (SQLCipher), com fila por
  dono, reenvio e detecção de conflito; recebimento de alertas vermelhos por
  MQTT com TLS e confirmação (ACK).

**Backoffice** (`apps/admin`, Flutter Web e Android)
- Login de coordenador/administrador com senha e TOTP obrigatório.
- Indicadores, microáreas, alertas (com escalonamento do alerta vermelho não
  confirmado), auditoria com selo por linha, verificação da cadeia e
  exportação CSV, gestão de contas de ACS e de MFA, pedidos do titular (LGPD),
  avisos agendados e versões dos Termos.

**Backend** (`backend/`, Serverpod)
- Motor de triagem determinístico (verde, amarelo, vermelho), alerta vermelho
  idempotente por microárea publicado no broker, sincronização de visitas,
  colunas clínicas cifradas em repouso (AES-256-GCM) e trilha de auditoria
  encadeada.

Consulte [PROGRESS.md](PROGRESS.md) para o status detalhado dos milestones e
[spec/PRD_system.md](spec/PRD_system.md) para requisitos e decisões técnicas.
As telas estão documentadas em [docs/README.md](docs/README.md).

## Estrutura

```text
apps/
	acs/       Aplicativo Flutter do Agente Comunitário de Saúde
	patient/   Aplicativo Flutter do paciente
	admin/     Backoffice administrativo (Flutter Web e Android)
backend/     Workspace Dart: servidor Serverpod (sinalacs_server) e cliente gerado (sinalacs_client)
infra/       Configuração local de infraestrutura (Mosquitto, Traefik, Gorush)
scripts/     dev/ (configuração e execução local), qa/ (validação e e2e), ci/
spec/        PRD, UX, privacidade e fluxos do produto
docs/        Telas, guias operacionais e planos de implementação
video/       Roteiro e material do vídeo de apresentação
```

## Pré-requisitos

- Flutter SDK compatível com Dart `>=3.3.0 <4.0.0`.
- Android SDK com API 36 e JDK 17 para gerar ou executar os apps ACS, paciente e admin no Android.
- Docker Engine com Docker Compose v2 para subir a stack local.
- Um emulador Android ou dispositivo físico, opcional para execução mobile.

As versões usadas pela CI estão definidas em
[.github/workflows/ci.yml](.github/workflows/ci.yml).

## Execução local

### Stack de serviços

Na raiz do repositório, suba PostgreSQL, Mosquitto, backend e Traefik:

```bash
docker compose up --build
```

Serviços expostos no ambiente local:

| Serviço | Endereço |
|---|---|
| Traefik | `http://localhost` |
| Dashboard Traefik (inseguro, somente desenvolvimento) | `http://localhost:8081` |
| Backend | `https://localhost/` (RPC atrás do Traefik; a 8080 em texto claro não é publicada) |
| PostgreSQL | `localhost:5432` |
| Mosquitto MQTT (TLS) | `localhost:8883` |

`8883` é a **única** porta que o broker publica. A 1883 anônima e a WebSocket
9001 não são publicadas **nem escutadas**: o `mosquitto.conf` só declara
`listener 8883` (medido: as duas recusam conexão no host e não aparecem em
`/proc/net/tcp` dentro do container). O `docker compose ps` mostra `1883/tcp` na
linha do mosquitto porque a imagem a declara em `EXPOSE`, não porque exista algo
atendendo nela.

Para encerrar a stack:

```bash
docker compose down
```

O Compose lê todas as credenciais do `.env` gerado por
[scripts/dev/bootstrap_env.sh](scripts/dev/bootstrap_env.sh) — cada máquina tem
as suas. Não reutilize credenciais de desenvolvimento nem habilite o dashboard
inseguro do Traefik em ambientes públicos.

### Aplicativo ACS

```bash
cd apps/acs && flutter pub get && cd -
./scripts/dev/run_acs.sh
```

Use o script, não `flutter run` direto. A senha do broker é resolvida em tempo
de compilação e não tem valor padrão: ela é gerada por máquina pelo
`bootstrap_env.sh`. O script lê o `.env`, copia as duas CAs de desenvolvimento
(a do broker e a do RPC) para os assets e passa os cinco `--dart-define` por um
arquivo temporário (`--dart-define-from-file`,
apagado ao sair), para a senha não trafegar na linha de comando do `flutter`. Os
cinco são `SINALACS_HOST`, `SINALACS_MQTT_HOST`, `SINALACS_MQTT_USER`,
`SINALACS_MQTT_PASSWORD` e `GOOGLE_MAPS_API_KEY`. Um
`flutter build apk` sem o `SINALACS_MQTT_PASSWORD` — o único dos cinco sem
valor padrão — **falha** (a guarda vive em
`apps/acs/android/app/build.gradle.kts`) em vez de compilar em silêncio um APK
que nunca recebe alerta.

Para escolher o dispositivo, ou gerar o APK:

```bash
flutter devices
./scripts/dev/run_acs.sh -d <device-id>
./scripts/dev/run_acs.sh --build
```

### Aplicativo do paciente

O paciente não usa MQTT: o default de `SINALACS_HOST` já serve no emulador.

```bash
cd apps/patient
flutter pub get
flutter run
# em aparelho físico, apontando para a máquina da stack:
flutter run --dart-define=SINALACS_HOST=https://<ip-da-máquina>/
```

**Em aparelho físico na LAN, o host precisa casar em dois lugares — não só no
certificado.** O `RPC_CERT_SAN_EXTRA` (`.env`) acrescenta o IP ao SAN da folha do
Traefik, mas quem decide se a requisição chega ao backend é a regra do router:
`Host(\`10.0.2.2\`) || Host(\`localhost\`) || Host(\`sinalacs.localhost\`)`
(`docker-compose.yml`). Um host coberto pelo SAN e **fora** da regra faz o TLS
passar e recebe o 404 do Traefik — medido: com a folha que cobre `127.0.0.1`,
`curl --cacert …/ca.crt https://127.0.0.1/health/check` devolve
`404 page not found`, enquanto `https://localhost/` devolve 200. Então o IP
precisa entrar **também** na regra; no broker não existe router, e é por isso
que lá o SAN sozinho basta.

Antes do primeiro `flutter run` — ou sempre que um `runtime/` da stack for
apagado —, copie as CAs de desenvolvimento para os assets, com a stack de pé:

```bash
./scripts/dev/sync_dev_ca.sh
```

Sem essa cópia **nada fica vermelho na hora de compilar**: `flutter build` e
`flutter test` saem verdes e o APK vai sem certificado nenhum dentro, e o app só
se denuncia depois, no handshake do TLS. O único comando que reclama é o
`flutter analyze`, pelo diretório que o `pubspec.yaml` declara e não existe.

## Build

### APK Android de depuração

O app ACS foi validado com `compileSdk` e `targetSdk` 36. Para gerar o APK:

```bash
cd apps/acs && flutter clean && flutter pub get && cd -
./scripts/dev/run_acs.sh --build
```

O artefato é criado em:

```text
apps/acs/build/app/outputs/flutter-apk/app-debug.apk
```

O mesmo procedimento pode ser aplicado ao app do paciente, substituindo
`apps/acs` por `apps/patient`.

### Build de release

A configuração Android atual assina builds de release com a chave de debug,
adequada apenas para testes internos. Antes de qualquer distribuição, defina
um `applicationId` próprio, configure assinatura de release e forneça os
segredos por variáveis de ambiente ou um cofre de segredos.

## Testes e análise

Execute cada conjunto a partir do respectivo diretório:

```bash
cd backend && dart pub get && dart analyze
cd backend/sinalacs_server && dart test
cd apps/acs && flutter pub get && flutter analyze && flutter test
cd apps/patient && flutter pub get && flutter analyze && flutter test
```

O backend é um workspace Dart com dois pacotes: `sinalacs_server` (servidor
Serverpod) e `sinalacs_client` (cliente tipado gerado). A suíte tem 25 testes —
16 unitários herméticos, que não precisam de banco, e 9 de integração sobre o
harness do Serverpod, que exigem um Postgres em `localhost:9090` conforme
`sinalacs_server/config/test.yaml`. Para rodar só os herméticos:
`dart test test/unit`.

A última validação local cobriu o ciclo crítico ponta a ponta em stack Docker —
autenticação, idempotência, publicação no broker e ACK do ACS. A CI
(`.github/workflows/ci.yml`) roda quatro jobs em pushes para main e pull
requests: `serverpod-backend` (sobe o Postgres de teste e roda `dart analyze`
mais a suíte completa), `backend-docker-build` (valida que a imagem builda),
`patient-app` e `acs-app`.

### Configuração

**Antes do primeiro `docker compose up`, gere a configuração local:**

```bash
./scripts/dev/bootstrap_env.sh
```

O script cria `.env` com segredos aleatórios desta máquina (senha do Postgres,
as duas do broker MQTT e o `JWT_SECRET`) e gera
`backend/sinalacs_server/config/passwords.yaml`, que é gitignored e por isso não
existe num clone limpo — sem ele a suíte de testes do Serverpod morre sem
imprimir nada. Nenhum dos dois entra no git.

[.env.example](.env.example) é a referência completa de todas as variáveis, com
um comentário por bloco dizendo quem consome cada uma. O `docker-compose.yml`
declara cada segredo como `${VAR:?...}`: se faltar, o Compose falha dizendo qual
variável está ausente, em vez de subir com uma senha embutida no arquivo
versionado.

Configuração de servidor e banco vem dos arquivos `sinalacs_server/config/*.yaml`
e pode ser sobrescrita por variáveis de ambiente: `SERVERPOD_DATABASE_HOST` e
companhia, `SERVERPOD_APPLY_MIGRATIONS` (aplica as migrações no boot),
`SERVERPOD_REDIS_ENABLED` (Redis é opcional e fica desligado) e
`SERVERPOD_INSIGHTS_SERVER_PORT`. O MQTT não faz parte do Serverpod e mantém as
próprias variáveis, lidas por `sinalacs_server/lib/src/config/app_config.dart`:
`MQTT_BROKER`/`MQTT_USERNAME`/`MQTT_PASSWORD`/`MQTT_USE_TLS`/`MQTT_CA_CERT_PATH`,
mais `JWT_SECRET`, `APP_ENV` e `ENABLE_DEV_LOGIN` (por padrão desligado — sem
ele, `auth.developmentLogin` falha como se o endpoint não existisse).

Fora de `development`, o servidor **recusa subir** se `JWT_SECRET` estiver
ausente, vazio ou igual ao valor de desenvolvimento (que é público, por estar no
código versionado). O token carrega o papel e a microárea, então assinar com uma
chave conhecida permitiria forjar um acesso de ACS a qualquer território. Veja
[backend/DEPLOY.md](backend/DEPLOY.md) para o runbook completo do piloto de
deploy free-tier.

## Deploy

**Não há deploy de produção implementado neste momento.** O arquivo
[docker-compose.yml](docker-compose.yml) é destinado ao desenvolvimento local;
ele não oferece TLS público, gestão de segredos, persistência operacional,
observabilidade, backup ou políticas de acesso compatíveis com produção.

Existe um caminho de **piloto/demo em serviços free-tier** para o backend,
documentado em [backend/DEPLOY.md](backend/DEPLOY.md). Esse caminho é
propositalmente barato e simplificado para demonstração — ele não substitui
nenhum dos requisitos de produção do PRD listados abaixo.

O caminho previsto no PRD para produção inclui:

1. Provisionamento imutável com Pulumi.
2. PostgreSQL, Mosquitto e Traefik com redes privadas, TLS 1.3 e segredos fora do repositório.
3. ACLs MQTT, autenticação institucional e RBAC por microárea.
4. Observabilidade com OpenTelemetry, Prometheus e Grafana.
5. Revisão de LGPD, auditoria e política de retenção antes de qualquer piloto.

Os critérios completos estão em [spec/PRD_system.md](spec/PRD_system.md) e o
desenho de privacidade em [spec/lgpd_design.md](spec/lgpd_design.md).

## Segurança e escopo

O projeto lida com dados de saúde. Não inclua dados reais de pacientes em
testes, logs, capturas de tela ou configurações de desenvolvimento. A
classificação de risco é determinística e não pode ser alterada manualmente,
alertas vermelhos não são descartados em silêncio e o acesso do ACS fica
restrito à própria microárea.

Autenticação, RBAC por microárea, TLS no RPC e no broker (com senha, ACL e
certificado de cliente) estão implementados **na stack local**. Ainda faltam,
entre outros: provisionamento de certificado de cliente por aparelho em
produção, refresh token para o paciente, imposição de append-only da trilha de
auditoria no banco e o deploy de produção — ver [PROGRESS.md](PROGRESS.md) e a
[política de segurança](.github/SECURITY.md).

## Licença

Consulte [LICENSE](LICENSE).
