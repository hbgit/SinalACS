# SinalACS

Plataforma para priorização de atendimentos na Atenção Primária à Saúde. O
SinalACS transforma sinais clínicos estruturados em uma fila de trabalho para
o Agente Comunitário de Saúde (ACS), priorizada por risco e preparada para
operação em conectividade instável.

> **Estado atual:** protótipo funcional da Fase 2 (Alpha/Beta). Os aplicativos
> Flutter, as regras de triagem, a fila offline e a infraestrutura de
> desenvolvimento local estão implementados. Integrações de produção com
> Serverpod, MQTT autenticado, identidade e deploy ainda não estão concluídas.

## Funcionalidades atuais

- App do paciente com acesso inicial, triagem estruturada e status da solicitação.
- App ACS com login institucional demonstrativo, painel de priorização,
	territorialização e registro local de visitas.
- Motor de triagem determinístico, com classificação verde, amarela ou vermelha.
- Fila de visitas offline com sincronização simulada, retry e detecção de conflitos.
- Contrato de alerta MQTT com configuração TLS/WSS, ainda sem conexão real ao broker.
- Persistência local preparada para SQLCipher.

Consulte [PROGRESS.md](PROGRESS.md) para o status detalhado dos milestones e
[spec/PRD_system.md](spec/PRD_system.md) para requisitos e decisões técnicas.

## Estrutura

```text
apps/
	acs/       Aplicativo Flutter do Agente Comunitário de Saúde
	patient/   Aplicativo Flutter do paciente
	admin/     Base do aplicativo administrativo
backend/     Backend Dart/Serverpod e regras de domínio
infra/       Configuração local de infraestrutura
spec/        PRD, UX, privacidade e fluxos do produto
tests/       Testes compartilhados
```

## Pré-requisitos

- Flutter SDK compatível com Dart `>=3.3.0 <4.0.0`.
- Android SDK com API 36 e JDK 17 para gerar ou executar o app ACS no Android.
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
| Backend | `http://localhost:8080` |
| PostgreSQL | `localhost:5432` |
| Mosquitto MQTT | `localhost:1883` |
| Mosquitto WebSocket | `localhost:9001` |

Para encerrar a stack:

```bash
docker compose down
```

O Compose atual usa credenciais de desenvolvimento declaradas no
[docker-compose.yml](docker-compose.yml). Não reutilize essas credenciais nem
habilite o dashboard inseguro do Traefik em ambientes públicos.

### Aplicativo ACS

```bash
cd apps/acs
flutter pub get
flutter run
```

Para selecionar explicitamente um emulador Android disponível:

```bash
flutter devices
flutter run -d <device-id>
```

### Aplicativo do paciente

```bash
cd apps/patient
flutter pub get
flutter run
```

## Build

### APK Android de depuração

O app ACS foi validado com `compileSdk` e `targetSdk` 36. Para gerar o APK:

```bash
cd apps/acs
flutter clean
flutter pub get
flutter build apk --debug
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
cd backend && dart pub get && dart analyze && dart test
cd apps/acs && flutter pub get && flutter analyze && flutter test
cd apps/patient && flutter pub get && flutter analyze && flutter test
```

A última validação local aprovou 14 testes que cobrem fluxos de login e
triagem, acessibilidade, fila offline, MQTT seguro, simulação de rede e banco
criptografado. A CI executa análise e testes para backend, paciente e ACS em
pushes para `main`/`master` e pull requests.

## Deploy

**Não há deploy de produção implementado neste momento.** O arquivo
[docker-compose.yml](docker-compose.yml) é destinado ao desenvolvimento local;
ele não oferece TLS público, gestão de segredos, persistência operacional,
observabilidade, backup ou políticas de acesso compatíveis com produção.

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
classificação de risco é determinística e alertas vermelhos não devem ser
descartados silenciosamente. As garantias de autenticação, autorização por
microárea e entrega MQTT com ACK permanecem pendentes de integração real.

## Licença

Consulte [LICENSE](LICENSE).
